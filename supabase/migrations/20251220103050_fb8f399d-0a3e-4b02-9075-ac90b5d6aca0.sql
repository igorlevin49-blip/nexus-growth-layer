-- Fix hard_delete_records function: remove ::text cast for UUID column
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
  v_record_id uuid;
  v_deleted_count integer := 0;
  v_preview_data json;
  v_admin_id uuid;
BEGIN
  -- Validate confirmation phrase
  IF confirmation_phrase != 'УДАЛИТЬ НАВСЕГДА' THEN
    RETURN json_build_object(
      'success', false,
      'error', 'Invalid confirmation phrase'
    );
  END IF;

  -- Get current user as admin
  v_admin_id := auth.uid();
  
  IF v_admin_id IS NULL THEN
    RETURN json_build_object(
      'success', false,
      'error', 'Not authenticated'
    );
  END IF;

  -- Check if user is superadmin
  IF NOT EXISTS (
    SELECT 1 FROM user_roles 
    WHERE user_id = v_admin_id AND role = 'superadmin'
  ) THEN
    RETURN json_build_object(
      'success', false,
      'error', 'Only superadmin can hard delete records'
    );
  END IF;

  -- Handle both singular and plural record types
  IF record_type IN ('order', 'orders') THEN
    IF dry_run THEN
      SELECT json_agg(json_build_object(
        'id', o.id,
        'user_id', o.user_id,
        'total_kzt', o.total_kzt,
        'status', o.status,
        'created_at', o.created_at
      ))
      INTO v_preview_data
      FROM orders o
      WHERE o.id = ANY(record_ids);
      
      RETURN json_build_object(
        'success', true,
        'dry_run', true,
        'preview', v_preview_data,
        'count', array_length(record_ids, 1)
      );
    ELSE
      -- Delete related order_items first
      DELETE FROM order_items WHERE order_id = ANY(record_ids);
      
      -- Delete orders
      FOREACH v_record_id IN ARRAY record_ids LOOP
        DELETE FROM orders WHERE id = v_record_id;
        IF FOUND THEN
          v_deleted_count := v_deleted_count + 1;
          
          -- Log admin action (fixed: removed ::text cast)
          INSERT INTO admin_audit (admin_id, action_type, target_type, target_id, comment)
          VALUES (v_admin_id, 'hard_delete', 'order', v_record_id, 'Permanent deletion');
        END IF;
      END LOOP;
    END IF;

  ELSIF record_type IN ('subscription', 'subscriptions') THEN
    IF dry_run THEN
      SELECT json_agg(json_build_object(
        'id', s.id,
        'user_id', s.user_id,
        'amount_kzt', s.amount_kzt,
        'status', s.status,
        'created_at', s.created_at
      ))
      INTO v_preview_data
      FROM subscriptions s
      WHERE s.id = ANY(record_ids);
      
      RETURN json_build_object(
        'success', true,
        'dry_run', true,
        'preview', v_preview_data,
        'count', array_length(record_ids, 1)
      );
    ELSE
      FOREACH v_record_id IN ARRAY record_ids LOOP
        DELETE FROM subscriptions WHERE id = v_record_id;
        IF FOUND THEN
          v_deleted_count := v_deleted_count + 1;
          
          -- Log admin action (fixed: removed ::text cast)
          INSERT INTO admin_audit (admin_id, action_type, target_type, target_id, comment)
          VALUES (v_admin_id, 'hard_delete', 'subscription', v_record_id, 'Permanent deletion');
        END IF;
      END LOOP;
    END IF;

  ELSIF record_type IN ('withdrawal', 'withdrawals') THEN
    IF dry_run THEN
      SELECT json_agg(json_build_object(
        'id', w.id,
        'user_id', w.user_id,
        'amount_cents', w.amount_cents,
        'status', w.status,
        'created_at', w.created_at
      ))
      INTO v_preview_data
      FROM withdrawals w
      WHERE w.id = ANY(record_ids);
      
      RETURN json_build_object(
        'success', true,
        'dry_run', true,
        'preview', v_preview_data,
        'count', array_length(record_ids, 1)
      );
    ELSE
      FOREACH v_record_id IN ARRAY record_ids LOOP
        DELETE FROM withdrawals WHERE id = v_record_id;
        IF FOUND THEN
          v_deleted_count := v_deleted_count + 1;
          
          -- Log admin action (fixed: removed ::text cast)
          INSERT INTO admin_audit (admin_id, action_type, target_type, target_id, comment)
          VALUES (v_admin_id, 'hard_delete', 'withdrawal', v_record_id, 'Permanent deletion');
        END IF;
      END LOOP;
    END IF;

  ELSIF record_type IN ('transaction', 'transactions') THEN
    IF dry_run THEN
      SELECT json_agg(json_build_object(
        'id', t.id,
        'user_id', t.user_id,
        'amount_cents', t.amount_cents,
        'type', t.type,
        'status', t.status,
        'created_at', t.created_at
      ))
      INTO v_preview_data
      FROM transactions t
      WHERE t.id = ANY(record_ids);
      
      RETURN json_build_object(
        'success', true,
        'dry_run', true,
        'preview', v_preview_data,
        'count', array_length(record_ids, 1)
      );
    ELSE
      FOREACH v_record_id IN ARRAY record_ids LOOP
        DELETE FROM transactions WHERE id = v_record_id;
        IF FOUND THEN
          v_deleted_count := v_deleted_count + 1;
          
          -- Log admin action (fixed: removed ::text cast)
          INSERT INTO admin_audit (admin_id, action_type, target_type, target_id, comment)
          VALUES (v_admin_id, 'hard_delete', 'transaction', v_record_id, 'Permanent deletion');
        END IF;
      END LOOP;
    END IF;

  ELSE
    RETURN json_build_object(
      'success', false,
      'error', 'Invalid record type: ' || record_type
    );
  END IF;

  RETURN json_build_object(
    'success', true,
    'deleted_count', v_deleted_count
  );
END;
$$;