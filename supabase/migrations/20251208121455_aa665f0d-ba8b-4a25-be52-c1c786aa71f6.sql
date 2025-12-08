-- Fix the update_full_name function to set search_path for security
CREATE OR REPLACE FUNCTION public.update_full_name()
RETURNS TRIGGER 
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Update full_name from first_name + last_name
  IF NEW.first_name IS DISTINCT FROM OLD.first_name OR NEW.last_name IS DISTINCT FROM OLD.last_name THEN
    NEW.full_name := TRIM(CONCAT(COALESCE(NEW.first_name, ''), ' ', COALESCE(NEW.last_name, '')));
    -- Handle empty result
    IF NEW.full_name = '' THEN
      NEW.full_name := OLD.full_name;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;