-- First drop existing functions to allow signature change
DROP FUNCTION IF EXISTS public.get_referral_network_from_table(uuid, integer, integer);
DROP FUNCTION IF EXISTS public.get_referral_network_from_table(uuid, integer);

-- Recreate function with correct column references
CREATE OR REPLACE FUNCTION public.get_referral_network_from_table(
  root_user_id uuid,
  max_level integer DEFAULT 10,
  p_structure_type integer DEFAULT 1
)
RETURNS TABLE(
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
  direct_referrals integer,
  total_team integer,
  monthly_volume numeric,
  parent_partner_id text,
  parent_user_id uuid,
  has_commission_received boolean,
  no_commission_reason text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  WITH RECURSIVE network AS (
    -- Base case: direct referrals of root user
    SELECT 
      r.referred_user_id AS uid,
      root_user_id AS parent_uid,
      1 AS lvl
    FROM referrals r
    WHERE r.referrer_id = root_user_id
      AND r.structure_type = p_structure_type
    
    UNION ALL
    
    -- Recursive case: referrals of referrals
    SELECT 
      r.referred_user_id AS uid,
      n.uid AS parent_uid,
      n.lvl + 1 AS lvl
    FROM referrals r
    JOIN network n ON r.referrer_id = n.uid
    WHERE n.lvl < max_level
      AND r.structure_type = p_structure_type
  ),
  -- Get current month activation status
  current_activations AS (
    SELECT 
      ma.user_id AS uid,
      ma.is_activated
    FROM monthly_activations ma
    WHERE ma.year = EXTRACT(YEAR FROM CURRENT_DATE)::integer
      AND ma.month = EXTRACT(MONTH FROM CURRENT_DATE)::integer
  ),
  -- Count direct referrals for each member
  direct_counts AS (
    SELECT 
      r.referrer_id,
      COUNT(*)::integer AS cnt
    FROM referrals r
    WHERE r.structure_type = p_structure_type
    GROUP BY r.referrer_id
  )
  SELECT 
    n.uid AS user_id,
    p.referral_code AS partner_id,
    n.lvl AS level,
    p.full_name,
    p.email,
    p.phone,
    p.avatar_url,
    p.subscription_status,
    p.subscription_expires_at,
    COALESCE(ca.is_activated, false) AS monthly_activation_met,
    p.referral_code,
    p.created_at,
    COALESCE(dc.cnt, 0) AS direct_referrals,
    0 AS total_team,
    0::numeric AS monthly_volume,
    parent_p.referral_code AS parent_partner_id,
    n.parent_uid AS parent_user_id,
    -- Commission logic
    CASE 
      WHEN p.subscription_status != 'active' THEN false
      WHEN NOT COALESCE(ca.is_activated, false) THEN false
      ELSE true
    END AS has_commission_received,
    -- Reason for no commission
    CASE 
      WHEN p.subscription_status != 'active' THEN 'no_subscription'
      WHEN NOT COALESCE(ca.is_activated, false) THEN 'no_activation'
      ELSE NULL
    END AS no_commission_reason
  FROM network n
  JOIN profiles p ON p.id = n.uid
  LEFT JOIN profiles parent_p ON parent_p.id = n.parent_uid
  LEFT JOIN current_activations ca ON ca.uid = n.uid
  LEFT JOIN direct_counts dc ON dc.referrer_id = n.uid
  WHERE p.is_active = true
    AND p.deleted_at IS NULL
  ORDER BY n.lvl, p.created_at;
END;
$$;

-- Create wrapper for old signature (without structure_type)
CREATE OR REPLACE FUNCTION public.get_referral_network_from_table(
  root_user_id uuid,
  max_level integer
)
RETURNS TABLE(
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
  direct_referrals integer,
  total_team integer,
  monthly_volume numeric,
  parent_partner_id text,
  parent_user_id uuid,
  has_commission_received boolean,
  no_commission_reason text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT * FROM public.get_referral_network_from_table(root_user_id, max_level, 1);
END;
$$;