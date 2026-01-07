
-- Fix get_referral_network_from_table to properly determine no_commission_reason
-- The reason should be based on WHY the SPONSOR (current user) didn't receive commission FROM this partner

CREATE OR REPLACE FUNCTION get_referral_network_from_table(
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
DECLARE
  root_subscription_status text;
  root_activation_met boolean;
  root_direct_referrals integer;
BEGIN
  -- Get root user's status to determine if they can receive commissions
  SELECT 
    p.subscription_status,
    COALESCE(ma.is_activated, false),
    COALESCE(p.direct_referrals_count, 0)
  INTO root_subscription_status, root_activation_met, root_direct_referrals
  FROM profiles p
  LEFT JOIN monthly_activations ma ON ma.user_id = p.id 
    AND ma.year = EXTRACT(YEAR FROM CURRENT_DATE)::integer
    AND ma.month = EXTRACT(MONTH FROM CURRENT_DATE)::integer
  WHERE p.id = root_user_id;

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
  -- Get current month activation status for each member
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
  ),
  -- Check if partner was from marketing free access
  marketing_free_subs AS (
    SELECT DISTINCT user_id AS uid
    FROM subscriptions
    WHERE is_marketing_free_access = true
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
    COALESCE(ca.is_activated, p.monthly_activation_completed, false) AS monthly_activation_met,
    p.referral_code,
    p.created_at,
    COALESCE(dc.cnt, 0) AS direct_referrals,
    0 AS total_team,
    0::numeric AS monthly_volume,
    parent_p.referral_code AS parent_partner_id,
    n.parent_uid AS parent_user_id,
    -- Commission received logic: did the ROOT USER receive commission from this partner?
    CASE 
      -- Root user must have active subscription
      WHEN root_subscription_status != 'active' THEN false
      -- Root user must have current month activation (for structure 1)
      WHEN p_structure_type = 1 AND NOT root_activation_met THEN false
      -- Partner must have active subscription
      WHEN p.subscription_status != 'active' THEN false
      -- Partner must have paid this month (for structure 1)
      WHEN p_structure_type = 1 AND NOT COALESCE(ca.is_activated, p.monthly_activation_completed, false) THEN false
      -- Marketing free access partners don't generate commissions
      WHEN mfs.uid IS NOT NULL THEN false
      -- Level unlock requirements (structure 1 only)
      WHEN p_structure_type = 1 AND n.lvl = 2 AND root_direct_referrals < 2 THEN false
      WHEN p_structure_type = 1 AND n.lvl = 3 AND root_direct_referrals < 3 THEN false
      WHEN p_structure_type = 1 AND n.lvl = 4 AND root_direct_referrals < 4 THEN false
      WHEN p_structure_type = 1 AND n.lvl = 5 AND root_direct_referrals < 5 THEN false
      WHEN p_structure_type = 1 AND n.lvl > 5 THEN false
      ELSE true
    END AS has_commission_received,
    -- Reason for no commission (from perspective of ROOT USER)
    CASE 
      -- Root user issues first
      WHEN root_subscription_status != 'active' THEN 'sponsor_inactive'
      WHEN p_structure_type = 1 AND NOT root_activation_met THEN 'sponsor_no_activation'
      -- Partner issues
      WHEN p.subscription_status != 'active' AND p.subscription_status = 'pending' THEN 'not_activated'
      WHEN p.subscription_status != 'active' THEN 'no_active_subscription'
      WHEN p_structure_type = 1 AND NOT COALESCE(ca.is_activated, p.monthly_activation_completed, false) THEN 'no_payment_this_month'
      -- Marketing free
      WHEN mfs.uid IS NOT NULL THEN 'marketing_free_access'
      -- Level locks (structure 1)
      WHEN p_structure_type = 1 AND n.lvl = 2 AND root_direct_referrals < 2 THEN 'level_2_locked'
      WHEN p_structure_type = 1 AND n.lvl = 3 AND root_direct_referrals < 3 THEN 'level_3_locked'
      WHEN p_structure_type = 1 AND n.lvl = 4 AND root_direct_referrals < 4 THEN 'level_4_locked'
      WHEN p_structure_type = 1 AND n.lvl = 5 AND root_direct_referrals < 5 THEN 'level_5_locked'
      WHEN p_structure_type = 1 AND n.lvl > 5 THEN 'too_deep'
      ELSE NULL
    END AS no_commission_reason
  FROM network n
  JOIN profiles p ON p.id = n.uid
  LEFT JOIN profiles parent_p ON parent_p.id = n.parent_uid
  LEFT JOIN current_activations ca ON ca.uid = n.uid
  LEFT JOIN direct_counts dc ON dc.referrer_id = n.uid
  LEFT JOIN marketing_free_subs mfs ON mfs.uid = n.uid
  WHERE p.is_active = true
    AND p.deleted_at IS NULL
  ORDER BY n.lvl, p.created_at;
END;
$$;

-- Ensure the wrapper function also exists
CREATE OR REPLACE FUNCTION get_referral_network_from_table(
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
  RETURN QUERY SELECT * FROM get_referral_network_from_table(root_user_id, max_level, 1);
END;
$$;
