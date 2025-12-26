
-- Fix get_referral_network_from_table to show marketing_free_access reason
CREATE OR REPLACE FUNCTION public.get_referral_network_from_table(
  root_user_id uuid,
  max_level integer DEFAULT 10,
  p_structure_type integer DEFAULT 1
)
RETURNS TABLE (
  user_id uuid,
  partner_id uuid,
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
  parent_partner_id uuid,
  has_commission_received boolean,
  no_commission_reason text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_max_level INT;
BEGIN
  -- Set max level based on structure type
  IF p_structure_type = 1 THEN
    v_max_level := LEAST(max_level, 5);
  ELSE
    v_max_level := LEAST(max_level, 10);
  END IF;

  RETURN QUERY
  WITH RECURSIVE network AS (
    -- Base: direct referrals (level 1)
    SELECT 
      p.id as user_id,
      p.id as partner_id,
      1 as lvl,
      p.sponsor_id as parent_id
    FROM profiles p
    WHERE p.sponsor_id = root_user_id
      AND p.deleted_at IS NULL
    
    UNION ALL
    
    -- Recursive: deeper levels
    SELECT 
      p.id as user_id,
      p.id as partner_id,
      n.lvl + 1 as lvl,
      p.sponsor_id as parent_id
    FROM profiles p
    INNER JOIN network n ON p.sponsor_id = n.user_id
    WHERE n.lvl < v_max_level
      AND p.deleted_at IS NULL
  ),
  -- Check commissions received for S1 structure only
  commission_check AS (
    SELECT DISTINCT 
      s.user_id as partner_user_id
    FROM transactions t
    JOIN subscriptions s ON s.id = t.source_id
    WHERE t.type = 'commission'
      AND t.structure_type = 'primary'
      AND t.user_id = root_user_id
      AND t.is_archived = false
      AND s.status = 'active'
  ),
  -- Check if partner has marketing_free_access subscription
  marketing_free_check AS (
    SELECT DISTINCT s.user_id as partner_user_id
    FROM subscriptions s
    WHERE s.status = 'active'
      AND s.is_marketing_free_access = true
  ),
  -- Calculate team sizes
  team_sizes AS (
    SELECT 
      n.user_id,
      (SELECT COUNT(*) FROM profiles WHERE sponsor_id = n.user_id AND deleted_at IS NULL)::INT as direct,
      (
        WITH RECURSIVE sub AS (
          SELECT id FROM profiles WHERE sponsor_id = n.user_id AND deleted_at IS NULL
          UNION ALL
          SELECT p.id FROM profiles p INNER JOIN sub s ON p.sponsor_id = s.id WHERE p.deleted_at IS NULL
        )
        SELECT COUNT(*)::INT FROM sub
      ) as team
    FROM network n
  ),
  -- Calculate monthly volume
  monthly_volume AS (
    SELECT 
      o.user_id,
      COALESCE(SUM(o.total_kzt), 0) as volume
    FROM orders o
    WHERE o.status = 'paid'
      AND o.created_at >= date_trunc('month', CURRENT_DATE)
      AND o.is_archived = false
    GROUP BY o.user_id
  ),
  -- Get current month activation status
  activation_status AS (
    SELECT 
      ma.user_id,
      ma.is_activated
    FROM monthly_activations ma
    WHERE ma.year = EXTRACT(YEAR FROM CURRENT_DATE)::INT
      AND ma.month = EXTRACT(MONTH FROM CURRENT_DATE)::INT
  )
  SELECT 
    n.user_id,
    n.partner_id,
    n.lvl as level,
    p.full_name,
    p.email,
    p.avatar_url,
    p.subscription_status,
    COALESCE(ast.is_activated, p.monthly_activation_completed, false) as monthly_activation_met,
    p.referral_code,
    p.created_at,
    COALESCE(ts.direct, 0) as direct_referrals,
    COALESCE(ts.team, 0) as total_team,
    COALESCE(mv.volume, 0) as monthly_volume,
    n.parent_id as parent_partner_id,
    -- Commission tracking (only meaningful for S1)
    CASE 
      WHEN p_structure_type = 1 THEN 
        CASE 
          WHEN mfc.partner_user_id IS NOT NULL THEN false  -- Marketing free = no commission
          WHEN p.subscription_status != 'active' AND NOT COALESCE(ast.is_activated, p.monthly_activation_completed, false) THEN false
          ELSE (cc.partner_user_id IS NOT NULL)
        END
      ELSE true -- S2 always shows as received (different logic)
    END as has_commission_received,
    -- Reason for no commission
    CASE
      WHEN p_structure_type != 1 THEN NULL
      WHEN mfc.partner_user_id IS NOT NULL THEN 'marketing_free_access'  -- NEW: Marketing free reason
      WHEN p.subscription_status != 'active' AND NOT COALESCE(ast.is_activated, p.monthly_activation_completed, false) THEN 'not_activated'
      WHEN n.lvl > 5 THEN 'too_deep'
      WHEN cc.partner_user_id IS NULL AND (p.subscription_status = 'active' OR COALESCE(ast.is_activated, p.monthly_activation_completed, false)) THEN 'sponsor_inactive'
      ELSE NULL
    END as no_commission_reason
  FROM network n
  JOIN profiles p ON p.id = n.user_id
  LEFT JOIN team_sizes ts ON ts.user_id = n.user_id
  LEFT JOIN monthly_volume mv ON mv.user_id = n.user_id
  LEFT JOIN activation_status ast ON ast.user_id = n.user_id
  LEFT JOIN commission_check cc ON cc.partner_user_id = n.user_id
  LEFT JOIN marketing_free_check mfc ON mfc.partner_user_id = n.user_id
  ORDER BY n.lvl, p.created_at;
END;
$$;
