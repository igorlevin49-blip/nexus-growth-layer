
-- Fix get_referral_network_from_table function: column name error
-- r.referral_id should be r.referred_user_id

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
  no_commission_reason text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_current_month_start date;
  v_current_month_end date;
  root_is_active boolean;
BEGIN
  -- Calculate current month boundaries
  v_current_month_start := date_trunc('month', CURRENT_DATE)::date;
  v_current_month_end := (date_trunc('month', CURRENT_DATE) + interval '1 month' - interval '1 day')::date;
  
  -- Check if root user has active subscription
  SELECT p.subscription_status = 'active' INTO root_is_active
  FROM profiles p WHERE p.id = root_user_id;
  
  RETURN QUERY
  WITH RECURSIVE network AS (
    -- Base case: direct referrals of root user for the specified structure
    SELECT 
      r.referred_user_id as user_id,
      r.referrer_id as parent_id,
      1 as level
    FROM referrals r
    WHERE r.referrer_id = root_user_id
      AND r.structure_type = p_structure_type
    
    UNION ALL
    
    -- Recursive case: referrals of referrals
    SELECT 
      r.referred_user_id as user_id,
      r.referrer_id as parent_id,
      n.level + 1 as level
    FROM referrals r
    INNER JOIN network n ON r.referrer_id = n.user_id
    WHERE n.level < max_level
      AND r.structure_type = p_structure_type
  ),
  -- Join with profiles to get user details
  network_with_profiles AS (
    SELECT 
      n.user_id,
      n.parent_id,
      n.level,
      p.full_name,
      p.email,
      p.phone,
      p.avatar_url,
      p.subscription_status,
      p.subscription_expires_at,
      p.referral_code,
      p.created_at,
      COALESCE((
        SELECT s.is_marketing_free_access 
        FROM subscriptions s 
        WHERE s.user_id = p.id AND s.status = 'active' 
        ORDER BY s.created_at DESC LIMIT 1
      ), false) as is_marketing_free_access,
      p.activation_due_from
    FROM network n
    JOIN profiles p ON p.id = n.user_id
    WHERE p.is_active = true 
      AND p.deleted_at IS NULL 
      AND COALESCE(p.is_archived, false) = false
  ),
  -- Get monthly activation status
  network_with_activation AS (
    SELECT 
      nwp.*,
      COALESCE(ma.is_activated, false) as monthly_activation_met
    FROM network_with_profiles nwp
    LEFT JOIN monthly_activations ma ON ma.user_id = nwp.user_id
      AND ma.year = EXTRACT(YEAR FROM CURRENT_DATE)::int
      AND ma.month = EXTRACT(MONTH FROM CURRENT_DATE)::int
  ),
  -- Get parent partner IDs
  network_with_parents AS (
    SELECT 
      nwa.*,
      parent_p.referral_code as parent_partner_id
    FROM network_with_activation nwa
    LEFT JOIN profiles parent_p ON parent_p.id = nwa.parent_id
  ),
  -- Calculate direct referrals count for each member (only active subscriptions)
  direct_counts AS (
    SELECT 
      r.referrer_id,
      COUNT(*) as direct_count
    FROM referrals r
    JOIN profiles p ON p.id = r.referred_user_id
    WHERE r.structure_type = p_structure_type
      AND p.subscription_status = 'active'
      AND p.is_active = true
      AND p.deleted_at IS NULL
      AND COALESCE(p.is_archived, false) = false
    GROUP BY r.referrer_id
  ),
  -- Calculate total team size for each member  
  team_counts AS (
    SELECT 
      nwp.user_id,
      (
        WITH RECURSIVE team AS (
          SELECT r.referred_user_id
          FROM referrals r
          JOIN profiles p ON p.id = r.referred_user_id
          WHERE r.referrer_id = nwp.user_id
            AND r.structure_type = p_structure_type
            AND p.is_active = true
            AND p.deleted_at IS NULL
            AND COALESCE(p.is_archived, false) = false
          UNION ALL
          SELECT r.referred_user_id
          FROM referrals r
          JOIN profiles p ON p.id = r.referred_user_id
          INNER JOIN team t ON r.referrer_id = t.referred_user_id
          WHERE r.structure_type = p_structure_type
            AND p.is_active = true
            AND p.deleted_at IS NULL
            AND COALESCE(p.is_archived, false) = false
        )
        SELECT COUNT(*) FROM team
      ) as total_team
    FROM network_with_profiles nwp
  ),
  -- Calculate monthly volume for each member
  monthly_volumes AS (
    SELECT 
      o.user_id,
      COALESCE(SUM(o.total_kzt), 0) as monthly_volume
    FROM orders o
    WHERE o.status = 'completed'
      AND o.paid_at >= v_current_month_start
      AND o.paid_at < v_current_month_end + interval '1 day'
      AND COALESCE(o.is_archived, false) = false
    GROUP BY o.user_id
  )
  SELECT 
    nwp.user_id,
    nwp.referral_code as partner_id,
    nwp.level,
    nwp.full_name,
    nwp.email,
    nwp.phone,
    nwp.avatar_url,
    nwp.subscription_status,
    nwp.subscription_expires_at,
    nwp.monthly_activation_met,
    nwp.referral_code,
    nwp.created_at,
    COALESCE(dc.direct_count, 0)::bigint as direct_referrals,
    COALESCE(tc.total_team, 0)::bigint as total_team,
    COALESCE(mv.monthly_volume, 0)::numeric as monthly_volume,
    nwp.parent_partner_id,
    nwp.parent_id as parent_user_id,
    -- Determine if commission was/would be received
    CASE
      WHEN p_structure_type != 1 THEN NULL
      WHEN nwp.subscription_status != 'active' THEN false
      WHEN nwp.is_marketing_free_access = true THEN false
      WHEN nwp.level > 5 THEN false
      WHEN nwp.level >= 2 AND COALESCE(dc_root.direct_count, 0) < 2 THEN false
      WHEN nwp.level >= 3 AND COALESCE(dc_root.direct_count, 0) < 3 THEN false
      WHEN nwp.level >= 4 AND COALESCE(dc_root.direct_count, 0) < 4 THEN false
      WHEN nwp.level >= 5 AND COALESCE(dc_root.direct_count, 0) < 5 THEN false
      WHEN NOT root_is_active THEN false
      -- Grace period: if activation_due_from is in the future, user is OK
      WHEN nwp.activation_due_from IS NOT NULL AND nwp.activation_due_from > CURRENT_TIMESTAMP THEN true
      WHEN NOT nwp.monthly_activation_met THEN false
      ELSE true
    END as has_commission_received,
    -- Reason why commission was not received
    CASE
      WHEN p_structure_type != 1 THEN NULL
      WHEN nwp.subscription_status != 'active' THEN 'not_activated'
      WHEN nwp.is_marketing_free_access = true THEN 'marketing_free_access'
      WHEN nwp.level > 5 THEN 'too_deep'
      WHEN nwp.level >= 2 AND COALESCE(dc_root.direct_count, 0) < 2 THEN 'level_2_locked'
      WHEN nwp.level >= 3 AND COALESCE(dc_root.direct_count, 0) < 3 THEN 'level_3_locked'
      WHEN nwp.level >= 4 AND COALESCE(dc_root.direct_count, 0) < 4 THEN 'level_4_locked'
      WHEN nwp.level >= 5 AND COALESCE(dc_root.direct_count, 0) < 5 THEN 'level_5_locked'
      WHEN NOT root_is_active THEN 'sponsor_inactive'
      -- Grace period: if activation_due_from is in the future, no reason needed
      WHEN nwp.activation_due_from IS NOT NULL AND nwp.activation_due_from > CURRENT_TIMESTAMP THEN NULL
      -- After grace period, check monthly activation
      WHEN NOT nwp.monthly_activation_met THEN 'no_payment_this_month'
      ELSE NULL
    END as no_commission_reason
  FROM network_with_parents nwp
  LEFT JOIN direct_counts dc ON dc.referrer_id = nwp.user_id
  LEFT JOIN team_counts tc ON tc.user_id = nwp.user_id
  LEFT JOIN monthly_volumes mv ON mv.user_id = nwp.user_id
  LEFT JOIN direct_counts dc_root ON dc_root.referrer_id = root_user_id
  ORDER BY nwp.level, nwp.created_at;
END;
$$;
