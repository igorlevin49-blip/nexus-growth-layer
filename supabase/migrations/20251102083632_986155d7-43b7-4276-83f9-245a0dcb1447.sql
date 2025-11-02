-- Update hard_delete_user function to cascade delete all related data
DROP FUNCTION IF EXISTS public.hard_delete_user(uuid, uuid);

CREATE OR REPLACE FUNCTION public.hard_delete_user(p_user_id uuid, p_admin_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  -- Check if admin has proper role
  IF NOT (has_role(p_admin_id, 'admin'::app_role) OR has_role(p_admin_id, 'superadmin'::app_role)) THEN
    RETURN jsonb_build_object('success', false, 'error', 'UNAUTHORIZED');
  END IF;

  -- Log admin action before deletion
  INSERT INTO admin_actions (admin_id, action_type, target_type, target_id, metadata)
  VALUES (
    p_admin_id,
    'hard_delete_user',
    'user',
    p_user_id,
    jsonb_build_object('deleted_at', NOW())
  );

  -- Delete all related data in correct order (respecting foreign keys)
  
  -- Delete transactions (commissions, bonuses, etc.)
  DELETE FROM transactions WHERE user_id = p_user_id;
  
  -- Delete withdrawals
  DELETE FROM withdrawals WHERE user_id = p_user_id;
  
  -- Delete order items (must be deleted before orders)
  DELETE FROM order_items WHERE order_id IN (SELECT id FROM orders WHERE user_id = p_user_id);
  
  -- Delete orders
  DELETE FROM orders WHERE user_id = p_user_id;
  
  -- Delete subscriptions
  DELETE FROM subscriptions WHERE user_id = p_user_id;
  
  -- Delete referrals where user is referrer or referred
  DELETE FROM referrals WHERE referrer_id = p_user_id OR referred_user_id = p_user_id;
  
  -- Delete payment methods
  DELETE FROM payment_methods WHERE user_id = p_user_id;
  
  -- Delete auto withdraw rules
  DELETE FROM auto_withdraw_rules WHERE user_id = p_user_id;
  
  -- Delete notification settings
  DELETE FROM notification_settings WHERE user_id = p_user_id;
  
  -- Delete activity log
  DELETE FROM activity_log WHERE user_id = p_user_id;
  
  -- Delete security events
  DELETE FROM security_events WHERE user_id = p_user_id;
  
  -- Delete user consents
  DELETE FROM user_consents WHERE user_id = p_user_id;
  
  -- Delete user roles
  DELETE FROM user_roles WHERE user_id = p_user_id;
  
  -- Delete from profiles
  DELETE FROM public.profiles WHERE id = p_user_id;
  
  -- Delete from auth.users
  DELETE FROM auth.users WHERE id = p_user_id;

  RETURN jsonb_build_object('success', true);
END;
$function$;