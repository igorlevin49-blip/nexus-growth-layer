-- Create trigger function to notify admins on payment/commission errors
CREATE OR REPLACE FUNCTION public.notify_admins_on_commission_skipped()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_admin_id UUID;
  v_payload JSONB;
  v_message TEXT;
  v_title TEXT;
BEGIN
  -- Only process commission_skipped events
  IF NEW.type != 'commission_skipped' THEN
    RETURN NEW;
  END IF;

  v_payload := COALESCE(NEW.payload, '{}'::jsonb);
  v_title := 'Пропущена комиссия';
  v_message := format(
    'Комиссия не начислена: %s. Причина: %s. Сумма: %s KZT',
    COALESCE(v_payload->>'subscription_id', v_payload->>'order_id', 'неизвестно'),
    COALESCE(v_payload->>'reason', 'неизвестно'),
    COALESCE(v_payload->>'would_be_amount_kzt', '0')
  );

  -- Insert notification for all admins
  FOR v_admin_id IN 
    SELECT user_id FROM user_roles WHERE role IN ('admin', 'superadmin')
  LOOP
    INSERT INTO admin_notifications (
      admin_id,
      type,
      title,
      message,
      metadata,
      read
    ) VALUES (
      v_admin_id,
      'payment_error',
      v_title,
      v_message,
      jsonb_build_object(
        'activity_log_id', NEW.id,
        'user_id', NEW.user_id,
        'error_type', v_payload->>'reason',
        'source_type', CASE 
          WHEN v_payload ? 'subscription_id' THEN 'subscription'
          WHEN v_payload ? 'order_id' THEN 'order'
          ELSE 'unknown'
        END,
        'source_id', COALESCE(v_payload->>'subscription_id', v_payload->>'order_id'),
        'amount_kzt', v_payload->>'would_be_amount_kzt'
      ),
      false
    );
  END LOOP;

  RETURN NEW;
END;
$function$;

-- Create trigger on activity_log for commission_skipped events
DROP TRIGGER IF EXISTS notify_admins_on_commission_error ON activity_log;
CREATE TRIGGER notify_admins_on_commission_error
  AFTER INSERT ON activity_log
  FOR EACH ROW
  WHEN (NEW.type = 'commission_skipped')
  EXECUTE FUNCTION notify_admins_on_commission_skipped();

-- Also create a function to log payment processing errors explicitly
CREATE OR REPLACE FUNCTION public.log_payment_error(
  p_user_id UUID,
  p_error_type TEXT,
  p_error_message TEXT,
  p_source_type TEXT,
  p_source_id UUID
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_admin_id UUID;
BEGIN
  -- Log to activity_log
  INSERT INTO activity_log (user_id, type, payload)
  VALUES (
    p_user_id,
    'payment_error',
    jsonb_build_object(
      'error_type', p_error_type,
      'error_message', p_error_message,
      'source_type', p_source_type,
      'source_id', p_source_id
    )
  );

  -- Notify all admins
  FOR v_admin_id IN 
    SELECT user_id FROM user_roles WHERE role IN ('admin', 'superadmin')
  LOOP
    INSERT INTO admin_notifications (
      admin_id,
      type,
      title,
      message,
      metadata,
      read
    ) VALUES (
      v_admin_id,
      'payment_error',
      'Ошибка обработки платежа',
      format('%s: %s', p_error_type, p_error_message),
      jsonb_build_object(
        'user_id', p_user_id,
        'error_type', p_error_type,
        'source_type', p_source_type,
        'source_id', p_source_id
      ),
      false
    );
  END LOOP;
END;
$function$;
