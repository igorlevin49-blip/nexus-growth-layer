-- =====================================================
-- FULL FIX: Restore referral network tree with complete business logic
-- 1) Allow access for admin + superadmin
-- 2) Restore no_commission_reason (including marketing_free_access)
-- 3) Restore commission status from transactions
-- 4) Fix structure_type type handling (integer vs enum)
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
DECLARE
  v_structure_enum structure_type;
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

  -- Map integer structure_type to enum for transactions table comparison
  v_structure_enum := CASE p_structure_type 
    WHEN 1 THEN 'primary'::structure_type 
    WHEN 2 THEN 'secondary'::structure_type 
    ELSE 'primary'::structure_type 
  END;

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
  -- Count direct referrals per user in this structure
  direct_counts AS (
    SELECT r.referrer_id, COUNT(*)::bigint AS cnt
    FROM public.referrals r
    WHERE r.structure_type = p_structure_type
    GROUP BY r.referrer_id
  ),
  -- Monthly activation status from monthly_activations table (source of truth)
  monthly_status AS (
    SELECT 
      ma.user_id,
      ma.is_met
    FROM public.monthly_activations ma
    WHERE ma.period_start <= now() 
      AND ma.period_end >= now()
  ),
  -- Marketing free access from subscriptions
  marketing_free AS (
    SELECT DISTINCT s.user_id
    FROM public.subscriptions s
    WHERE s.is_marketing_free_access = true
      AND s.status = 'active'
  ),
  -- Commission info from transactions (using correct enum type)
  commission_info AS (
    SELECT 
      t.referral_id AS ref_user_id,
      true AS has_commission,
      t.status AS comm_status,
      t.frozen_until AS comm_frozen_until
    FROM public.transactions t
    WHERE t.type = 'commission'
      AND t.structure_type = v_structure_enum
      AND t.created_at >= date_trunc('month', now())
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
    -- Use monthly_activations as source of truth, fallback to profile
    COALESCE(ms.is_met, p.monthly_activation_completed, false) AS monthly_activation_met,
    p.referral_code,
    COALESCE(p.created_at, now()) AS created_at,
    COALESCE(dc.cnt, 0) AS direct_referrals,
    0::bigint AS total_team,
    0::numeric AS monthly_volume,
    parent_p.referral_code AS parent_partner_id,
    n.parent_id AS parent_user_id,
    -- Commission fields
    ci.has_commission AS has_commission_received,
    -- Calculate no_commission_reason
    CASE
      WHEN mf.user_id IS NOT NULL THEN 'marketing_free_access'
      WHEN p.subscription_status IS NULL OR p.subscription_status NOT IN ('active', 'trialing') THEN 'no_active_subscription'
      WHEN COALESCE(ms.is_met, p.monthly_activation_completed, false) = false THEN 'monthly_activation_not_met'
      WHEN ci.comm_status = 'frozen' THEN 'commission_frozen'
      ELSE NULL
    END AS no_commission_reason,
    ci.comm_status AS commission_status,
    ci.comm_frozen_until AS commission_frozen_until
  FROM network n
  JOIN public.profiles p ON p.id = n.user_id
  LEFT JOIN public.profiles parent_p ON parent_p.id = n.parent_id
  LEFT JOIN direct_counts dc ON dc.referrer_id = n.user_id
  LEFT JOIN monthly_status ms ON ms.user_id = n.user_id
  LEFT JOIN marketing_free mf ON mf.user_id = n.user_id
  LEFT JOIN commission_info ci ON ci.ref_user_id = n.user_id
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

-- Diagnostic function for admins to debug empty trees
CREATE OR REPLACE FUNCTION public.get_network_debug_report(p_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  result jsonb;
BEGIN
  -- Only admin/superadmin can run diagnostics
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
    'monthly_activation_met', (SELECT is_met FROM monthly_activations WHERE user_id = p_user_id AND period_start <= now() AND period_end >= now() LIMIT 1),
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