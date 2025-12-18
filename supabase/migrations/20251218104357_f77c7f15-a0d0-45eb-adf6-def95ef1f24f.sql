-- ============================================
-- МИГРАЦИЯ СИСТЕМЫ НА ТЕНГЕ (KZT)
-- ============================================
-- ВАЖНО: Эта миграция конвертирует все суммы из USD центов в целые тенге
-- Курс: 1 USD cent = 5.5 KZT (при rate_usd_kzt = 550)
-- ============================================

-- ЭТАП 1: Конвертация существующих данных
-- ============================================

-- 1.1. Конвертация транзакций
UPDATE transactions 
SET amount_cents = ROUND(amount_cents * 5.5)::BIGINT,
    currency = 'KZT'
WHERE currency = 'USD';

-- 1.2. Конвертация withdrawals (amount_cents и fee_cents)
UPDATE withdrawals
SET amount_cents = ROUND(amount_cents * 5.5)::BIGINT,
    fee_cents = ROUND(fee_cents * 5.5)::BIGINT;

-- 1.3. Конвертация auto_withdraw_rules
UPDATE auto_withdraw_rules
SET threshold_cents = ROUND(threshold_cents * 5.5)::BIGINT,
    min_amount_cents = ROUND(min_amount_cents * 5.5)::BIGINT;

-- ЭТАП 2: Обновление SQL функций
-- ============================================

-- 2.1. Обновить функцию create_commission_transactions (комиссии за заказы S2)
CREATE OR REPLACE FUNCTION public.create_commission_transactions()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_buyer_id UUID;
  v_referrer_id UUID;
  v_current_level INTEGER := 1;
  v_max_level INTEGER := 5;
  v_level_percent NUMERIC;
  v_commission_amount BIGINT;
  v_total_kzt NUMERIC;
  v_freeze_days INTEGER;
  v_freeze_until TIMESTAMPTZ;
  v_buyer_activated BOOLEAN;
BEGIN
  -- Only process when order becomes paid
  IF NEW.status = 'paid' AND (OLD IS NULL OR OLD.status IS DISTINCT FROM 'paid') THEN
    v_buyer_id := NEW.user_id;
    v_total_kzt := NEW.total_kzt;
    
    -- Get freeze period from settings
    SELECT COALESCE((value::text)::integer, 14)
    INTO v_freeze_days
    FROM mlm_settings
    WHERE key = 'commission_freeze_days';
    
    v_freeze_until := now() + (v_freeze_days || ' days')::interval;
    
    -- Check if buyer is activated
    SELECT is_active INTO v_buyer_activated
    FROM profiles WHERE id = v_buyer_id;
    
    -- Find first referrer
    SELECT referrer_id INTO v_referrer_id
    FROM referrals
    WHERE referred_user_id = v_buyer_id
      AND structure_type = 2
    LIMIT 1;
    
    -- Walk up the referral chain
    WHILE v_referrer_id IS NOT NULL AND v_current_level <= v_max_level LOOP
      -- Get commission percent for this level
      SELECT percent INTO v_level_percent
      FROM mlm_commission_rules
      WHERE structure_type = 2
        AND level = v_current_level
        AND is_active = true
      ORDER BY effective_from DESC
      LIMIT 1;
      
      IF v_level_percent IS NOT NULL AND v_level_percent > 0 THEN
        -- Calculate commission in KZT (целые тенге)
        v_commission_amount := (v_total_kzt * v_level_percent / 100)::BIGINT;
        
        IF v_commission_amount > 0 THEN
          -- Create commission transaction in KZT
          INSERT INTO transactions (
            user_id,
            type,
            amount_cents,
            currency,
            status,
            source_id,
            source_ref,
            level,
            structure_type,
            frozen_until,
            payload
          ) VALUES (
            v_referrer_id,
            'commission',
            v_commission_amount,
            'KZT',
            'frozen',
            NEW.id,
            'order_' || NEW.id,
            v_current_level,
            'secondary',
            v_freeze_until,
            jsonb_build_object(
              'order_id', NEW.id,
              'buyer_id', v_buyer_id,
              'level', v_current_level,
              'percent', v_level_percent,
              'order_total_kzt', v_total_kzt
            )
          );
        END IF;
      END IF;
      
      -- Move to next level
      v_current_level := v_current_level + 1;
      
      -- Find next referrer in chain
      SELECT r.referrer_id INTO v_referrer_id
      FROM referrals r
      WHERE r.referred_user_id = v_referrer_id
        AND r.structure_type = 2
      LIMIT 1;
    END LOOP;
  END IF;
  
  RETURN NEW;
END;
$$;

-- 2.2. Обновить функцию award_s1_subscription_commission (комиссии за подписки S1)
CREATE OR REPLACE FUNCTION public.award_s1_subscription_commission()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_subscriber_id UUID;
  v_referrer_id UUID;
  v_current_level INTEGER := 1;
  v_max_level INTEGER := 10;
  v_level_percent NUMERIC;
  v_commission_amount BIGINT;
  v_freeze_days INTEGER;
  v_freeze_until TIMESTAMPTZ;
  v_referrer_active BOOLEAN;
  v_referrer_subscription_status TEXT;
BEGIN
  -- Only process when subscription becomes active (status changes to 'active' and paid_at is set)
  IF NEW.status = 'active' AND NEW.paid_at IS NOT NULL AND (OLD IS NULL OR OLD.status IS DISTINCT FROM 'active' OR OLD.paid_at IS NULL) THEN
    v_subscriber_id := NEW.user_id;
    
    -- Skip if this is a marketing free access subscription
    IF NEW.is_marketing_free_access = true THEN
      RETURN NEW;
    END IF;
    
    -- Get freeze period from settings
    SELECT COALESCE((value::text)::integer, 14)
    INTO v_freeze_days
    FROM mlm_settings
    WHERE key = 'commission_freeze_days';
    
    v_freeze_until := now() + (v_freeze_days || ' days')::interval;
    
    -- Find first referrer in S1 structure
    SELECT referrer_id INTO v_referrer_id
    FROM referrals
    WHERE referred_user_id = v_subscriber_id
      AND structure_type = 1
    LIMIT 1;
    
    -- If no S1 referrer, try sponsor from profile
    IF v_referrer_id IS NULL THEN
      SELECT sponsor_id INTO v_referrer_id
      FROM profiles
      WHERE id = v_subscriber_id;
    END IF;
    
    -- Walk up the referral chain
    WHILE v_referrer_id IS NOT NULL AND v_current_level <= v_max_level LOOP
      -- Check if referrer is active and has subscription
      SELECT is_active, subscription_status
      INTO v_referrer_active, v_referrer_subscription_status
      FROM profiles
      WHERE id = v_referrer_id;
      
      -- Get commission percent for this level
      SELECT percent INTO v_level_percent
      FROM mlm_commission_rules
      WHERE structure_type = 1
        AND level = v_current_level
        AND is_active = true
      ORDER BY effective_from DESC
      LIMIT 1;
      
      IF v_level_percent IS NOT NULL AND v_level_percent > 0 THEN
        -- Calculate commission in KZT (целые тенге)
        v_commission_amount := (NEW.amount_kzt * v_level_percent / 100)::BIGINT;
        
        IF v_commission_amount > 0 THEN
          -- Create commission transaction in KZT
          INSERT INTO transactions (
            user_id,
            type,
            amount_cents,
            currency,
            status,
            source_id,
            source_ref,
            level,
            structure_type,
            frozen_until,
            payload
          ) VALUES (
            v_referrer_id,
            'commission',
            v_commission_amount,
            'KZT',
            'frozen',
            NEW.id,
            'subscription_' || NEW.id,
            v_current_level,
            'primary',
            v_freeze_until,
            jsonb_build_object(
              'subscription_id', NEW.id,
              'subscriber_id', v_subscriber_id,
              'level', v_current_level,
              'percent', v_level_percent,
              'subscription_amount_kzt', NEW.amount_kzt
            )
          );
        END IF;
      END IF;
      
      -- Move to next level
      v_current_level := v_current_level + 1;
      
      -- Find next referrer in chain (using sponsor_id)
      SELECT sponsor_id INTO v_referrer_id
      FROM profiles
      WHERE id = v_referrer_id;
    END LOOP;
  END IF;
  
  RETURN NEW;
END;
$$;

-- 2.3. Обновить функцию process_manual_payout (ручные выплаты)
CREATE OR REPLACE FUNCTION public.process_manual_payout(
  p_user_id UUID,
  p_amount_cents BIGINT,
  p_comment TEXT
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_balance_record RECORD;
  v_withdrawal_id UUID;
  v_transaction_id UUID;
BEGIN
  -- Check available balance
  SELECT * INTO v_balance_record
  FROM get_user_balance(p_user_id);
  
  IF v_balance_record.available_cents < p_amount_cents THEN
    RETURN json_build_object(
      'success', false,
      'error', 'Недостаточно средств на балансе'
    );
  END IF;
  
  -- Create withdrawal record
  INSERT INTO withdrawals (
    user_id,
    amount_cents,
    fee_cents,
    status
  ) VALUES (
    p_user_id,
    p_amount_cents,
    0,
    'completed'
  )
  RETURNING id INTO v_withdrawal_id;
  
  -- Create withdrawal transaction in KZT
  INSERT INTO transactions (
    user_id,
    type,
    amount_cents,
    currency,
    status,
    source_id,
    source_ref,
    payload
  ) VALUES (
    p_user_id,
    'withdrawal',
    p_amount_cents,
    'KZT',
    'completed',
    v_withdrawal_id,
    'manual_payout_' || v_withdrawal_id,
    jsonb_build_object('comment', p_comment)
  )
  RETURNING id INTO v_transaction_id;
  
  -- Update withdrawal with transaction_id
  UPDATE withdrawals
  SET transaction_id = v_transaction_id,
      processed_at = now()
  WHERE id = v_withdrawal_id;
  
  RETURN json_build_object(
    'success', true,
    'withdrawal_id', v_withdrawal_id,
    'transaction_id', v_transaction_id
  );
END;
$$;

-- 2.4. Обновить функцию notify_commission_earned (уведомления)
CREATE OR REPLACE FUNCTION public.notify_commission_earned()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_email TEXT;
  v_user_telegram_chat_id TEXT;
  v_notification_settings RECORD;
  v_amount_display TEXT;
  v_structure_name TEXT;
BEGIN
  -- Only notify on new commission transactions
  IF NEW.type = 'commission' THEN
    -- Get user info
    SELECT email, telegram_chat_id
    INTO v_user_email, v_user_telegram_chat_id
    FROM profiles
    WHERE id = NEW.user_id;
    
    -- Get notification settings
    SELECT * INTO v_notification_settings
    FROM notification_settings
    WHERE user_id = NEW.user_id;
    
    -- Format amount display in KZT (amount_cents уже в тенге)
    v_amount_display := NEW.amount_cents::text || ' ₸';
    
    -- Get structure name
    IF NEW.structure_type = 'primary' THEN
      v_structure_name := 'Структура 1 (подписки)';
    ELSE
      v_structure_name := 'Структура 2 (продукты)';
    END IF;
    
    -- Create admin notification
    INSERT INTO admin_notifications (
      admin_id,
      type,
      title,
      message,
      metadata
    )
    SELECT 
      ur.user_id,
      'commission',
      'Новая комиссия начислена',
      'Пользователю ' || COALESCE(v_user_email, 'unknown') || ' начислена комиссия ' || v_amount_display || ' (' || v_structure_name || ', уровень ' || COALESCE(NEW.level::text, '?') || ')',
      jsonb_build_object(
        'transaction_id', NEW.id,
        'user_id', NEW.user_id,
        'amount_kzt', NEW.amount_cents,
        'level', NEW.level,
        'structure_type', NEW.structure_type
      )
    FROM user_roles ur
    WHERE ur.role IN ('admin', 'superadmin');
  END IF;
  
  RETURN NEW;
END;
$$;