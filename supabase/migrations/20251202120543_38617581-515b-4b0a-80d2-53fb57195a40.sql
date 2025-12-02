-- =====================================================
-- COMPREHENSIVE FIX FOR MLM FINANCIAL LOGIC
-- =====================================================
-- This migration fixes:
-- 1. Network stats counting (all levels, not just L1)
-- 2. S1 commission trigger (5 levels instead of 1)
-- 3. Adds recalculation function for existing subscriptions
-- 4. Adds commission structure stats for frontend
-- =====================================================

-- =====================================================
-- PART 1: Fix get_network_stats to count all levels
-- =====================================================
CREATE OR REPLACE FUNCTION public.get_network_stats(user_id_param UUID)
RETURNS TABLE(
  total_partners INTEGER,
  active_partners INTEGER,
  frozen_partners INTEGER,
  max_level INTEGER,
  new_this_month INTEGER,
  activations_this_month INTEGER,
  volume_this_month NUMERIC,
  commissions_this_month NUMERIC
) 
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  WITH RECURSIVE network AS (
    -- Level 1: Direct referrals
    SELECT 
      r.referred_user_id,
      1 as level
    FROM referrals r
    WHERE r.referrer_id = user_id_param
      AND r.structure_type = 1
    
    UNION ALL
    
    -- Levels 2-10: Recursive traversal
    SELECT 
      r.referred_user_id,
      n.level + 1
    FROM referrals r
    INNER JOIN network n ON r.referrer_id = n.referred_user_id
    WHERE n.level < 10
      AND r.structure_type = 1
  ),
  network_profiles AS (
    SELECT DISTINCT ON (n.referred_user_id)
      n.referred_user_id,
      n.level,
      p.subscription_status,
      p.monthly_activation_completed,
      p.created_at
    FROM network n
    INNER JOIN profiles p ON p.id = n.referred_user_id
  )
  SELECT
    -- Total partners (all levels)
    COUNT(DISTINCT np.referred_user_id)::INTEGER as total_partners,
    
    -- Active partners
    COUNT(DISTINCT CASE 
      WHEN np.subscription_status = 'active' OR np.monthly_activation_completed = true 
      THEN np.referred_user_id 
    END)::INTEGER as active_partners,
    
    -- Frozen partners
    COUNT(DISTINCT CASE 
      WHEN np.subscription_status = 'frozen' 
      THEN np.referred_user_id 
    END)::INTEGER as frozen_partners,
    
    -- Max level reached
    COALESCE(MAX(np.level), 0)::INTEGER as max_level,
    
    -- New partners this month
    COUNT(DISTINCT CASE 
      WHEN np.created_at >= DATE_TRUNC('month', NOW()) 
      THEN np.referred_user_id 
    END)::INTEGER as new_this_month,
    
    -- Activations this month
    COUNT(DISTINCT CASE 
      WHEN np.monthly_activation_completed = true 
        AND np.subscription_status = 'active'
      THEN np.referred_user_id 
    END)::INTEGER as activations_this_month,
    
    -- Volume this month (from orders)
    COALESCE((
      SELECT SUM(o.total_usd)
      FROM orders o
      WHERE o.user_id IN (SELECT referred_user_id FROM network_profiles)
        AND o.status = 'paid'
        AND o.created_at >= DATE_TRUNC('month', NOW())
    ), 0) as volume_this_month,
    
    -- Commissions this month (earned by user_id_param from their network)
    COALESCE((
      SELECT SUM(t.amount_cents) / 100.0
      FROM transactions t
      WHERE t.user_id = user_id_param
        AND t.type = 'commission'
        AND t.status = 'completed'
        AND t.created_at >= DATE_TRUNC('month', NOW())
    ), 0) as commissions_this_month
  FROM network_profiles np;
END;
$$;

-- =====================================================
-- PART 2: Fix S1 commission trigger (5 levels)
-- =====================================================

-- Drop old trigger first (correct name from existing DB)
DROP TRIGGER IF EXISTS award_s1_on_subscription_paid ON subscriptions;

-- Drop old function
DROP FUNCTION IF EXISTS public.award_s1_subscription_commission();

-- Create new function that awards commissions for 5 levels
CREATE OR REPLACE FUNCTION public.award_s1_subscription_commission()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_buyer_id UUID;
  v_buyer_name TEXT;
  v_current_sponsor_id UUID;
  v_current_level INTEGER := 1;
  v_subscription_amount_cents BIGINT;
  v_commission_percent NUMERIC;
  v_commission_cents BIGINT;
  v_sponsor_is_active BOOLEAN;
  v_freeze_reason TEXT;
  v_unique_ref TEXT;
  v_hold_days INTEGER := 7;
  v_max_levels INTEGER := 5;
BEGIN
  -- Only process when subscription becomes active
  IF NEW.status = 'active' AND (OLD.status IS NULL OR OLD.status != 'active') THEN
    
    -- Get buyer info
    SELECT id, full_name INTO v_buyer_id, v_buyer_name
    FROM profiles 
    WHERE id = NEW.user_id;
    
    -- Get subscription amount in cents
    v_subscription_amount_cents := (NEW.amount_usd * 100)::BIGINT;
    
    -- Get initial sponsor
    SELECT sponsor_id INTO v_current_sponsor_id
    FROM profiles
    WHERE id = v_buyer_id;
    
    -- Loop through 5 levels up the sponsor chain
    WHILE v_current_level <= v_max_levels AND v_current_sponsor_id IS NOT NULL LOOP
      
      -- Get commission percentage for this level from mlm_commission_rules
      SELECT percent INTO v_commission_percent
      FROM mlm_commission_rules
      WHERE structure_type = 1
        AND level = v_current_level
        AND plan_id = 'default'
        AND is_active = true
      LIMIT 1;
      
      -- If no rule found, skip this level
      IF v_commission_percent IS NULL THEN
        v_current_level := v_current_level + 1;
        CONTINUE;
      END IF;
      
      -- Calculate commission amount
      v_commission_cents := (v_subscription_amount_cents * v_commission_percent / 100)::BIGINT;
      
      -- Check if sponsor is active
      SELECT 
        (subscription_active AND monthly_activation_completed) as is_active
      INTO v_sponsor_is_active
      FROM profiles
      WHERE id = v_current_sponsor_id;
      
      -- Determine freeze reason
      IF NOT COALESCE(v_sponsor_is_active, false) THEN
        v_freeze_reason := 'sponsor_inactive';
      ELSE
        v_freeze_reason := NULL;
      END IF;
      
      -- Create unique reference
      v_unique_ref := 'subscription_' || NEW.id || '_s1_level_' || v_current_level;
      
      -- Insert commission transaction
      INSERT INTO transactions (
        user_id,
        type,
        amount_cents,
        status,
        source_id,
        source_ref,
        level,
        structure_type,
        frozen_until,
        currency,
        payload
      ) VALUES (
        v_current_sponsor_id,
        'commission',
        v_commission_cents,
        'completed',
        NEW.id,
        v_unique_ref,
        v_current_level,
        'primary',
        CASE 
          WHEN v_freeze_reason IS NOT NULL THEN NOW() + INTERVAL '365 days'
          ELSE NOW() + (v_hold_days || ' days')::INTERVAL
        END,
        'USD',
        jsonb_build_object(
          'subscription_id', NEW.id,
          'buyer_id', v_buyer_id,
          'buyer_name', v_buyer_name,
          'structure', 's1',
          'level', v_current_level,
          'percent', v_commission_percent,
          'freeze_reason', v_freeze_reason
        )
      ) ON CONFLICT (source_ref) DO NOTHING;
      
      -- Move to next sponsor up the chain
      SELECT sponsor_id INTO v_current_sponsor_id
      FROM profiles
      WHERE id = v_current_sponsor_id;
      
      v_current_level := v_current_level + 1;
    END LOOP;
    
  END IF;
  
  RETURN NEW;
END;
$$;

-- Recreate trigger
CREATE TRIGGER award_s1_on_subscription_paid
  AFTER INSERT OR UPDATE ON subscriptions
  FOR EACH ROW
  EXECUTE FUNCTION award_s1_subscription_commission();

-- =====================================================
-- PART 3: Create function to recalculate all S1 commissions
-- =====================================================
CREATE OR REPLACE FUNCTION public.recalculate_all_s1_commissions(p_admin_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_subscription RECORD;
  v_buyer_id UUID;
  v_buyer_name TEXT;
  v_current_sponsor_id UUID;
  v_current_level INTEGER;
  v_subscription_amount_cents BIGINT;
  v_commission_percent NUMERIC;
  v_commission_cents BIGINT;
  v_sponsor_is_active BOOLEAN;
  v_freeze_reason TEXT;
  v_unique_ref TEXT;
  v_hold_days INTEGER := 7;
  v_max_levels INTEGER := 5;
  v_subscriptions_processed INTEGER := 0;
  v_commissions_created INTEGER := 0;
  v_commissions_skipped INTEGER := 0;
BEGIN
  -- Check admin role
  IF NOT (has_role(p_admin_id, 'admin'::app_role) OR has_role(p_admin_id, 'superadmin'::app_role)) THEN
    RETURN jsonb_build_object('success', false, 'error', 'UNAUTHORIZED');
  END IF;
  
  -- Loop through all active subscriptions
  FOR v_subscription IN
    SELECT s.id, s.user_id, s.amount_usd, s.paid_at
    FROM subscriptions s
    WHERE s.status = 'active'
      AND s.paid_at IS NOT NULL
    ORDER BY s.paid_at ASC
  LOOP
    v_subscriptions_processed := v_subscriptions_processed + 1;
    
    -- Get buyer info
    SELECT id, full_name INTO v_buyer_id, v_buyer_name
    FROM profiles 
    WHERE id = v_subscription.user_id;
    
    -- Get subscription amount in cents
    v_subscription_amount_cents := (v_subscription.amount_usd * 100)::BIGINT;
    
    -- Get initial sponsor
    SELECT sponsor_id INTO v_current_sponsor_id
    FROM profiles
    WHERE id = v_buyer_id;
    
    -- Reset level counter
    v_current_level := 1;
    
    -- Loop through 5 levels up the sponsor chain
    WHILE v_current_level <= v_max_levels AND v_current_sponsor_id IS NOT NULL LOOP
      
      -- Get commission percentage for this level
      SELECT percent INTO v_commission_percent
      FROM mlm_commission_rules
      WHERE structure_type = 1
        AND level = v_current_level
        AND plan_id = 'default'
        AND is_active = true
      LIMIT 1;
      
      -- If no rule found, skip this level
      IF v_commission_percent IS NULL THEN
        v_current_level := v_current_level + 1;
        CONTINUE;
      END IF;
      
      -- Calculate commission amount
      v_commission_cents := (v_subscription_amount_cents * v_commission_percent / 100)::BIGINT;
      
      -- Check if sponsor is active
      SELECT 
        (subscription_active AND monthly_activation_completed) as is_active
      INTO v_sponsor_is_active
      FROM profiles
      WHERE id = v_current_sponsor_id;
      
      -- Determine freeze reason
      IF NOT COALESCE(v_sponsor_is_active, false) THEN
        v_freeze_reason := 'sponsor_inactive';
      ELSE
        v_freeze_reason := NULL;
      END IF;
      
      -- Create unique reference
      v_unique_ref := 'subscription_' || v_subscription.id || '_s1_level_' || v_current_level || '_recalc';
      
      -- Try to insert commission (will skip if already exists)
      BEGIN
        INSERT INTO transactions (
          user_id,
          type,
          amount_cents,
          status,
          source_id,
          source_ref,
          level,
          structure_type,
          frozen_until,
          currency,
          payload
        ) VALUES (
          v_current_sponsor_id,
          'commission',
          v_commission_cents,
          'completed',
          v_subscription.id,
          v_unique_ref,
          v_current_level,
          'primary',
          CASE 
            WHEN v_freeze_reason IS NOT NULL THEN NOW() + INTERVAL '365 days'
            ELSE NOW() + (v_hold_days || ' days')::INTERVAL
          END,
          'USD',
          jsonb_build_object(
            'subscription_id', v_subscription.id,
            'buyer_id', v_buyer_id,
            'buyer_name', v_buyer_name,
            'structure', 's1',
            'level', v_current_level,
            'percent', v_commission_percent,
            'freeze_reason', v_freeze_reason,
            'recalculated', true,
            'recalculated_at', NOW(),
            'recalculated_by', p_admin_id
          )
        );
        
        v_commissions_created := v_commissions_created + 1;
      EXCEPTION
        WHEN unique_violation THEN
          v_commissions_skipped := v_commissions_skipped + 1;
      END;
      
      -- Move to next sponsor up the chain
      SELECT sponsor_id INTO v_current_sponsor_id
      FROM profiles
      WHERE id = v_current_sponsor_id;
      
      v_current_level := v_current_level + 1;
    END LOOP;
    
  END LOOP;
  
  -- Log admin action
  INSERT INTO admin_actions (admin_id, action_type, target_type, metadata)
  VALUES (
    p_admin_id,
    'recalculate_s1_commissions',
    'system',
    jsonb_build_object(
      'subscriptions_processed', v_subscriptions_processed,
      'commissions_created', v_commissions_created,
      'commissions_skipped', v_commissions_skipped,
      'executed_at', NOW()
    )
  );
  
  RETURN jsonb_build_object(
    'success', true,
    'subscriptions_processed', v_subscriptions_processed,
    'commissions_created', v_commissions_created,
    'commissions_skipped', v_commissions_skipped
  );
END;
$$;

-- =====================================================
-- PART 4: Create commission structure stats function
-- =====================================================
CREATE OR REPLACE FUNCTION public.get_commission_structure_stats(
  p_user_id UUID,
  p_structure_type INTEGER,
  p_start_date TIMESTAMPTZ DEFAULT NULL,
  p_end_date TIMESTAMPTZ DEFAULT NULL
)
RETURNS TABLE(
  level INTEGER,
  percent NUMERIC,
  partners_count INTEGER,
  earned_cents BIGINT,
  frozen_cents BIGINT,
  volume_cents BIGINT,
  status TEXT,
  unlock_requirement TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_start_date TIMESTAMPTZ;
  v_end_date TIMESTAMPTZ;
BEGIN
  -- Set default date range (current month if not provided)
  v_start_date := COALESCE(p_start_date, DATE_TRUNC('month', NOW()));
  v_end_date := COALESCE(p_end_date, NOW());
  
  RETURN QUERY
  WITH RECURSIVE network AS (
    -- Level 1: Direct referrals
    SELECT 
      r.referred_user_id,
      1 as level
    FROM referrals r
    WHERE r.referrer_id = p_user_id
      AND r.structure_type = p_structure_type
    
    UNION ALL
    
    -- Levels 2+: Recursive traversal
    SELECT 
      r.referred_user_id,
      n.level + 1
    FROM referrals r
    INNER JOIN network n ON r.referrer_id = n.referred_user_id
    WHERE n.level < 10
      AND r.structure_type = p_structure_type
  ),
  level_partners AS (
    SELECT 
      n.level,
      COUNT(DISTINCT n.referred_user_id) as partners_count
    FROM network n
    GROUP BY n.level
  ),
  level_transactions AS (
    SELECT
      t.level,
      SUM(CASE WHEN t.status = 'completed' AND (t.frozen_until IS NULL OR t.frozen_until <= NOW()) THEN t.amount_cents ELSE 0 END) as earned_cents,
      SUM(CASE WHEN t.status = 'completed' AND t.frozen_until > NOW() THEN t.amount_cents ELSE 0 END) as frozen_cents
    FROM transactions t
    WHERE t.user_id = p_user_id
      AND t.type = 'commission'
      AND t.structure_type = CASE 
        WHEN p_structure_type = 1 THEN 'primary'::structure_type
        ELSE 'secondary'::structure_type
      END
      AND t.created_at >= v_start_date
      AND t.created_at <= v_end_date
    GROUP BY t.level
  ),
  user_info AS (
    SELECT
      subscription_active,
      monthly_activation_completed,
      direct_referrals_count
    FROM profiles
    WHERE id = p_user_id
  )
  SELECT
    r.level,
    r.percent,
    COALESCE(lp.partners_count, 0)::INTEGER as partners_count,
    COALESCE(lt.earned_cents, 0)::BIGINT as earned_cents,
    COALESCE(lt.frozen_cents, 0)::BIGINT as frozen_cents,
    COALESCE((lt.earned_cents + lt.frozen_cents) * 100 / NULLIF(r.percent, 0), 0)::BIGINT as volume_cents,
    CASE
      WHEN p_structure_type = 1 THEN
        CASE
          WHEN NOT COALESCE((SELECT subscription_active FROM user_info), false) THEN 'locked'
          WHEN r.level = 1 THEN 'active'
          WHEN r.level <= (SELECT direct_referrals_count FROM user_info) THEN 'active'
          ELSE 'locked'
        END
      ELSE
        CASE
          WHEN NOT COALESCE((SELECT monthly_activation_completed FROM user_info), false) THEN 'locked'
          ELSE 'active'
        END
    END as status,
    CASE
      WHEN p_structure_type = 1 AND r.level > 1 THEN
        CASE
          WHEN r.level > (SELECT direct_referrals_count FROM user_info) 
          THEN 'Требуется ' || r.level || ' прямых партнеров'
          ELSE NULL
        END
      ELSE NULL
    END as unlock_requirement
  FROM mlm_commission_rules r
  LEFT JOIN level_partners lp ON lp.level = r.level
  LEFT JOIN level_transactions lt ON lt.level = r.level
  WHERE r.structure_type = p_structure_type
    AND r.plan_id = 'default'
    AND r.is_active = true
  ORDER BY r.level;
END;
$$;

COMMENT ON FUNCTION public.get_commission_structure_stats IS 'Returns commission structure statistics with partner counts, earnings, and status for each level';
COMMENT ON FUNCTION public.recalculate_all_s1_commissions IS 'Recalculates all S1 subscription commissions for 5 levels. Safe to run multiple times (uses ON CONFLICT).';
COMMENT ON FUNCTION public.get_network_stats IS 'Returns network statistics counting all partners up to 10 levels deep';
COMMENT ON FUNCTION public.award_s1_subscription_commission IS 'Awards S1 subscription commissions for 5 levels using mlm_commission_rules';