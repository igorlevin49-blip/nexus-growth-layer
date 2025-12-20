-- Унифицировать record_type в archive_records - принимать "orders", "subscriptions", "transactions"
CREATE OR REPLACE FUNCTION public.archive_records(
  record_type text,
  record_ids uuid[]
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  affected_count int;
  result jsonb;
BEGIN
  IF NOT (has_role(auth.uid(), 'admin'::app_role) OR has_role(auth.uid(), 'superadmin'::app_role)) THEN
    RAISE EXCEPTION 'Only admins can archive records';
  END IF;

  CASE record_type
    WHEN 'orders', 'order' THEN
      UPDATE orders 
      SET is_archived = true, archived_at = now()
      WHERE id = ANY(record_ids) AND (is_archived = false OR is_archived IS NULL);
      GET DIAGNOSTICS affected_count = ROW_COUNT;
      
    WHEN 'subscriptions', 'subscription' THEN
      UPDATE subscriptions 
      SET is_archived = true, archived_at = now()
      WHERE id = ANY(record_ids) AND (is_archived = false OR is_archived IS NULL);
      GET DIAGNOSTICS affected_count = ROW_COUNT;
      
    WHEN 'transactions', 'transaction' THEN
      UPDATE transactions 
      SET is_archived = true, archived_at = now()
      WHERE id = ANY(record_ids) AND (is_archived = false OR is_archived IS NULL);
      GET DIAGNOSTICS affected_count = ROW_COUNT;
      
    ELSE
      RAISE EXCEPTION 'Invalid record type: %', record_type;
  END CASE;

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