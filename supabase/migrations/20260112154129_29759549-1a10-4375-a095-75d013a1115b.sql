-- Исправление функции award_s1_subscription_commission
-- Проблемы в предыдущей версии:
-- 1. Использовала таблицу mlm_rules (не существует) вместо mlm_commission_rules
-- 2. Использовала колонку unfreeze_at (не существует) вместо frozen_until
-- 3. Не заполняла structure_type, level, source_ref, source_id

CREATE OR REPLACE FUNCTION public.award_s1_subscription_commission()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sponsor_id uuid;
  v_current_user_id uuid;
  v_level integer := 0;
  v_max_level integer := 5;
  v_percent numeric;
  v_commission_kzt numeric;
  v_freeze_months integer;
  v_source_ref text;
  v_existing_count integer;
BEGIN
  -- Получаем период заморозки из настроек
  SELECT COALESCE((value->>'months')::integer, 1) INTO v_freeze_months
  FROM mlm_settings
  WHERE key = 'commission_freeze_period';

  -- Если настройка не найдена, используем 1 месяц по умолчанию
  IF v_freeze_months IS NULL THEN
    v_freeze_months := 1;
  END IF;

  v_current_user_id := NEW.user_id;

  -- Проходим по 5 уровням спонсоров
  WHILE v_level < v_max_level LOOP
    -- Получаем спонсора текущего пользователя
    SELECT sponsor_id INTO v_sponsor_id
    FROM profiles
    WHERE id = v_current_user_id;

    -- Если спонсора нет, выходим
    IF v_sponsor_id IS NULL THEN
      EXIT;
    END IF;

    v_level := v_level + 1;

    -- Получаем процент комиссии для уровня из ПРАВИЛЬНОЙ таблицы mlm_commission_rules
    SELECT percent INTO v_percent
    FROM mlm_commission_rules
    WHERE structure_type = 1  -- S1 = структура 1
      AND level = v_level
      AND is_active = true
    ORDER BY effective_from DESC
    LIMIT 1;

    IF v_percent IS NOT NULL AND v_percent > 0 THEN
      -- Формируем уникальный ключ для идемпотентности
      v_source_ref := 'subscription_' || NEW.id || '_s1_L' || v_level || '_' || v_sponsor_id;
      
      -- Проверяем, не существует ли уже такая комиссия
      SELECT COUNT(*) INTO v_existing_count
      FROM transactions
      WHERE source_ref = v_source_ref;
      
      IF v_existing_count = 0 THEN
        -- Правильная формула: amount * percent / 100
        v_commission_kzt := ROUND(NEW.amount_kzt * v_percent / 100);

        -- Создаём комиссию с ПРАВИЛЬНЫМИ колонками
        INSERT INTO transactions (
          user_id,
          type,
          amount_cents,
          currency,
          status,
          structure_type,
          level,
          source_id,
          source_ref,
          frozen_until,
          payload
        ) VALUES (
          v_sponsor_id,
          'commission',
          v_commission_kzt,
          'KZT',
          CASE WHEN v_freeze_months > 0 THEN 'frozen' ELSE 'completed' END,
          'primary',  -- S1 = primary structure
          v_level,
          NEW.id,
          v_source_ref,
          CASE WHEN v_freeze_months > 0 THEN NOW() + (v_freeze_months || ' months')::interval ELSE NULL END,
          jsonb_build_object(
            'source', 'subscription',
            'subscription_id', NEW.id,
            'from_user_id', NEW.user_id,
            'level', v_level,
            'percent', v_percent,
            'structure', 'S1',
            'amount_kzt', NEW.amount_kzt
          )
        );
      END IF;
    END IF;

    v_current_user_id := v_sponsor_id;
  END LOOP;

  RETURN NEW;
END;
$$;