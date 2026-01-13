-- КРИТИЧЕСКОЕ ИСПРАВЛЕНИЕ: Ошибка x100 в backfill комиссиях
-- Проблема: amount_cents = expected_commission_kzt * 100 (НЕПРАВИЛЬНО!)
-- Решение: amount_cents = expected_commission_kzt (для KZT хранятся целые тенге)

-- ====================================================================
-- ЭТАП 1: Исправить все 270 ошибочных транзакций
-- ====================================================================

UPDATE transactions
SET 
  amount_cents = amount_cents / 100,
  updated_at = NOW(),
  payload = COALESCE(payload, '{}'::jsonb) || jsonb_build_object(
    'fix_applied', 'divided_by_100',
    'fix_date', NOW()::text,
    'original_amount_cents', amount_cents
  )
WHERE type = 'commission'
  AND structure_type = 'primary'
  AND level = 1
  AND amount_cents = 550000
  AND source_ref LIKE 'backfill:%';

-- ====================================================================
-- ЭТАП 2: Исправить функцию backfill_missing_s1_commissions
-- ====================================================================

CREATE OR REPLACE FUNCTION public.backfill_missing_s1_commissions(
  p_admin_id uuid,
  p_dry_run boolean DEFAULT true,
  p_sponsor_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rec RECORD;
  v_count integer := 0;
  v_total_kzt bigint := 0;  -- ИСПРАВЛЕНО: было v_total_cents
  v_details jsonb := '[]'::jsonb;
  v_created_transaction_id uuid;
  v_freeze_days integer;
BEGIN
  -- Проверяем права админа
  IF NOT has_role('admin', p_admin_id) AND NOT has_role('superadmin', p_admin_id) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Access denied');
  END IF;

  -- Получаем период заморозки
  SELECT COALESCE((value->>'days')::integer, 30)
  INTO v_freeze_days
  FROM mlm_settings
  WHERE key = 'commission_freeze_period';

  -- Находим все подписки с пропущенными комиссиями
  FOR v_rec IN
    SELECT 
      s.id as subscription_id,
      s.user_id as subscriber_id,
      p_sub.full_name as subscriber_name,
      s.amount_kzt,
      s.paid_at,
      p_sub.sponsor_id,
      p_sp.full_name as sponsor_name,
      p_sp.email as sponsor_email,
      s.amount_kzt * 0.10 as expected_commission_kzt  -- 10% для S1 Level 1
    FROM subscriptions s
    JOIN profiles p_sub ON p_sub.id = s.user_id
    JOIN profiles p_sp ON p_sp.id = p_sub.sponsor_id
    WHERE s.status = 'active'
      AND s.paid_at IS NOT NULL
      AND p_sub.sponsor_id IS NOT NULL
      AND (p_sponsor_id IS NULL OR p_sub.sponsor_id = p_sponsor_id)
      -- Проверяем что комиссии нет ни по source_id, ни по payload
      AND NOT EXISTS (
        SELECT 1 FROM transactions t
        WHERE t.type = 'commission'
          AND t.structure_type = 'primary'
          AND t.level = 1
          AND t.user_id = p_sub.sponsor_id
          AND (t.source_id = s.id OR t.payload->>'subscription_id' = s.id::text)
      )
      -- Исключаем бесплатный маркетинг доступ
      AND COALESCE(s.is_marketing_free_access, false) = false
    ORDER BY s.paid_at
  LOOP
    v_count := v_count + 1;
    -- ИСПРАВЛЕНО: убрано умножение на 100
    v_total_kzt := v_total_kzt + v_rec.expected_commission_kzt;
    
    IF NOT p_dry_run THEN
      INSERT INTO transactions (
        user_id,
        type,
        amount_cents,  -- ВАЖНО: для KZT хранит целые тенге, НЕ умножаем на 100!
        currency,
        status,
        level,
        structure_type,
        source_id,
        source_ref,
        frozen_until,
        payload,
        created_at,
        updated_at
      ) VALUES (
        v_rec.sponsor_id,
        'commission',
        v_rec.expected_commission_kzt,  -- ИСПРАВЛЕНО: убрано * 100
        'KZT',
        'frozen',
        1,
        'primary',
        v_rec.subscription_id,
        'backfill:s1_commission',
        v_rec.paid_at + (v_freeze_days || ' days')::interval,
        jsonb_build_object(
          'subscription_id', v_rec.subscription_id,
          'subscriber_id', v_rec.subscriber_id,
          'subscriber_name', v_rec.subscriber_name,
          'subscription_amount_kzt', v_rec.amount_kzt,
          'commission_kzt', v_rec.expected_commission_kzt,  -- ИСПРАВЛЕНО: было commission_cents
          'backfill_date', NOW()::text,
          'backfill_admin', p_admin_id
        ),
        v_rec.paid_at,
        NOW()
      )
      RETURNING id INTO v_created_transaction_id;
    END IF;
    
    v_details := v_details || jsonb_build_object(
      'subscription_id', v_rec.subscription_id,
      'sponsor_id', v_rec.sponsor_id,
      'sponsor_name', v_rec.sponsor_name,
      'sponsor_email', v_rec.sponsor_email,
      'subscriber_name', v_rec.subscriber_name,
      'subscription_amount_kzt', v_rec.amount_kzt,
      'commission_kzt', v_rec.expected_commission_kzt,  -- ИСПРАВЛЕНО
      'paid_at', v_rec.paid_at,
      'transaction_id', v_created_transaction_id
    );
  END LOOP;

  -- Логируем действие
  IF NOT p_dry_run AND v_count > 0 THEN
    INSERT INTO admin_audit (
      admin_id,
      action_type,
      target_type,
      target_id,
      metadata
    ) VALUES (
      p_admin_id,
      'backfill_s1_commissions',
      'system',
      'bulk',
      jsonb_build_object(
        'commissions_created', v_count,
        'total_kzt', v_total_kzt
      )
    );
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'dry_run', p_dry_run,
    'commissions_to_create', v_count,
    'total_kzt', v_total_kzt,
    'details', v_details
  );
END;
$$;

-- ====================================================================
-- ЭТАП 3: Триггер-валидатор для защиты от подобных ошибок
-- ====================================================================

CREATE OR REPLACE FUNCTION public.validate_commission_amount()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  -- Для комиссий S1 Level 1 максимум ~10% от 55000 = 5500 KZT
  -- Даём запас до 10000 на случай изменения тарифов
  IF NEW.type = 'commission' 
     AND NEW.structure_type = 'primary' 
     AND NEW.level = 1 
     AND NEW.currency = 'KZT'
     AND NEW.amount_cents > 10000 THEN
    RAISE EXCEPTION 'ЗАЩИТА: Подозрительная сумма комиссии S1 L1: % KZT (максимум ~5500). Возможно ошибка умножения на 100!', NEW.amount_cents;
  END IF;
  
  -- Для всех комиссий: максимум не может быть больше суммы подписки
  IF NEW.type = 'commission' 
     AND NEW.currency = 'KZT'
     AND NEW.amount_cents > 100000 THEN  -- более 100,000 KZT явно ошибка
    RAISE EXCEPTION 'ЗАЩИТА: Нереальная сумма комиссии: % KZT. Проверьте расчёты!', NEW.amount_cents;
  END IF;
  
  RETURN NEW;
END;
$$;

-- Удаляем триггер если существует
DROP TRIGGER IF EXISTS tr_validate_commission_amount ON transactions;

-- Создаём триггер
CREATE TRIGGER tr_validate_commission_amount
  BEFORE INSERT ON transactions
  FOR EACH ROW
  EXECUTE FUNCTION validate_commission_amount();

-- ====================================================================
-- ЭТАП 4: Логируем исправление
-- ====================================================================

INSERT INTO activity_log (user_id, type, payload)
SELECT 
  '4138e0b5-7376-4b71-8832-c90f77da3d7a'::uuid,
  'critical_fix_applied',
  jsonb_build_object(
    'fix_type', 'backfill_commission_x100_error',
    'transactions_fixed', 270,
    'original_total_kzt', 148500000,
    'corrected_total_kzt', 1485000,
    'savings_kzt', 147015000,
    'applied_at', NOW()
  )
WHERE EXISTS (SELECT 1 FROM profiles WHERE id = '4138e0b5-7376-4b71-8832-c90f77da3d7a');

COMMENT ON FUNCTION validate_commission_amount() IS 
'Защитный триггер: блокирует создание комиссий с подозрительно большими суммами. 
Добавлен после инцидента с ошибкой x100 в backfill функции (13.01.2026).';