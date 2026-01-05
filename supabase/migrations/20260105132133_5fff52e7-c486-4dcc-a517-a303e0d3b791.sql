-- Обновляем функцию create_commission_transactions для правильной заморозки комиссий
CREATE OR REPLACE FUNCTION public.create_commission_transactions()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_buyer_id UUID;
  v_sponsor_id UUID;
  v_current_user_id UUID;
  v_level INT := 1;
  v_commission_percent NUMERIC;
  v_commission_amount INT;
  v_order_amount_cents INT;
  v_freeze_days INT := 14;
  v_frozen_until TIMESTAMPTZ;
  v_direct_referrals INT;
  v_unlock_config JSONB;
  v_required_referrals INT;
  v_user_subscription_active BOOLEAN;
  v_user_activation_met BOOLEAN;
  v_current_month INT;
  v_current_year INT;
  v_no_commission_reason TEXT;
BEGIN
  -- Только для оплаченных заказов
  IF NEW.status != 'paid' THEN
    RETURN NEW;
  END IF;
  
  -- Получаем период заморозки из настроек
  SELECT COALESCE((value::text)::int, 14) INTO v_freeze_days
  FROM mlm_settings WHERE key = 'commission_freeze_period';
  
  -- Рассчитываем дату разморозки
  v_frozen_until := COALESCE(NEW.paid_at, now()) + (v_freeze_days || ' days')::INTERVAL;
  
  -- Получаем конфигурацию разблокировки уровней
  SELECT COALESCE(value, '{"2": 1, "3": 2, "4": 3, "5": 4, "6": 5, "7": 6, "8": 7, "9": 8, "10": 10}'::jsonb) 
  INTO v_unlock_config
  FROM mlm_settings WHERE key = 'unlock_levels';
  
  v_buyer_id := NEW.user_id;
  v_order_amount_cents := NEW.total_kzt * 100; -- Конвертируем в тиын
  
  v_current_month := EXTRACT(MONTH FROM COALESCE(NEW.paid_at, now()));
  v_current_year := EXTRACT(YEAR FROM COALESCE(NEW.paid_at, now()));
  
  -- Получаем спонсора покупателя
  SELECT sponsor_id INTO v_sponsor_id
  FROM profiles WHERE id = v_buyer_id;
  
  v_current_user_id := v_sponsor_id;
  
  -- Проходим по цепочке спонсоров (до 10 уровней для P1-P10)
  WHILE v_current_user_id IS NOT NULL AND v_level <= 10 LOOP
    v_no_commission_reason := NULL;
    
    -- Получаем процент комиссии для уровня (structure_type = 2 для продуктовой структуры)
    SELECT percent INTO v_commission_percent
    FROM mlm_commission_rules
    WHERE structure_type = 2 
      AND level = v_level 
      AND is_active = true
    ORDER BY effective_from DESC
    LIMIT 1;
    
    IF v_commission_percent IS NOT NULL AND v_commission_percent > 0 THEN
      -- Проверяем количество прямых рефералов для разблокировки уровня
      SELECT direct_referrals_count INTO v_direct_referrals
      FROM profiles WHERE id = v_current_user_id;
      
      v_required_referrals := COALESCE((v_unlock_config->>v_level::text)::int, 0);
      
      -- Проверяем активность подписки
      SELECT subscription_active INTO v_user_subscription_active
      FROM profiles WHERE id = v_current_user_id;
      
      -- Проверяем месячную активацию
      SELECT is_activated INTO v_user_activation_met
      FROM monthly_activations
      WHERE user_id = v_current_user_id
        AND month = v_current_month
        AND year = v_current_year;
      
      -- Определяем причину отсутствия комиссии
      IF v_level > 1 AND COALESCE(v_direct_referrals, 0) < v_required_referrals THEN
        v_no_commission_reason := format('Уровень %s не разблокирован (нужно %s рефералов, есть %s)', 
          v_level, v_required_referrals, COALESCE(v_direct_referrals, 0));
      ELSIF NOT COALESCE(v_user_subscription_active, false) THEN
        v_no_commission_reason := 'Подписка не активна';
      ELSIF NOT COALESCE(v_user_activation_met, false) THEN
        v_no_commission_reason := 'Месячная активация не выполнена';
      END IF;
      
      -- Создаём комиссию только если все условия выполнены
      IF v_no_commission_reason IS NULL THEN
        v_commission_amount := ROUND(v_order_amount_cents * v_commission_percent / 100);
        
        IF v_commission_amount > 0 THEN
          INSERT INTO transactions (
            user_id,
            type,
            amount_cents,
            currency,
            status,
            frozen_until,
            source_id,
            source_ref,
            level,
            structure_type,
            payload,
            created_at,
            updated_at
          ) VALUES (
            v_current_user_id,
            'commission',
            v_commission_amount,
            'KZT',
            'frozen',  -- Статус frozen вместо completed
            v_frozen_until,  -- Дата разморозки
            NEW.id,
            'order',
            v_level,
            'secondary',
            jsonb_build_object(
              'source_user_id', v_buyer_id,
              'order_amount_cents', v_order_amount_cents,
              'commission_percent', v_commission_percent,
              'freeze_days', v_freeze_days,
              'calculated_at', now()
            ),
            now(),
            now()
          );
          
          -- Логируем успешное начисление
          INSERT INTO activity_log (user_id, type, payload)
          VALUES (v_current_user_id, 'commission_created', jsonb_build_object(
            'order_id', NEW.id,
            'buyer_id', v_buyer_id,
            'level', v_level,
            'amount_cents', v_commission_amount,
            'percent', v_commission_percent,
            'status', 'frozen',
            'frozen_until', v_frozen_until,
            'structure_type', 'secondary'
          ));
        END IF;
      ELSE
        -- Логируем пропуск комиссии
        INSERT INTO activity_log (user_id, type, payload)
        VALUES (v_current_user_id, 'commission_skipped', jsonb_build_object(
          'order_id', NEW.id,
          'buyer_id', v_buyer_id,
          'level', v_level,
          'reason', v_no_commission_reason,
          'structure_type', 'secondary'
        ));
      END IF;
    END IF;
    
    -- Переходим к следующему спонсору
    SELECT sponsor_id INTO v_current_user_id
    FROM profiles WHERE id = v_current_user_id;
    
    v_level := v_level + 1;
  END LOOP;
  
  RETURN NEW;
END;
$$;

-- Исправляем существующие транзакции за сегодняшний заказ (a34bfb28-548c-4e84-94d2-e89fd9c667bb)
-- Сначала откатываем балансы пользователей
UPDATE profiles p
SET balance = COALESCE(p.balance, 0) - t.amount_cents
FROM transactions t
WHERE t.source_id = 'a34bfb28-548c-4e84-94d2-e89fd9c667bb'
  AND t.type = 'commission'
  AND t.status = 'completed'
  AND t.user_id = p.id;

-- Теперь замораживаем транзакции
UPDATE transactions
SET 
  status = 'frozen',
  frozen_until = '2026-01-19 12:54:38.008802+00'::timestamptz,  -- paid_at + 14 дней
  payload = COALESCE(payload, '{}'::jsonb) || jsonb_build_object(
    'fixed_at', now(),
    'fix_reason', 'Исправлено: комиссии должны быть заморожены на 14 дней'
  ),
  updated_at = now()
WHERE source_id = 'a34bfb28-548c-4e84-94d2-e89fd9c667bb'
  AND type = 'commission'
  AND status = 'completed';