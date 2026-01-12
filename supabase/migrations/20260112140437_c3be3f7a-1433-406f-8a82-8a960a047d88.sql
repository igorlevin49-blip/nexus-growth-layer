-- Шаг 1: Исправить monthly_activation_completed для пользователей в grace period
UPDATE profiles
SET monthly_activation_completed = true, updated_at = now()
WHERE subscription_status = 'active'
  AND monthly_activation_completed = false
  AND activation_due_from > NOW()
  AND is_active = true
  AND deleted_at IS NULL;

-- Шаг 2: Обновить функцию award_s1_subscription_commission с правильной логикой grace period
CREATE OR REPLACE FUNCTION award_s1_subscription_commission()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_subscriber_id uuid;
  v_subscription_id uuid;
  v_amount_kzt numeric;
  v_sponsor_id uuid;
  v_sponsor_sponsor_id uuid;
  v_l1_percent numeric;
  v_l2_percent numeric;
  v_l1_commission numeric;
  v_l2_commission numeric;
  v_freeze_days integer := 14;
  v_frozen_until timestamptz;
  v_sponsor_qualified boolean;
  v_sponsor_sponsor_qualified boolean;
BEGIN
  -- Получаем данные подписки
  v_subscriber_id := NEW.user_id;
  v_subscription_id := NEW.id;
  v_amount_kzt := NEW.amount_kzt;
  
  -- Если сумма 0 или null, выходим
  IF v_amount_kzt IS NULL OR v_amount_kzt <= 0 THEN
    RAISE LOG '[S1 Commission] Skipping - amount is null or zero for subscription %', v_subscription_id;
    RETURN NEW;
  END IF;
  
  -- Получаем спонсора подписчика
  SELECT sponsor_id INTO v_sponsor_id
  FROM profiles
  WHERE id = v_subscriber_id;
  
  IF v_sponsor_id IS NULL THEN
    RAISE LOG '[S1 Commission] No sponsor for subscriber %', v_subscriber_id;
    RETURN NEW;
  END IF;
  
  -- Получаем проценты из mlm_commission_rules для structure_type = 'primary' (S1)
  SELECT percent INTO v_l1_percent
  FROM mlm_commission_rules
  WHERE structure_type = 1 AND level = 1 AND is_active = true
  ORDER BY effective_from DESC
  LIMIT 1;
  
  SELECT percent INTO v_l2_percent
  FROM mlm_commission_rules
  WHERE structure_type = 1 AND level = 2 AND is_active = true
  ORDER BY effective_from DESC
  LIMIT 1;
  
  -- Если проценты не найдены, используем дефолтные значения
  IF v_l1_percent IS NULL THEN
    v_l1_percent := 10;
  END IF;
  
  IF v_l2_percent IS NULL THEN
    v_l2_percent := 5;
  END IF;
  
  -- Вычисляем комиссии
  v_l1_commission := v_amount_kzt * v_l1_percent / 100;
  v_l2_commission := v_amount_kzt * v_l2_percent / 100;
  v_frozen_until := NOW() + (v_freeze_days || ' days')::interval;
  
  -- Проверяем квалификацию спонсора L1 (активная подписка + (активирован ИЛИ в grace period))
  SELECT 
    subscription_status = 'active' AND 
    (monthly_activation_completed = true OR activation_due_from > NOW())
  INTO v_sponsor_qualified
  FROM profiles
  WHERE id = v_sponsor_id;
  
  -- Начисляем L1 комиссию если спонсор квалифицирован
  IF v_sponsor_qualified = true AND v_l1_commission > 0 THEN
    -- Проверяем что комиссия ещё не существует
    IF NOT EXISTS (
      SELECT 1 FROM transactions 
      WHERE user_id = v_sponsor_id 
        AND type = 'commission'
        AND structure_type = 'primary'
        AND level = 1
        AND source_id = v_subscription_id
    ) THEN
      INSERT INTO transactions (
        user_id, type, amount_cents, currency, status, 
        structure_type, level, source_id, source_ref, frozen_until, payload
      ) VALUES (
        v_sponsor_id, 'commission', (v_l1_commission * 100)::bigint, 'KZT', 'frozen',
        'primary', 1, v_subscription_id, 'subscription', v_frozen_until,
        jsonb_build_object(
          'subscription_id', v_subscription_id,
          'subscriber_id', v_subscriber_id,
          'amount_kzt', v_amount_kzt,
          'percent', v_l1_percent,
          'trigger', 'award_s1_subscription_commission'
        )
      );
      RAISE LOG '[S1 Commission] Created L1 commission % KZT for sponsor % from subscription %', v_l1_commission, v_sponsor_id, v_subscription_id;
    ELSE
      RAISE LOG '[S1 Commission] L1 commission already exists for sponsor % subscription %', v_sponsor_id, v_subscription_id;
    END IF;
  ELSE
    RAISE LOG '[S1 Commission] L1 sponsor % not qualified (qualified=%)', v_sponsor_id, v_sponsor_qualified;
  END IF;
  
  -- Получаем спонсора спонсора (L2)
  SELECT sponsor_id INTO v_sponsor_sponsor_id
  FROM profiles
  WHERE id = v_sponsor_id;
  
  IF v_sponsor_sponsor_id IS NOT NULL THEN
    -- Проверяем квалификацию L2 спонсора
    SELECT 
      subscription_status = 'active' AND 
      (monthly_activation_completed = true OR activation_due_from > NOW())
    INTO v_sponsor_sponsor_qualified
    FROM profiles
    WHERE id = v_sponsor_sponsor_id;
    
    IF v_sponsor_sponsor_qualified = true AND v_l2_commission > 0 THEN
      -- Проверяем что комиссия ещё не существует
      IF NOT EXISTS (
        SELECT 1 FROM transactions 
        WHERE user_id = v_sponsor_sponsor_id 
          AND type = 'commission'
          AND structure_type = 'primary'
          AND level = 2
          AND source_id = v_subscription_id
      ) THEN
        INSERT INTO transactions (
          user_id, type, amount_cents, currency, status,
          structure_type, level, source_id, source_ref, frozen_until, payload
        ) VALUES (
          v_sponsor_sponsor_id, 'commission', (v_l2_commission * 100)::bigint, 'KZT', 'frozen',
          'primary', 2, v_subscription_id, 'subscription', v_frozen_until,
          jsonb_build_object(
            'subscription_id', v_subscription_id,
            'subscriber_id', v_subscriber_id,
            'amount_kzt', v_amount_kzt,
            'percent', v_l2_percent,
            'trigger', 'award_s1_subscription_commission'
          )
        );
        RAISE LOG '[S1 Commission] Created L2 commission % KZT for sponsor % from subscription %', v_l2_commission, v_sponsor_sponsor_id, v_subscription_id;
      ELSE
        RAISE LOG '[S1 Commission] L2 commission already exists for sponsor % subscription %', v_sponsor_sponsor_id, v_subscription_id;
      END IF;
    ELSE
      RAISE LOG '[S1 Commission] L2 sponsor % not qualified (qualified=%)', v_sponsor_sponsor_id, v_sponsor_sponsor_qualified;
    END IF;
  END IF;
  
  RETURN NEW;
END;
$$;

-- Шаг 3: Воссоздать триггер на subscriptions
DROP TRIGGER IF EXISTS trg_award_s1_subscription_commission ON subscriptions;

CREATE TRIGGER trg_award_s1_subscription_commission
  AFTER UPDATE OF status ON subscriptions
  FOR EACH ROW
  WHEN (OLD.status IS DISTINCT FROM NEW.status AND NEW.status = 'active')
  EXECUTE FUNCTION award_s1_subscription_commission();

-- Шаг 4: Создать функцию для автоматической установки monthly_activation_completed
CREATE OR REPLACE FUNCTION set_activation_on_subscription()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Когда подписка становится активной, если пользователь в grace period - устанавливаем monthly_activation_completed = true
  IF NEW.status = 'active' AND (OLD.status IS NULL OR OLD.status IS DISTINCT FROM NEW.status) THEN
    UPDATE profiles
    SET monthly_activation_completed = true, updated_at = now()
    WHERE id = NEW.user_id
      AND activation_due_from > NOW()
      AND monthly_activation_completed = false;
  END IF;
  
  RETURN NEW;
END;
$$;

-- Создаём триггер для автоматической установки
DROP TRIGGER IF EXISTS trg_set_activation_on_subscription ON subscriptions;

CREATE TRIGGER trg_set_activation_on_subscription
  AFTER UPDATE OF status ON subscriptions
  FOR EACH ROW
  WHEN (NEW.status = 'active')
  EXECUTE FUNCTION set_activation_on_subscription();