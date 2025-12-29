-- Сначала удалить существующую функцию
DROP FUNCTION IF EXISTS public.hard_delete_user(uuid, uuid);

-- Создать функцию заново: только суперадмин может удалять
CREATE FUNCTION public.hard_delete_user(p_user_id uuid, p_admin_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_email text;
  v_user_name text;
  v_affected_referrals int;
BEGIN
  -- ТОЛЬКО суперадмин может удалять пользователей (исправлен порядок аргументов)
  IF NOT has_role(p_admin_id, 'superadmin'::app_role) THEN
    RAISE EXCEPTION 'Access denied: superadmin role required';
  END IF;

  -- Получить данные пользователя перед удалением
  SELECT email, full_name INTO v_user_email, v_user_name
  FROM profiles WHERE id = p_user_id;

  IF v_user_email IS NULL THEN
    RAISE EXCEPTION 'User not found';
  END IF;

  -- Подсчитать затронутых рефералов
  SELECT COUNT(*) INTO v_affected_referrals
  FROM profiles WHERE sponsor_id = p_user_id;

  -- Удалить связанные данные
  DELETE FROM withdrawals WHERE user_id = p_user_id;
  DELETE FROM transactions WHERE user_id = p_user_id;
  DELETE FROM subscriptions WHERE user_id = p_user_id;
  DELETE FROM order_items WHERE order_id IN (SELECT id FROM orders WHERE user_id = p_user_id);
  DELETE FROM orders WHERE user_id = p_user_id;
  DELETE FROM monthly_activations WHERE user_id = p_user_id;
  DELETE FROM referrals WHERE referred_user_id = p_user_id OR referrer_id = p_user_id;
  DELETE FROM notification_settings WHERE user_id = p_user_id;
  DELETE FROM auto_withdraw_rules WHERE user_id = p_user_id;
  DELETE FROM payment_methods WHERE user_id = p_user_id;
  DELETE FROM user_roles WHERE user_id = p_user_id;
  DELETE FROM user_consents WHERE user_id = p_user_id;
  DELETE FROM user_modal_notifications WHERE user_id = p_user_id;
  DELETE FROM user_status_achievements WHERE user_id = p_user_id;
  DELETE FROM user_sensitive_data WHERE user_id = p_user_id;
  DELETE FROM security_events WHERE user_id = p_user_id;
  DELETE FROM activity_log WHERE user_id = p_user_id;
  DELETE FROM activation_reminder_logs WHERE user_id = p_user_id;

  -- Обнулить sponsor_id у рефералов
  UPDATE profiles SET sponsor_id = NULL WHERE sponsor_id = p_user_id;

  -- Удалить профиль
  DELETE FROM profiles WHERE id = p_user_id;

  -- Логировать действие
  INSERT INTO admin_audit (admin_id, action_type, target_type, target_id, metadata)
  VALUES (p_admin_id, 'hard_delete_user', 'user', p_user_id, jsonb_build_object(
    'deleted_email', v_user_email,
    'deleted_name', v_user_name,
    'affected_referrals', v_affected_referrals
  ));

  RETURN jsonb_build_object(
    'success', true,
    'deleted_user', v_user_email,
    'deleted_name', v_user_name,
    'affected_referrals', v_affected_referrals
  );
END;
$$;