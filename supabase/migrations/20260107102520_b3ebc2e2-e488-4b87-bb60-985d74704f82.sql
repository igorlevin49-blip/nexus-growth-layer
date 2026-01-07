-- =====================================================
-- FIX: Restore referral network tree (schema-safe)
-- Reason: previous version referenced non-existent columns
-- (referrals.referral_id, transactions.amount, transactions.referral_user_id, etc.)
-- which caused the RPC to fail and the UI to show "Не удалось загрузить структуру".
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
  -- Access control: allow self or admins
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  IF auth.uid() <> root_user_id AND NOT public.has_role(auth.uid(), 'admin'::app_role) THEN
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
  )
  SELECT
    n.user_id,
    -- Use referral_code as stable partner_id for UI tree linking
    p.referral_code AS partner_id,
    n.lvl AS level,
    COALESCE(p.full_name, '') AS full_name,
    p.email,
    p.phone,
    p.avatar_url,
    p.subscription_status,
    p.subscription_expires_at,
    COALESCE(p.monthly_activation_completed, false) AS monthly_activation_met,
    p.referral_code,
    COALESCE(p.created_at, now()) AS created_at,
    COALESCE(dc.cnt, 0) AS direct_referrals,
    0::bigint AS total_team,
    0::numeric AS monthly_volume,
    parent_p.referral_code AS parent_partner_id,
    n.parent_id AS parent_user_id,
    NULL::boolean AS has_commission_received,
    NULL::text AS no_commission_reason,
    NULL::text AS commission_status,
    NULL::timestamptz AS commission_frozen_until
  FROM network n
  JOIN public.profiles p ON p.id = n.user_id
  LEFT JOIN public.profiles parent_p ON parent_p.id = n.parent_id
  LEFT JOIN direct_counts dc ON dc.referrer_id = n.user_id
  ORDER BY n.lvl, p.created_at;
END;
$$;

-- Keep backward-compatible overload used by some clients
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
