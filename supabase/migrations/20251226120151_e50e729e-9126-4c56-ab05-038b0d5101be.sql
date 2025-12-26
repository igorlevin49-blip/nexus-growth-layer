
-- =====================================================
-- КОМПЛЕКСНОЕ ИСПРАВЛЕНИЕ ВСЕХ ФУНКЦИЙ С ENUM ТИПАМИ
-- =====================================================

-- 1. ИСПРАВЛЕНИЕ ТРИГГЕРА sync_withdrawal_transaction (ГЛАВНАЯ ПРОБЛЕМА)
CREATE OR REPLACE FUNCTION public.sync_withdrawal_transaction()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_existing_tx_id uuid;
  v_transaction_status transaction_status;
BEGIN
  -- Only process for processing/completed withdrawals without transaction_id
  IF NEW.status IN ('processing'::withdrawal_status, 'completed'::withdrawal_status) AND NEW.transaction_id IS NULL THEN
    -- Map withdrawal_status to transaction_status explicitly
    v_transaction_status := CASE NEW.status
      WHEN 'completed'::withdrawal_status THEN 'completed'::transaction_status
      WHEN 'processing'::withdrawal_status THEN 'processing'::transaction_status
      ELSE 'pending'::transaction_status
    END;
    
    -- Check if transaction already exists for this withdrawal
    SELECT id INTO v_existing_tx_id
    FROM transactions
    WHERE source_ref = 'withdrawal:' || NEW.id::text
       OR source_ref = 'withdrawal_' || NEW.id::text
       OR source_ref = 'auto_withdrawal_' || NEW.id::text
       OR source_ref = 'manual_payout_' || NEW.id::text
       OR source_id = NEW.id
    LIMIT 1;
    
    IF v_existing_tx_id IS NULL THEN
      -- Create transaction if it doesn't exist with explicit type casts
      INSERT INTO transactions (
        user_id, 
        type, 
        amount_cents, 
        currency, 
        status, 
        source_id,
        source_ref
      ) VALUES (
        NEW.user_id, 
        'withdrawal'::transaction_type, 
        NEW.amount_cents, 
        'KZT', 
        v_transaction_status,
        NEW.id,
        'withdrawal:' || NEW.id::text
      );
      
      RAISE NOTICE 'Auto-created transaction for withdrawal %', NEW.id;
    END IF;
  END IF;
  
  RETURN NEW;
END;
$function$;

-- 2. ИСПРАВЛЕНИЕ admin_adjust_balance
CREATE OR REPLACE FUNCTION public.admin_adjust_balance(p_user_id uuid, p_amount_cents bigint, p_reason text, p_admin_id uuid)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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

  -- Создать транзакцию корректировки с явными кастами типов
  INSERT INTO transactions (
    user_id,
    type,
    amount_cents,
    status,
    currency,
    payload
  ) VALUES (
    p_user_id,
    'adjustment'::transaction_type,
    ABS(p_amount_cents),
    'completed'::transaction_status,
    'KZT',
    jsonb_build_object(
      'reason', TRIM(p_reason),
      'admin_id', p_admin_id,
      'direction', CASE WHEN p_amount_cents > 0 THEN 'credit' ELSE 'debit' END,
      'balance_before', v_current_balance
    )
  )
  RETURNING id INTO v_transaction_id;

  -- Если списание - создать withdrawal запись для учёта с явным кастом
  IF p_amount_cents < 0 THEN
    INSERT INTO withdrawals (
      user_id,
      amount_cents,
      status,
      transaction_id
    ) VALUES (
      p_user_id,
      ABS(p_amount_cents),
      'completed'::withdrawal_status,
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
$function$;

-- 3. ИСПРАВЛЕНИЕ create_user_withdrawal
CREATE OR REPLACE FUNCTION public.create_user_withdrawal(p_user_id uuid, p_amount_cents bigint, p_method_id uuid)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_available bigint;
  v_withdrawal_id uuid;
  v_transaction_id uuid;
  v_has_processing boolean;
BEGIN
  -- Проверяем есть ли уже processing вывод
  SELECT has_processing_withdrawal(p_user_id) INTO v_has_processing;
  
  IF v_has_processing THEN
    RETURN json_build_object(
      'success', false,
      'message', 'У вас уже есть заявка на вывод в обработке. Дождитесь её завершения.'
    );
  END IF;

  -- Блокируем строки для атомарности
  SELECT available_cents INTO v_available
  FROM get_user_balance(p_user_id);
  
  -- Проверяем достаточность средств
  IF v_available < p_amount_cents THEN
    RETURN json_build_object(
      'success', false,
      'message', 'Недостаточно средств на балансе. Доступно: ' || v_available || ' ₸'
    );
  END IF;
  
  -- Создаём withdrawal с явным кастом типа
  INSERT INTO withdrawals (user_id, amount_cents, method_id, status, fee_cents)
  VALUES (p_user_id, p_amount_cents, p_method_id, 'processing'::withdrawal_status, 0)
  RETURNING id INTO v_withdrawal_id;
  
  -- Создаём транзакцию с явными кастами типов
  INSERT INTO transactions (
    user_id, 
    type, 
    amount_cents, 
    currency, 
    status, 
    source_ref
  )
  VALUES (
    p_user_id, 
    'withdrawal'::transaction_type, 
    p_amount_cents, 
    'KZT', 
    'processing'::transaction_status, 
    'withdrawal:' || v_withdrawal_id
  )
  RETURNING id INTO v_transaction_id;
  
  -- Обновляем withdrawal с transaction_id
  UPDATE withdrawals 
  SET transaction_id = v_transaction_id 
  WHERE id = v_withdrawal_id;
  
  RETURN json_build_object(
    'success', true,
    'withdrawal_id', v_withdrawal_id,
    'transaction_id', v_transaction_id
  );
END;
$function$;

-- 4. ИСПРАВЛЕНИЕ create_commission_transactions
CREATE OR REPLACE FUNCTION public.create_commission_transactions()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
      v_commission_cents := ROUND(v_base_amount_cents * v_rules.percent / 100 / 100) * 100;
      
      -- Минимальная комиссия - 100 тийинов (1 тенге)
      IF v_commission_cents >= 100 THEN
        -- Вставка с явными кастами типов
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
          'commission'::transaction_type,
          v_commission_cents,
          'KZT',
          'frozen'::transaction_status,
          NEW.id,
          'order',
          v_level,
          'secondary'::structure_type,
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
$function$;

-- 5. ИСПРАВЛЕНИЕ recalculate_all_s1_commissions
CREATE OR REPLACE FUNCTION public.recalculate_all_s1_commissions(p_admin_id uuid)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_is_admin boolean;
  v_subscription record;
  v_sponsor_id uuid;
  v_current_level integer;
  v_commission_percent numeric;
  v_commission_amount integer;
  v_existing_commission uuid;
  v_subscriptions_processed integer := 0;
  v_commissions_created integer := 0;
  v_commissions_skipped integer := 0;
  v_source_ref text;
BEGIN
  -- Verify admin permissions
  SELECT EXISTS(
    SELECT 1 FROM user_roles 
    WHERE user_id = p_admin_id 
    AND role IN ('admin', 'superadmin')
  ) INTO v_is_admin;
  
  IF NOT v_is_admin THEN
    RETURN json_build_object(
      'success', false,
      'error', 'Unauthorized: Admin access required'
    );
  END IF;

  -- Process each PAID (not marketing free) active subscription
  FOR v_subscription IN
    SELECT s.id, s.user_id, s.amount_usd, p.full_name, p.sponsor_id as first_sponsor
    FROM subscriptions s
    JOIN profiles p ON p.id = s.user_id
    WHERE s.status = 'active'
      AND s.paid_at IS NOT NULL
      AND (s.is_marketing_free_access = false OR s.is_marketing_free_access IS NULL)
  LOOP
    v_subscriptions_processed := v_subscriptions_processed + 1;
    
    -- Start from the subscriber's direct sponsor
    v_sponsor_id := v_subscription.first_sponsor;
    v_current_level := 1;
    
    -- Process up to 5 levels
    WHILE v_current_level <= 5 AND v_sponsor_id IS NOT NULL LOOP
      -- Get commission percent for this level
      SELECT percent INTO v_commission_percent
      FROM mlm_commission_rules
      WHERE structure_type = 1
        AND level = v_current_level
        AND is_active = true
      ORDER BY effective_from DESC
      LIMIT 1;
      
      IF v_commission_percent IS NULL THEN
        v_commission_percent := 10;
      END IF;
      
      -- Calculate commission in cents
      v_commission_amount := ROUND(v_subscription.amount_usd * v_commission_percent)::integer;
      
      -- Build source_ref
      v_source_ref := v_subscription.id::text || '_s1_level_' || v_current_level::text;
      
      -- Check if commission already exists
      SELECT id INTO v_existing_commission
      FROM transactions
      WHERE source_id = v_subscription.id
        AND user_id = v_sponsor_id
        AND level = v_current_level
        AND type = 'commission'::transaction_type
        AND structure_type = 'primary'::structure_type
      LIMIT 1;
      
      IF v_existing_commission IS NULL THEN
        -- Вставка с явными кастами типов
        INSERT INTO transactions (
          user_id, type, amount_cents, status, source_id, source_ref,
          level, structure_type, payload, created_at, updated_at
        ) VALUES (
          v_sponsor_id, 
          'commission'::transaction_type, 
          v_commission_amount, 
          'completed'::transaction_status,
          v_subscription.id, v_source_ref, v_current_level, 
          'primary'::structure_type,
          jsonb_build_object(
            'from_user', v_subscription.full_name,
            'subscription_amount', v_subscription.amount_usd,
            'percent', v_commission_percent,
            'recalculated', true,
            'recalculated_at', now()
          ),
          now(), now()
        );
        v_commissions_created := v_commissions_created + 1;
      ELSE
        v_commissions_skipped := v_commissions_skipped + 1;
      END IF;
      
      -- Move to next level
      SELECT sponsor_id INTO v_sponsor_id FROM profiles WHERE id = v_sponsor_id;
      v_current_level := v_current_level + 1;
    END LOOP;
  END LOOP;

  -- Log action
  INSERT INTO admin_actions (admin_id, action_type, target_type, comment, metadata)
  VALUES (p_admin_id, 'recalculate_commissions', 'system', 
    'Recalculated S1 commissions for paid subscriptions only',
    jsonb_build_object(
      'subscriptions_processed', v_subscriptions_processed,
      'commissions_created', v_commissions_created,
      'commissions_skipped', v_commissions_skipped
    )
  );

  RETURN json_build_object(
    'success', true,
    'subscriptions_processed', v_subscriptions_processed,
    'commissions_created', v_commissions_created,
    'commissions_skipped', v_commissions_skipped
  );
END;
$function$;
