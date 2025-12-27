-- =====================================================
-- CRITICAL FIX: Remove duplicate award_s1_subscription_commission functions
-- Keep only the trigger function version (no arguments)
-- =====================================================

-- Drop the RPC version with integer argument
DROP FUNCTION IF EXISTS public.award_s1_subscription_commission(uuid, uuid, integer);

-- Drop the RPC version with numeric argument  
DROP FUNCTION IF EXISTS public.award_s1_subscription_commission(uuid, uuid, numeric);

-- Verify only trigger version remains (will be called by trg_award_s1_subscription_commission)
-- The trigger function has signature: award_s1_subscription_commission() RETURNS trigger