
-- =====================================================
-- КОМПЛЕКСНОЕ ИСПРАВЛЕНИЕ: Данные + RPC + Защита
-- =====================================================

-- ФАЗА 1: Исправление подозрительных транзакций
-- ---------------------------------------------

-- 1.1. Исправить S2 комиссию 200000 -> 2000 (10% от 20000)
UPDATE transactions
SET 
  amount_cents = 2000,
  payload = COALESCE(payload, '{}'::jsonb) || jsonb_build_object(
    'fix_applied', now()::text,
    'fix_reason', 'S2_commission_100x_error',
    'original_amount_cents', 200000
  )
WHERE id = '2cb11001-83ac-4183-b87d-99a9f9e5e81d'
  AND amount_cents = 200000;

-- 1.2. Исправить S2 комиссию 17500 -> 175 (если это 10% от 1750 или ошибка)
-- Но 17500 может быть корректным (10% от 175000 заказа)
-- Оставляем пока как есть, нужна проверка вручную

-- ФАЗА 2: Исправление RPC функции get_sponsors_with_missing_commissions
-- ----------------------------------------------------------------------
-- Удаляем старую версию и создаём исправленную

DROP FUNCTION IF EXISTS public.get_sponsors_with_missing_commissions(uuid);

CREATE OR REPLACE FUNCTION public.get_sponsors_with_missing_commissions(p_admin_id uuid)
RETURNS TABLE (
  sponsor_id uuid,
  sponsor_name text,
  sponsor_email text,
  missing_count bigint,
  missing_amount_kzt bigint,  -- Переименовано с _cents на _kzt
  partners_count bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Проверка прав администратора
  IF NOT EXISTS (
    SELECT 1 FROM user_roles 
    WHERE user_id = p_admin_id AND role IN ('admin', 'superadmin')
  ) THEN
    RAISE EXCEPTION 'Access denied: admin role required';
  END IF;

  RETURN QUERY
  WITH sponsor_partners AS (
    -- Все связки спонсор-партнёр с активными подписками
    SELECT 
      p.sponsor_id,
      p.id AS partner_id,
      s.id AS subscription_id,
      s.amount_kzt,
      s.paid_at
    FROM profiles p
    INNER JOIN subscriptions s ON s.user_id = p.id
    WHERE p.sponsor_id IS NOT NULL
      AND s.status = 'active'
      AND s.paid_at IS NOT NULL
      AND s.is_marketing_free_access IS NOT TRUE
      AND (s.is_test IS NOT TRUE OR s.is_test IS NULL)
  ),
  existing_commissions AS (
    -- Существующие S1 комиссии уровня 1
    SELECT DISTINCT t.source_id AS subscription_id
    FROM transactions t
    WHERE t.type = 'commission'
      AND t.structure_type = 'primary'
      AND t.level = 1
      AND t.source_ref LIKE 'sub_%'
  ),
  missing AS (
    -- Подписки без комиссий
    SELECT 
      sp.sponsor_id,
      sp.subscription_id,
      sp.amount_kzt
    FROM sponsor_partners sp
    LEFT JOIN existing_commissions ec ON ec.subscription_id = sp.subscription_id
    WHERE ec.subscription_id IS NULL
  )
  SELECT 
    m.sponsor_id,
    COALESCE(sp.full_name, 'Без имени') AS sponsor_name,
    sp.email AS sponsor_email,
    COUNT(DISTINCT m.subscription_id) AS missing_count,
    -- НЕ умножаем на 100! amount_kzt уже в тенге
    SUM((m.amount_kzt * 0.10)::BIGINT) AS missing_amount_kzt,
    COUNT(DISTINCT p2.id) AS partners_count
  FROM missing m
  INNER JOIN profiles sp ON sp.id = m.sponsor_id
  LEFT JOIN profiles p2 ON p2.sponsor_id = m.sponsor_id
  GROUP BY m.sponsor_id, sp.full_name, sp.email
  ORDER BY missing_count DESC;
END;
$$;

-- ФАЗА 3: Обновить комментарии к колонкам
-- ---------------------------------------

COMMENT ON COLUMN transactions.amount_cents IS 
  'Сумма в ЦЕЛЫХ ТЕНГЕ (KZT), НЕ в центах/тиынах! Историческое название сохранено для совместимости';

COMMENT ON COLUMN withdrawals.amount_cents IS 
  'Сумма в ЦЕЛЫХ ТЕНГЕ (KZT), НЕ в центах/тиынах! Историческое название сохранено для совместимости';

COMMENT ON COLUMN withdrawals.fee_cents IS 
  'Комиссия в ЦЕЛЫХ ТЕНГЕ (KZT), НЕ в центах/тиынах! Историческое название сохранено для совместимости';

COMMENT ON COLUMN auto_withdraw_rules.threshold_cents IS 
  'Порог в ЦЕЛЫХ ТЕНГЕ (KZT), НЕ в центах/тиынах! Историческое название сохранено для совместимости';

COMMENT ON COLUMN auto_withdraw_rules.min_amount_cents IS 
  'Минимальная сумма в ЦЕЛЫХ ТЕНГЕ (KZT), НЕ в центах/тиынах! Историческое название сохранено для совместимости';

-- ФАЗА 4: Расширить триггер validate_commission_amount для S2
-- -----------------------------------------------------------

CREATE OR REPLACE FUNCTION public.validate_commission_amount()
RETURNS TRIGGER AS $$
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
  IF NEW.structure_type = 'primary' AND NEW.currency = 'KZT' THEN
    IF NEW.level = 1 AND NEW.amount_cents > 10000 THEN
      RAISE EXCEPTION 'S1 Level 1 комиссия % KZT превышает максимум 10,000 KZT (10%% от 100,000). '
        'Возможная ошибка умножения. Транзакция заблокирована.', NEW.amount_cents;
    END IF;
    
    -- Для других уровней S1 (2-5) проверяем разумные лимиты
    IF NEW.level > 1 AND NEW.amount_cents > 5000 THEN
      RAISE EXCEPTION 'S1 Level % комиссия % KZT превышает максимум 5,000 KZT. '
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
$$ LANGUAGE plpgsql SET search_path = public;

-- ФАЗА 5: Добавить CHECK constraint (если ещё не существует)
-- ---------------------------------------------------------

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'chk_reasonable_commission_amount'
  ) THEN
    ALTER TABLE transactions 
    ADD CONSTRAINT chk_reasonable_commission_amount 
    CHECK (type != 'commission' OR amount_cents <= 500000);
  END IF;
END $$;

-- ФАЗА 6: Создать функцию для ежедневной проверки целостности данных
-- ------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.daily_data_integrity_check()
RETURNS TABLE (
  check_name text,
  issue_count bigint,
  sample_ids text[],
  description text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Проверка 1: Подозрительно большие S1 комиссии
  RETURN QUERY
  SELECT 
    'large_s1_commissions'::text AS check_name,
    COUNT(*)::bigint AS issue_count,
    ARRAY_AGG(t.id::text) AS sample_ids,
    'S1 комиссии > 10000 KZT (возможно ошибка умножения)'::text AS description
  FROM transactions t
  WHERE t.type = 'commission'
    AND t.structure_type = 'primary'
    AND t.amount_cents > 10000
    AND t.created_at > now() - interval '7 days';

  -- Проверка 2: Подозрительно большие S2 комиссии
  RETURN QUERY
  SELECT 
    'large_s2_commissions'::text,
    COUNT(*)::bigint,
    ARRAY_AGG(t.id::text),
    'S2 комиссии > 15% от суммы заказа'::text
  FROM transactions t
  WHERE t.type = 'commission'
    AND t.structure_type = 'secondary'
    AND t.payload ? 'order_amount'
    AND t.amount_cents > (t.payload->>'order_amount')::numeric * 0.15 * 1.1
    AND t.created_at > now() - interval '7 days';

  -- Проверка 3: Отрицательные балансы
  RETURN QUERY
  SELECT 
    'negative_balances'::text,
    COUNT(*)::bigint,
    ARRAY_AGG(p.id::text),
    'Пользователи с отрицательным балансом'::text
  FROM profiles p
  WHERE p.balance < 0
    AND p.deleted_at IS NULL;

  -- Проверка 4: Дубликаты комиссий
  RETURN QUERY
  SELECT 
    'duplicate_commissions'::text,
    COUNT(*)::bigint,
    ARRAY_AGG(DISTINCT t.source_id::text),
    'Подписки/заказы с несколькими комиссиями одного уровня'::text
  FROM (
    SELECT source_id, level, structure_type, COUNT(*) as cnt
    FROM transactions
    WHERE type = 'commission'
      AND source_id IS NOT NULL
      AND created_at > now() - interval '30 days'
    GROUP BY source_id, level, structure_type
    HAVING COUNT(*) > 1
  ) dup
  JOIN transactions t ON t.source_id = dup.source_id 
    AND t.level = dup.level 
    AND t.structure_type = dup.structure_type;
END;
$$;

-- Логируем исправление
INSERT INTO activity_log (user_id, type, payload)
SELECT 
  id, 
  'system_fix',
  jsonb_build_object(
    'action', 'comprehensive_currency_fix',
    'date', now()::text,
    'fixes', ARRAY[
      'Fixed S2 commission 200000 -> 2000',
      'Fixed get_sponsors_with_missing_commissions (removed *100)',
      'Extended validate_commission_amount trigger for S2',
      'Added CHECK constraint for max 500000 KZT',
      'Created daily_data_integrity_check function'
    ]
  )
FROM profiles 
WHERE is_system_account = true 
LIMIT 1;
