
-- Drop existing function first to allow signature changes
DROP FUNCTION IF EXISTS public.get_referral_network_from_table(uuid, integer, integer);

-- Recreate function with proper activation checks
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
  direct_referrals integer,
  total_team integer,
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
  current_year integer := EXTRACT(YEAR FROM NOW());
  current_month integer := EXTRACT(MONTH FROM NOW());
  root_is_activated boolean;
  root_subscription_status text;
BEGIN
  -- Get root user's activation and subscription status for sponsor checks
  SELECT 
    COALESCE(p.monthly_activation_completed, FALSE),
    COALESCE(p.subscription_status, 'inactive')
  INTO root_is_activated, root_subscription_status
  FROM profiles p
  WHERE p.id = root_user_id;

  RETURN QUERY
  WITH RECURSIVE network AS (
    -- Base case: direct referrals of root user
    SELECT 
      r.referred_user_id,
      r.referrer_id,
      1 as lvl
    FROM referrals r
    WHERE r.referrer_id = root_user_id
      AND r.structure_type = p_structure_type
    
    UNION ALL
    
    -- Recursive case: referrals of referrals
    SELECT 
      r.referred_user_id,
      r.referrer_id,
      n.lvl + 1
    FROM referrals r
    INNER JOIN network n ON r.referrer_id = n.referred_user_id
    WHERE r.structure_type = p_structure_type
      AND n.lvl < max_level
  ),
  -- Get direct referral counts for each user
  direct_counts AS (
    SELECT 
      r.referrer_id,
      COUNT(*)::integer as cnt
    FROM referrals r
    WHERE r.structure_type = p_structure_type
    GROUP BY r.referrer_id
  ),
  -- Get team sizes (all descendants)
  team_sizes AS (
    SELECT 
      n1.referred_user_id as user_id,
      (
        SELECT COUNT(*)::integer
        FROM network n2
        WHERE n2.lvl > n1.lvl
          AND EXISTS (
            SELECT 1 FROM referrals r 
            WHERE r.referrer_id = n1.referred_user_id 
              AND r.structure_type = p_structure_type
          )
      ) as team_count
    FROM network n1
  ),
  -- Calculate monthly volume from orders
  monthly_volumes AS (
    SELECT 
      o.user_id,
      COALESCE(SUM(o.total_kzt), 0) as volume
    FROM orders o
    WHERE o.status = 'paid'
      AND EXTRACT(YEAR FROM o.paid_at) = current_year
      AND EXTRACT(MONTH FROM o.paid_at) = current_month
    GROUP BY o.user_id
  ),
  -- Check for commission transactions for this user from each partner
  commission_check AS (
    SELECT DISTINCT
      t.payload->>'source_user_id' as source_user_id,
      t.user_id as receiver_id,
      t.status as tx_status,
      t.frozen_until
    FROM transactions t
    WHERE t.user_id = root_user_id
      AND t.type = 'commission'
      AND t.structure_type = (CASE WHEN p_structure_type = 1 THEN 'primary' ELSE 'secondary' END)::structure_type
      AND EXTRACT(YEAR FROM t.created_at) = current_year
      AND EXTRACT(MONTH FROM t.created_at) = current_month
  ),
  -- Calculate unlock requirements based on direct referrals
  unlock_levels AS (
    SELECT 
      COALESCE(dc.cnt, 0) as direct_count,
      CASE 
        WHEN COALESCE(dc.cnt, 0) >= 5 THEN 10  -- All levels unlocked
        WHEN COALESCE(dc.cnt, 0) >= 4 THEN 5
        WHEN COALESCE(dc.cnt, 0) >= 3 THEN 4
        WHEN COALESCE(dc.cnt, 0) >= 2 THEN 3
        WHEN COALESCE(dc.cnt, 0) >= 1 THEN 2
        ELSE 1
      END as max_unlocked_level
    FROM direct_counts dc
    WHERE dc.referrer_id = root_user_id
  )
  SELECT 
    n.referred_user_id as user_id,
    COALESCE(LEFT(p.referral_code, 8), LEFT(n.referred_user_id::text, 8)) as partner_id,
    n.lvl as level,
    p.full_name,
    p.email,
    p.phone,
    p.avatar_url,
    COALESCE(p.subscription_status, 'inactive') as subscription_status,
    p.subscription_expires_at,
    -- Use monthly_activations if exists, otherwise fallback to profiles.monthly_activation_completed
    COALESCE(ma.is_activated, p.monthly_activation_completed, FALSE) as monthly_activation_met,
    p.referral_code,
    p.created_at,
    COALESCE(dc.cnt, 0) as direct_referrals,
    COALESCE(ts.team_count, 0) as total_team,
    COALESCE(mv.volume, 0) as monthly_volume,
    -- Parent info
    LEFT(parent_p.referral_code, 8) as parent_partner_id,
    n.referrer_id as parent_user_id,
    -- Commission received check
    (cc.source_user_id IS NOT NULL) as has_commission_received,
    -- Determine no_commission_reason with priority order
    CASE
      -- 1. Check if sponsor (root user) is inactive
      WHEN root_subscription_status NOT IN ('active', 'trial') THEN 'sponsor_inactive'
      -- 2. Check if sponsor hasn't done monthly activation
      WHEN NOT root_is_activated THEN 'sponsor_no_activation'
      -- 3. Check if partner has no active subscription
      WHEN COALESCE(p.subscription_status, 'inactive') NOT IN ('active', 'trial') THEN 'no_active_subscription'
      -- 4. Check if partner hasn't done monthly activation (use both sources)
      WHEN NOT COALESCE(ma.is_activated, p.monthly_activation_completed, FALSE) THEN 'no_payment_this_month'
      -- 5. Check if level is locked (only for S1)
      WHEN p_structure_type = 1 AND n.lvl > COALESCE(ul.max_unlocked_level, 1) THEN 
        CASE n.lvl
          WHEN 2 THEN 'level_2_locked'
          WHEN 3 THEN 'level_3_locked'
          WHEN 4 THEN 'level_4_locked'
          WHEN 5 THEN 'level_5_locked'
          ELSE 'level_not_unlocked'
        END
      -- 6. Check if commission was already received
      WHEN cc.source_user_id IS NOT NULL THEN 'already_received'
      -- 7. Check for marketing free access
      WHEN EXISTS (
        SELECT 1 FROM subscriptions s 
        WHERE s.user_id = n.referred_user_id 
          AND s.is_marketing_free_access = true
          AND s.status = 'active'
      ) THEN 'marketing_free_access'
      -- No reason - commission should be/was received
      ELSE NULL
    END as no_commission_reason,
    -- Commission status
    CASE
      WHEN cc.tx_status = 'frozen' THEN 'frozen'
      WHEN cc.tx_status = 'completed' THEN 'completed'
      WHEN cc.source_user_id IS NOT NULL THEN 'pending'
      ELSE NULL
    END as commission_status,
    cc.frozen_until as commission_frozen_until
  FROM network n
  INNER JOIN profiles p ON p.id = n.referred_user_id
  LEFT JOIN profiles parent_p ON parent_p.id = n.referrer_id
  LEFT JOIN direct_counts dc ON dc.referrer_id = n.referred_user_id
  LEFT JOIN team_sizes ts ON ts.user_id = n.referred_user_id
  LEFT JOIN monthly_volumes mv ON mv.user_id = n.referred_user_id
  LEFT JOIN monthly_activations ma ON ma.user_id = n.referred_user_id 
    AND ma.year = current_year 
    AND ma.month = current_month
  LEFT JOIN commission_check cc ON cc.source_user_id = n.referred_user_id::text
  LEFT JOIN unlock_levels ul ON TRUE
  WHERE p.is_active = TRUE
    AND p.deleted_at IS NULL
  ORDER BY n.lvl, p.created_at DESC;
END;
$$;
