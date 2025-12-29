
-- Drop existing function and recreate with fix for sponsor_id constraint
DROP FUNCTION IF EXISTS public.hard_delete_user(uuid, uuid);

CREATE FUNCTION public.hard_delete_user(p_user_id uuid, p_admin_id uuid)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_email text;
  v_user_name text;
  v_affected_referrals int;
BEGIN
  -- Check admin permissions
  IF NOT has_role('admin', p_admin_id) AND NOT has_role('superadmin', p_admin_id) THEN
    RAISE EXCEPTION 'Access denied: admin role required';
  END IF;

  -- Get user info for logging
  SELECT email, full_name INTO v_user_email, v_user_name
  FROM profiles WHERE id = p_user_id;

  IF v_user_email IS NULL THEN
    RAISE EXCEPTION 'User not found';
  END IF;

  -- Save sponsor snapshot and clear sponsor_id for users who have this user as sponsor
  UPDATE public.profiles
  SET 
    referrer_snapshot = jsonb_build_object(
      'id', p_user_id,
      'full_name', v_user_name,
      'email', v_user_email,
      'deleted_at', NOW()
    ),
    sponsor_id = NULL
  WHERE sponsor_id = p_user_id;
  
  GET DIAGNOSTICS v_affected_referrals = ROW_COUNT;

  -- Delete related data in correct order
  DELETE FROM public.user_modal_notifications WHERE user_id = p_user_id;
  DELETE FROM public.system_notification_logs WHERE user_id = p_user_id;
  DELETE FROM public.activation_reminder_logs WHERE user_id = p_user_id;
  DELETE FROM public.notification_settings WHERE user_id = p_user_id;
  DELETE FROM public.user_consents WHERE user_id = p_user_id;
  DELETE FROM public.user_status_achievements WHERE user_id = p_user_id;
  DELETE FROM public.security_events WHERE user_id = p_user_id;
  DELETE FROM public.activity_log WHERE user_id = p_user_id;
  DELETE FROM public.auto_withdraw_rules WHERE user_id = p_user_id;
  DELETE FROM public.payment_methods WHERE user_id = p_user_id;
  DELETE FROM public.withdrawals WHERE user_id = p_user_id;
  DELETE FROM public.transactions WHERE user_id = p_user_id;
  DELETE FROM public.monthly_activations WHERE user_id = p_user_id;
  DELETE FROM public.referrals WHERE referred_user_id = p_user_id OR referrer_id = p_user_id;
  DELETE FROM public.order_items WHERE order_id IN (SELECT id FROM orders WHERE user_id = p_user_id);
  DELETE FROM public.orders WHERE user_id = p_user_id;
  DELETE FROM public.subscriptions WHERE user_id = p_user_id;
  DELETE FROM public.user_roles WHERE user_id = p_user_id;
  DELETE FROM public.user_sensitive_data WHERE user_id = p_user_id;
  
  -- Delete the profile
  DELETE FROM public.profiles WHERE id = p_user_id;

  -- Log the action
  INSERT INTO admin_audit (admin_id, action_type, target_type, target_id, metadata)
  VALUES (
    p_admin_id,
    'hard_delete_user',
    'user',
    p_user_id::text,
    jsonb_build_object(
      'email', v_user_email,
      'full_name', v_user_name,
      'affected_referrals', v_affected_referrals
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'deleted_user', v_user_email,
    'affected_referrals', v_affected_referrals
  );
END;
$$;
