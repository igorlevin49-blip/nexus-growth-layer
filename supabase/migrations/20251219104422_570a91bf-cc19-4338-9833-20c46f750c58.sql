-- Allow new notification type for payment/commission processing errors
ALTER TABLE public.admin_notifications
  DROP CONSTRAINT IF EXISTS admin_notifications_type_check;

ALTER TABLE public.admin_notifications
  ADD CONSTRAINT admin_notifications_type_check
  CHECK (
    type = ANY (
      ARRAY[
        'status_achievement',
        'payment',
        'system',
        'suspicious_activity',
        'commission',
        'payment_error'
      ]
    )
  );
