
-- Create trigger to notify admins about suspicious referral binding attempts
CREATE OR REPLACE FUNCTION public.notify_admins_suspicious_activity()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_admin_id UUID;
  v_user_name TEXT;
  v_user_email TEXT;
  v_reason TEXT;
  v_title TEXT;
  v_message TEXT;
BEGIN
  -- Only process suspicious activity types
  IF NEW.type NOT IN ('referral_bind_failed', 'admin_bind_sponsor_failed') THEN
    RETURN NEW;
  END IF;

  -- Check if this is a suspicious reason
  v_reason := NEW.payload->>'reason';
  IF v_reason NOT IN ('sponsor_registered_later', 'already_sponsor', 'SPONSOR_REGISTERED_LATER', 'USER_IS_SPONSOR') THEN
    RETURN NEW;
  END IF;

  -- Get user info
  SELECT full_name, email INTO v_user_name, v_user_email
  FROM public.profiles WHERE id = NEW.user_id;

  -- Build notification message
  CASE v_reason
    WHEN 'sponsor_registered_later', 'SPONSOR_REGISTERED_LATER' THEN
      v_title := 'Подозрительная привязка реферала';
      v_message := format('Попытка привязки %s (%s) к спонсору, зарегистрированному позже. Возможная попытка мошенничества.',
        COALESCE(v_user_name, 'Неизвестный'), COALESCE(v_user_email, NEW.user_id::text));
    WHEN 'already_sponsor', 'USER_IS_SPONSOR' THEN
      v_title := 'Попытка привязки спонсора';
      v_message := format('Попытка привязки %s (%s), который уже является спонсором для других пользователей.',
        COALESCE(v_user_name, 'Неизвестный'), COALESCE(v_user_email, NEW.user_id::text));
    ELSE
      RETURN NEW;
  END CASE;

  -- Notify all superadmins
  FOR v_admin_id IN
    SELECT user_id FROM public.user_roles WHERE role = 'superadmin'
  LOOP
    INSERT INTO public.admin_notifications (admin_id, type, title, message, metadata)
    VALUES (
      v_admin_id,
      'suspicious_activity',
      v_title,
      v_message,
      jsonb_build_object(
        'activity_log_id', NEW.id,
        'user_id', NEW.user_id,
        'user_name', v_user_name,
        'user_email', v_user_email,
        'reason', v_reason,
        'payload', NEW.payload
      )
    );
  END LOOP;

  RETURN NEW;
END;
$function$;

-- Create trigger on activity_log
DROP TRIGGER IF EXISTS trigger_notify_suspicious_activity ON public.activity_log;
CREATE TRIGGER trigger_notify_suspicious_activity
  AFTER INSERT ON public.activity_log
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_admins_suspicious_activity();
