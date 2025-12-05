-- 1. Удаляем ВСЕ существующие reversal-транзакции от marketing_free_access
DELETE FROM transactions
WHERE type = 'adjustment'
AND payload->>'reversal_type' = 'marketing_free_access';

-- 2. Удаляем оставшиеся комиссии от бесплатных подписок (на случай если есть)
DELETE FROM transactions
WHERE type = 'commission'
AND source_ref LIKE 'subscription_%'
AND source_id IN (
  SELECT id FROM subscriptions WHERE is_marketing_free_access = true
);

-- 3. Исправляем функцию reverse_marketing_free_commissions - теперь УДАЛЯЕТ комиссии вместо создания reversals
CREATE OR REPLACE FUNCTION public.reverse_marketing_free_commissions(
  p_source_user_id uuid,
  p_admin_id uuid,
  p_comment text DEFAULT 'Отмена комиссий от бесплатной подписки'::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_subscription_id UUID;
  v_deleted_count INTEGER := 0;
  v_deleted_amount BIGINT := 0;
BEGIN
  -- Check admin role
  IF NOT (has_role(p_admin_id, 'admin'::app_role) OR has_role(p_admin_id, 'superadmin'::app_role)) THEN
    RETURN jsonb_build_object('success', false, 'error', 'UNAUTHORIZED');
  END IF;

  -- Find the marketing free subscription for this user
  SELECT id INTO v_subscription_id
  FROM subscriptions
  WHERE user_id = p_source_user_id
    AND is_marketing_free_access = true
    AND status = 'active'
  ORDER BY created_at DESC
  LIMIT 1;

  IF v_subscription_id IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'NO_MARKETING_SUBSCRIPTION',
      'message', 'У пользователя нет активной бесплатной подписки'
    );
  END IF;

  -- Count and sum commissions to be deleted
  SELECT COUNT(*), COALESCE(SUM(amount_cents), 0)
  INTO v_deleted_count, v_deleted_amount
  FROM transactions
  WHERE type = 'commission'
    AND source_id = v_subscription_id;

  -- Delete all commissions from this subscription
  DELETE FROM transactions
  WHERE type = 'commission'
    AND source_id = v_subscription_id;

  -- Log admin action
  INSERT INTO admin_actions (admin_id, action_type, target_type, target_id, comment, metadata)
  VALUES (
    p_admin_id,
    'reverse_marketing_commissions',
    'subscription',
    v_subscription_id,
    p_comment,
    jsonb_build_object(
      'source_user_id', p_source_user_id,
      'deleted_count', v_deleted_count,
      'deleted_amount_cents', v_deleted_amount
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'deleted_count', v_deleted_count,
    'deleted_amount_cents', v_deleted_amount,
    'subscription_id', v_subscription_id,
    'message', 'Комиссии удалены: ' || v_deleted_count || ' транзакций на сумму $' || (v_deleted_amount / 100.0)::TEXT
  );
END;
$function$;