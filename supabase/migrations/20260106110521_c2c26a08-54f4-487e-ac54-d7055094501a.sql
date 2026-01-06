
-- First drop the existing function, then recreate with updated logic
DROP FUNCTION IF EXISTS public.get_referral_network_from_table(uuid, integer, integer);

-- Recreate function to count only ACTIVE direct referrals for level unlocking
CREATE OR REPLACE FUNCTION public.get_referral_network_from_table(
  root_user_id uuid,
  max_level integer DEFAULT 10,
  p_structure_type integer DEFAULT 1
)
RETURNS TABLE(
  user_id uuid,
  partner_id uuid,
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
  parent_partner_id uuid,
  parent_user_id uuid,
  has_commission_received boolean,
  no_commission_reason text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  current_month integer := EXTRACT(MONTH FROM NOW());
  current_year integer := EXTRACT(YEAR FROM NOW());
  v_active_root_direct_count integer;
BEGIN
  -- Count only ACTIVE direct referrals for the root user (for level unlocking)
  SELECT COUNT(*)::integer INTO v_active_root_direct_count
  FROM referrals r
  JOIN profiles p ON p.id = r.referred_user_id
  WHERE r.referrer_id = root_user_id
    AND r.structure_type = p_structure_type
    AND p.subscription_status = 'active';

  RETURN QUERY
  WITH RECURSIVE network AS (
    -- Base case: direct referrals of root user (level 1)
    SELECT 
      r.referred_user_id as user_id,
      r.id as partner_id,
      1 as level,
      r.referrer_id as parent_user_id,
      NULL::uuid as parent_partner_id
    FROM referrals r
    WHERE r.referrer_id = root_user_id
      AND r.structure_type = p_structure_type
    
    UNION ALL
    
    -- Recursive case: referrals of referrals
    SELECT 
      r.referred_user_id,
      r.id,
      n.level + 1,
      r.referrer_id,
      n.partner_id
    FROM referrals r
    INNER JOIN network n ON r.referrer_id = n.user_id
    WHERE r.structure_type = p_structure_type
      AND n.level < max_level
  ),
  -- Count direct referrals for each member
  direct_counts AS (
    SELECT 
      r.referrer_id,
      COUNT(*) as direct_count
    FROM referrals r
    WHERE r.structure_type = p_structure_type
    GROUP BY r.referrer_id
  ),
  -- Calculate team sizes
  team_sizes AS (
    SELECT 
      n1.user_id,
      COUNT(DISTINCT n2.user_id) as team_count
    FROM network n1
    LEFT JOIN network n2 ON n2.level > n1.level
      AND EXISTS (
        SELECT 1 FROM referrals r 
        WHERE r.referred_user_id = n2.user_id 
          AND r.structure_type = p_structure_type
          AND r.referrer_id IN (
            SELECT n3.user_id FROM network n3 WHERE n3.level >= n1.level
          )
      )
    GROUP BY n1.user_id
  ),
  -- Get monthly volumes from orders
  monthly_volumes AS (
    SELECT 
      o.user_id,
      COALESCE(SUM(o.total_kzt), 0) as volume
    FROM orders o
    WHERE o.status = 'paid'
      AND EXTRACT(MONTH FROM o.paid_at) = current_month
      AND EXTRACT(YEAR FROM o.paid_at) = current_year
    GROUP BY o.user_id
  ),
  -- Get commission info
  commission_info AS (
    SELECT 
      t.source_id,
      t.user_id as commission_receiver,
      TRUE as has_commission
    FROM transactions t
    WHERE t.type = 'commission'
      AND t.structure_type = (CASE WHEN p_structure_type = 1 THEN 'primary'::structure_type ELSE 'secondary'::structure_type END)
      AND EXTRACT(MONTH FROM t.created_at) = current_month
      AND EXTRACT(YEAR FROM t.created_at) = current_year
      AND t.user_id = root_user_id
  )
  SELECT 
    n.user_id,
    n.partner_id,
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
    COALESCE(dc.direct_count, 0) as direct_referrals,
    COALESCE(ts.team_count, 0) as total_team,
    COALESCE(mv.volume, 0) as monthly_volume,
    n.parent_partner_id,
    n.parent_user_id,
    COALESCE(ci.has_commission, FALSE) as has_commission_received,
    -- Determine no_commission_reason using ACTIVE direct count
    CASE
      -- Check if level is unlocked based on ACTIVE referrals
      WHEN n.level = 2 AND v_active_root_direct_count < 2 THEN 'level_2_locked'
      WHEN n.level = 3 AND v_active_root_direct_count < 3 THEN 'level_3_locked'
      WHEN n.level = 4 AND v_active_root_direct_count < 4 THEN 'level_4_locked'
      WHEN n.level = 5 AND v_active_root_direct_count < 5 THEN 'level_5_locked'
      WHEN n.level > 5 THEN 'too_deep'
      -- Check partner's activation status
      WHEN p.subscription_status != 'active' THEN 'no_active_subscription'
      WHEN NOT COALESCE(ma.is_activated, FALSE) THEN 'no_payment_this_month'
      -- Commission received
      WHEN COALESCE(ci.has_commission, FALSE) THEN NULL
      ELSE NULL
    END as no_commission_reason
  FROM network n
  JOIN profiles p ON p.id = n.user_id
  LEFT JOIN direct_counts dc ON dc.referrer_id = n.user_id
  LEFT JOIN team_sizes ts ON ts.user_id = n.user_id
  LEFT JOIN monthly_volumes mv ON mv.user_id = n.user_id
  LEFT JOIN monthly_activations ma ON ma.user_id = n.user_id 
    AND ma.month = current_month 
    AND ma.year = current_year
  LEFT JOIN commission_info ci ON ci.source_id = n.user_id
  ORDER BY n.level, p.created_at;
END;
$$;
