-- Add archive fields to orders, subscriptions, and transactions
ALTER TABLE orders 
ADD COLUMN IF NOT EXISTS is_archived boolean DEFAULT false,
ADD COLUMN IF NOT EXISTS archived_at timestamp with time zone;

ALTER TABLE subscriptions 
ADD COLUMN IF NOT EXISTS is_archived boolean DEFAULT false,
ADD COLUMN IF NOT EXISTS archived_at timestamp with time zone;

ALTER TABLE transactions 
ADD COLUMN IF NOT EXISTS is_archived boolean DEFAULT false,
ADD COLUMN IF NOT EXISTS archived_at timestamp with time zone;

ALTER TABLE withdrawals 
ADD COLUMN IF NOT EXISTS is_archived boolean DEFAULT false,
ADD COLUMN IF NOT EXISTS archived_at timestamp with time zone;

-- Create indexes for faster filtering
CREATE INDEX IF NOT EXISTS idx_orders_archived ON orders(is_archived) WHERE is_archived = false;
CREATE INDEX IF NOT EXISTS idx_subscriptions_archived ON subscriptions(is_archived) WHERE is_archived = false;
CREATE INDEX IF NOT EXISTS idx_transactions_archived ON transactions(is_archived) WHERE is_archived = false;
CREATE INDEX IF NOT EXISTS idx_withdrawals_archived ON withdrawals(is_archived) WHERE is_archived = false;

-- Function to soft delete (archive) records
CREATE OR REPLACE FUNCTION archive_records(
  record_type text,
  record_ids uuid[]
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  affected_count int;
  result jsonb;
BEGIN
  -- Check if user is admin or superadmin
  IF NOT (has_role(auth.uid(), 'admin') OR has_role(auth.uid(), 'superadmin')) THEN
    RAISE EXCEPTION 'Only admins can archive records';
  END IF;

  -- Archive based on record type
  CASE record_type
    WHEN 'order' THEN
      UPDATE orders 
      SET is_archived = true, archived_at = now()
      WHERE id = ANY(record_ids) AND is_archived = false;
      GET DIAGNOSTICS affected_count = ROW_COUNT;
      
    WHEN 'subscription' THEN
      UPDATE subscriptions 
      SET is_archived = true, archived_at = now()
      WHERE id = ANY(record_ids) AND is_archived = false;
      GET DIAGNOSTICS affected_count = ROW_COUNT;
      
    WHEN 'transaction' THEN
      UPDATE transactions 
      SET is_archived = true, archived_at = now()
      WHERE id = ANY(record_ids) AND is_archived = false;
      GET DIAGNOSTICS affected_count = ROW_COUNT;
      
    ELSE
      RAISE EXCEPTION 'Invalid record type: %', record_type;
  END CASE;

  -- Log the action
  INSERT INTO admin_actions (admin_id, action_type, target_type, metadata)
  VALUES (
    auth.uid(),
    'archive',
    record_type,
    jsonb_build_object(
      'record_ids', record_ids,
      'affected_count', affected_count
    )
  );

  result := jsonb_build_object(
    'success', true,
    'affected_count', affected_count
  );

  RETURN result;
END;
$$;

-- Function to hard delete records (superadmin only)
CREATE OR REPLACE FUNCTION hard_delete_records(
  record_type text,
  record_ids uuid[],
  confirmation_phrase text,
  dry_run boolean DEFAULT true
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  affected_orders int := 0;
  affected_subscriptions int := 0;
  affected_transactions int := 0;
  affected_withdrawals int := 0;
  result jsonb;
BEGIN
  -- Check if user is superadmin
  IF NOT has_role(auth.uid(), 'superadmin') THEN
    RAISE EXCEPTION 'Only superadmins can permanently delete records';
  END IF;

  -- Verify confirmation phrase
  IF NOT dry_run AND confirmation_phrase != 'DELETE PERMANENTLY' THEN
    RAISE EXCEPTION 'Invalid confirmation phrase';
  END IF;

  -- Count what will be affected
  IF record_type = 'order' THEN
    SELECT COUNT(*) INTO affected_orders FROM orders WHERE id = ANY(record_ids);
    SELECT COUNT(*) INTO affected_transactions FROM transactions WHERE source_ref = 'order' AND source_id = ANY(record_ids);
    
  ELSIF record_type = 'subscription' THEN
    SELECT COUNT(*) INTO affected_subscriptions FROM subscriptions WHERE id = ANY(record_ids);
    SELECT COUNT(*) INTO affected_transactions FROM transactions WHERE source_ref = 'subscription' AND source_id = ANY(record_ids);
  END IF;

  -- If dry run, just return counts
  IF dry_run THEN
    result := jsonb_build_object(
      'dry_run', true,
      'orders', affected_orders,
      'subscriptions', affected_subscriptions,
      'transactions', affected_transactions,
      'withdrawals', affected_withdrawals
    );
    RETURN result;
  END IF;

  -- Perform actual deletion in correct order (transactions first, then source records)
  IF record_type = 'order' THEN
    DELETE FROM transactions WHERE source_ref = 'order' AND source_id = ANY(record_ids);
    DELETE FROM order_items WHERE order_id = ANY(record_ids);
    DELETE FROM orders WHERE id = ANY(record_ids);
    
  ELSIF record_type = 'subscription' THEN
    DELETE FROM transactions WHERE source_ref = 'subscription' AND source_id = ANY(record_ids);
    DELETE FROM subscriptions WHERE id = ANY(record_ids);
  END IF;

  -- Log the action
  INSERT INTO admin_actions (admin_id, action_type, target_type, metadata, comment)
  VALUES (
    auth.uid(),
    'hard_delete',
    record_type,
    jsonb_build_object(
      'record_ids', record_ids,
      'affected_orders', affected_orders,
      'affected_subscriptions', affected_subscriptions,
      'affected_transactions', affected_transactions
    ),
    'PERMANENT DELETION'
  );

  result := jsonb_build_object(
    'success', true,
    'deleted', jsonb_build_object(
      'orders', affected_orders,
      'subscriptions', affected_subscriptions,
      'transactions', affected_transactions
    )
  );

  RETURN result;
END;
$$;