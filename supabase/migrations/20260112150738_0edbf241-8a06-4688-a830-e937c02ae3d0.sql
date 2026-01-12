-- Исправление функции award_s1_subscription_commission
-- Проблема: функция проверяла NEW.type, которого нет в таблице subscriptions

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
BEGIN
  -- Триггер уже фильтрует по WHEN (new.status = 'active')
  -- Нет проверки NEW.type - таблица subscriptions не имеет этого поля
  
  -- Получаем период заморозки
  SELECT COALESCE((value->>'months')::integer, 1) INTO v_freeze_months
  FROM mlm_settings
  WHERE key = 'commission_freeze_period';

  v_current_user_id := NEW.user_id;

  -- Проходим по 5 уровням спонсоров
  WHILE v_level < v_max_level LOOP
    SELECT sponsor_id INTO v_sponsor_id
    FROM profiles
    WHERE id = v_current_user_id;

    IF v_sponsor_id IS NULL THEN
      EXIT;
    END IF;

    v_level := v_level + 1;

    -- Получаем процент комиссии для уровня
    SELECT percent INTO v_percent
    FROM mlm_rules
    WHERE structure = 'S1' AND level = v_level;

    IF v_percent IS NOT NULL AND v_percent > 0 THEN
      -- Правильная формула: amount * percent / 100
      v_commission_kzt := ROUND(NEW.amount_kzt * v_percent / 100);

      -- Создаём комиссию
      INSERT INTO transactions (
        user_id, type, amount_cents, currency, status, payload, unfreeze_at
      ) VALUES (
        v_sponsor_id,
        'commission',
        v_commission_kzt,
        'KZT',
        'frozen',
        jsonb_build_object(
          'source', 'subscription',
          'subscription_id', NEW.id,
          'from_user_id', NEW.user_id,
          'level', v_level,
          'percent', v_percent,
          'structure', 'S1'
        ),
        NOW() + (v_freeze_months || ' months')::interval
      );
    END IF;

    v_current_user_id := v_sponsor_id;
  END LOOP;

  RETURN NEW;
END;
$$;