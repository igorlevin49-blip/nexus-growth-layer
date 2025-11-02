-- Create function to permanently delete user from both profiles and auth.users
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

  -- Delete from profiles (cascading will handle related records)
  DELETE FROM public.profiles WHERE id = p_user_id;
  
  -- Delete from auth.users
  DELETE FROM auth.users WHERE id = p_user_id;

  RETURN jsonb_build_object('success', true);
END;
$function$;