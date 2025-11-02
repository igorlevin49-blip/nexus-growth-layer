-- Функция для очистки всех пользователей кроме указанных email
CREATE OR REPLACE FUNCTION public.cleanup_all_test_users(
  p_keep_emails TEXT[],
  p_admin_id UUID,
  p_confirmation_phrase TEXT,
  p_dry_run BOOLEAN DEFAULT true
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_keep_user_ids UUID[];
  v_users_count INT;
  v_orders_count INT;
  v_subscriptions_count INT;
  v_transactions_count INT;
  v_withdrawals_count INT;
  v_referrals_count INT;
  v_activity_count INT;
BEGIN
  -- Проверка прав superadmin
  IF NOT has_role(p_admin_id, 'superadmin'::app_role) THEN
    RAISE EXCEPTION 'Only superadmin can cleanup users';
  END IF;

  -- Проверка фразы подтверждения для реального удаления
  IF NOT p_dry_run AND p_confirmation_phrase != 'УДАЛИТЬ ВСЕ ТЕСТОВЫЕ ДАННЫЕ' THEN
    RAISE EXCEPTION 'Invalid confirmation phrase';
  END IF;

  -- Получаем ID пользователей которых нужно сохранить
  SELECT ARRAY_AGG(id) INTO v_keep_user_ids
  FROM profiles
  WHERE email = ANY(p_keep_emails);
  
  IF v_keep_user_ids IS NULL OR array_length(v_keep_user_ids, 1) = 0 THEN
    RAISE EXCEPTION 'No users found with provided emails: %', p_keep_emails;
  END IF;

  -- Подсчёт записей для удаления
  SELECT COUNT(*) INTO v_users_count 
  FROM profiles 
  WHERE id != ALL(v_keep_user_ids) AND is_active = true;
  
  SELECT COUNT(*) INTO v_orders_count 
  FROM orders 
  WHERE user_id != ALL(v_keep_user_ids);
  
  SELECT COUNT(*) INTO v_subscriptions_count 
  FROM subscriptions 
  WHERE user_id != ALL(v_keep_user_ids);
  
  SELECT COUNT(*) INTO v_transactions_count 
  FROM transactions 
  WHERE user_id != ALL(v_keep_user_ids);
  
  SELECT COUNT(*) INTO v_withdrawals_count 
  FROM withdrawals 
  WHERE user_id != ALL(v_keep_user_ids);
  
  SELECT COUNT(*) INTO v_referrals_count 
  FROM referrals 
  WHERE referrer_id != ALL(v_keep_user_ids) AND referred_user_id != ALL(v_keep_user_ids);
  
  SELECT COUNT(*) INTO v_activity_count 
  FROM activity_log 
  WHERE user_id != ALL(v_keep_user_ids);

  -- Если не dry run, выполняем удаление
  IF NOT p_dry_run THEN
    -- Удаляем в правильном порядке (учитывая зависимости)
    DELETE FROM transactions WHERE user_id != ALL(v_keep_user_ids);
    DELETE FROM withdrawals WHERE user_id != ALL(v_keep_user_ids);
    DELETE FROM activity_log WHERE user_id != ALL(v_keep_user_ids);
    DELETE FROM order_items WHERE order_id IN (SELECT id FROM orders WHERE user_id != ALL(v_keep_user_ids));
    DELETE FROM orders WHERE user_id != ALL(v_keep_user_ids);
    DELETE FROM subscriptions WHERE user_id != ALL(v_keep_user_ids);
    DELETE FROM referrals WHERE referrer_id != ALL(v_keep_user_ids) AND referred_user_id != ALL(v_keep_user_ids);
    DELETE FROM payment_methods WHERE user_id != ALL(v_keep_user_ids);
    DELETE FROM auto_withdraw_rules WHERE user_id != ALL(v_keep_user_ids);
    DELETE FROM notification_settings WHERE user_id != ALL(v_keep_user_ids);
    DELETE FROM security_events WHERE user_id != ALL(v_keep_user_ids);
    DELETE FROM user_consents WHERE user_id != ALL(v_keep_user_ids);
    
    -- Мягкое удаление профилей
    UPDATE profiles 
    SET is_active = false, deleted_at = NOW(), updated_at = NOW()
    WHERE id != ALL(v_keep_user_ids) AND is_active = true;
    
    -- Удаляем роли
    DELETE FROM user_roles WHERE user_id != ALL(v_keep_user_ids);

    -- Логируем действие
    INSERT INTO admin_actions (admin_id, action_type, target_type, metadata)
    VALUES (
      p_admin_id,
      'cleanup_all_test_users',
      'system',
      jsonb_build_object(
        'keep_emails', p_keep_emails,
        'keep_user_ids', v_keep_user_ids,
        'users_deleted', v_users_count,
        'orders_deleted', v_orders_count,
        'subscriptions_deleted', v_subscriptions_count,
        'transactions_deleted', v_transactions_count,
        'withdrawals_deleted', v_withdrawals_count,
        'referrals_deleted', v_referrals_count,
        'activity_deleted', v_activity_count
      )
    );
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'dry_run', p_dry_run,
    'users', v_users_count,
    'orders', v_orders_count,
    'subscriptions', v_subscriptions_count,
    'transactions', v_transactions_count,
    'withdrawals', v_withdrawals_count,
    'referrals', v_referrals_count,
    'activity', v_activity_count,
    'keep_emails', p_keep_emails
  );
END;
$$;