-- ============================================
-- CRITICAL FIX: structure_type integer → enum conversion
-- Fixes: Tree not displaying, order status not updating
-- ============================================

-- Drop all affected functions first
DROP FUNCTION IF EXISTS get_referral_network_from_table(UUID, INTEGER, INTEGER);
DROP FUNCTION IF EXISTS get_commission_structure_stats(UUID, INTEGER, TIMESTAMPTZ, TIMESTAMPTZ);
DROP FUNCTION IF EXISTS award_s1_subscription_commission(UUID, UUID, NUMERIC);
DROP FUNCTION IF EXISTS create_commission_transactions(UUID);

-- ============================================
-- 1. FIXED: get_referral_network_from_table
-- Now correctly converts integer to enum for transactions
-- ============================================
CREATE OR REPLACE FUNCTION get_referral_network_from_table(
  root_user_id UUID,
  p_max_levels INTEGER DEFAULT 10,
  p_structure_type INTEGER DEFAULT 1
)
RETURNS TABLE (
  id UUID,
  full_name TEXT,
  avatar_url TEXT,
  level INTEGER,
  parent_id UUID,
  subscription_status TEXT,
  subscription_expires_at TIMESTAMPTZ,
  personal_activation_volume NUMERIC,
  has_commission_received BOOLEAN,
  no_commission_reason TEXT,
  commission_frozen_until TIMESTAMPTZ,
  is_activated BOOLEAN,
  created_at TIMESTAMPTZ
) 
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_unlock_levels JSONB;
  v_root_direct_referrals INTEGER;
  v_structure_type_enum structure_type;
BEGIN
  -- Convert integer to enum for transactions table
  v_structure_type_enum := CASE WHEN p_structure_type = 1 THEN 'primary'::structure_type ELSE 'secondary'::structure_type END;
  
  -- Get unlock levels from settings
  SELECT COALESCE((SELECT value::jsonb FROM mlm_settings WHERE key = 'unlock_levels'), 
    '{"l1": 0, "l2": 3, "l3": 5, "l4": 8, "l5": 10}'::jsonb)
  INTO v_unlock_levels;
  
  -- Count direct referrals for root user
  SELECT COUNT(*) INTO v_root_direct_referrals
  FROM profiles 
  WHERE sponsor_id = root_user_id;

  RETURN QUERY
  WITH RECURSIVE network AS (
    -- Base case: direct referrals (level 1)
    SELECT 
      p.id,
      p.full_name,
      p.avatar_url,
      1 as level,
      p.sponsor_id as parent_id,
      p.subscription_status,
      p.subscription_expires_at,
      COALESCE(p.personal_activation_volume, 0) as personal_activation_volume,
      p.is_activated,
      p.created_at
    FROM profiles p
    WHERE p.sponsor_id = root_user_id
    
    UNION ALL
    
    -- Recursive case
    SELECT 
      p.id,
      p.full_name,
      p.avatar_url,
      n.level + 1,
      p.sponsor_id,
      p.subscription_status,
      p.subscription_expires_at,
      COALESCE(p.personal_activation_volume, 0),
      p.is_activated,
      p.created_at
    FROM profiles p
    INNER JOIN network n ON p.sponsor_id = n.id
    WHERE n.level < p_max_levels
  )
  SELECT 
    n.id,
    n.full_name,
    n.avatar_url,
    n.level,
    n.parent_id,
    n.subscription_status,
    n.subscription_expires_at,
    n.personal_activation_volume,
    -- Check if commission was received (using enum type!)
    EXISTS (
      SELECT 1 FROM transactions t 
      WHERE t.user_id = root_user_id 
      AND t.source_user_id = n.id
      AND t.type = 'commission'
      AND t.structure_type = v_structure_type_enum
    ) as has_commission_received,
    -- Determine no commission reason
    CASE
      -- For S1 (structure 1): Check levels 1-5
      WHEN p_structure_type = 1 THEN
        CASE
          -- Level 1 is always open
          WHEN n.level = 1 THEN
            CASE
              WHEN n.subscription_status != 'active' THEN 'partner_no_subscription'
              WHEN NOT EXISTS (
                SELECT 1 FROM transactions t 
                WHERE t.user_id = root_user_id 
                AND t.source_user_id = n.id
                AND t.type = 'commission'
                AND t.structure_type = v_structure_type_enum
              ) THEN 'no_subscription_payment'
              ELSE NULL
            END
          -- Levels 2-5: check unlock requirements
          WHEN n.level BETWEEN 2 AND 5 THEN
            CASE
              WHEN v_root_direct_referrals < COALESCE((v_unlock_levels->('l' || n.level))::integer, 0) 
                THEN 'level_not_unlocked'
              WHEN n.subscription_status != 'active' THEN 'partner_no_subscription'
              WHEN NOT EXISTS (
                SELECT 1 FROM transactions t 
                WHERE t.user_id = root_user_id 
                AND t.source_user_id = n.id
                AND t.type = 'commission'
                AND t.structure_type = v_structure_type_enum
              ) THEN 'no_subscription_payment'
              ELSE NULL
            END
          ELSE NULL
        END
      -- For S2 (structure 2): Check levels 1-10
      WHEN p_structure_type = 2 THEN
        CASE
          WHEN n.subscription_status != 'active' THEN 'partner_no_subscription'
          WHEN NOT n.is_activated THEN 'partner_no_activation'
          WHEN NOT EXISTS (
            SELECT 1 FROM transactions t 
            WHERE t.user_id = root_user_id 
            AND t.source_user_id = n.id
            AND t.type = 'commission'
            AND t.structure_type = v_structure_type_enum
          ) THEN 'no_order_payment'
          ELSE NULL
        END
      ELSE NULL
    END as no_commission_reason,
    -- Get frozen until date (using enum type!)
    (
      SELECT t.frozen_until FROM transactions t 
      WHERE t.user_id = root_user_id 
      AND t.source_user_id = n.id
      AND t.type = 'commission'
      AND t.structure_type = v_structure_type_enum
      AND t.status = 'frozen'
      ORDER BY t.created_at DESC
      LIMIT 1
    ) as commission_frozen_until,
    n.is_activated,
    n.created_at
  FROM network n
  ORDER BY n.level, n.created_at;
END;
$$;

-- ============================================
-- 2. FIXED: get_commission_structure_stats
-- Now correctly converts integer to enum for transactions
-- ============================================
CREATE OR REPLACE FUNCTION get_commission_structure_stats(
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
  
  -- Count direct referrals
  SELECT COUNT(*) INTO v_direct_referrals
  FROM profiles WHERE sponsor_id = p_user_id;
  
  -- Set max level based on structure type
  v_max_level := CASE WHEN p_structure_type = 1 THEN 5 ELSE 10 END;

  RETURN QUERY
  WITH levels AS (
    SELECT generate_series(1, v_max_level) as lvl
  ),
  rules AS (
    -- Get commission percentages from mlm_commission_rules (uses integer structure_type!)
    SELECT 
      r.level as rule_level,
      r.percent as rule_percent
    FROM mlm_commission_rules r
    WHERE r.structure_type = p_structure_type
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
    -- Use enum type for transactions table!
    SELECT 
      t.level as tx_level,
      SUM(CASE WHEN t.status = 'completed' THEN t.amount ELSE 0 END) as earned,
      SUM(CASE WHEN t.status = 'frozen' THEN t.amount ELSE 0 END) as frozen
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
      -- Level 1 always active
      WHEN l.lvl = 1 THEN 'active'
      -- For S1: levels 2-5 need unlock
      WHEN p_structure_type = 1 AND l.lvl BETWEEN 2 AND 5 THEN
        CASE 
          WHEN v_direct_referrals >= COALESCE((v_unlock_levels->('l' || l.lvl))::integer, 0) THEN 'active'
          ELSE 'locked'
        END
      -- For S2: levels 2-10 always active (no unlock requirement)
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

-- ============================================
-- 3. FIXED: award_s1_subscription_commission
-- Uses 'primary'::structure_type for INSERT
-- ============================================
CREATE OR REPLACE FUNCTION award_s1_subscription_commission(
  p_subscriber_id UUID,
  p_payment_id UUID,
  p_amount NUMERIC
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_current_user_id UUID;
  v_current_level INTEGER := 1;
  v_max_level INTEGER := 5;
  v_commission_percent NUMERIC;
  v_commission_amount NUMERIC;
  v_commissions_created INTEGER := 0;
  v_freeze_days INTEGER;
  v_frozen_until TIMESTAMPTZ;
  v_required_referrals INTEGER;
  v_sponsor_direct_referrals INTEGER;
  v_unlock_levels JSONB;
  v_commission_rates JSONB := '{}'::jsonb;
  v_source_ref TEXT;
BEGIN
  -- Get commission percentages from mlm_commission_rules
  SELECT jsonb_object_agg('l' || level, percent)
  INTO v_commission_rates
  FROM mlm_commission_rules
  WHERE structure_type = 1;
  
  -- Get unlock levels
  SELECT COALESCE((SELECT value::jsonb FROM mlm_settings WHERE key = 'unlock_levels'),
    '{"l1": 0, "l2": 3, "l3": 5, "l4": 8, "l5": 10}'::jsonb)
  INTO v_unlock_levels;
  
  -- Get freeze period
  SELECT COALESCE(
    (SELECT (value::jsonb->>'days')::integer FROM mlm_settings WHERE key = 'commission_freeze_period'),
    14
  ) INTO v_freeze_days;
  
  v_frozen_until := NOW() + (v_freeze_days || ' days')::interval;
  v_source_ref := 's1_' || p_payment_id::text;
  
  -- Start from subscriber's sponsor
  SELECT sponsor_id INTO v_current_user_id
  FROM profiles WHERE id = p_subscriber_id;
  
  -- Walk up the tree
  WHILE v_current_user_id IS NOT NULL AND v_current_level <= v_max_level LOOP
    -- Get commission percent for this level
    v_commission_percent := COALESCE((v_commission_rates->('l' || v_current_level))::numeric, 0);
    
    IF v_commission_percent > 0 THEN
      -- Get required referrals for this level (level 1 always 0)
      v_required_referrals := COALESCE((v_unlock_levels->('l' || v_current_level))::integer, 0);
      
      -- Count sponsor's direct referrals (registered before the subscriber)
      SELECT COUNT(*) INTO v_sponsor_direct_referrals
      FROM profiles
      WHERE sponsor_id = v_current_user_id
        AND id != p_subscriber_id
        AND created_at <= (SELECT created_at FROM profiles WHERE id = p_subscriber_id);
      
      -- Check if level is unlocked
      IF v_sponsor_direct_referrals >= v_required_referrals THEN
        v_commission_amount := ROUND(p_amount * v_commission_percent / 100);
        
        IF v_commission_amount > 0 THEN
          -- Insert commission transaction using ENUM type!
          INSERT INTO transactions (
            user_id,
            amount,
            type,
            status,
            description,
            source_user_id,
            level,
            source_ref,
            frozen_until,
            structure_type
          ) VALUES (
            v_current_user_id,
            v_commission_amount,
            'commission',
            'frozen',
            'Комиссия L' || v_current_level || ' (S1) за подписку',
            p_subscriber_id,
            v_current_level,
            v_source_ref,
            v_frozen_until,
            'primary'::structure_type  -- FIXED: Use enum!
          )
          ON CONFLICT (user_id, source_ref) WHERE source_ref IS NOT NULL DO NOTHING;
          
          IF FOUND THEN
            v_commissions_created := v_commissions_created + 1;
            
            RAISE LOG '[S1 Commission] Created L% commission: % KZT for user % from subscriber %', 
              v_current_level, v_commission_amount, v_current_user_id, p_subscriber_id;
          END IF;
        END IF;
      ELSE
        RAISE LOG '[S1 Commission] Level % locked for user % (has % referrals, needs %)',
          v_current_level, v_current_user_id, v_sponsor_direct_referrals, v_required_referrals;
      END IF;
    END IF;
    
    -- Move up
    SELECT sponsor_id INTO v_current_user_id
    FROM profiles WHERE id = v_current_user_id;
    
    v_current_level := v_current_level + 1;
  END LOOP;
  
  RETURN v_commissions_created;
END;
$$;

-- ============================================
-- 4. FIXED: create_commission_transactions
-- Uses 'secondary'::structure_type for INSERT
-- ============================================
CREATE OR REPLACE FUNCTION create_commission_transactions(p_order_id UUID)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order RECORD;
  v_current_user_id UUID;
  v_current_level INTEGER := 1;
  v_max_level INTEGER := 10;
  v_commission_percent NUMERIC;
  v_commission_amount NUMERIC;
  v_commissions_created INTEGER := 0;
  v_freeze_days INTEGER;
  v_frozen_until TIMESTAMPTZ;
  v_order_total NUMERIC;
  v_unlock_levels JSONB;
  v_required_referrals INTEGER;
  v_sponsor_direct_referrals INTEGER;
BEGIN
  -- Get order details
  SELECT o.*, p.sponsor_id as buyer_sponsor_id
  INTO v_order
  FROM orders o
  JOIN profiles p ON p.id = o.user_id
  WHERE o.id = p_order_id;
  
  IF NOT FOUND THEN
    RAISE LOG '[S2 Commission] Order % not found', p_order_id;
    RETURN 0;
  END IF;
  
  -- Get activation amount from order items
  SELECT COALESCE(SUM(oi.activation_amount * oi.quantity), 0)
  INTO v_order_total
  FROM order_items oi
  WHERE oi.order_id = p_order_id;
  
  IF v_order_total <= 0 THEN
    RAISE LOG '[S2 Commission] Order % has no activation amount', p_order_id;
    RETURN 0;
  END IF;
  
  -- Get unlock levels (only for L1-L5 in S2)
  SELECT COALESCE((SELECT value::jsonb FROM mlm_settings WHERE key = 'unlock_levels'),
    '{"l1": 0, "l2": 3, "l3": 5, "l4": 8, "l5": 10}'::jsonb)
  INTO v_unlock_levels;
  
  -- Get freeze period
  SELECT COALESCE(
    (SELECT (value::jsonb->>'days')::integer FROM mlm_settings WHERE key = 'commission_freeze_period'),
    14
  ) INTO v_freeze_days;
  
  v_frozen_until := NOW() + (v_freeze_days || ' days')::interval;
  v_current_user_id := v_order.buyer_sponsor_id;
  
  -- Walk up the sponsor tree
  WHILE v_current_user_id IS NOT NULL AND v_current_level <= v_max_level LOOP
    -- Get commission percent for this level from mlm_commission_rules
    SELECT percent INTO v_commission_percent
    FROM mlm_commission_rules
    WHERE structure_type = 2 AND level = v_current_level;
    
    IF v_commission_percent IS NOT NULL AND v_commission_percent > 0 THEN
      -- Check unlock requirements only for levels 1-5
      IF v_current_level <= 5 THEN
        v_required_referrals := COALESCE((v_unlock_levels->('l' || v_current_level))::integer, 0);
        
        SELECT COUNT(*) INTO v_sponsor_direct_referrals
        FROM profiles
        WHERE sponsor_id = v_current_user_id;
        
        IF v_sponsor_direct_referrals < v_required_referrals THEN
          RAISE LOG '[S2 Commission] Level % locked for user % (has % referrals, needs %)',
            v_current_level, v_current_user_id, v_sponsor_direct_referrals, v_required_referrals;
          
          -- Move to next sponsor
          SELECT sponsor_id INTO v_current_user_id
          FROM profiles WHERE id = v_current_user_id;
          v_current_level := v_current_level + 1;
          CONTINUE;
        END IF;
      END IF;
      
      v_commission_amount := ROUND(v_order_total * v_commission_percent / 100);
      
      IF v_commission_amount > 0 THEN
        -- Insert commission using ENUM type!
        INSERT INTO transactions (
          user_id,
          amount,
          type,
          status,
          description,
          source_user_id,
          level,
          source_ref,
          frozen_until,
          structure_type
        ) VALUES (
          v_current_user_id,
          v_commission_amount,
          'commission',
          'frozen',
          'Комиссия L' || v_current_level || ' (S2) за заказ #' || p_order_id,
          v_order.user_id,
          v_current_level,
          's2_' || p_order_id::text || '_' || v_current_level,
          v_frozen_until,
          'secondary'::structure_type  -- FIXED: Use enum!
        )
        ON CONFLICT (user_id, source_ref) WHERE source_ref IS NOT NULL DO NOTHING;
        
        IF FOUND THEN
          v_commissions_created := v_commissions_created + 1;
          RAISE LOG '[S2 Commission] Created L% commission: % KZT for user % from order %',
            v_current_level, v_commission_amount, v_current_user_id, p_order_id;
        END IF;
      END IF;
    END IF;
    
    -- Move up
    SELECT sponsor_id INTO v_current_user_id
    FROM profiles WHERE id = v_current_user_id;
    v_current_level := v_current_level + 1;
  END LOOP;
  
  RETURN v_commissions_created;
END;
$$;

-- Grant execute permissions
GRANT EXECUTE ON FUNCTION get_referral_network_from_table(UUID, INTEGER, INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION get_commission_structure_stats(UUID, INTEGER, TIMESTAMPTZ, TIMESTAMPTZ) TO authenticated;
GRANT EXECUTE ON FUNCTION award_s1_subscription_commission(UUID, UUID, NUMERIC) TO authenticated;
GRANT EXECUTE ON FUNCTION create_commission_transactions(UUID) TO authenticated;