-- Update the function with p_structure_type parameter to include new_partner check
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
  v_active_root_direct_count integer;
BEGIN
  -- Count active direct referrals for the root user
  SELECT COUNT(*)
  INTO v_active_root_direct_count
  FROM referrals r
  JOIN profiles p ON p.id = r.referred_id
  WHERE r.referrer_id = root_user_id
    AND r.structure_type = p_structure_type
    AND p.subscription_status = 'active';

  RETURN QUERY
  WITH RECURSIVE network AS (
    -- Base case: direct referrals of root user
    SELECT 
      r.referred_id as user_id,
      r.referrer_id as parent_id,
      1 as level
    FROM referrals r
    WHERE r.referrer_id = root_user_id
      AND r.structure_type = p_structure_type
    
    UNION ALL
    
    -- Recursive case: referrals of referrals
    SELECT 
      r.referred_id as user_id,
      r.referrer_id as parent_id,
      n.level + 1 as level
    FROM referrals r
    INNER JOIN network n ON r.referrer_id = n.user_id
    WHERE n.level < max_level
      AND r.structure_type = p_structure_type
  ),
  -- Get monthly activation status
  current_month_activations AS (
    SELECT 
      ma.user_id,
      ma.is_activated
    FROM monthly_activations ma
    WHERE ma.month = date_trunc('month', CURRENT_DATE)::date
  ),
  -- Get marketing free access users
  marketing_free_access AS (
    SELECT DISTINCT s.user_id
    FROM subscriptions s
    WHERE s.is_marketing_free_access = true
      AND s.status = 'active'
  ),
  -- Check if user has received commission from this referral
  commission_info AS (
    SELECT 
      t.from_user_id as referred_user_id,
      TRUE as has_commission
    FROM transactions t
    WHERE t.user_id = root_user_id
      AND t.type = 'referral_bonus'
      AND t.created_at >= date_trunc('month', CURRENT_DATE)
    GROUP BY t.from_user_id
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
    COALESCE(ma.is_activated, FALSE) as monthly_activation_met,
    p.referral_code,
    p.created_at,
    (
      SELECT COUNT(*)
      FROM referrals r2
      WHERE r2.referrer_id = n.user_id
        AND r2.structure_type = p_structure_type
    ) as direct_referrals,
    (
      WITH RECURSIVE sub_network AS (
        SELECT r3.referred_id
        FROM referrals r3
        WHERE r3.referrer_id = n.user_id
          AND r3.structure_type = p_structure_type
        UNION ALL
        SELECT r4.referred_id
        FROM referrals r4
        INNER JOIN sub_network sn ON r4.referrer_id = sn.referred_id
        WHERE r4.structure_type = p_structure_type
      )
      SELECT COUNT(*) FROM sub_network
    ) as total_team,
    COALESCE((
      SELECT SUM(o.total_amount)
      FROM orders o
      WHERE o.user_id = n.user_id
        AND o.status = 'completed'
        AND o.created_at >= date_trunc('month', CURRENT_DATE)
    ), 0) as monthly_volume,
    parent_p.partner_id as parent_partner_id,
    n.parent_id as parent_user_id,
    COALESCE(ci.has_commission, FALSE) as has_commission_received,
    CASE
      WHEN n.level = 2 AND v_active_root_direct_count < 2 THEN 'level_2_locked'
      WHEN n.level = 3 AND v_active_root_direct_count < 3 THEN 'level_3_locked'
      WHEN n.level = 4 AND v_active_root_direct_count < 4 THEN 'level_4_locked'
      WHEN n.level = 5 AND v_active_root_direct_count < 5 THEN 'level_5_locked'
      WHEN n.level > 5 THEN 'too_deep'
      WHEN p.subscription_status != 'active' THEN 'no_active_subscription'
      WHEN mfa.user_id IS NOT NULL THEN 'marketing_free_access'
      WHEN p.created_at >= date_trunc('month', CURRENT_DATE) THEN 'new_partner'
      WHEN NOT COALESCE(ma.is_activated, FALSE) THEN 'no_payment_this_month'
      WHEN COALESCE(ci.has_commission, FALSE) THEN NULL
      ELSE NULL
    END as no_commission_reason
  FROM network n
  JOIN profiles p ON p.id = n.user_id
  LEFT JOIN profiles parent_p ON parent_p.id = n.parent_id
  LEFT JOIN current_month_activations ma ON ma.user_id = n.user_id
  LEFT JOIN marketing_free_access mfa ON mfa.user_id = n.user_id
  LEFT JOIN commission_info ci ON ci.referred_user_id = n.user_id
  ORDER BY n.level, p.created_at;
END;
$$;