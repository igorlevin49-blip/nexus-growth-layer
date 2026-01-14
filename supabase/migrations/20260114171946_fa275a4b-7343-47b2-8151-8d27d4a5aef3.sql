
-- Исправляем триггер валидации комиссий: 
-- Подписка стоит 55,000 KZT, 10% = 5,500 KZT
-- Увеличиваем лимит до 6,000 KZT с запасом

CREATE OR REPLACE FUNCTION public.validate_commission_amount()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
DECLARE
  v_max_percent numeric;
  v_order_amount numeric;
  v_max_expected numeric;
BEGIN
  -- Только для комиссий
  IF NEW.type != 'commission' THEN
    RETURN NEW;
  END IF;

  -- ЗАЩИТА 1: Абсолютный лимит для любых комиссий (max 500,000 KZT)
  IF NEW.amount_cents > 500000 THEN
    RAISE EXCEPTION 'Подозрительная комиссия: % KZT превышает абсолютный лимит 500,000 KZT. '
      'Транзакция заблокирована для проверки.', NEW.amount_cents;
  END IF;

  -- ЗАЩИТА 2: S1 комиссии (подписки) - max 10% от 55000 = 5500 KZT
  -- Устанавливаем лимит 6000 KZT с небольшим запасом
  IF NEW.structure_type = 'primary' AND NEW.currency = 'KZT' THEN
    IF NEW.level = 1 AND NEW.amount_cents > 10000 THEN
      RAISE EXCEPTION 'S1 Level 1 комиссия % KZT превышает максимум 10,000 KZT (10%% от 100,000). '
        'Возможная ошибка умножения. Транзакция заблокирована.', NEW.amount_cents;
    END IF;
    
    -- Для уровней S1 (2-5): 10% от 55,000 = 5,500 KZT, лимит 6,000 KZT
    IF NEW.level > 1 AND NEW.amount_cents > 6000 THEN
      RAISE EXCEPTION 'S1 Level % комиссия % KZT превышает максимум 6,000 KZT. '
        'Возможная ошибка умножения. Транзакция заблокирована.', NEW.level, NEW.amount_cents;
    END IF;
  END IF;

  -- ЗАЩИТА 3: S2 комиссии (заказы) - проверяем соответствие проценту
  IF NEW.structure_type = 'secondary' AND NEW.currency = 'KZT' THEN
    -- Получаем сумму заказа из payload если есть
    v_order_amount := (NEW.payload->>'order_amount')::numeric;
    
    IF v_order_amount IS NOT NULL AND v_order_amount > 0 THEN
      -- Максимальный процент для S2: 10% на первом уровне
      IF NEW.level = 1 THEN
        v_max_percent := 0.10;
      ELSE
        v_max_percent := 0.05; -- меньше для глубоких уровней
      END IF;
      
      v_max_expected := v_order_amount * v_max_percent * 1.5; -- 50% запас на погрешность
      
      IF NEW.amount_cents > v_max_expected THEN
        RAISE EXCEPTION 'S2 Level % комиссия % KZT превышает ожидаемые %.0f KZT (%.0f%% от заказа % KZT). '
          'Возможная ошибка расчёта. Транзакция заблокирована.', 
          NEW.level, NEW.amount_cents, v_max_expected, v_max_percent * 100, v_order_amount;
      END IF;
    END IF;
  END IF;

  RETURN NEW;
END;
$function$;
