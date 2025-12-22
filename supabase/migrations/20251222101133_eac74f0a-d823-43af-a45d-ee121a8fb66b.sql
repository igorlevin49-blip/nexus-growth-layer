-- =============================================
-- КОМПЛЕКСНОЕ ИСПРАВЛЕНИЕ СИСТЕМЫ ЗАМОРОЗКИ КОМИССИЙ
-- =============================================

-- 1. Добавить настройку периода заморозки (14 дней)
INSERT INTO mlm_settings (key, value, description)
VALUES ('commission_freeze_period', '{"days": 14}'::jsonb, 'Период заморозки комиссий в днях')
ON CONFLICT (key) DO UPDATE SET value = '{"days": 14}'::jsonb;

-- 2. Исправить функцию расчёта баланса пользователя
-- Теперь учитывает status='frozen' ИЛИ completed с frozen_until > NOW()
CREATE OR REPLACE FUNCTION public.get_user_balance(p_user_id uuid)
RETURNS TABLE(
  user_id uuid,
  available_cents bigint,
  frozen_cents bigint,
  pending_cents bigint,
  withdrawn_cents bigint,
  updated_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT
    p_user_id as user_id,
    -- Доступный баланс: completed комиссии/бонусы БЕЗ заморозки минус выводы
    COALESCE(SUM(CASE 
      WHEN t.type IN ('commission', 'bonus') 
        AND t.status = 'completed'
        AND (t.frozen_until IS NULL OR t.frozen_until <= NOW())
      THEN t.amount_cents 
      ELSE 0 
    END), 0)::bigint
    -
    COALESCE(SUM(CASE 
      WHEN t.type = 'withdrawal' AND t.status IN ('completed', 'processing', 'pending')
      THEN t.amount_cents 
      ELSE 0 
    END), 0)::bigint
    as available_cents,
    
    -- Замороженные: status='frozen' ИЛИ (completed И frozen_until > NOW())
    COALESCE(SUM(CASE 
      WHEN t.type IN ('commission', 'bonus') 
        AND (
          t.status = 'frozen'
          OR (t.status = 'completed' AND t.frozen_until > NOW())
        )
      THEN t.amount_cents 
      ELSE 0 
    END), 0)::bigint as frozen_cents,
    
    -- Ожидающие: pending комиссии/бонусы
    COALESCE(SUM(CASE 
      WHEN t.type IN ('commission', 'bonus') AND t.status = 'pending'
      THEN t.amount_cents 
      ELSE 0 
    END), 0)::bigint as pending_cents,
    
    -- Выведенные: completed выводы
    COALESCE(SUM(CASE 
      WHEN t.type = 'withdrawal' AND t.status = 'completed'
      THEN t.amount_cents 
      ELSE 0 
    END), 0)::bigint as withdrawn_cents,
    
    NOW() as updated_at
  FROM transactions t
  WHERE t.user_id = p_user_id
    AND (t.is_archived IS NULL OR t.is_archived = false);
END;
$$;

-- 3. Исправить функцию начисления комиссий S1 (подписки)
-- Создаёт комиссии со status='completed' и frozen_until = NOW() + 14 дней
CREATE OR REPLACE FUNCTION public.award_s1_subscription_commission()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_current_user_id uuid;
  v_sponsor_id uuid;
  v_level int := 0;
  v_max_levels int := 5;
  v_percent numeric;
  v_commission_cents bigint;
  v_freeze_days int := 14;
  v_freeze_until timestamptz;
  v_sponsor_activation_due_from timestamptz;
  v_subscription_created_at timestamptz;
BEGIN
  -- Только при одобрении подписки
  IF NEW.status != 'approved' OR OLD.status = 'approved' THEN
    RETURN NEW;
  END IF;
  
  -- Получаем дату создания подписки
  v_subscription_created_at := NEW.created_at;
  
  -- Получаем период заморозки из настроек
  SELECT (value->>'days')::int INTO v_freeze_days
  FROM mlm_settings WHERE key = 'commission_freeze_period';
  
  IF v_freeze_days IS NULL THEN
    v_freeze_days := 14;
  END IF;
  
  v_freeze_until := NOW() + (v_freeze_days || ' days')::interval;
  
  -- Начинаем со спонсора пользователя подписки
  SELECT sponsor_id INTO v_current_user_id
  FROM profiles WHERE id = NEW.user_id;
  
  -- Проходим по цепочке спонсоров до 5 уровней
  WHILE v_current_user_id IS NOT NULL AND v_level < v_max_levels LOOP
    v_level := v_level + 1;
    
    -- Получаем процент для данного уровня S1
    SELECT percent INTO v_percent
    FROM mlm_commission_rules
    WHERE structure_type = 1 
      AND level = v_level 
      AND is_active = true
    LIMIT 1;
    
    IF v_percent IS NULL THEN
      v_percent := 10; -- 10% по умолчанию
    END IF;
    
    -- Проверяем activation_due_from спонсора
    SELECT activation_due_from INTO v_sponsor_activation_due_from
    FROM profiles WHERE id = v_current_user_id;
    
    -- Спонсор получает комиссию только если подписка создана ДО его activation_due_from
    -- или если activation_due_from не установлен
    IF v_sponsor_activation_due_from IS NULL 
       OR v_subscription_created_at < v_sponsor_activation_due_from THEN
      
      -- Рассчитываем комиссию (amount_kzt в тенге, конвертируем в центы: 1 тенге = 1 цент для KZT)
      v_commission_cents := ROUND(NEW.amount_kzt * v_percent / 100);
      
      IF v_commission_cents > 0 THEN
        -- Создаём транзакцию комиссии
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
          v_current_user_id,
          'commission',
          v_commission_cents,
          'KZT',
          'completed',
          NEW.id,
          'subscription_' || NEW.id || '_s1_level_' || v_level,
          v_level,
          'primary',
          v_freeze_until,
          jsonb_build_object(
            'source_type', 'subscription',
            'source_user_id', NEW.user_id,
            'percent', v_percent,
            'original_amount', NEW.amount_kzt,
            'freeze_days', v_freeze_days
          )
        );
      END IF;
    END IF;
    
    -- Переходим к следующему спонсору
    SELECT sponsor_id INTO v_sponsor_id
    FROM profiles WHERE id = v_current_user_id;
    
    v_current_user_id := v_sponsor_id;
  END LOOP;
  
  RETURN NEW;
END;
$$;

-- 4. Исправить функцию начисления комиссий P (заказы)
-- Создаёт комиссии со status='completed' и frozen_until = NOW() + 14 дней
CREATE OR REPLACE FUNCTION public.create_commission_transactions()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_current_user_id uuid;
  v_sponsor_id uuid;
  v_level int := 0;
  v_max_levels int := 10;
  v_percent numeric;
  v_commission_cents bigint;
  v_order_amount numeric;
  v_freeze_days int := 14;
  v_freeze_until timestamptz;
  v_sponsor_activation_due_from timestamptz;
  v_order_created_at timestamptz;
BEGIN
  -- Только при оплате заказа
  IF NEW.status != 'paid' OR OLD.status = 'paid' THEN
    RETURN NEW;
  END IF;
  
  -- Получаем дату создания заказа
  v_order_created_at := NEW.created_at;
  v_order_amount := NEW.total_kzt;
  
  -- Получаем период заморозки из настроек
  SELECT (value->>'days')::int INTO v_freeze_days
  FROM mlm_settings WHERE key = 'commission_freeze_period';
  
  IF v_freeze_days IS NULL THEN
    v_freeze_days := 14;
  END IF;
  
  v_freeze_until := NOW() + (v_freeze_days || ' days')::interval;
  
  -- Начинаем со спонсора пользователя заказа
  SELECT sponsor_id INTO v_current_user_id
  FROM profiles WHERE id = NEW.user_id;
  
  -- Проходим по цепочке спонсоров до 10 уровней
  WHILE v_current_user_id IS NOT NULL AND v_level < v_max_levels LOOP
    v_level := v_level + 1;
    
    -- Получаем процент для данного уровня P (structure_type = 2)
    SELECT percent INTO v_percent
    FROM mlm_commission_rules
    WHERE structure_type = 2 
      AND level = v_level 
      AND is_active = true
    LIMIT 1;
    
    IF v_percent IS NULL THEN
      -- Стандартные проценты для товарной структуры
      v_percent := CASE v_level
        WHEN 1 THEN 20
        WHEN 2 THEN 10
        WHEN 3 THEN 5
        WHEN 4 THEN 3
        WHEN 5 THEN 2
        ELSE 1
      END;
    END IF;
    
    -- Проверяем activation_due_from спонсора
    SELECT activation_due_from INTO v_sponsor_activation_due_from
    FROM profiles WHERE id = v_current_user_id;
    
    -- Спонсор получает комиссию только если заказ создан ДО его activation_due_from
    IF v_sponsor_activation_due_from IS NULL 
       OR v_order_created_at < v_sponsor_activation_due_from THEN
      
      -- Рассчитываем комиссию
      v_commission_cents := ROUND(v_order_amount * v_percent / 100);
      
      IF v_commission_cents > 0 THEN
        -- Создаём транзакцию комиссии
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
          v_current_user_id,
          'commission',
          v_commission_cents,
          'KZT',
          'completed',
          NEW.id,
          'order_' || NEW.id || '_p_level_' || v_level,
          v_level,
          'secondary',
          v_freeze_until,
          jsonb_build_object(
            'source_type', 'order',
            'source_user_id', NEW.user_id,
            'percent', v_percent,
            'original_amount', v_order_amount,
            'freeze_days', v_freeze_days
          )
        );
      END IF;
    END IF;
    
    -- Переходим к следующему спонсору
    SELECT sponsor_id INTO v_sponsor_id
    FROM profiles WHERE id = v_current_user_id;
    
    v_current_user_id := v_sponsor_id;
  END LOOP;
  
  RETURN NEW;
END;
$$;

-- 5. Исправить существующие транзакции
-- 5a. Установить frozen_until для транзакций где он NULL
UPDATE transactions 
SET frozen_until = created_at + interval '14 days'
WHERE type = 'commission' 
  AND frozen_until IS NULL
  AND status IN ('frozen', 'completed');

-- 5b. Изменить статус frozen на completed (они теперь различаются по frozen_until)
UPDATE transactions 
SET status = 'completed'
WHERE type = 'commission' 
  AND status = 'frozen';

-- 6. Пересоздать триггеры (на случай если они были удалены)
DROP TRIGGER IF EXISTS trigger_award_s1_subscription_commission ON subscriptions;
CREATE TRIGGER trigger_award_s1_subscription_commission
  AFTER UPDATE ON subscriptions
  FOR EACH ROW
  EXECUTE FUNCTION award_s1_subscription_commission();

DROP TRIGGER IF EXISTS trigger_create_commission_transactions ON orders;
CREATE TRIGGER trigger_create_commission_transactions
  AFTER UPDATE ON orders
  FOR EACH ROW
  EXECUTE FUNCTION create_commission_transactions();