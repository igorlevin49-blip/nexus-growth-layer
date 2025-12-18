-- Fix: Add buyer name to commission transaction payload and update notification trigger

-- 1. Update create_commission_transactions to include buyer name
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
  buyer_full_name TEXT;
  commission_percent NUMERIC;
  commission_amount_cents BIGINT;
  hold_days INTEGER := 7;
BEGIN
  IF NEW.status = 'paid' AND (OLD.status IS NULL OR OLD.status != 'paid') THEN
    -- Get order total and buyer name
    SELECT (total_usd * 100)::BIGINT INTO order_total_cents FROM orders WHERE id = NEW.id;
    SELECT full_name INTO buyer_full_name FROM profiles WHERE id = NEW.user_id;
    
    current_user_id := NEW.user_id;
    
    WHILE current_level <= 10 AND current_user_id IS NOT NULL LOOP
      SELECT sponsor_id INTO current_user_id FROM profiles WHERE id = current_user_id;
      
      IF current_user_id IS NOT NULL THEN
        -- Use mlm_commission_rules with structure_type = 2 for orders
        SELECT percent INTO commission_percent 
        FROM mlm_commission_rules 
        WHERE plan_id = 'default' 
          AND structure_type = 2
          AND level = current_level
          AND is_active = true;
        
        IF commission_percent IS NOT NULL AND commission_percent > 0 THEN
          commission_amount_cents := (order_total_cents * commission_percent / 100)::BIGINT;
          
          INSERT INTO transactions (
            user_id, type, amount_cents, status, source_id, source_ref,
            level, structure_type, frozen_until, payload
          ) VALUES (
            current_user_id, 'commission'::transaction_type, commission_amount_cents, 'completed'::transaction_status,
            NEW.id, 'order_' || NEW.id || '_level_' || current_level || '_secondary',
            current_level, 'secondary', NOW() + (hold_days || ' days')::INTERVAL,
            jsonb_build_object(
              'order_id', NEW.id, 
              'buyer_id', NEW.user_id, 
              'from_user', COALESCE(buyer_full_name, 'партнёра'),
              'level', current_level, 
              'structure', 'secondary', 
              'percent', commission_percent
            )
          ) ON CONFLICT (source_ref) DO NOTHING;
        END IF;
        
        current_level := current_level + 1;
      END IF;
    END LOOP;
  END IF;
  
  RETURN NEW;
END;
$function$;

-- 2. Update award_s1_subscription_commission to include buyer name
CREATE OR REPLACE FUNCTION public.award_s1_subscription_commission()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_sponsor_id UUID;
  v_sponsor_active BOOLEAN;
  v_buyer_name TEXT;
  v_commission_percent NUMERIC := 10;
  v_commission_cents BIGINT;
  v_hold_days INTEGER := 7;
  v_freeze_reason TEXT;
  v_unique_ref TEXT;
  v_current_level INTEGER;
  v_current_user_id UUID;
  v_level_percent NUMERIC;
BEGIN
  IF NEW.status = 'active' AND (OLD.status IS NULL OR OLD.status != 'active') THEN
    -- Get buyer name
    SELECT full_name INTO v_buyer_name FROM profiles WHERE id = NEW.user_id;
    
    v_current_user_id := NEW.user_id;
    v_current_level := 1;
    
    WHILE v_current_level <= 5 AND v_current_user_id IS NOT NULL LOOP
      SELECT sponsor_id INTO v_current_user_id FROM profiles WHERE id = v_current_user_id;
      
      IF v_current_user_id IS NOT NULL THEN
        SELECT (subscription_status = 'active' AND monthly_activation_completed = true)
        INTO v_sponsor_active
        FROM profiles
        WHERE id = v_current_user_id;
        
        v_level_percent := 10;
        v_commission_cents := (NEW.amount_usd * 100 * v_level_percent / 100)::BIGINT;
        
        IF NOT COALESCE(v_sponsor_active, false) THEN
          v_freeze_reason := 'sponsor_inactive';
        ELSE
          v_freeze_reason := NULL;
        END IF;
        
        v_unique_ref := 'subscription_' || NEW.id || '_s1_level_' || v_current_level;
        
        INSERT INTO transactions (
          user_id, type, amount_cents, status, source_id, source_ref,
          level, structure_type, frozen_until, currency, payload
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
            'from_user', COALESCE(v_buyer_name, 'партнёра'),
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

-- 3. Update notify_commission_earned to check both from_user and buyer_name
CREATE OR REPLACE FUNCTION public.notify_commission_earned()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_from_user text;
  v_amount_display text;
BEGIN
  IF NEW.type = 'commission' AND NEW.status = 'completed' THEN
    -- Try from_user first, then buyer_name, then default
    v_from_user := COALESCE(
      NEW.payload->>'from_user', 
      NEW.payload->>'buyer_name', 
      'партнёра'
    );
    
    -- Format amount: cents * 5 for KZT (assuming USD cents * 500 rate)
    v_amount_display := ROUND(NEW.amount_cents * 5)::text || ' ₸';
    
    INSERT INTO user_modal_notifications (user_id, title, message, type)
    VALUES (
      NEW.user_id,
      'Поздравляем с комиссией!',
      'Вам начислено ' || v_amount_display || ' за партнёра ' || v_from_user,
      'success'
    );
  END IF;
  RETURN NEW;
END;
$$;