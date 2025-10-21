-- Update the handle_new_user function to automatically assign superadmin to first user
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  user_count INTEGER;
  assigned_role app_role;
BEGIN
  -- Insert into profiles first
  INSERT INTO public.profiles (id, full_name, email)
  VALUES (
    new.id,
    new.raw_user_meta_data->>'full_name',
    new.email
  );
  
  -- Check if this is the first user
  SELECT COUNT(*) INTO user_count FROM public.user_roles;
  
  -- Assign role based on user count
  IF user_count = 0 THEN
    assigned_role := 'superadmin';
  ELSE
    assigned_role := 'user';
  END IF;
  
  -- Assign the determined role
  INSERT INTO public.user_roles (user_id, role)
  VALUES (new.id, assigned_role);
  
  RETURN new;
END;
$function$;

-- Add RLS policy for superadmins to update user roles
CREATE POLICY "Superadmins can update user roles"
ON public.user_roles
FOR UPDATE
USING (has_role(auth.uid(), 'superadmin'));

-- Add RLS policy for superadmins to delete user roles
CREATE POLICY "Superadmins can delete user roles"
ON public.user_roles
FOR DELETE
USING (has_role(auth.uid(), 'superadmin'));

-- Add RLS policy for superadmins to insert user roles
CREATE POLICY "Superadmins can insert user roles"
ON public.user_roles
FOR INSERT
WITH CHECK (has_role(auth.uid(), 'superadmin'));

-- Add RLS policy for superadmins to delete profiles
CREATE POLICY "Superadmins can delete profiles"
ON public.profiles
FOR DELETE
USING (has_role(auth.uid(), 'superadmin'));