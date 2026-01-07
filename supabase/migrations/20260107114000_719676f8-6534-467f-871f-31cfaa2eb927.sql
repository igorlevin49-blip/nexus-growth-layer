-- =====================================================
-- HOTFIX: get_referral_network_from_table runtime errors
-- Fixes:
--  - monthly_activations schema mismatch (no period_start/period_end, no is_met)
--  - remove invalid commission_info join (referral_id column does not exist in transactions)
-- Keeps access control + marketing_free_access reason.
-- =====================================================

CREATE OR REPLACE FUNCTION public.get_referral_network_from_table(
  root_user_id uuid,
  max_level integer DEFAULT 10,
  p_structure_type integer DEFAULT 1
)
RETURNS TABLE (
  user_id uuid,
  partner_id text,
  level integer,
  full_name text,
  email text,
  phone text,
  avatar_url text,
  subscription_status text,
  subscription_expires_at timestamptz,
  monthly_activation_met boolean,
  referral_code text,
  created_at timestamptz,
  direct_referrals bigint,
  total_team bigint,
  monthly_volume numeric,
  parent_partner_id text,
  parent_user_id uuid,
  has_commission_received boolean,
  no_commission_reason text,
  commission_status text,
  commission_frozen_until timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Access control: allow self, admin, or superadmin
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  IF auth.uid() <> root_user_id
     AND NOT public.has_role(auth.uid(), 'admin'::app_role)
     AND NOT public.has_role(auth.uid(), 'superadmin'::app_role) THEN
    RAISE EXCEPTION 'Forbidden';
  END IF;

  RETURN QUERY
  WITH RECURSIVE network AS (
    -- Level 1: direct referrals
    SELECT
      r.referred_user_id AS user_id,
      r.referrer_id AS parent_id,
      1 AS lvl
    FROM public.referrals r
    WHERE r.referrer_id = root_user_id
      AND r.structure_type = p_structure_type

    UNION ALL

    -- Next levels
    SELECT
      r.referred_user_id AS user_id,
      r.referrer_id AS parent_id,
      n.lvl + 1 AS lvl
    FROM public.referrals r
    JOIN network n ON r.referrer_id = n.user_id
    WHERE n.lvl < max_level
      AND r.structure_type = p_structure_type
  ),
  direct_counts AS (
    SELECT r.referrer_id, COUNT(*)::bigint AS cnt
    FROM public.referrals r
    WHERE r.structure_type = p_structure_type
    GROUP BY r.referrer_id
  ),
  monthly_status AS (
    SELECT ma.user_id, ma.is_activated
    FROM public.monthly_activations ma
    WHERE ma.year = EXTRACT(YEAR FROM now())::int
      AND ma.month = EXTRACT(MONTH FROM now())::int
  ),
  marketing_free AS (
    SELECT DISTINCT s.user_id
    FROM public.subscriptions s
    WHERE s.is_marketing_free_access = true
      AND s.status = 'active'
  )
  SELECT
    n.user_id,
    p.referral_code AS partner_id,
    n.lvl AS level,
    COALESCE(p.full_name, '') AS full_name,
    p.email,
    p.phone,
    p.avatar_url,
    p.subscription_status,
    p.subscription_expires_at,
    COALESCE(ms.is_activated, p.monthly_activation_completed, false) AS monthly_activation_met,
    p.referral_code,
    COALESCE(p.created_at, now()) AS created_at,
    COALESCE(dc.cnt, 0) AS direct_referrals,
    0::bigint AS total_team,
    0::numeric AS monthly_volume,
    parent_p.referral_code AS parent_partner_id,
    n.parent_id AS parent_user_id,
    NULL::boolean AS has_commission_received,
    CASE
      WHEN mf.user_id IS NOT NULL THEN 'marketing_free_access'
      WHEN p.subscription_status IS NULL OR p.subscription_status NOT IN ('active','trialing') THEN 'not_activated'
      WHEN COALESCE(ms.is_activated, p.monthly_activation_completed, false) = false THEN 'no_payment_this_month'
      ELSE NULL
    END AS no_commission_reason,
    NULL::text AS commission_status,
    NULL::timestamptz AS commission_frozen_until
  FROM network n
  JOIN public.profiles p ON p.id = n.user_id
  LEFT JOIN public.profiles parent_p ON parent_p.id = n.parent_id
  LEFT JOIN direct_counts dc ON dc.referrer_id = n.user_id
  LEFT JOIN monthly_status ms ON ms.user_id = n.user_id
  LEFT JOIN marketing_free mf ON mf.user_id = n.user_id
  ORDER BY n.lvl, p.created_at;
END;
$$;

-- Backward-compatible overload (2 params)
CREATE OR REPLACE FUNCTION public.get_referral_network_from_table(
  root_user_id uuid,
  max_level integer
)
RETURNS TABLE (
  user_id uuid,
  partner_id text,
  level integer,
  full_name text,
  email text,
  phone text,
  avatar_url text,
  subscription_status text,
  subscription_expires_at timestamptz,
  monthly_activation_met boolean,
  referral_code text,
  created_at timestamptz,
  direct_referrals bigint,
  total_team bigint,
  monthly_volume numeric,
  parent_partner_id text,
  parent_user_id uuid,
  has_commission_received boolean,
  no_commission_reason text,
  commission_status text,
  commission_frozen_until timestamptz
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT * FROM public.get_referral_network_from_table(root_user_id, max_level, 1);
$$;

-- HOTFIX: debug report should not reference non-existent monthly_activation columns
CREATE OR REPLACE FUNCTION public.get_network_debug_report(p_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  result jsonb;
BEGIN
  IF NOT public.has_role(auth.uid(), 'admin'::app_role)
     AND NOT public.has_role(auth.uid(), 'superadmin'::app_role) THEN
    RAISE EXCEPTION 'Forbidden';
  END IF;

  SELECT jsonb_build_object(
    'user_id', p_user_id,
    'profile_exists', EXISTS(SELECT 1 FROM profiles WHERE id = p_user_id),
    'referrals_s1_count', (SELECT COUNT(*) FROM referrals WHERE referrer_id = p_user_id AND structure_type = 1),
    'referrals_s2_count', (SELECT COUNT(*) FROM referrals WHERE referrer_id = p_user_id AND structure_type = 2),
    'sponsor_refs_count', (SELECT COUNT(*) FROM profiles WHERE sponsor_id = p_user_id),
    'subscription_status', (SELECT subscription_status FROM profiles WHERE id = p_user_id),
    'subscription_expires_at', (SELECT subscription_expires_at FROM profiles WHERE id = p_user_id),
    'monthly_activation_met', (
      SELECT ma.is_activated
      FROM monthly_activations ma
      WHERE ma.user_id = p_user_id
        AND ma.year = EXTRACT(YEAR FROM now())::int
        AND ma.month = EXTRACT(MONTH FROM now())::int
      LIMIT 1
    ),
    'recent_referrals', (
      SELECT jsonb_agg(jsonb_build_object(
        'referred_user_id', r.referred_user_id,
        'structure_type', r.structure_type,
        'created_at', r.created_at,
        'referred_name', p.full_name
      ))
      FROM (SELECT * FROM referrals WHERE referrer_id = p_user_id ORDER BY created_at DESC LIMIT 5) r
      LEFT JOIN profiles p ON p.id = r.referred_user_id
    ),
    'recent_transactions', (
      SELECT jsonb_agg(jsonb_build_object(
        'type', t.type,
        'amount_cents', t.amount_cents,
        'status', t.status,
        'structure_type', t.structure_type,
        'created_at', t.created_at
      ))
      FROM (SELECT * FROM transactions WHERE user_id = p_user_id ORDER BY created_at DESC LIMIT 5) t
    )
  ) INTO result;

  RETURN result;
END;
$$;