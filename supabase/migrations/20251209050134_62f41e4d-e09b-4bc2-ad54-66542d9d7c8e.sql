
-- Fix the view security issue by setting security_invoker = true
DROP VIEW IF EXISTS public.profiles_network_safe;

CREATE VIEW public.profiles_network_safe 
WITH (security_invoker = true)
AS
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
