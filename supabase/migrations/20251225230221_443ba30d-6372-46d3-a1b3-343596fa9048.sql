-- =====================================================
-- ЧАСТЬ 1: Пересчёт дробных комиссий
-- =====================================================

-- Создать функцию для пересчёта дробных комиссий
CREATE OR REPLACE FUNCTION admin_fix_fractional_commissions(p_admin_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_fixed_count INTEGER := 0;
  v_fixed_transactions JSON;
BEGIN
  -- Проверить права
  IF NOT has_role(p_admin_id, 'superadmin') THEN
    RETURN json_build_object('success', false, 'error', 'UNAUTHORIZED');
  END IF;

  -- Собрать информацию о дробных комиссиях ДО исправления
  WITH fractional_before AS (
    SELECT 
      t.id,
      t.user_id,
      t.amount_cents as old_amount_cents,
      t.source_id,
      t.level,
      (t.payload->>'percent')::numeric as percent,
      COALESCE(o.total_kzt, s.amount_kzt) as base_kzt
    FROM transactions t
    LEFT JOIN orders o ON o.id = t.source_id AND t.source_ref IS NULL
    LEFT JOIN subscriptions s ON s.id = t.source_id
    WHERE t.type = 'commission'
      AND t.amount_cents % 100 != 0
      AND (t.is_archived IS NULL OR t.is_archived = false)
  ),
  -- Пересчитать комиссии
  recalculated AS (
    SELECT 
      fb.id,
      fb.user_id,
      fb.old_amount_cents,
      fb.base_kzt,
      fb.percent,
      -- Корректный расчёт: base_kzt * percent / 100, округлённое до целого KZT, * 100 для тийинов
      CASE 
        WHEN fb.base_kzt IS NOT NULL AND fb.percent IS NOT NULL THEN
          ROUND(fb.base_kzt * fb.percent / 100) * 100
        ELSE
          -- Если нет источника - округлить вверх до целого KZT
          CEIL(fb.old_amount_cents / 100.0) * 100
      END as new_amount_cents
    FROM fractional_before fb
  ),
  -- Применить исправления
  updated AS (
    UPDATE transactions t
    SET 
      amount_cents = r.new_amount_cents,
      payload = COALESCE(t.payload, '{}'::jsonb) || jsonb_build_object(
        'recalculated_at', now()::text,
        'old_amount_cents', r.old_amount_cents,
        'recalculation_reason', 'fractional_fix'
      ),
      updated_at = now()
    FROM recalculated r
    WHERE t.id = r.id
    RETURNING t.id, r.old_amount_cents, t.amount_cents as new_amount_cents, t.user_id
  )
  SELECT 
    COUNT(*),
    COALESCE(json_agg(json_build_object(
      'id', id,
      'user_id', user_id,
      'old_cents', old_amount_cents,
      'new_cents', new_amount_cents
    )), '[]'::json)
  INTO v_fixed_count, v_fixed_transactions
  FROM updated;

  -- Записать аудит
  IF v_fixed_count > 0 THEN
    INSERT INTO admin_audit (admin_id, target_type, target_id, action_type, comment, metadata)
    VALUES (
      p_admin_id,
      'system',
      p_admin_id,
      'fix_fractional_commissions',
      'Исправлено ' || v_fixed_count || ' дробных комиссий',
      jsonb_build_object('fixed_transactions', v_fixed_transactions)
    );
  END IF;

  RETURN json_build_object(
    'success', true,
    'fixed_count', v_fixed_count,
    'transactions', v_fixed_transactions
  );
END;
$$;

-- =====================================================
-- ЧАСТЬ 2: Функция корректировки баланса
-- =====================================================

CREATE OR REPLACE FUNCTION admin_adjust_balance(
  p_user_id UUID,
  p_amount_cents BIGINT,  -- положительное = начислить, отрицательное = списать
  p_reason TEXT,
  p_admin_id UUID
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_transaction_id UUID;
  v_current_balance BIGINT;
  v_user_name TEXT;
BEGIN
  -- Проверить права
  IF NOT has_role(p_admin_id, 'superadmin') THEN
    RETURN json_build_object('success', false, 'error', 'UNAUTHORIZED');
  END IF;

  -- Проверить что сумма не нулевая
  IF p_amount_cents = 0 THEN
    RETURN json_build_object('success', false, 'error', 'ZERO_AMOUNT');
  END IF;

  -- Проверить что причина указана
  IF p_reason IS NULL OR LENGTH(TRIM(p_reason)) < 3 THEN
    RETURN json_build_object('success', false, 'error', 'REASON_REQUIRED');
  END IF;

  -- Получить текущий баланс и имя пользователя
  SELECT 
    (SELECT available_cents FROM get_user_balance(p_user_id)),
    full_name
  INTO v_current_balance, v_user_name
  FROM profiles
  WHERE id = p_user_id;

  IF v_user_name IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'USER_NOT_FOUND');
  END IF;

  -- Убедиться что сумма кратна 100 (целые KZT)
  IF p_amount_cents % 100 != 0 THEN
    p_amount_cents := ROUND(p_amount_cents / 100.0) * 100;
  END IF;

  -- Создать транзакцию корректировки
  INSERT INTO transactions (
    user_id,
    type,
    amount_cents,
    status,
    currency,
    payload
  ) VALUES (
    p_user_id,
    'adjustment',
    ABS(p_amount_cents),  -- Сумма всегда положительная
    CASE WHEN p_amount_cents > 0 THEN 'completed' ELSE 'completed' END,
    'KZT',
    jsonb_build_object(
      'reason', TRIM(p_reason),
      'admin_id', p_admin_id,
      'direction', CASE WHEN p_amount_cents > 0 THEN 'credit' ELSE 'debit' END,
      'balance_before', v_current_balance
    )
  )
  RETURNING id INTO v_transaction_id;

  -- Если списание - создать withdrawal запись для учёта
  IF p_amount_cents < 0 THEN
    INSERT INTO withdrawals (
      user_id,
      amount_cents,
      status,
      transaction_id
    ) VALUES (
      p_user_id,
      ABS(p_amount_cents),
      'completed',
      v_transaction_id
    );
  END IF;

  -- Записать аудит
  INSERT INTO admin_audit (admin_id, target_type, target_id, action_type, comment, metadata)
  VALUES (
    p_admin_id,
    'user',
    p_user_id,
    'balance_adjustment',
    CASE WHEN p_amount_cents > 0 
      THEN 'Начислено ' || (ABS(p_amount_cents) / 100) || ' KZT: ' || TRIM(p_reason)
      ELSE 'Списано ' || (ABS(p_amount_cents) / 100) || ' KZT: ' || TRIM(p_reason)
    END,
    jsonb_build_object(
      'amount_cents', p_amount_cents,
      'balance_before', v_current_balance,
      'transaction_id', v_transaction_id,
      'user_name', v_user_name
    )
  );

  RETURN json_build_object(
    'success', true,
    'transaction_id', v_transaction_id,
    'new_balance_cents', v_current_balance + p_amount_cents
  );
END;
$$;

-- =====================================================
-- ЧАСТЬ 3: Защита от дробных сумм в create_commission_transactions
-- =====================================================

-- Обновить функцию create_commission_transactions с защитой от дробных сумм
CREATE OR REPLACE FUNCTION create_commission_transactions()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rules RECORD;
  v_current_user_id UUID;
  v_level INT := 0;
  v_max_level INT;
  v_commission_cents BIGINT;
  v_freeze_days INT := 14;
  v_frozen_until TIMESTAMPTZ;
  v_base_amount_cents BIGINT;
BEGIN
  -- Получить максимальный уровень и период заморозки
  SELECT COALESCE((SELECT (value::text)::int FROM mlm_settings WHERE key = 'freeze_days'), 14)
  INTO v_freeze_days;
  
  v_frozen_until := NOW() + (v_freeze_days || ' days')::interval;
  
  -- Используем total_kzt как базу для расчёта (в тийинах)
  v_base_amount_cents := (NEW.total_kzt * 100)::BIGINT;
  
  -- Получить ID покупателя
  v_current_user_id := NEW.user_id;
  
  -- Получить спонсора покупателя
  SELECT sponsor_id INTO v_current_user_id
  FROM profiles
  WHERE id = NEW.user_id;
  
  IF v_current_user_id IS NULL THEN
    RETURN NEW;
  END IF;

  -- Получить максимальный уровень для структуры 2
  SELECT COALESCE(MAX(level), 10) INTO v_max_level
  FROM mlm_commission_rules
  WHERE structure_type = 2 AND is_active = true;

  -- Пройти по всей цепочке спонсоров
  WHILE v_current_user_id IS NOT NULL AND v_level < v_max_level LOOP
    v_level := v_level + 1;
    
    -- Получить правило комиссии для этого уровня
    SELECT percent INTO v_rules
    FROM mlm_commission_rules
    WHERE structure_type = 2 
      AND level = v_level 
      AND is_active = true
    ORDER BY effective_from DESC
    LIMIT 1;
    
    IF v_rules.percent IS NOT NULL AND v_rules.percent > 0 THEN
      -- Рассчитать комиссию с округлением до целого KZT
      -- base_cents * percent / 100 = комиссия в тийинах
      -- Округляем до целых тенге: ROUND(... / 100) * 100
      v_commission_cents := ROUND(v_base_amount_cents * v_rules.percent / 100 / 100) * 100;
      
      -- Минимальная комиссия - 100 тийинов (1 тенге)
      IF v_commission_cents >= 100 THEN
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
          'frozen',
          NEW.id,
          'order',
          v_level,
          'secondary',
          v_frozen_until,
          jsonb_build_object(
            'order_id', NEW.id,
            'buyer_id', NEW.user_id,
            'percent', v_rules.percent,
            'base_amount_kzt', NEW.total_kzt
          )
        );
      END IF;
    END IF;
    
    -- Перейти к спонсору текущего пользователя
    SELECT sponsor_id INTO v_current_user_id
    FROM profiles
    WHERE id = v_current_user_id;
  END LOOP;

  RETURN NEW;
END;
$$;

-- =====================================================
-- ЧАСТЬ 4: Защита от дробных сумм в award_s1_subscription_commission
-- =====================================================

CREATE OR REPLACE FUNCTION award_s1_subscription_commission(
  p_user_id UUID,
  p_subscription_id UUID,
  p_amount_kzt NUMERIC
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_current_user_id UUID;
  v_level INT := 0;
  v_max_level INT := 10;
  v_commission_cents BIGINT;
  v_base_amount_cents BIGINT;
  v_percent NUMERIC;
  v_freeze_days INT := 14;
  v_frozen_until TIMESTAMPTZ;
  v_commissions_created INT := 0;
BEGIN
  -- Получить период заморозки
  SELECT COALESCE((SELECT (value::text)::int FROM mlm_settings WHERE key = 'freeze_days'), 14)
  INTO v_freeze_days;
  
  v_frozen_until := NOW() + (v_freeze_days || ' days')::interval;
  
  -- База для расчёта в тийинах
  v_base_amount_cents := (p_amount_kzt * 100)::BIGINT;
  
  -- Получить спонсора покупателя
  SELECT sponsor_id INTO v_current_user_id
  FROM profiles
  WHERE id = p_user_id;
  
  IF v_current_user_id IS NULL THEN
    RETURN json_build_object('success', true, 'commissions_created', 0);
  END IF;

  -- Получить максимальный уровень для структуры 1
  SELECT COALESCE(MAX(level), 10) INTO v_max_level
  FROM mlm_commission_rules
  WHERE structure_type = 1 AND is_active = true;

  -- Пройти по всей цепочке спонсоров
  WHILE v_current_user_id IS NOT NULL AND v_level < v_max_level LOOP
    v_level := v_level + 1;
    
    -- Получить процент комиссии для этого уровня
    SELECT percent INTO v_percent
    FROM mlm_commission_rules
    WHERE structure_type = 1 
      AND level = v_level 
      AND is_active = true
    ORDER BY effective_from DESC
    LIMIT 1;
    
    IF v_percent IS NOT NULL AND v_percent > 0 THEN
      -- Рассчитать комиссию с округлением до целого KZT
      v_commission_cents := ROUND(v_base_amount_cents * v_percent / 100 / 100) * 100;
      
      -- Минимальная комиссия - 100 тийинов (1 тенге)
      IF v_commission_cents >= 100 THEN
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
          'frozen',
          p_subscription_id,
          'subscription',
          v_level,
          'primary',
          v_frozen_until,
          jsonb_build_object(
            'subscription_id', p_subscription_id,
            'buyer_id', p_user_id,
            'percent', v_percent,
            'base_amount_kzt', p_amount_kzt
          )
        );
        
        v_commissions_created := v_commissions_created + 1;
      END IF;
    END IF;
    
    -- Перейти к спонсору текущего пользователя
    SELECT sponsor_id INTO v_current_user_id
    FROM profiles
    WHERE id = v_current_user_id;
  END LOOP;

  RETURN json_build_object(
    'success', true,
    'commissions_created', v_commissions_created
  );
END;
$$;