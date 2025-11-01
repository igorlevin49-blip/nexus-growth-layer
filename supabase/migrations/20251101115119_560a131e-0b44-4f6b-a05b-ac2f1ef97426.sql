-- Add referrer_snapshot column to profiles table
ALTER TABLE public.profiles 
ADD COLUMN IF NOT EXISTS referrer_snapshot JSONB DEFAULT NULL;

COMMENT ON COLUMN public.profiles.referrer_snapshot IS 'Snapshot of sponsor data at registration time (preserved even if sponsor is deleted)';