-- Step 1: Backup old balance values into referrer_snapshot
UPDATE profiles
SET referrer_snapshot = COALESCE(referrer_snapshot, '{}'::jsonb) || 
    jsonb_build_object('old_balance_backup_20260112', balance)
WHERE is_active = true 
  AND deleted_at IS NULL;

-- Step 2: Synchronize balance with get_user_balance()
UPDATE profiles p
SET balance = COALESCE((SELECT available_kzt FROM get_user_balance(p.id)), 0),
    updated_at = now()
WHERE p.is_active = true 
  AND p.deleted_at IS NULL
  AND p.is_system_account = false;

-- Step 3: Create trigger function to auto-update profile.balance on transaction changes
CREATE OR REPLACE FUNCTION sync_profile_balance_on_transaction()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid;
  v_new_balance numeric;
BEGIN
  -- Determine which user to update
  IF TG_OP = 'DELETE' THEN
    v_user_id := OLD.user_id;
  ELSE
    v_user_id := NEW.user_id;
  END IF;
  
  -- Skip if no user_id
  IF v_user_id IS NULL THEN
    RETURN COALESCE(NEW, OLD);
  END IF;
  
  -- Get the correct balance from get_user_balance()
  SELECT available_kzt INTO v_new_balance
  FROM get_user_balance(v_user_id);
  
  -- Update profile.balance
  UPDATE profiles
  SET balance = COALESCE(v_new_balance, 0),
      updated_at = now()
  WHERE id = v_user_id;
  
  RETURN COALESCE(NEW, OLD);
END;
$$;

-- Step 4: Create trigger on transactions table
DROP TRIGGER IF EXISTS sync_balance_on_transaction_change ON transactions;

CREATE TRIGGER sync_balance_on_transaction_change
AFTER INSERT OR UPDATE OR DELETE ON transactions
FOR EACH ROW
EXECUTE FUNCTION sync_profile_balance_on_transaction();