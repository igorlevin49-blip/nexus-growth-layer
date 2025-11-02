-- Функция для полного удаления всех пользователей кроме указанных
CREATE OR REPLACE FUNCTION public.cleanup_all_test_users(
  p_keep_emails text[],
  p_admin_id uuid,
  p_confirmation_phrase text,
  p_dry_run boolean DEFAULT true
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_users_to_delete uuid[];
  v_deleted_count int := 0;
  v_orders_count int := 0;
  v_subscriptions_count int := 0;
  v_transactions_count int := 0;
  v_withdrawals_count int := 0;
  v_referrals_count int := 0;
  v_activity_count int := 0;
BEGIN
  -- Check if user is superadmin
  IF NOT has_role(p_admin_id, 'superadmin'::app_role) THEN
    RAISE EXCEPTION 'Only superadmin can perform full cleanup';
  END IF;

  -- Verify confirmation phrase
  IF NOT p_dry_run AND p_confirmation_phrase != 'УДАЛИТЬ ВСЕ ТЕСТОВЫЕ АККАУНТЫ' THEN
    RAISE EXCEPTION 'Invalid confirmation phrase';
  END IF;

  -- Get list of users to delete (all except keep_emails)
  SELECT ARRAY_AGG(id) INTO v_users_to_delete
  FROM profiles
  WHERE email != ALL(p_keep_emails);

  -- Count what will be deleted
  SELECT COUNT(*) INTO v_deleted_count FROM profiles WHERE id = ANY(v_users_to_delete);
  SELECT COUNT(*) INTO v_orders_count FROM orders WHERE user_id = ANY(v_users_to_delete);
  SELECT COUNT(*) INTO v_subscriptions_count FROM subscriptions WHERE user_id = ANY(v_users_to_delete);
  SELECT COUNT(*) INTO v_transactions_count FROM transactions WHERE user_id = ANY(v_users_to_delete);
  SELECT COUNT(*) INTO v_withdrawals_count FROM withdrawals WHERE user_id = ANY(v_users_to_delete);
  SELECT COUNT(*) INTO v_referrals_count FROM referrals 
  WHERE referrer_id = ANY(v_users_to_delete) OR referred_user_id = ANY(v_users_to_delete);
  SELECT COUNT(*) INTO v_activity_count FROM activity_log WHERE user_id = ANY(v_users_to_delete);

  -- If dry run, just return counts
  IF p_dry_run THEN
    RETURN jsonb_build_object(
      'dry_run', true,
      'users', v_deleted_count,
      'orders', v_orders_count,
      'subscriptions', v_subscriptions_count,
      'transactions', v_transactions_count,
      'withdrawals', v_withdrawals_count,
      'referrals', v_referrals_count,
      'activity', v_activity_count,
      'keep_emails', p_keep_emails
    );
  END IF;

  -- Perform actual deletion in correct order (child tables first)
  DELETE FROM transactions WHERE user_id = ANY(v_users_to_delete);
  DELETE FROM withdrawals WHERE user_id = ANY(v_users_to_delete);
  DELETE FROM activity_log WHERE user_id = ANY(v_users_to_delete);
  DELETE FROM order_items WHERE order_id IN (SELECT id FROM orders WHERE user_id = ANY(v_users_to_delete));
  DELETE FROM orders WHERE user_id = ANY(v_users_to_delete);
  DELETE FROM subscriptions WHERE user_id = ANY(v_users_to_delete);
  DELETE FROM referrals WHERE referrer_id = ANY(v_users_to_delete) OR referred_user_id = ANY(v_users_to_delete);
  DELETE FROM payment_methods WHERE user_id = ANY(v_users_to_delete);
  DELETE FROM auto_withdraw_rules WHERE user_id = ANY(v_users_to_delete);
  DELETE FROM notification_settings WHERE user_id = ANY(v_users_to_delete);
  DELETE FROM security_events WHERE user_id = ANY(v_users_to_delete);
  DELETE FROM user_consents WHERE user_id = ANY(v_users_to_delete);
  DELETE FROM user_roles WHERE user_id = ANY(v_users_to_delete);
  
  -- Delete profiles
  DELETE FROM profiles WHERE id = ANY(v_users_to_delete);
  
  -- Delete from auth.users (Supabase auth table)
  DELETE FROM auth.users WHERE id = ANY(v_users_to_delete);

  -- Recalculate referral counts for remaining users
  UPDATE profiles p
  SET direct_referrals_count = (
    SELECT COUNT(*) FROM referrals r 
    WHERE r.referrer_id = p.id AND r.structure_type = 1
  )
  WHERE email = ANY(p_keep_emails);

  -- Log the action
  INSERT INTO admin_actions (admin_id, action_type, target_type, metadata)
  VALUES (
    p_admin_id,
    'cleanup_all_test_users',
    'system',
    jsonb_build_object(
      'users_deleted', v_deleted_count,
      'orders_deleted', v_orders_count,
      'subscriptions_deleted', v_subscriptions_count,
      'transactions_deleted', v_transactions_count,
      'withdrawals_deleted', v_withdrawals_count,
      'referrals_deleted', v_referrals_count,
      'activity_deleted', v_activity_count,
      'kept_emails', p_keep_emails
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'dry_run', false,
    'users', v_deleted_count,
    'orders', v_orders_count,
    'subscriptions', v_subscriptions_count,
    'transactions', v_transactions_count,
    'withdrawals', v_withdrawals_count,
    'referrals', v_referrals_count,
    'activity', v_activity_count,
    'keep_emails', p_keep_emails
  );
END;
$function$;