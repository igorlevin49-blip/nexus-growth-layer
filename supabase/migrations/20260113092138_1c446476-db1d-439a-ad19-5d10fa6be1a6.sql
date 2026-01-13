-- Fix get_commission_structure_stats function: use amount_cents instead of amount
CREATE OR REPLACE FUNCTION public.get_commission_structure_stats(
  p_user_id UUID,
  p_structure_type INTEGER DEFAULT 1,
  p_start_date TIMESTAMPTZ DEFAULT NULL,
  p_end_date TIMESTAMPTZ DEFAULT NULL
)
RETURNS TABLE (
  level INTEGER,
  percent NUMERIC,
  earned_cents NUMERIC,
  frozen_cents NUMERIC,
  volume_cents NUMERIC,
  partners_count INTEGER,
  status TEXT,
  unlock_requirement TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_direct_referrals INTEGER;
  v_unlock_levels JSONB;
  v_max_level INTEGER;
  v_structure_type_enum structure_type;
BEGIN
  -- Convert integer to enum for transactions table
  v_structure_type_enum := CASE WHEN p_structure_type = 1 THEN 'primary'::structure_type ELSE 'secondary'::structure_type END;
  
  -- Get unlock levels from settings
  SELECT COALESCE((SELECT value::jsonb FROM mlm_settings WHERE key = 'unlock_levels'), 
    '{"l1": 0, "l2": 3, "l3": 5, "l4": 8, "l5": 10}'::jsonb)
  INTO v_unlock_levels;
  
  -- Count direct referrals (only count active partners)
  SELECT COUNT(*) INTO v_direct_referrals
  FROM profiles 
  WHERE sponsor_id = p_user_id 
    AND subscription_status = 'active';
  
  -- Set max level based on structure type
  v_max_level := CASE WHEN p_structure_type = 1 THEN 5 ELSE 10 END;

  RETURN QUERY
  WITH levels AS (
    SELECT generate_series(1, v_max_level) as lvl
  ),
  rules AS (
    SELECT 
      r.level as rule_level,
      r.percent as rule_percent
    FROM mlm_commission_rules r
    WHERE r.structure_type = p_structure_type AND r.is_active = true
  ),
  network_stats AS (
    SELECT 
      n.level as network_level,
      COUNT(DISTINCT n.id)::integer as total_partners,
      SUM(n.personal_activation_volume) as total_volume
    FROM get_referral_network_from_table(p_user_id, v_max_level, p_structure_type) n
    GROUP BY n.level
  ),
  commission_stats AS (
    -- Fix: use amount_cents instead of amount
    SELECT 
      t.level as tx_level,
      SUM(CASE WHEN t.status = 'completed' THEN t.amount_cents ELSE 0 END) as earned,
      SUM(CASE WHEN t.status = 'frozen' THEN t.amount_cents ELSE 0 END) as frozen
    FROM transactions t
    WHERE t.user_id = p_user_id
      AND t.type = 'commission'
      AND t.structure_type = v_structure_type_enum
      AND (p_start_date IS NULL OR t.created_at >= p_start_date)
      AND (p_end_date IS NULL OR t.created_at <= p_end_date)
    GROUP BY t.level
  )
  SELECT 
    l.lvl::integer as level,
    COALESCE(r.rule_percent, 0)::numeric as percent,
    COALESCE(cs.earned, 0)::numeric as earned_cents,
    COALESCE(cs.frozen, 0)::numeric as frozen_cents,
    COALESCE(ns.total_volume, 0)::numeric as volume_cents,
    COALESCE(ns.total_partners, 0)::integer as partners_count,
    CASE
      WHEN l.lvl = 1 THEN 'active'
      WHEN p_structure_type = 1 AND l.lvl BETWEEN 2 AND 5 THEN
        CASE 
          WHEN v_direct_referrals >= COALESCE((v_unlock_levels->('l' || l.lvl))::integer, 0) THEN 'active'
          ELSE 'locked'
        END
      WHEN p_structure_type = 2 THEN 'active'
      ELSE 'active'
    END::text as status,
    CASE
      WHEN l.lvl = 1 THEN NULL
      WHEN p_structure_type = 1 AND l.lvl BETWEEN 2 AND 5 THEN
        COALESCE((v_unlock_levels->('l' || l.lvl))::text, '0') || ' личников'
      ELSE NULL
    END::text as unlock_requirement
  FROM levels l
  LEFT JOIN rules r ON r.rule_level = l.lvl
  LEFT JOIN network_stats ns ON ns.network_level = l.lvl
  LEFT JOIN commission_stats cs ON cs.tx_level = l.lvl
  ORDER BY l.lvl;
END;
$$;