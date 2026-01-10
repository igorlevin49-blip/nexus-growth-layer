-- Fix award_s1_subscription_commission trigger function
-- The trigger is on 'subscriptions' table which has 'status' column, not 'subscription_status'
-- Also fix structure_type comparison (integer, not text)

CREATE OR REPLACE FUNCTION public.award_s1_subscription_commission()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_subscriber_id uuid;
  v_sponsor_id uuid;
  v_current_sponsor uuid;
  v_level integer := 0;
  v_commission_rate numeric;
  v_commission_amount numeric;
  v_subscription_price numeric;
  v_sponsor_qualified boolean;
  v_max_levels integer := 5;
  v_freeze_days integer;
  v_frozen_until timestamptz;
  v_source_ref text;
  v_direct_referrals_count integer;
  v_required_referrals integer;
BEGIN
  -- Только для активных подписок (subscriptions table has 'status', not 'subscription_status')
  IF NEW.status != 'active' THEN
    RETURN NEW;
  END IF;
  
  -- Только если статус изменился на active
  IF OLD IS NOT NULL AND OLD.status = 'active' THEN
    RETURN NEW;
  END IF;
  
  -- Подписка теперь активна - начисляем комиссии
  v_subscriber_id := NEW.user_id;
  
  -- Получаем настройки заморозки
  SELECT COALESCE((value->>'commission_freeze_days')::integer, 30)
  INTO v_freeze_days
  FROM mlm_settings
  WHERE key = 'freeze_settings';
  
  IF v_freeze_days > 0 THEN
    v_frozen_until := NOW() + (v_freeze_days || ' days')::interval;
  END IF;
  
  -- Используем сумму из подписки
  v_subscription_price := NEW.amount_kzt;
  
  -- Если сумма 0 или null, получаем из настроек
  IF v_subscription_price IS NULL OR v_subscription_price <= 0 THEN
    SELECT COALESCE((value->>'subscription_price')::numeric, 11000)
    INTO v_subscription_price
    FROM mlm_settings
    WHERE key = 'subscription_settings';
  END IF;
  
  -- Находим primary спонсора (structure_type = 1, not 'primary')
  SELECT referrer_id INTO v_sponsor_id
  FROM referrals
  WHERE referred_user_id = v_subscriber_id
    AND structure_type = 1
  LIMIT 1;
  
  IF v_sponsor_id IS NULL THEN
    RETURN NEW;
  END IF;
  
  v_current_sponsor := v_sponsor_id;
  
  -- Проходим по уровням
  WHILE v_current_sponsor IS NOT NULL AND v_level < v_max_levels LOOP
    v_level := v_level + 1;
    
    -- Получаем процент для уровня
    SELECT COALESCE((value->>('level_' || v_level))::numeric, 0)
    INTO v_commission_rate
    FROM mlm_settings
    WHERE key = 's1_commission_rates';
    
    IF v_commission_rate IS NULL OR v_commission_rate = 0 THEN
      -- Переходим к следующему спонсору
      SELECT referrer_id INTO v_current_sponsor
      FROM referrals
      WHERE referred_user_id = v_current_sponsor
        AND structure_type = 1
      LIMIT 1;
      CONTINUE;
    END IF;
    
    -- Проверяем квалификацию спонсора
    SELECT 
      subscription_status = 'active' AND COALESCE(monthly_activation_completed, false)
    INTO v_sponsor_qualified
    FROM profiles
    WHERE id = v_current_sponsor;
    
    IF NOT COALESCE(v_sponsor_qualified, false) THEN
      -- Переходим к следующему спонсору
      SELECT referrer_id INTO v_current_sponsor
      FROM referrals
      WHERE referred_user_id = v_current_sponsor
        AND structure_type = 1
      LIMIT 1;
      CONTINUE;
    END IF;
    
    -- Проверяем количество прямых рефералов для разблокировки уровня
    SELECT COALESCE((value->>('unlock_level_' || v_level))::integer, 0)
    INTO v_required_referrals
    FROM mlm_settings
    WHERE key = 's1_unlock_requirements';
    
    IF v_required_referrals > 0 THEN
      SELECT COALESCE(direct_referrals_count, 0)
      INTO v_direct_referrals_count
      FROM profiles
      WHERE id = v_current_sponsor;
      
      IF v_direct_referrals_count < v_required_referrals THEN
        -- Переходим к следующему спонсору
        SELECT referrer_id INTO v_current_sponsor
        FROM referrals
        WHERE referred_user_id = v_current_sponsor
          AND structure_type = 1
        LIMIT 1;
        CONTINUE;
      END IF;
    END IF;
    
    -- Вычисляем комиссию
    v_commission_amount := ROUND(v_subscription_price * v_commission_rate / 100);
    
    IF v_commission_amount > 0 THEN
      v_source_ref := 'subscription:' || NEW.id || ':s1:lvl' || v_level;
      
      -- Создаем транзакцию
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
        v_current_sponsor,
        'commission',
        v_commission_amount::integer,
        'KZT',
        'completed',
        NEW.id,
        v_source_ref,
        v_level,
        'S1',
        v_frozen_until,
        jsonb_build_object(
          'type', 'S1',
          'level', v_level,
          'percent', v_commission_rate,
          'subscriber_id', v_subscriber_id,
          'subscription_amount', v_subscription_price,
          'frozen_until', v_frozen_until
        )
      )
      ON CONFLICT (user_id, source_ref) WHERE source_ref IS NOT NULL DO NOTHING;
      
      -- Обновляем баланс если нет заморозки
      IF v_frozen_until IS NULL THEN
        UPDATE profiles
        SET balance = COALESCE(balance, 0) + v_commission_amount,
            updated_at = NOW()
        WHERE id = v_current_sponsor;
      END IF;
    END IF;
    
    -- Переходим к следующему спонсору
    SELECT referrer_id INTO v_current_sponsor
    FROM referrals
    WHERE referred_user_id = v_current_sponsor
      AND structure_type = 1
    LIMIT 1;
  END LOOP;
  
  RETURN NEW;
END;
$$;