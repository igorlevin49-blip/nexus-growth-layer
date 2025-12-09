
-- Create a separate table for sensitive user data with stricter access
CREATE TABLE IF NOT EXISTS public.user_sensitive_data (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE UNIQUE,
  payment_details_encrypted TEXT,
  bank_account TEXT,
  card_last_four TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.user_sensitive_data ENABLE ROW LEVEL SECURITY;

-- Only the user can view/manage their own sensitive data
CREATE POLICY "Users can view their own sensitive data"
ON public.user_sensitive_data
FOR SELECT
USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own sensitive data"
ON public.user_sensitive_data
FOR INSERT
WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own sensitive data"
ON public.user_sensitive_data
FOR UPDATE
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

-- Superadmins cannot directly access sensitive data (only through secure functions)
-- This is intentional - even admins should not see raw payment details

-- Migrate existing payment_details to the new table (if any exist)
INSERT INTO public.user_sensitive_data (user_id, payment_details_encrypted)
SELECT id, payment_details
FROM public.profiles
WHERE payment_details IS NOT NULL AND payment_details != ''
ON CONFLICT (user_id) DO NOTHING;

-- Clear payment_details from profiles table for users who had data migrated
UPDATE public.profiles
SET payment_details = NULL
WHERE id IN (SELECT user_id FROM public.user_sensitive_data WHERE payment_details_encrypted IS NOT NULL);

-- Add comment to document that payment_details is deprecated
COMMENT ON COLUMN public.profiles.payment_details IS 'DEPRECATED: Use user_sensitive_data table for payment details. This column should remain empty.';

-- Create a view for network display that excludes all sensitive information
CREATE OR REPLACE VIEW public.profiles_network_safe AS
SELECT 
  id,
  full_name,
  avatar_url,
  referral_code,
  subscription_status,
  is_active,
  sponsor_id,
  direct_referrals_count,
  monthly_activation_completed,
  created_at
FROM public.profiles
WHERE is_active = true 
  AND deleted_at IS NULL 
  AND (is_archived IS NULL OR is_archived = false);

-- Grant select on the view
GRANT SELECT ON public.profiles_network_safe TO authenticated;
