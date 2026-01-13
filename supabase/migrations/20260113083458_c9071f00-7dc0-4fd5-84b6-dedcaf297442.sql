
-- Fix get_referral_network_from_table to use correct table name 'referrals' 
-- (not 'referral_network' which doesn't exist)
-- Fields: referrer_id (sponsor), referred_user_id (referral), structure_type

CREATE OR REPLACE FUNCTION public.get_referral_network_from_table(
  root_user_id uuid,
  p_max_levels integer DEFAULT 10,
  p_structure_type integer DEFAULT 1
)
RETURNS TABLE (
  id uuid,
  full_name text,
  avatar_url text,
  level integer,
  parent_id uuid,
  subscription_status text,
  subscription_expires_at timestamptz,
  personal_activation_volume numeric,
  has_commission_received boolean,
  no_commission_reason text,
  commission_frozen_until timestamptz,
  is_activated boolean,
  created_at timestamptz
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
      r.referred_user_id AS id,
      1 AS lvl,
      r.referrer_id AS parent
    FROM referrals r
    WHERE r.referrer_id = root_user_id
      AND r.structure_type = p_structure_type
    
    UNION ALL
    
    -- Recursive case: referrals of referrals
    SELECT 
      r.referred_user_id AS id,
      net.lvl + 1 AS lvl,
      r.referrer_id AS parent
    FROM referrals r
    INNER JOIN network net ON r.referrer_id = net.id
    WHERE r.structure_type = p_structure_type
      AND net.lvl < p_max_levels
  )
  SELECT 
    n.id,
    p.full_name,
    p.avatar_url,
    n.lvl AS level,
    n.parent AS parent_id,
    p.subscription_status,
    p.subscription_expires_at,
    COALESCE(p.personal_activation_volume, 0) AS personal_activation_volume,
    -- Check if commission was received for this partner
    EXISTS (
      SELECT 1 FROM transactions t 
      WHERE t.user_id = root_user_id 
        AND t.source_user_id = n.id
        AND t.type = 'commission'
        AND t.source_ref LIKE 'subscription_%_s1_level_%'
    ) AS has_commission_received,
    -- Determine reason for no commission - with is_marketing_free_access check
    CASE 
      WHEN s.is_marketing_free_access = true THEN 'marketing_free_access'
      WHEN p.subscription_status IS NULL OR p.subscription_status != 'active' THEN 'partner_no_subscription'
      WHEN p_structure_type = 2 AND p.monthly_activation_completed IS NOT TRUE THEN 'partner_no_activation'
      ELSE NULL
    END AS no_commission_reason,
    -- Get commission frozen until date if exists
    (
      SELECT t.frozen_until FROM transactions t 
      WHERE t.user_id = root_user_id 
        AND t.source_user_id = n.id
        AND t.type = 'commission'
        AND t.status = 'frozen'
      ORDER BY t.created_at DESC
      LIMIT 1
    ) AS commission_frozen_until,
    COALESCE(p.monthly_activation_completed, false) AS is_activated,
    p.created_at
  FROM network n
  JOIN profiles p ON p.id = n.id
  LEFT JOIN subscriptions s ON s.user_id = n.id AND s.status = 'active'
  ORDER BY n.lvl, p.full_name;
END;
$$;
