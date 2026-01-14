
-- PHASE 1: Fix critical RPC failures
-- 1. Fix get_referral_network_from_table - replace invalid enum values
-- 2. Fix get_commission_structure_stats - use correct column names from get_referral_network_from_table

-- 1. Fix get_referral_network_from_table - use correct enum values
CREATE OR REPLACE FUNCTION public.get_referral_network_from_table(
  root_user_id uuid, 
  p_max_levels integer DEFAULT 10, 
  p_structure_type integer DEFAULT 1
)
RETURNS TABLE(
  user_id uuid, 
  partner_id text, 
  email text, 
  full_name text, 
  referral_code text, 
  subscription_status text, 
  monthly_activation_met boolean, 
  level integer, 
  structure_type integer, 
  created_at timestamp with time zone, 
  has_commission_received boolean, 
  no_commission_reason text
)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_structure_type_enum structure_type;
BEGIN
  -- Convert integer to enum correctly
  v_structure_type_enum := CASE WHEN p_structure_type = 1 THEN 'primary'::structure_type ELSE 'secondary'::structure_type END;

  RETURN QUERY
  WITH RECURSIVE network AS (
    -- Direct referrals (level 1)
    SELECT 
      r.referred_user_id AS uid,
      1 AS lvl
    FROM referrals r
    WHERE r.referrer_id = root_user_id
      AND r.structure_type = p_structure_type
    
    UNION ALL
    
    -- Deeper levels
    SELECT 
      r.referred_user_id,
      n.lvl + 1
    FROM referrals r
    INNER JOIN network n ON r.referrer_id = n.uid
    WHERE r.structure_type = p_structure_type
      AND n.lvl < p_max_levels
  ),
  -- Check if commission was received from each network member
  -- Use 'completed' and 'frozen' instead of invalid 'available'
  -- Use 'primary'/'secondary' instead of 'S1'/'S2'
  commission_check AS (
    SELECT 
      COALESCE(t.payload->>'subscriber_id', t.payload->>'source_user_id', t.source_id::text) AS source_user,
      true AS has_commission
    FROM transactions t
    WHERE t.user_id = root_user_id
      AND t.type = 'commission'
      AND t.structure_type = v_structure_type_enum
      AND t.status IN ('completed'::transaction_status, 'frozen'::transaction_status)
    GROUP BY COALESCE(t.payload->>'subscriber_id', t.payload->>'source_user_id', t.source_id::text)
  )
  SELECT 
    p.id AS user_id,
    p.referral_code AS partner_id,
    p.email,
    p.full_name,
    p.referral_code,
    p.subscription_status,
    COALESCE(p.monthly_activation_completed, false) AS monthly_activation_met,
    n.lvl AS level,
    p_structure_type AS structure_type,
    p.created_at,
    COALESCE(cc.has_commission, false) AS has_commission_received,
    -- Determine reason for no commission
    CASE 
      WHEN cc.has_commission = true THEN NULL
      WHEN p.subscription_status IS NULL OR p.subscription_status != 'active' THEN 'partner_no_subscription'
      WHEN p_structure_type = 1 AND n.lvl > 5 THEN 'too_deep'
      WHEN p_structure_type = 2 AND n.lvl > 10 THEN 'too_deep'
      WHEN EXISTS (
        SELECT 1 FROM subscriptions s 
        WHERE s.user_id = p.id 
          AND s.status = 'active' 
          AND s.is_marketing_free_access = true
      ) THEN 'marketing_free_access'
      WHEN p_structure_type = 2 AND COALESCE(p.monthly_activation_completed, false) = false THEN 'partner_no_activation'
      ELSE 'no_commission'
    END AS no_commission_reason
  FROM network n
  INNER JOIN profiles p ON p.id = n.uid
  LEFT JOIN subscriptions s ON s.user_id = p.id AND s.status = 'active'
  LEFT JOIN commission_check cc ON cc.source_user = p.id::text
  ORDER BY n.lvl, p.full_name;
END;
$function$;

-- 2. Fix get_commission_structure_stats to use correct column names
CREATE OR REPLACE FUNCTION public.get_commission_structure_stats(
  p_user_id uuid, 
  p_structure_type integer DEFAULT 1, 
  p_start_date timestamp with time zone DEFAULT NULL, 
  p_end_date timestamp with time zone DEFAULT NULL
)
RETURNS TABLE(
  level integer, 
  percent numeric, 
  earned_cents numeric, 
  frozen_cents numeric, 
  volume_cents numeric, 
  partners_count integer, 
  status text, 
  unlock_requirement text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
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
  -- Get network members directly from profiles + referrals (avoid column name issues)
  network_stats AS (
    SELECT 
      rn.level as network_level,
      COUNT(DISTINCT rn.user_id)::integer as total_partners,
      -- Sum personal activation volume from monthly_activations for current period
      COALESCE(SUM(
        (SELECT COALESCE(ma.total_amount_kzt, 0) 
         FROM monthly_activations ma 
         WHERE ma.user_id = rn.user_id 
         AND ma.year = EXTRACT(YEAR FROM CURRENT_DATE)
         AND ma.month = EXTRACT(MONTH FROM CURRENT_DATE)
         LIMIT 1)
      ), 0) as total_volume
    FROM get_referral_network_from_table(p_user_id, v_max_level, p_structure_type) rn
    GROUP BY rn.level
  ),
  commission_stats AS (
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
$function$;
