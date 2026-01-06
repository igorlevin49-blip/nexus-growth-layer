
-- Drop and recreate get_referral_network_from_table to add marketing_free_access check
DROP FUNCTION IF EXISTS public.get_referral_network_from_table(UUID, INT, INT);

CREATE OR REPLACE FUNCTION public.get_referral_network_from_table(
  root_user_id UUID,
  max_level INT DEFAULT 10,
  p_structure_type INT DEFAULT 1
)
RETURNS TABLE (
  user_id UUID,
  partner_id TEXT,
  level INT,
  full_name TEXT,
  email TEXT,
  phone TEXT,
  avatar_url TEXT,
  subscription_status TEXT,
  subscription_expires_at TIMESTAMPTZ,
  monthly_activation_met BOOLEAN,
  referral_code TEXT,
  created_at TIMESTAMPTZ,
  direct_referrals BIGINT,
  total_team BIGINT,
  monthly_volume NUMERIC,
  parent_partner_id TEXT,
  parent_user_id UUID,
  has_commission_received BOOLEAN,
  no_commission_reason TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_current_month_start DATE;
  v_active_root_direct_count INT;
BEGIN
  -- Get current month start for commission checks
  v_current_month_start := date_trunc('month', CURRENT_DATE)::DATE;
  
  -- Count active direct referrals for the root user (for level unlock checks)
  SELECT COUNT(*)
  INTO v_active_root_direct_count
  FROM referrals r
  JOIN profiles p ON p.id = r.referred_id
  WHERE r.referrer_id = root_user_id
    AND r.structure_type = p_structure_type
    AND r.level = 1
    AND p.subscription_status = 'active';

  RETURN QUERY
  WITH RECURSIVE network AS (
    -- Base case: direct referrals of root user
    SELECT 
      r.referred_id as user_id,
      r.level,
      r.referrer_id as parent_id
    FROM referrals r
    WHERE r.referrer_id = root_user_id
      AND r.structure_type = p_structure_type
      AND r.level = 1
    
    UNION ALL
    
    -- Recursive case: referrals of referrals
    SELECT 
      r.referred_id as user_id,
      n.level + 1 as level,
      r.referrer_id as parent_id
    FROM referrals r
    INNER JOIN network n ON r.referrer_id = n.user_id
    WHERE r.structure_type = p_structure_type
      AND r.level = 1
      AND n.level < max_level
  ),
  -- Get monthly activation status for all users in network
  monthly_activations_cte AS (
    SELECT 
      ma.user_id,
      ma.is_activated
    FROM monthly_activations ma
    WHERE ma.month_start = v_current_month_start
  ),
  -- Get users with marketing free access
  marketing_free_access AS (
    SELECT DISTINCT s.user_id
    FROM subscriptions s
    WHERE s.status = 'active'
      AND s.is_marketing_free_access = true
  ),
  -- Get commission info for this month from root user's perspective
  commission_info AS (
    SELECT 
      t.payload->>'from_user_id' as from_user_id,
      TRUE as has_commission
    FROM transactions t
    WHERE t.user_id = root_user_id
      AND t.type IN ('commission', 'secondary')
      AND t.created_at >= v_current_month_start
      AND t.payload->>'from_user_id' IS NOT NULL
    GROUP BY t.payload->>'from_user_id'
  ),
  -- Count direct referrals for each user
  direct_counts AS (
    SELECT 
      r.referrer_id,
      COUNT(*) as direct_count
    FROM referrals r
    WHERE r.structure_type = p_structure_type
      AND r.level = 1
    GROUP BY r.referrer_id
  ),
  -- Calculate total team for each user
  team_counts AS (
    SELECT 
      n.user_id,
      (
        SELECT COUNT(*)
        FROM referrals r2
        WHERE r2.referrer_id = n.user_id
          AND r2.structure_type = p_structure_type
      ) as total_team
    FROM network n
  ),
  -- Get monthly volume (sum of orders this month)
  monthly_volumes AS (
    SELECT 
      o.user_id,
      COALESCE(SUM(o.total_amount), 0) as volume
    FROM orders o
    WHERE o.status = 'completed'
      AND o.created_at >= v_current_month_start
    GROUP BY o.user_id
  )
  SELECT 
    n.user_id,
    p.partner_id,
    n.level,
    p.full_name,
    p.email,
    p.phone,
    p.avatar_url,
    p.subscription_status,
    p.subscription_expires_at,
    COALESCE(mac.is_activated, FALSE) as monthly_activation_met,
    p.referral_code,
    p.created_at,
    COALESCE(dc.direct_count, 0)::BIGINT as direct_referrals,
    COALESCE(tc.total_team, 0)::BIGINT as total_team,
    COALESCE(mv.volume, 0) as monthly_volume,
    parent_p.partner_id as parent_partner_id,
    n.parent_id as parent_user_id,
    COALESCE(ci.has_commission, FALSE) as has_commission_received,
    CASE
      -- Level unlock checks (for S1 structure)
      WHEN p_structure_type = 1 AND n.level = 2 AND v_active_root_direct_count < 2 THEN 'level_2_locked'
      WHEN p_structure_type = 1 AND n.level = 3 AND v_active_root_direct_count < 3 THEN 'level_3_locked'
      WHEN p_structure_type = 1 AND n.level = 4 AND v_active_root_direct_count < 4 THEN 'level_4_locked'
      WHEN p_structure_type = 1 AND n.level = 5 AND v_active_root_direct_count < 5 THEN 'level_5_locked'
      WHEN p_structure_type = 1 AND n.level > 5 THEN 'too_deep'
      -- Partner status checks
      WHEN p.subscription_status != 'active' THEN 'no_active_subscription'
      -- Marketing free access (check BEFORE monthly activation!)
      WHEN mfa.user_id IS NOT NULL THEN 'marketing_free_access'
      -- Monthly activation check
      WHEN NOT COALESCE(mac.is_activated, FALSE) THEN 'no_payment_this_month'
      -- Commission already received
      WHEN COALESCE(ci.has_commission, FALSE) THEN NULL
      ELSE NULL
    END as no_commission_reason
  FROM network n
  JOIN profiles p ON p.id = n.user_id
  LEFT JOIN profiles parent_p ON parent_p.id = n.parent_id
  LEFT JOIN monthly_activations_cte mac ON mac.user_id = n.user_id
  LEFT JOIN marketing_free_access mfa ON mfa.user_id = n.user_id
  LEFT JOIN commission_info ci ON ci.from_user_id = n.user_id::TEXT
  LEFT JOIN direct_counts dc ON dc.referrer_id = n.user_id
  LEFT JOIN team_counts tc ON tc.user_id = n.user_id
  LEFT JOIN monthly_volumes mv ON mv.user_id = n.user_id
  ORDER BY n.level, p.created_at;
END;
$$;
