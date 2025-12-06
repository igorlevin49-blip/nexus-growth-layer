-- Fix profiles RLS policies
-- Drop existing SELECT policies that may conflict
DROP POLICY IF EXISTS "Users can view own profile" ON public.profiles;
DROP POLICY IF EXISTS "Users can view their own profile" ON public.profiles;
DROP POLICY IF EXISTS "Admins can view all profiles" ON public.profiles;

-- Create a single clear SELECT policy (PERMISSIVE by default)
-- Users can only see their own profile, admins can see all
CREATE POLICY "Users can view own profile"
ON public.profiles
FOR SELECT
USING (
  (auth.uid() = id AND is_active = true AND deleted_at IS NULL AND (is_archived IS NULL OR is_archived = false))
  OR has_role(auth.uid(), 'admin'::app_role)
  OR has_role(auth.uid(), 'superadmin'::app_role)
);

-- Note: For network tree display (viewing partner names/codes), 
-- we use SECURITY DEFINER functions (get_network_tree, get_referral_network) 
-- which already mask sensitive data like emails for non-admins