-- 1. Create trigger function to auto-update full_name when first_name or last_name changes
CREATE OR REPLACE FUNCTION public.update_full_name()
RETURNS TRIGGER AS $$
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
$$ LANGUAGE plpgsql;

-- 2. Create trigger on profiles table
DROP TRIGGER IF EXISTS trg_update_full_name ON profiles;
CREATE TRIGGER trg_update_full_name
BEFORE UPDATE OF first_name, last_name ON profiles
FOR EACH ROW EXECUTE FUNCTION public.update_full_name();

-- 3. Sync existing data: update full_name where first_name/last_name are filled
UPDATE profiles
SET full_name = TRIM(CONCAT(COALESCE(first_name, ''), ' ', COALESCE(last_name, '')))
WHERE (first_name IS NOT NULL AND first_name != '')
   OR (last_name IS NOT NULL AND last_name != '');

-- 4. Populate first_name/last_name from full_name for backward compatibility
UPDATE profiles 
SET 
  first_name = SPLIT_PART(full_name, ' ', 1),
  last_name = CASE 
    WHEN POSITION(' ' IN full_name) > 0 
    THEN TRIM(SUBSTRING(full_name FROM POSITION(' ' IN full_name) + 1))
    ELSE ''
  END
WHERE (first_name IS NULL OR first_name = '')
  AND full_name IS NOT NULL 
  AND full_name != '';