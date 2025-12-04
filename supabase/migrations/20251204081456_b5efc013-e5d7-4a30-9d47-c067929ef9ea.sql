-- Fix type casting for status column in commission functions

-- 1. Fix award_s1_subscription_commission
CREATE OR REPLACE FUNCTION public.award_s1_subscription_commission()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_sponsor_id UUID;
  v_sponsor_active BOOLEAN;
  v_commission_percent NUMERIC := 10;
  v_commission_cents BIGINT;
  v_hold_days INTEGER := 7;
  v_freeze_reason TEXT;
  v_unique_ref TEXT;
  v_current_level INTEGER;
  v_current_user_id UUID;
  v_level_percent NUMERIC;
BEGIN
  -- Only process when subscription becomes active
  IF NEW.status = 'active' AND (OLD.status IS NULL OR OLD.status != 'active') THEN
    
    -- Get the buyer's sponsor chain
    v_current_user_id := NEW.user_id;
    v_current_level := 1;
    
    -- Process up to 5 levels for S1 subscription commission
    WHILE v_current_level <= 5 AND v_current_user_id IS NOT NULL LOOP
      -- Get sponsor
      SELECT sponsor_id INTO v_current_user_id 
      FROM profiles 
      WHERE id = v_current_user_id;
      
      IF v_current_user_id IS NOT NULL THEN
        -- Check if sponsor is active
        SELECT 
          (subscription_status = 'active' AND monthly_activation_completed = true)
        INTO v_sponsor_active
        FROM profiles
        WHERE id = v_current_user_id;
        
        -- Set commission percent based on level (10% for all 5 levels)
        v_level_percent := 10;
        v_commission_cents := (NEW.amount_usd * 100 * v_level_percent / 100)::BIGINT;
        
        -- Determine if commission should be frozen
        IF NOT COALESCE(v_sponsor_active, false) THEN
          v_freeze_reason := 'sponsor_inactive';
        ELSE
          v_freeze_reason := NULL;
        END IF;
        
        -- Create unique reference
        v_unique_ref := 'subscription_' || NEW.id || '_s1_level_' || v_current_level;
        
        -- Insert commission transaction with explicit type cast
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
          'commission'::transaction_type,
          v_commission_cents,
          CASE WHEN v_freeze_reason IS NOT NULL THEN 'frozen'::transaction_status ELSE 'completed'::transaction_status END,
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
            'buyer_id', NEW.user_id,
            'structure', 's1',
            'level', v_current_level,
            'percent', v_level_percent,
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

-- 2. Fix create_commission_transactions
CREATE OR REPLACE FUNCTION public.create_commission_transactions()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  order_total_cents BIGINT;
  current_level INTEGER := 1;
  current_user_id UUID;
  commission_percent NUMERIC;
  commission_amount_cents BIGINT;
  hold_days INTEGER := 7;
BEGIN
  IF NEW.status = 'paid' AND (OLD.status IS NULL OR OLD.status != 'paid') THEN
    SELECT (total_usd * 100)::BIGINT INTO order_total_cents FROM orders WHERE id = NEW.id;
    current_user_id := NEW.user_id;
    
    WHILE current_level <= 10 AND current_user_id IS NOT NULL LOOP
      SELECT sponsor_id INTO current_user_id FROM profiles WHERE id = current_user_id;
      
      IF current_user_id IS NOT NULL THEN
        SELECT percent INTO commission_percent 
        FROM commission_plan_levels 
        WHERE plan_id = 'default' 
          AND structure_type = 'primary' 
          AND level = current_level;
        
        IF commission_percent IS NOT NULL AND commission_percent > 0 THEN
          commission_amount_cents := (order_total_cents * commission_percent / 100)::BIGINT;
          
          INSERT INTO transactions (
            user_id, type, amount_cents, status, source_id, source_ref,
            level, structure_type, frozen_until, payload
          ) VALUES (
            current_user_id, 'commission'::transaction_type, commission_amount_cents, 'completed'::transaction_status,
            NEW.id, 'order_' || NEW.id || '_level_' || current_level || '_primary',
            current_level, 'primary', NOW() + (hold_days || ' days')::INTERVAL,
            jsonb_build_object('order_id', NEW.id, 'buyer_id', NEW.user_id, 'level', current_level, 'structure', 'primary', 'percent', commission_percent)
          ) ON CONFLICT (source_ref) DO NOTHING;
        END IF;
        
        current_level := current_level + 1;
      END IF;
    END LOOP;
  END IF;
  
  RETURN NEW;
END;
$function$;

-- 3. Fix admin_recalculate_commissions
CREATE OR REPLACE FUNCTION public.admin_recalculate_commissions()
 RETURNS TABLE(recalculated_subscriptions integer, recalculated_orders integer, total_commissions_created integer, details jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_subscription RECORD;
  v_order RECORD;
  v_sponsor_id UUID;
  v_current_user_id UUID;
  v_current_level INTEGER;
  v_commission_percent NUMERIC;
  v_commission_cents BIGINT;
  v_sponsor_is_active BOOLEAN;
  v_freeze_reason TEXT;
  v_unique_ref TEXT;
  v_subscription_count INTEGER := 0;
  v_order_count INTEGER := 0;
  v_total_commissions INTEGER := 0;
  v_hold_days INTEGER := 7;
  v_details JSONB := '[]'::JSONB;
BEGIN
  -- Check if user is admin or superadmin
  IF NOT (has_role(auth.uid(), 'admin') OR has_role(auth.uid(), 'superadmin')) THEN
    RAISE EXCEPTION 'UNAUTHORIZED';
  END IF;

  -- ====================================
  -- PART 1: Recalculate Subscription Commissions (S1)
  -- ====================================
  FOR v_subscription IN
    SELECT s.id, s.user_id, s.amount_usd, s.paid_at, p.sponsor_id, p.full_name, p.email
    FROM subscriptions s
    JOIN profiles p ON p.id = s.user_id
    WHERE s.status = 'active'
      AND s.paid_at IS NOT NULL
      AND p.sponsor_id IS NOT NULL
      AND NOT EXISTS (
        SELECT 1 FROM transactions t 
        WHERE t.source_ref LIKE 'subscription_' || s.id::TEXT || '%'
        AND t.type = 'commission'
      )
  LOOP
    -- Get sponsor details
    SELECT 
      id,
      subscription_active AND monthly_activation_completed as is_active
    INTO v_sponsor_id, v_sponsor_is_active
    FROM profiles
    WHERE id = v_subscription.sponsor_id;

    -- Set S1 commission (10%)
    v_commission_percent := 10;
    v_commission_cents := (v_subscription.amount_usd * 100 * v_commission_percent / 100)::BIGINT;

    -- Determine freeze reason if sponsor not active
    IF NOT v_sponsor_is_active THEN
      v_freeze_reason := 'sponsor_inactive';
    ELSE
      v_freeze_reason := NULL;
    END IF;

    -- Create unique reference
    v_unique_ref := 'subscription_' || v_subscription.id || '_s1_recalc';

    -- Insert S1 commission with explicit type cast
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
      v_sponsor_id,
      'commission'::transaction_type,
      v_commission_cents,
      'completed'::transaction_status,
      v_subscription.id,
      v_unique_ref,
      1,
      'primary',
      CASE 
        WHEN v_freeze_reason IS NOT NULL THEN NOW() + INTERVAL '365 days'
        ELSE NOW() + (v_hold_days || ' days')::INTERVAL
      END,
      'USD',
      jsonb_build_object(
        'subscription_id', v_subscription.id,
        'buyer_id', v_subscription.user_id,
        'buyer_name', v_subscription.full_name,
        'structure', 's1',
        'percent', v_commission_percent,
        'freeze_reason', v_freeze_reason,
        'recalculated', true,
        'recalculated_at', NOW()
      )
    ) ON CONFLICT (source_ref) DO NOTHING;

    v_subscription_count := v_subscription_count + 1;
    v_total_commissions := v_total_commissions + 1;

    v_details := v_details || jsonb_build_object(
      'type', 'subscription',
      'subscription_id', v_subscription.id,
      'user_email', v_subscription.email,
      'sponsor_id', v_sponsor_id,
      'commission_cents', v_commission_cents
    );
  END LOOP;

  -- ====================================
  -- PART 2: Recalculate Order Commissions (P1-P10)
  -- ====================================
  FOR v_order IN
    SELECT o.id, o.user_id, o.total_usd, o.paid_at, p.sponsor_id, p.full_name, p.email
    FROM orders o
    JOIN profiles p ON p.id = o.user_id
    WHERE o.status = 'paid'
      AND o.paid_at IS NOT NULL
      AND p.sponsor_id IS NOT NULL
      AND NOT EXISTS (
        SELECT 1 FROM transactions t 
        WHERE t.source_ref LIKE 'order_' || o.id::TEXT || '%'
        AND t.type = 'commission'
      )
  LOOP
    -- Initialize for traversing sponsor chain
    v_current_user_id := v_order.user_id;
    v_current_level := 1;

    -- Traverse up to 10 levels for primary structure
    WHILE v_current_level <= 10 AND v_current_user_id IS NOT NULL LOOP
      -- Get sponsor
      SELECT sponsor_id INTO v_current_user_id 
      FROM profiles 
      WHERE id = v_current_user_id;

      IF v_current_user_id IS NOT NULL THEN
        -- Get commission percentage for this level
        SELECT percent INTO v_commission_percent 
        FROM commission_plan_levels 
        WHERE plan_id = 'default' 
          AND structure_type = 'primary' 
          AND level = v_current_level;

        IF v_commission_percent IS NOT NULL AND v_commission_percent > 0 THEN
          -- Calculate commission
          v_commission_cents := (v_order.total_usd * 100 * v_commission_percent / 100)::BIGINT;

          -- Create unique reference
          v_unique_ref := 'order_' || v_order.id || '_level_' || v_current_level || '_primary_recalc';

          -- Insert commission with explicit type cast
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
            'commission'::transaction_type,
            v_commission_cents,
            'completed'::transaction_status,
            v_order.id,
            v_unique_ref,
            v_current_level,
            'primary',
            NOW() + (v_hold_days || ' days')::INTERVAL,
            'USD',
            jsonb_build_object(
              'order_id', v_order.id,
              'buyer_id', v_order.user_id,
              'buyer_name', v_order.full_name,
              'level', v_current_level,
              'structure', 'primary',
              'percent', v_commission_percent,
              'recalculated', true,
              'recalculated_at', NOW()
            )
          ) ON CONFLICT (source_ref) DO NOTHING;

          v_total_commissions := v_total_commissions + 1;
        END IF;

        v_current_level := v_current_level + 1;
      END IF;
    END LOOP;

    v_order_count := v_order_count + 1;

    v_details := v_details || jsonb_build_object(
      'type', 'order',
      'order_id', v_order.id,
      'user_email', v_order.email,
      'levels_processed', v_current_level - 1
    );
  END LOOP;

  -- Return summary
  RETURN QUERY SELECT 
    v_subscription_count,
    v_order_count,
    v_total_commissions,
    v_details;
END;
$function$;

-- 4. Fix recalculate_all_s1_commissions
CREATE OR REPLACE FUNCTION public.recalculate_all_s1_commissions(p_admin_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_subscription RECORD;
  v_current_user_id UUID;
  v_current_level INTEGER;
  v_sponsor_active BOOLEAN;
  v_commission_cents BIGINT;
  v_freeze_reason TEXT;
  v_unique_ref TEXT;
  v_hold_days INTEGER := 7;
  v_subscriptions_processed INTEGER := 0;
  v_commissions_created INTEGER := 0;
  v_commissions_skipped INTEGER := 0;
BEGIN
  -- Check if user is admin or superadmin
  IF NOT (has_role(p_admin_id, 'admin') OR has_role(p_admin_id, 'superadmin')) THEN
    RAISE EXCEPTION 'UNAUTHORIZED';
  END IF;

  -- Process all active subscriptions
  FOR v_subscription IN
    SELECT s.id, s.user_id, s.amount_usd, p.full_name
    FROM subscriptions s
    JOIN profiles p ON p.id = s.user_id
    WHERE s.status = 'active'
      AND s.paid_at IS NOT NULL
  LOOP
    v_subscriptions_processed := v_subscriptions_processed + 1;
    v_current_user_id := v_subscription.user_id;
    v_current_level := 1;
    
    -- Process up to 5 levels for S1
    WHILE v_current_level <= 5 AND v_current_user_id IS NOT NULL LOOP
      -- Get sponsor
      SELECT sponsor_id INTO v_current_user_id 
      FROM profiles 
      WHERE id = v_current_user_id;
      
      IF v_current_user_id IS NOT NULL THEN
        -- Check if sponsor is active
        SELECT 
          (subscription_status = 'active' AND monthly_activation_completed = true)
        INTO v_sponsor_active
        FROM profiles
        WHERE id = v_current_user_id;
        
        -- Calculate commission (10% for all levels)
        v_commission_cents := (v_subscription.amount_usd * 100 * 10 / 100)::BIGINT;
        
        -- Determine freeze reason
        IF NOT COALESCE(v_sponsor_active, false) THEN
          v_freeze_reason := 'sponsor_inactive';
        ELSE
          v_freeze_reason := NULL;
        END IF;
        
        -- Create unique reference
        v_unique_ref := 'subscription_' || v_subscription.id || '_s1_level_' || v_current_level;
        
        -- Try to insert (skip if exists)
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
          'commission'::transaction_type,
          v_commission_cents,
          CASE WHEN v_freeze_reason IS NOT NULL THEN 'frozen'::transaction_status ELSE 'completed'::transaction_status END,
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
            'buyer_name', v_subscription.full_name,
            'structure', 's1',
            'level', v_current_level,
            'percent', 10,
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
        
        v_current_level := v_current_level + 1;
      END IF;
    END LOOP;
  END LOOP;

  RETURN jsonb_build_object(
    'success', true,
    'subscriptions_processed', v_subscriptions_processed,
    'commissions_created', v_commissions_created,
    'commissions_skipped', v_commissions_skipped
  );
END;
$function$;