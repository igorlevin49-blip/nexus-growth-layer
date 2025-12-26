
-- 1. Обновить get_user_balance - игнорировать failed withdrawal транзакции
CREATE OR REPLACE FUNCTION public.get_user_balance(p_user_id uuid)
RETURNS TABLE(
  user_id uuid, 
  available_cents bigint, 
  frozen_cents bigint, 
  pending_cents bigint, 
  withdrawn_cents bigint, 
  updated_at timestamp with time zone
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  RETURN QUERY
  SELECT 
    p_user_id as user_id,
    
    -- Available: разблокированные комиссии/бонусы МИНУС завершённые/processing выводы
    -- ВАЖНО: НЕ учитываем failed/cancelled выводы
    COALESCE(SUM(
      CASE 
        WHEN t.type IN ('commission', 'bonus', 'adjustment') 
          AND t.status = 'completed' 
          AND (t.frozen_until IS NULL OR t.frozen_until <= NOW())
        THEN t.amount_cents 
        WHEN t.type = 'withdrawal' AND t.status IN ('completed', 'processing')
        THEN -t.amount_cents
        -- failed и cancelled НЕ вычитаем - деньги вернулись
        ELSE 0 
      END
    ), 0)::bigint as available_cents,
    
    -- Frozen: комиссии где frozen_until > NOW() ИЛИ status = 'frozen'
    COALESCE(SUM(
      CASE 
        WHEN t.type IN ('commission', 'bonus', 'adjustment') 
          AND (
            t.status = 'frozen'
            OR (t.status = 'completed' AND t.frozen_until IS NOT NULL AND t.frozen_until > NOW())
          )
        THEN t.amount_cents 
        ELSE 0 
      END
    ), 0)::bigint as frozen_cents,
    
    -- Pending: ожидающие транзакции
    COALESCE(SUM(
      CASE 
        WHEN t.type IN ('commission', 'bonus', 'adjustment') 
          AND t.status = 'pending'
        THEN t.amount_cents 
        ELSE 0 
      END
    ), 0)::bigint as pending_cents,
    
    -- Withdrawn: только завершённые выводы
    COALESCE(SUM(
      CASE 
        WHEN t.type = 'withdrawal' AND t.status = 'completed'
        THEN t.amount_cents 
        ELSE 0 
      END
    ), 0)::bigint as withdrawn_cents,
    
    NOW() as updated_at
    
  FROM transactions t
  WHERE t.user_id = p_user_id
    AND t.currency = 'KZT'
    AND (t.is_archived IS NULL OR t.is_archived = false);
END;
$function$;

-- 2. Добавить функцию для проверки наличия processing выводов
CREATE OR REPLACE FUNCTION public.has_processing_withdrawal(p_user_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  has_pending boolean;
BEGIN
  SELECT EXISTS(
    SELECT 1 FROM withdrawals 
    WHERE user_id = p_user_id 
      AND status = 'processing'
      AND (is_archived IS NULL OR is_archived = false)
  ) INTO has_pending;
  
  RETURN has_pending;
END;
$function$;

-- 3. Обновить create_user_withdrawal с проверкой на дубли
CREATE OR REPLACE FUNCTION public.create_user_withdrawal(
  p_user_id uuid,
  p_amount_cents bigint,
  p_method_id uuid
)
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
  
  -- Создаём withdrawal
  INSERT INTO withdrawals (user_id, amount_cents, method_id, status, fee_cents)
  VALUES (p_user_id, p_amount_cents, p_method_id, 'processing', 0)
  RETURNING id INTO v_withdrawal_id;
  
  -- Создаём транзакцию
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
    'withdrawal', 
    p_amount_cents, 
    'KZT', 
    'processing', 
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
