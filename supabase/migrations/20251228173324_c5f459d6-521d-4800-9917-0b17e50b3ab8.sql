-- Update get_referral_network_from_table with correct commission reason logic
-- Changes:
-- 1. Add 'not_activated' for partners without active subscription
-- 2. Add 'marketing_free_access' check
-- 3. Fix level unlock requirements: 2->3, 3->5, 4->8, 5->10
-- 4. Count only active non-marketing-free referrals for root_direct_count

CREATE OR REPLACE FUNCTION public.get_referral_network_from_table(
  root_user_id uuid,
  max_level int DEFAULT 10,
  p_structure_type int DEFAULT 1
)
RETURNS TABLE (
  user_id uuid,
  partner_id text,
  level int,
  full_name text,
  email text,
  avatar_url text,
  subscription_status text,
  monthly_activation_met boolean,
  referral_code text,
  created_at timestamptz,
  direct_referrals int,
  total_team int,
  monthly_volume numeric,
  parent_partner_id text,
  has_commission_received boolean,
  no_commission_reason text
)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  current_year int := extract(year from CURRENT_DATE)::int;
  current_month int := extract(month from CURRENT_DATE)::int;
BEGIN
  RETURN QUERY
  WITH RECURSIVE network AS (
    -- Direct referrals (level 1)
    SELECT 
      r.referred_user_id as user_id,
      r.referrer_id as parent_id,
      1 as level
    FROM referrals r
    WHERE r.referrer_id = root_user_id
      AND r.structure_type = p_structure_type
    
    UNION ALL
    
    -- Deeper levels
    SELECT 
      r.referred_user_id as user_id,
      r.referrer_id as parent_id,
      n.level + 1 as level
    FROM referrals r
    INNER JOIN network n ON r.referrer_id = n.user_id
    WHERE n.level < max_level
      AND r.structure_type = p_structure_type
  ),
  -- Get sponsor's activation status using monthly_activations
  sponsor_activation AS (
    SELECT 
      ma.is_activated
    FROM monthly_activations ma
    WHERE ma.user_id = root_user_id
      AND ma.year = current_year
      AND ma.month = current_month
    LIMIT 1
  ),
  -- Calculate direct referrals count for root user
  -- ONLY count active partners with active subscription AND NOT marketing free access
  root_direct_count AS (
    SELECT COUNT(*)::int as cnt
    FROM referrals r
    INNER JOIN profiles p ON r.referred_user_id = p.id
    LEFT JOIN subscriptions s ON s.user_id = p.id AND s.status = 'active'
    WHERE r.referrer_id = root_user_id
      AND r.structure_type = p_structure_type
      AND p.is_active = true
      AND p.subscription_status = 'active'
      AND COALESCE(s.is_marketing_free_access, false) = false
  ),
  -- Get partner data with monthly activation check
  partner_data AS (
    SELECT 
      n.user_id,
      n.parent_id,
      n.level,
      p.full_name,
      p.email,
      p.avatar_url,
      p.subscription_status,
      -- Use monthly_activations for activation check
      COALESCE(ma.is_activated, false) as monthly_activation_met,
      p.referral_code,
      p.created_at,
      COALESCE(p.direct_referrals_count, 0)::int as direct_referrals,
      -- Calculate total team size
      (
        SELECT COUNT(*)::int 
        FROM referrals r2 
        WHERE r2.referrer_id = n.user_id 
          AND r2.structure_type = p_structure_type
      ) as total_team,
      -- Monthly volume from orders
      COALESCE((
        SELECT SUM(o.total_kzt)
        FROM orders o
        WHERE o.user_id = n.user_id
          AND o.status = 'paid'
          AND o.paid_at >= date_trunc('month', CURRENT_DATE)
      ), 0)::numeric as monthly_volume,
      -- Parent partner_id
      (SELECT p2.referral_code FROM profiles p2 WHERE p2.id = n.parent_id) as parent_partner_id,
      -- Check if partner made payment this month using monthly_activations
      COALESCE(ma.is_activated, false) as partner_current_payments,
      -- Check if partner has marketing free access
      EXISTS (
        SELECT 1 FROM subscriptions s
        WHERE s.user_id = n.user_id
          AND s.status = 'active'
          AND s.is_marketing_free_access = true
      ) as is_marketing_free
    FROM network n
    INNER JOIN profiles p ON n.user_id = p.id
    LEFT JOIN monthly_activations ma ON ma.user_id = n.user_id 
      AND ma.year = current_year 
      AND ma.month = current_month
    WHERE p.deleted_at IS NULL
  )
  SELECT 
    pd.user_id,
    pd.referral_code as partner_id,
    pd.level,
    pd.full_name,
    pd.email,
    pd.avatar_url,
    pd.subscription_status,
    pd.monthly_activation_met,
    pd.referral_code,
    pd.created_at,
    pd.direct_referrals,
    pd.total_team,
    pd.monthly_volume,
    pd.parent_partner_id,
    -- Commission received check
    EXISTS (
      SELECT 1 FROM transactions t
      WHERE t.user_id = root_user_id
        AND t.type = 'commission'
        AND t.source_id = pd.user_id
        AND t.created_at >= date_trunc('month', CURRENT_DATE)
        AND t.structure_type = (CASE WHEN p_structure_type = 1 THEN 'primary'::structure_type ELSE 'secondary'::structure_type END)
    ) as has_commission_received,
    -- Reason for no commission (priority order)
    CASE
      -- 1. Partner has no active subscription (didn't pay annual activation)
      WHEN pd.subscription_status != 'active' THEN 'not_activated'
      
      -- 2. Partner has marketing free access (no commission for free subscriptions)
      WHEN pd.is_marketing_free THEN 'marketing_free_access'
      
      -- 3. Level not unlocked (CORRECTED requirements: 3,5,8,10 for levels 2,3,4,5)
      WHEN pd.level >= 2 AND (SELECT cnt FROM root_direct_count) < 
        CASE 
          WHEN pd.level = 2 THEN 3   -- Need 3 direct referrals for level 2
          WHEN pd.level = 3 THEN 5   -- Need 5 direct referrals for level 3
          WHEN pd.level = 4 THEN 8   -- Need 8 direct referrals for level 4
          WHEN pd.level = 5 THEN 10  -- Need 10 direct referrals for level 5
          WHEN pd.level >= 6 THEN 999 -- Level 6+ not available in S1
          ELSE pd.level
        END
      THEN 'level_not_unlocked'
      
      -- 4. Sponsor (you) is inactive this month
      WHEN NOT COALESCE((SELECT is_activated FROM sponsor_activation), false) THEN 'sponsor_inactive'
      
      -- 5. Partner didn't make monthly activation (for S1 after first month and S2)
      WHEN NOT pd.partner_current_payments THEN 'no_payment_this_month'
      
      -- Commission was received
      WHEN EXISTS (
        SELECT 1 FROM transactions t
        WHERE t.user_id = root_user_id
          AND t.type = 'commission'
          AND t.source_id = pd.user_id
          AND t.created_at >= date_trunc('month', CURRENT_DATE)
          AND t.structure_type = (CASE WHEN p_structure_type = 1 THEN 'primary'::structure_type ELSE 'secondary'::structure_type END)
      ) THEN NULL
      ELSE NULL
    END as no_commission_reason
  FROM partner_data pd
  ORDER BY pd.level, pd.created_at;
END;
$$;