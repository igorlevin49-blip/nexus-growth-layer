-- Drop both conflicting versions of hard_delete_records function
DROP FUNCTION IF EXISTS public.hard_delete_records(text, uuid[], text, boolean);
DROP FUNCTION IF EXISTS public.hard_delete_records(text, uuid[], boolean, text);

-- Create single consistent version of hard_delete_records
CREATE OR REPLACE FUNCTION public.hard_delete_records(
  record_type text,
  record_ids uuid[],
  confirmation_phrase text,
  dry_run boolean DEFAULT true
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_deleted_count integer := 0;
  v_record_id uuid;
  v_admin_id uuid;
  v_is_superadmin boolean;
  v_details jsonb := '[]'::jsonb;
BEGIN
  -- Get current user
  v_admin_id := auth.uid();
  
  -- Check if user is superadmin
  SELECT EXISTS (
    SELECT 1 FROM user_roles 
    WHERE user_id = v_admin_id AND role = 'superadmin'
  ) INTO v_is_superadmin;
  
  IF NOT v_is_superadmin THEN
    RETURN json_build_object(
      'success', false,
      'error', 'Only superadmins can permanently delete records'
    );
  END IF;
  
  -- Verify confirmation phrase
  IF confirmation_phrase != 'DELETE PERMANENTLY' THEN
    RETURN json_build_object(
      'success', false,
      'error', 'Invalid confirmation phrase. Expected: DELETE PERMANENTLY'
    );
  END IF;
  
  -- Validate record type
  IF record_type NOT IN ('orders', 'subscriptions', 'transactions', 'withdrawals') THEN
    RETURN json_build_object(
      'success', false,
      'error', 'Invalid record type: ' || record_type
    );
  END IF;
  
  -- Dry run mode - just return what would be deleted
  IF dry_run THEN
    RETURN json_build_object(
      'success', true,
      'dry_run', true,
      'would_delete', array_length(record_ids, 1),
      'record_type', record_type,
      'record_ids', record_ids
    );
  END IF;
  
  -- Perform actual deletion
  FOREACH v_record_id IN ARRAY record_ids
  LOOP
    BEGIN
      IF record_type = 'orders' THEN
        -- Clear monthly_activations.last_order_id references
        UPDATE monthly_activations SET last_order_id = NULL WHERE last_order_id = v_record_id;
        -- Delete related transactions
        DELETE FROM transactions WHERE source_id = v_record_id;
        -- Delete order items
        DELETE FROM order_items WHERE order_id = v_record_id;
        -- Delete the order
        DELETE FROM orders WHERE id = v_record_id;
        
      ELSIF record_type = 'subscriptions' THEN
        -- Delete related transactions
        DELETE FROM transactions WHERE source_id = v_record_id;
        -- Delete the subscription
        DELETE FROM subscriptions WHERE id = v_record_id;
        
      ELSIF record_type = 'transactions' THEN
        DELETE FROM transactions WHERE id = v_record_id;
        
      ELSIF record_type = 'withdrawals' THEN
        -- Delete related transaction if exists
        DELETE FROM transactions WHERE id = (SELECT transaction_id FROM withdrawals WHERE id = v_record_id);
        -- Delete the withdrawal
        DELETE FROM withdrawals WHERE id = v_record_id;
      END IF;
      
      v_deleted_count := v_deleted_count + 1;
      v_details := v_details || jsonb_build_object('id', v_record_id, 'status', 'deleted');
      
    EXCEPTION WHEN OTHERS THEN
      v_details := v_details || jsonb_build_object('id', v_record_id, 'status', 'error', 'message', SQLERRM);
    END;
  END LOOP;
  
  -- Log admin action
  INSERT INTO admin_actions (admin_id, action_type, target_type, target_id, metadata)
  VALUES (
    v_admin_id,
    'hard_delete',
    record_type,
    record_ids[1]::text,
    jsonb_build_object(
      'record_type', record_type,
      'deleted_count', v_deleted_count,
      'record_ids', record_ids
    )
  );
  
  RETURN json_build_object(
    'success', true,
    'deleted_count', v_deleted_count,
    'details', v_details
  );
END;
$$;