-- Drop existing function to allow changing return type
DROP FUNCTION IF EXISTS get_referral_network_from_table(UUID, INT, INT);

-- 1. Recreate function with commission tracking fields
CREATE OR REPLACE FUNCTION get_referral_network_from_table(
  root_user_id UUID,
  max_level INT DEFAULT 10,
  p_structure_type INT DEFAULT 1
)
RETURNS TABLE (
  user_id UUID,
  partner_id UUID,
  level INT,
  full_name TEXT,
  email TEXT,
  avatar_url TEXT,
  subscription_status TEXT,
  monthly_activation_met BOOLEAN,
  referral_code TEXT,
  created_at TIMESTAMPTZ,
  direct_referrals INT,
  total_team INT,
  monthly_volume NUMERIC,
  parent_partner_id UUID,
  has_commission_received BOOLEAN,
  no_commission_reason TEXT
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
          WHEN p.subscription_status != 'active' AND NOT COALESCE(ast.is_activated, p.monthly_activation_completed, false) THEN false
          ELSE (cc.partner_user_id IS NOT NULL)
        END
      ELSE true -- S2 always shows as received (different logic)
    END as has_commission_received,
    -- Reason for no commission
    CASE
      WHEN p_structure_type != 1 THEN NULL
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
  ORDER BY n.lvl, p.created_at;
END;
$$;

-- 2. Create admin function to audit user commissions
CREATE OR REPLACE FUNCTION admin_audit_user_commissions(
  p_admin_id UUID,
  p_user_id UUID
)
RETURNS TABLE (
  partner_id UUID,
  partner_name TEXT,
  partner_email TEXT,
  level INT,
  subscription_id UUID,
  subscription_amount_kzt NUMERIC,
  commission_received BOOLEAN,
  commission_amount_cents BIGINT,
  expected_percent NUMERIC,
  expected_commission_cents BIGINT,
  actual_vs_expected TEXT,
  no_commission_reason TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Check admin access
  IF NOT has_role(p_admin_id, 'admin') AND NOT has_role(p_admin_id, 'superadmin') THEN
    RAISE EXCEPTION 'Access denied';
  END IF;

  RETURN QUERY
  WITH RECURSIVE network AS (
    -- Direct referrals
    SELECT 
      p.id as user_id,
      1 as lvl
    FROM profiles p
    WHERE p.sponsor_id = p_user_id
      AND p.deleted_at IS NULL
    
    UNION ALL
    
    -- Deeper levels (max 5 for S1)
    SELECT 
      p.id as user_id,
      n.lvl + 1 as lvl
    FROM profiles p
    INNER JOIN network n ON p.sponsor_id = n.user_id
    WHERE n.lvl < 5
      AND p.deleted_at IS NULL
  ),
  -- Get S1 commission percentages
  commission_rates AS (
    SELECT level, percent
    FROM mlm_commission_rules
    WHERE structure_type = 1 AND is_active = true
  ),
  -- Partner subscriptions with commission info
  partner_subs AS (
    SELECT 
      n.user_id as partner_id,
      p.full_name,
      p.email,
      n.lvl,
      s.id as subscription_id,
      s.amount_kzt,
      cr.percent as rate_percent,
      -- Check if commission exists for this subscription
      (
        SELECT t.id 
        FROM transactions t 
        WHERE t.source_id = s.id 
          AND t.user_id = p_user_id 
          AND t.type = 'commission'
          AND t.structure_type = 'primary'
        LIMIT 1
      ) as commission_tx_id,
      (
        SELECT t.amount_cents 
        FROM transactions t 
        WHERE t.source_id = s.id 
          AND t.user_id = p_user_id 
          AND t.type = 'commission'
          AND t.structure_type = 'primary'
        LIMIT 1
      ) as actual_commission,
      -- Expected commission
      ROUND(s.amount_kzt * 100 * COALESCE(cr.percent, 0) / 100) as expected_commission,
      -- Reason if no commission
      CASE
        WHEN s.status != 'active' THEN 'subscription_not_active'
        WHEN n.lvl > 5 THEN 'too_deep'
        ELSE 'unknown'
      END as reason
    FROM network n
    JOIN profiles p ON p.id = n.user_id
    LEFT JOIN subscriptions s ON s.user_id = n.user_id AND s.status = 'active'
    LEFT JOIN commission_rates cr ON cr.level = n.lvl
    WHERE s.id IS NOT NULL
  )
  SELECT 
    ps.partner_id,
    ps.full_name as partner_name,
    ps.email as partner_email,
    ps.lvl as level,
    ps.subscription_id,
    ps.amount_kzt as subscription_amount_kzt,
    (ps.commission_tx_id IS NOT NULL) as commission_received,
    ps.actual_commission as commission_amount_cents,
    ps.rate_percent as expected_percent,
    ps.expected_commission as expected_commission_cents,
    CASE
      WHEN ps.commission_tx_id IS NULL THEN 'MISSING'
      WHEN ps.actual_commission = ps.expected_commission THEN 'OK'
      WHEN ps.actual_commission < ps.expected_commission THEN 'UNDERPAID'
      ELSE 'OVERPAID'
    END as actual_vs_expected,
    CASE
      WHEN ps.commission_tx_id IS NOT NULL THEN NULL
      ELSE ps.reason
    END as no_commission_reason
  FROM partner_subs ps
  ORDER BY ps.lvl, ps.full_name;
END;
$$;