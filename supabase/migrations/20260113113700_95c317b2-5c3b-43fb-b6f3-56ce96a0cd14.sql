-- Исправляем функцию с правильным приведением типов
DROP FUNCTION IF EXISTS reconcile_s1_commissions(uuid, integer, timestamptz, timestamptz);

CREATE OR REPLACE FUNCTION reconcile_s1_commissions(
  p_sponsor_id uuid,
  p_depth integer DEFAULT 5,
  p_from_date timestamptz DEFAULT NULL,
  p_to_date timestamptz DEFAULT NULL
)
RETURNS TABLE (
  subscriber_id uuid,
  subscriber_name text,
  subscriber_email text,
  network_level integer,
  subscription_id uuid,
  subscription_status text,
  paid_at timestamptz,
  amount_kzt numeric,
  is_marketing_free_access boolean,
  expected_commission_kzt numeric,
  actual_transaction_id uuid,
  actual_status text,
  actual_amount_kzt numeric,
  missing_reason text
) AS $$
DECLARE
  v_sponsor_sub_started timestamptz;
BEGIN
  SELECT started_at INTO v_sponsor_sub_started
  FROM subscriptions WHERE user_id = p_sponsor_id AND status = 'active'
  ORDER BY started_at ASC LIMIT 1;

  RETURN QUERY
  WITH RECURSIVE sponsor_network AS (
    SELECT r.referred_user_id AS user_id, 1 AS lvl
    FROM referrals r WHERE r.referrer_id = p_sponsor_id AND r.structure_type = 1
    UNION ALL
    SELECT r.referred_user_id, sn.lvl + 1
    FROM sponsor_network sn
    JOIN referrals r ON r.referrer_id = sn.user_id AND r.structure_type = 1
    WHERE sn.lvl < p_depth
  ),
  commission_rules AS (
    SELECT mcr.level AS rule_level, mcr.percent AS rule_percent
    FROM mlm_commission_rules mcr
    WHERE mcr.structure_type = 1 AND mcr.is_active = true AND mcr.plan_id = 'default'
  ),
  network_subscriptions AS (
    SELECT DISTINCT ON (sn.user_id)
      sn.user_id, sn.lvl, s.id AS sub_id, s.status AS sub_status,
      s.paid_at AS sub_paid_at, s.amount_kzt AS sub_amount_kzt,
      COALESCE(s.is_marketing_free_access, false) AS is_free,
      p.full_name, p.email
    FROM sponsor_network sn
    JOIN subscriptions s ON s.user_id = sn.user_id
    JOIN profiles p ON p.id = sn.user_id
    WHERE s.status = 'active' AND s.paid_at IS NOT NULL
      AND (p_from_date IS NULL OR s.paid_at >= p_from_date)
      AND (p_to_date IS NULL OR s.paid_at <= p_to_date)
    ORDER BY sn.user_id, s.paid_at DESC
  ),
  existing_commissions AS (
    SELECT t.id AS tx_id, t.source_id, t.status::text AS tx_status,
           t.amount_cents AS tx_amount, t.level AS tx_level
    FROM transactions t
    WHERE t.user_id = p_sponsor_id AND t.type = 'commission'
      AND t.structure_type = 'primary' AND t.source_id IS NOT NULL
  )
  SELECT 
    ns.user_id, ns.full_name, ns.email, ns.lvl, ns.sub_id, ns.sub_status,
    ns.sub_paid_at, ns.sub_amount_kzt, ns.is_free,
    CASE WHEN ns.is_free THEN 0 ELSE COALESCE(ns.sub_amount_kzt * cr.rule_percent / 100, 0) END,
    ec.tx_id, ec.tx_status, ec.tx_amount,
    CASE
      WHEN ns.is_free THEN 'marketing_free_access'
      WHEN v_sponsor_sub_started IS NULL THEN 'sponsor_no_subscription'
      WHEN ns.sub_paid_at < v_sponsor_sub_started THEN 'paid_before_sponsor_subscription'
      WHEN ec.tx_id IS NOT NULL AND ec.tx_status = 'completed' THEN 'OK'
      WHEN ec.tx_id IS NOT NULL AND ec.tx_status = 'frozen' THEN 'frozen'
      WHEN ec.tx_id IS NOT NULL AND ec.tx_status = 'failed' THEN 'failed'
      ELSE 'missing_commission'
    END
  FROM network_subscriptions ns
  LEFT JOIN commission_rules cr ON cr.rule_level = ns.lvl
  LEFT JOIN existing_commissions ec ON ec.source_id = ns.sub_id AND ec.tx_level = ns.lvl
  ORDER BY ns.lvl, ns.sub_paid_at DESC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

GRANT EXECUTE ON FUNCTION reconcile_s1_commissions TO authenticated;