-- =============================================
-- FIX: Duplicate S1 commissions and unify source_ref format
-- =============================================

-- Step 1: Delete duplicate transactions, keeping only the earliest one per subscription+level
DELETE FROM transactions 
WHERE id IN (
  SELECT id FROM (
    SELECT id, 
           ROW_NUMBER() OVER (
             PARTITION BY source_id, level, user_id 
             ORDER BY created_at ASC
           ) as rn
    FROM transactions 
    WHERE type = 'commission' 
      AND structure_type = 'primary'
      AND source_id IS NOT NULL
  ) ranked
  WHERE rn > 1
);

-- Step 2: Unify source_ref format for all existing S1 commission transactions
UPDATE transactions 
SET source_ref = 'subscription_' || source_id || '_s1_level_' || level
WHERE type = 'commission' 
  AND structure_type = 'primary'
  AND source_id IS NOT NULL
  AND source_ref IS DISTINCT FROM ('subscription_' || source_id || '_s1_level_' || level);

-- Step 3: Fix award_s1_subscription_commission function with unified source_ref format
CREATE OR REPLACE FUNCTION public.award_s1_subscription_commission()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_buyer_id UUID;
  v_buyer_name TEXT;
  v_amount_usd NUMERIC;
  v_current_user_id UUID;
  v_current_level INTEGER := 1;
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
    FROM profiles WHERE id = NEW.user_id;
    
    v_amount_usd := NEW.amount_usd;
    v_current_user_id := NEW.user_id;
    
    -- Traverse sponsor chain up to 5 levels
    WHILE v_current_level <= v_max_levels AND v_current_user_id IS NOT NULL LOOP
      -- Get sponsor
      SELECT sponsor_id INTO v_current_user_id 
      FROM profiles 
      WHERE id = v_current_user_id;
      
      IF v_current_user_id IS NOT NULL THEN
        -- Check sponsor activation status
        SELECT 
          (subscription_status = 'active' AND monthly_activation_completed = true)
        INTO v_sponsor_is_active
        FROM profiles
        WHERE id = v_current_user_id;
        
        -- Get commission percent from mlm_commission_rules (S1 = structure_type 1)
        SELECT percent INTO v_commission_percent 
        FROM mlm_commission_rules 
        WHERE structure_type = 1 
          AND level = v_current_level
          AND plan_id = 'default'
          AND is_active = true;
        
        -- Default to 10% if no rule found
        IF v_commission_percent IS NULL THEN
          v_commission_percent := 10;
        END IF;
        
        -- Calculate commission in cents
        v_commission_cents := (v_amount_usd * 100 * v_commission_percent / 100)::BIGINT;
        
        -- Determine freeze reason
        IF NOT COALESCE(v_sponsor_is_active, false) THEN
          v_freeze_reason := 'sponsor_inactive';
        ELSE
          v_freeze_reason := NULL;
        END IF;
        
        -- UNIFIED source_ref format (NO _recalc suffix!)
        v_unique_ref := 'subscription_' || NEW.id || '_s1_level_' || v_current_level;
        
        -- Insert commission transaction with conflict handling
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
          v_current_user_id,
          'commission',
          v_commission_cents,
          CASE WHEN v_freeze_reason IS NOT NULL THEN 'frozen' ELSE 'completed' END,
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
            'percent', v_commission_percent,
            'freeze_reason', v_freeze_reason
          )
        ) ON CONFLICT (source_ref) DO NOTHING;
        
        v_current_level := v_current_level + 1;
      END IF;
    END LOOP;
  END IF;
  
  RETURN NEW;
END;
$function$;

-- Step 4: Fix recalculate_all_s1_commissions function with unified source_ref format
CREATE OR REPLACE FUNCTION public.recalculate_all_s1_commissions(p_admin_id UUID)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_subscription RECORD;
  v_current_user_id UUID;
  v_current_level INTEGER;
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

  -- Process all active subscriptions
  FOR v_subscription IN
    SELECT s.id, s.user_id, s.amount_usd, p.full_name as buyer_name
    FROM subscriptions s
    JOIN profiles p ON p.id = s.user_id
    WHERE s.status = 'active'
      AND s.paid_at IS NOT NULL
  LOOP
    v_subscriptions_processed := v_subscriptions_processed + 1;
    v_current_user_id := v_subscription.user_id;
    v_current_level := 1;
    
    -- Traverse sponsor chain up to 5 levels
    WHILE v_current_level <= v_max_levels AND v_current_user_id IS NOT NULL LOOP
      -- Get sponsor
      SELECT sponsor_id INTO v_current_user_id 
      FROM profiles 
      WHERE id = v_current_user_id;
      
      IF v_current_user_id IS NOT NULL THEN
        -- Check sponsor activation status
        SELECT 
          (subscription_status = 'active' AND monthly_activation_completed = true)
        INTO v_sponsor_is_active
        FROM profiles
        WHERE id = v_current_user_id;
        
        -- Get commission percent
        SELECT percent INTO v_commission_percent 
        FROM mlm_commission_rules 
        WHERE structure_type = 1 
          AND level = v_current_level
          AND plan_id = 'default'
          AND is_active = true;
        
        IF v_commission_percent IS NULL THEN
          v_commission_percent := 10;
        END IF;
        
        -- Calculate commission
        v_commission_cents := (v_subscription.amount_usd * 100 * v_commission_percent / 100)::BIGINT;
        
        -- Determine freeze reason
        IF NOT COALESCE(v_sponsor_is_active, false) THEN
          v_freeze_reason := 'sponsor_inactive';
        ELSE
          v_freeze_reason := NULL;
        END IF;
        
        -- UNIFIED source_ref format (same as trigger, NO _recalc!)
        v_unique_ref := 'subscription_' || v_subscription.id || '_s1_level_' || v_current_level;
        
        -- Insert commission (skip if exists)
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
            v_current_user_id,
            'commission',
            v_commission_cents,
            CASE WHEN v_freeze_reason IS NOT NULL THEN 'frozen' ELSE 'completed' END,
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
              'buyer_id', v_subscription.user_id,
              'buyer_name', v_subscription.buyer_name,
              'structure', 's1',
              'percent', v_commission_percent,
              'freeze_reason', v_freeze_reason,
              'recalculated', true,
              'recalculated_at', NOW()
            )
          ) ON CONFLICT (source_ref) DO NOTHING;
          
          IF FOUND THEN
            v_commissions_created := v_commissions_created + 1;
          ELSE
            v_commissions_skipped := v_commissions_skipped + 1;
          END IF;
        EXCEPTION WHEN unique_violation THEN
          v_commissions_skipped := v_commissions_skipped + 1;
        END;
        
        v_current_level := v_current_level + 1;
      END IF;
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
      'commissions_skipped', v_commissions_skipped
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'subscriptions_processed', v_subscriptions_processed,
    'commissions_created', v_commissions_created,
    'commissions_skipped', v_commissions_skipped
  );
END;
$function$;