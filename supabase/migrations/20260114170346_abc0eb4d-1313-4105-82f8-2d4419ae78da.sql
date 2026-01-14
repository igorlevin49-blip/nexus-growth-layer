
-- Исправляем admin_audit_user_commissions
-- 1. Переименовываем переменную level → lvl для устранения конфликта
-- 2. Исправляем structure_type: 'S1' → 'primary'
CREATE OR REPLACE FUNCTION public.admin_audit_user_commissions(p_admin_id uuid, p_user_id uuid)
RETURNS TABLE(
  subscription_id uuid,
  partner_id uuid,
  partner_name text,
  partner_email text,
  level integer,
  subscription_amount_kzt numeric,
  expected_percent numeric,
  expected_commission_kzt numeric,
  commission_received boolean,
  commission_amount_kzt numeric,
  no_commission_reason text,
  actual_vs_expected text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM user_roles WHERE user_id = p_admin_id AND role IN ('admin', 'superadmin')
  ) THEN
    RAISE EXCEPTION 'Unauthorized: admin access required';
  END IF;

  RETURN QUERY
  WITH RECURSIVE
  commission_percents AS (
    SELECT mcr.level AS lvl, mcr.percent AS pct
    FROM mlm_commission_rules mcr
    WHERE mcr.structure_type = 1 AND mcr.plan_id = 'default' AND mcr.is_active = true
  ),
  referral_tree AS (
    SELECT r.referred_user_id, r.referrer_id, 1 AS lvl
    FROM referrals r
    WHERE r.referrer_id = p_user_id AND r.structure_type = 1
    UNION ALL
    SELECT r.referred_user_id, r.referrer_id, rt.lvl + 1
    FROM referrals r
    INNER JOIN referral_tree rt ON r.referrer_id = rt.referred_user_id
    WHERE r.structure_type = 1 AND rt.lvl < 5
  ),
  network_subscriptions AS (
    SELECT s.id AS sub_id, s.user_id AS p_id, p.full_name AS p_name, p.email AS p_email,
           rt.lvl, s.amount_kzt, s.is_marketing_free_access
    FROM referral_tree rt
    INNER JOIN profiles p ON p.id = rt.referred_user_id
    INNER JOIN subscriptions s ON s.user_id = rt.referred_user_id
    WHERE s.status = 'active' AND s.paid_at IS NOT NULL
  ),
  expected_commissions AS (
    SELECT ns.sub_id, ns.p_id, ns.p_name, ns.p_email, ns.lvl, ns.amount_kzt,
           ns.is_marketing_free_access, COALESCE(cp.pct, 0) AS exp_pct,
           CASE WHEN ns.is_marketing_free_access = true THEN 0
                ELSE ROUND(ns.amount_kzt * COALESCE(cp.pct, 0) / 100) END AS exp_comm
    FROM network_subscriptions ns
    LEFT JOIN commission_percents cp ON cp.lvl = ns.lvl
  ),
  actual_commissions AS (
    SELECT t.source_id, t.level AS tx_lvl, SUM(t.amount_cents) AS actual_kzt
    FROM transactions t
    WHERE t.user_id = p_user_id AND t.type = 'commission' 
      AND t.structure_type = 'primary' AND t.status IN ('available', 'frozen')
    GROUP BY t.source_id, t.level
  ),
  audit_results AS (
    SELECT ec.sub_id, ec.p_id, ec.p_name, ec.p_email, ec.lvl, ec.amount_kzt,
           ec.exp_pct, ec.exp_comm, ec.is_marketing_free_access,
           COALESCE(ac.actual_kzt, 0) AS actual_kzt
    FROM expected_commissions ec
    LEFT JOIN actual_commissions ac ON ac.source_id = ec.sub_id AND ac.tx_lvl = ec.lvl
  )
  SELECT ar.sub_id, ar.p_id, ar.p_name, ar.p_email, ar.lvl, ar.amount_kzt,
         ar.exp_pct, ar.exp_comm, (ar.actual_kzt > 0),
         ar.actual_kzt,
         CASE WHEN ar.is_marketing_free_access THEN 'marketing_free_access'
              WHEN ar.actual_kzt = 0 AND ar.exp_comm > 0 THEN 'no_commission' ELSE NULL END,
         CASE WHEN ar.is_marketing_free_access THEN 'SKIPPED (free access)'
              WHEN ar.exp_comm = 0 THEN 'N/A'
              WHEN ABS(ar.actual_kzt - ar.exp_comm) < 100 THEN 'OK'
              WHEN ar.actual_kzt > ar.exp_comm THEN 'OVERPAID'
              WHEN ar.actual_kzt < ar.exp_comm THEN 'UNDERPAID' ELSE 'UNKNOWN' END
  FROM audit_results ar ORDER BY ar.lvl, ar.p_name;
END;
$$;
