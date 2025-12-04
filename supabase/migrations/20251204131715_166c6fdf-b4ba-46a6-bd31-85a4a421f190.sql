-- 1. Обновляем функцию award_s1_subscription_commission с проверкой is_marketing_free_access
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
    
    -- ВАЖНО: Пропускаем маркетинговые подписки (бесплатный доступ) - от них НЕ начисляются комиссии
    IF NEW.is_marketing_free_access = true THEN
      RETURN NEW;
    END IF;
    
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

-- 2. Удаляем ошибочно начисленные комиссии от бесплатных подписок
DELETE FROM transactions
WHERE type = 'commission'
AND source_ref LIKE 'subscription_%'
AND source_id IN (
  SELECT id FROM subscriptions WHERE is_marketing_free_access = true
);