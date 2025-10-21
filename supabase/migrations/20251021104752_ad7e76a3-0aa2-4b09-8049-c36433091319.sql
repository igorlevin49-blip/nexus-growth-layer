-- Update RLS policy to allow admins (not just superadmins) to view all roles
DROP POLICY IF EXISTS "Superadmins can view all roles" ON public.user_roles;

CREATE POLICY "Admins can view all roles" 
ON public.user_roles 
FOR SELECT 
USING (
  has_role(auth.uid(), 'admin'::app_role) OR 
  has_role(auth.uid(), 'superadmin'::app_role)
);