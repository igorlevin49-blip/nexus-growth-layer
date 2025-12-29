-- 1) Удалить дублирующий триггер, который срабатывает на любой UPDATE
DROP TRIGGER IF EXISTS create_commissions_on_payment ON public.orders;

-- 2) Обновить функцию create_commission_transactions с уникальным source_ref и проверкой дублей
CREATE OR REPLACE FUNCTION public.create_commission_transactions()
RETURNS TRIGGER AS $$
DECLARE
  v_referrer_id UUID;
  v_level INT;
  v_percent NUMERIC;
  v_amount_cents INT;
  v_order_source_ref TEXT;
BEGIN
  -- Только если статус изменился на 'paid'
  IF NEW.status <> 'paid' OR OLD.status = 'paid' THEN
    RETURN NEW;
  END IF;

  -- Уникальный source_ref для этого заказа
  v_order_source_ref := 'order:' || NEW.id::text;

  -- Проверяем, не созданы ли уже комиссии для этого заказа
  IF EXISTS (
    SELECT 1 FROM transactions 
    WHERE source_ref = v_order_source_ref 
    AND type = 'commission'
    LIMIT 1
  ) THEN
    -- Комиссии уже созданы, пропускаем
    RETURN NEW;
  END IF;

  -- Получаем спонсора покупателя
  SELECT sponsor_id INTO v_referrer_id
  FROM profiles
  WHERE id = NEW.user_id;

  -- Если нет спонсора - выходим
  IF v_referrer_id IS NULL THEN
    RETURN NEW;
  END IF;

  -- Начисляем комиссии по уровням (S1 - primary structure)
  v_level := 1;
  WHILE v_referrer_id IS NOT NULL AND v_level <= 10 LOOP
    -- Получаем процент для уровня из commission_plan_levels
    SELECT percent INTO v_percent
    FROM commission_plan_levels
    WHERE level = v_level 
    AND structure_type = 'primary'
    LIMIT 1;

    IF v_percent IS NOT NULL AND v_percent > 0 THEN
      -- Рассчитываем сумму комиссии (в тиынах/копейках)
      v_amount_cents := ROUND(NEW.total_kzt * v_percent / 100);

      IF v_amount_cents > 0 THEN
        -- Проверяем, что такая комиссия еще не существует для этого пользователя и заказа
        IF NOT EXISTS (
          SELECT 1 FROM transactions 
          WHERE user_id = v_referrer_id 
          AND source_ref = v_order_source_ref
          AND type = 'commission'
        ) THEN
          INSERT INTO transactions (
            user_id,
            type,
            amount_cents,
            currency,
            status,
            source_id,
            source_ref,
            level,
            structure_type
          ) VALUES (
            v_referrer_id,
            'commission',
            v_amount_cents,
            'KZT',
            'completed',
            NEW.id,
            v_order_source_ref,
            v_level,
            'primary'
          );
        END IF;
      END IF;
    END IF;

    -- Переходим к следующему спонсору вверх по цепочке
    SELECT sponsor_id INTO v_referrer_id
    FROM profiles
    WHERE id = v_referrer_id;

    v_level := v_level + 1;
  END LOOP;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;