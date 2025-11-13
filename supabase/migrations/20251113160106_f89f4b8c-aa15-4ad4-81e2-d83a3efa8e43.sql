-- Extend activity_log type constraint to allow referral binding events
-- This fixes "Database error saving new user" during registration

-- Drop old constraint
ALTER TABLE public.activity_log DROP CONSTRAINT IF EXISTS activity_log_type_check;

-- Create new constraint with additional referral binding types
ALTER TABLE public.activity_log ADD CONSTRAINT activity_log_type_check 
CHECK (type = ANY (ARRAY[
  'invite'::text,
  'activation'::text,
  'freeze'::text,
  'unfreeze'::text,
  'purchase'::text,
  'registration'::text,
  'subscription_activated'::text,
  'manual_payment_approved'::text,
  'manual_payment_rejected'::text,
  'admin_action'::text,
  'referral_auto_bound'::text,
  'referral_bind_failed'::text
]));