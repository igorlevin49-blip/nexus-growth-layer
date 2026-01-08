-- Функция для исправления маркетинговых нарушений (комиссии за is_marketing_free_access подписки)
CREATE OR REPLACE FUNCTION public.admin_fix_marketing_free_violations(
  p_admin_id uuid,
  p_dry_run boolean DEFAULT true
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_violations jsonb;
  v_fixed_count integer := 0;
  v_total_amount numeric := 0;
  v_transaction record;
BEGIN
  -- Проверяем права админа
  IF NOT EXISTS (
    SELECT 1 FROM profiles 
    WHERE id = p_admin_id 
    AND role IN ('admin', 'superadmin')
  ) THEN
    RAISE EXCEPTION 'Access denied: admin privileges required';
  END IF;

  -- Находим все комиссии за подписки с is_marketing_free_access = true
  SELECT jsonb_agg(jsonb_build_object(
    'transaction_id', t.id,
    'user_id', t.user_id,
    'user_email', p.email,
    'amount', t.amount,
    'subscription_id', t.reference_id,
    'created_at', t.created_at,
    'current_status', t.status
  ))
  INTO v_violations
  FROM transactions t
  JOIN profiles p ON p.id = t.user_id
  JOIN subscriptions s ON s.id = t.reference_id::uuid
  WHERE t.type = 'commission'
    AND t.status = 'completed'
    AND s.is_marketing_free_access = true;

  -- Если нет нарушений
  IF v_violations IS NULL OR jsonb_array_length(v_violations) = 0 THEN
    RETURN jsonb_build_object(
      'success', true,
      'dry_run', p_dry_run,
      'message', 'No marketing free violations found',
      'fixed_count', 0,
      'total_amount', 0,
      'violations', '[]'::jsonb
    );
  END IF;

  -- Если dry run - просто возвращаем найденные нарушения
  IF p_dry_run THEN
    SELECT COUNT(*), COALESCE(SUM(amount), 0)
    INTO v_fixed_count, v_total_amount
    FROM transactions t
    JOIN subscriptions s ON s.id = t.reference_id::uuid
    WHERE t.type = 'commission'
      AND t.status = 'completed'
      AND s.is_marketing_free_access = true;

    RETURN jsonb_build_object(
      'success', true,
      'dry_run', true,
      'message', format('Found %s marketing free violations totaling %s KZT', v_fixed_count, v_total_amount),
      'fixed_count', v_fixed_count,
      'total_amount', v_total_amount,
      'violations', v_violations
    );
  END IF;

  -- Реальное исправление: помечаем транзакции как failed и корректируем балансы
  FOR v_transaction IN
    SELECT t.id, t.user_id, t.amount
    FROM transactions t
    JOIN subscriptions s ON s.id = t.reference_id::uuid
    WHERE t.type = 'commission'
      AND t.status = 'completed'
      AND s.is_marketing_free_access = true
  LOOP
    -- Помечаем транзакцию как failed
    UPDATE transactions 
    SET status = 'failed',
        metadata = COALESCE(metadata, '{}'::jsonb) || jsonb_build_object(
          'fixed_by', p_admin_id,
          'fixed_at', now(),
          'fix_reason', 'marketing_free_violation'
        )
    WHERE id = v_transaction.id;

    -- Уменьшаем баланс пользователя
    UPDATE profiles
    SET balance = GREATEST(0, balance - v_transaction.amount)
    WHERE id = v_transaction.user_id;

    v_fixed_count := v_fixed_count + 1;
    v_total_amount := v_total_amount + v_transaction.amount;
  END LOOP;

  -- Логируем действие
  INSERT INTO admin_logs (admin_id, action, details)
  VALUES (
    p_admin_id,
    'fix_marketing_free_violations',
    jsonb_build_object(
      'fixed_count', v_fixed_count,
      'total_amount', v_total_amount,
      'violations', v_violations
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'dry_run', false,
    'message', format('Fixed %s marketing free violations, corrected %s KZT', v_fixed_count, v_total_amount),
    'fixed_count', v_fixed_count,
    'total_amount', v_total_amount,
    'violations', v_violations
  );
END;
$$;