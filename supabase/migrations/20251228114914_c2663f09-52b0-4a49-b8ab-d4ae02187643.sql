
-- Drop and recreate get_referral_network_from_table to use monthly_activations table
DROP FUNCTION IF EXISTS public.get_referral_network_from_table(uuid, integer, integer);

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
  avatar_url text,
  subscription_status text,
  monthly_activation_met boolean,
  referral_code text,
  created_at timestamptz,
  direct_referrals integer,
  total_team integer,
  monthly_volume numeric,
  parent_partner_id text,
  has_commission_received boolean,
  no_commission_reason text
)
LANGUAGE plpgsql
SECURITY DEFINER
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
  -- Calculate direct referrals count for root user (needed for unlock levels)
  root_direct_count AS (
    SELECT COUNT(*)::int as cnt
    FROM referrals r
    INNER JOIN profiles p ON r.referred_user_id = p.id
    WHERE r.referrer_id = root_user_id
      AND r.structure_type = p_structure_type
      AND p.is_active = true
      AND p.subscription_status = 'active'
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
      COALESCE(ma.is_activated, false) as partner_current_payments
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
        AND t.source_id = pd.user_id::text
        AND t.created_at >= date_trunc('month', CURRENT_DATE)
        AND t.structure_type = (CASE WHEN p_structure_type = 1 THEN 'primary'::structure_type ELSE 'secondary'::structure_type END)
    ) as has_commission_received,
    -- Reason for no commission
    CASE
      -- Partner didn't make payment this month (check monthly_activations)
      WHEN NOT pd.partner_current_payments THEN 'no_payment_this_month'
      -- Sponsor (root user) inactive
      WHEN NOT COALESCE((SELECT is_activated FROM sponsor_activation), false) THEN 'sponsor_inactive'
      -- Level not unlocked (need more direct referrals)
      WHEN pd.level >= 2 AND (SELECT cnt FROM root_direct_count) < 
        CASE 
          WHEN pd.level = 2 THEN 2
          WHEN pd.level = 3 THEN 3
          WHEN pd.level = 4 THEN 4
          WHEN pd.level = 5 THEN 5
          WHEN pd.level >= 6 THEN 6
          ELSE pd.level
        END
      THEN 'level_not_unlocked'
      -- Commission was received
      WHEN EXISTS (
        SELECT 1 FROM transactions t
        WHERE t.user_id = root_user_id
          AND t.type = 'commission'
          AND t.source_id = pd.user_id::text
          AND t.created_at >= date_trunc('month', CURRENT_DATE)
          AND t.structure_type = (CASE WHEN p_structure_type = 1 THEN 'primary'::structure_type ELSE 'secondary'::structure_type END)
      ) THEN NULL
      ELSE NULL
    END as no_commission_reason
  FROM partner_data pd
  ORDER BY pd.level, pd.created_at;
END;
$$;
