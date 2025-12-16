-- Task 1: Drop and recreate get_monthly_activation_report with new column
DROP FUNCTION IF EXISTS public.get_monthly_activation_report(integer,integer,text,text,integer,integer);

CREATE OR REPLACE FUNCTION public.get_monthly_activation_report(
  p_year integer,
  p_month integer,
  p_status text DEFAULT 'all',
  p_search text DEFAULT NULL,
  p_limit integer DEFAULT 50,
  p_offset integer DEFAULT 0
)
RETURNS TABLE (
  user_id uuid,
  full_name text,
  email text,
  referral_code text,
  total_amount_kzt numeric,
  threshold_kzt numeric,
  is_activated boolean,
  last_order_date timestamp with time zone,
  orders_count bigint,
  activation_due_from timestamp with time zone
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    p.id as user_id,
    p.full_name,
    p.email,
    p.referral_code,
    COALESCE(ma.total_amount_kzt, 0) as total_amount_kzt,
    COALESCE(ma.threshold_kzt, (SELECT monthly_activation_required_kzt FROM shop_settings WHERE id = 1)) as threshold_kzt,
    COALESCE(ma.is_activated, false) as is_activated,
    ma.last_order_date,
    (
      SELECT COUNT(*)::bigint 
      FROM orders o 
      WHERE o.user_id = p.id 
        AND o.status = 'paid'
        AND EXTRACT(YEAR FROM o.paid_at) = p_year
        AND EXTRACT(MONTH FROM o.paid_at) = p_month
    ) as orders_count,
    p.activation_due_from
  FROM profiles p
  LEFT JOIN monthly_activations ma ON ma.user_id = p.id 
    AND ma.year = p_year 
    AND ma.month = p_month
  WHERE p.is_active = true
    AND p.deleted_at IS NULL
    AND (p.is_archived IS NULL OR p.is_archived = false)
    AND p.subscription_status = 'active'
    AND p.activation_due_from IS NOT NULL
    AND p.activation_due_from <= make_timestamptz(p_year, p_month, 1, 0, 0, 0)
    AND (
      p_status = 'all'
      OR (p_status = 'activated' AND COALESCE(ma.is_activated, false) = true)
      OR (p_status = 'not_activated' AND COALESCE(ma.is_activated, false) = false)
    )
    AND (
      p_search IS NULL 
      OR p.full_name ILIKE '%' || p_search || '%'
      OR p.email ILIKE '%' || p_search || '%'
      OR p.referral_code ILIKE '%' || p_search || '%'
    )
  ORDER BY COALESCE(ma.is_activated, false), p.full_name
  LIMIT p_limit
  OFFSET p_offset;
END;
$$;

-- Task 4: Create trigger for commission notifications
CREATE OR REPLACE FUNCTION public.notify_commission_earned()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_from_user text;
  v_amount_display text;
BEGIN
  IF NEW.type = 'commission' AND NEW.status = 'completed' THEN
    v_from_user := COALESCE(NEW.payload->>'from_user', 'партнёра');
    v_amount_display := ROUND(NEW.amount_cents * 5)::text || ' ₸';
    
    INSERT INTO user_modal_notifications (user_id, title, message, type)
    VALUES (
      NEW.user_id,
      'Поздравляем с комиссией!',
      'Вам начислено ' || v_amount_display || ' за ' || v_from_user,
      'success'
    );
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_notify_commission_earned ON transactions;
CREATE TRIGGER trigger_notify_commission_earned
  AFTER INSERT ON transactions
  FOR EACH ROW
  EXECUTE FUNCTION notify_commission_earned();

-- Task 5: Fix foreign key constraint
ALTER TABLE monthly_activations DROP CONSTRAINT IF EXISTS monthly_activations_last_order_id_fkey;
ALTER TABLE monthly_activations ADD CONSTRAINT monthly_activations_last_order_id_fkey 
  FOREIGN KEY (last_order_id) REFERENCES orders(id) ON DELETE SET NULL;

-- Update hard_delete_records function
CREATE OR REPLACE FUNCTION public.hard_delete_records(
  record_type text, record_ids uuid[], dry_run boolean DEFAULT true, confirmation_phrase text DEFAULT ''
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  v_count integer;
  v_deleted_count integer := 0;
BEGIN
  IF NOT has_role(auth.uid(), 'superadmin'::app_role) THEN
    RAISE EXCEPTION 'Access denied. Superadmin role required.';
  END IF;

  IF NOT dry_run AND confirmation_phrase != 'DELETE CONFIRM' THEN
    RAISE EXCEPTION 'Invalid confirmation phrase. Use "DELETE CONFIRM"';
  END IF;

  IF record_type = 'order' THEN
    SELECT COUNT(*) INTO v_count FROM orders WHERE id = ANY(record_ids);
  ELSIF record_type = 'subscription' THEN
    SELECT COUNT(*) INTO v_count FROM subscriptions WHERE id = ANY(record_ids);
  ELSIF record_type = 'transaction' THEN
    SELECT COUNT(*) INTO v_count FROM transactions WHERE id = ANY(record_ids);
  ELSIF record_type = 'withdrawal' THEN
    SELECT COUNT(*) INTO v_count FROM withdrawals WHERE id = ANY(record_ids);
  ELSE
    RAISE EXCEPTION 'Invalid record type: %', record_type;
  END IF;

  IF NOT dry_run THEN
    IF record_type = 'order' THEN
      UPDATE monthly_activations SET last_order_id = NULL WHERE last_order_id = ANY(record_ids);
      DELETE FROM transactions WHERE source_id = ANY(record_ids);
      DELETE FROM order_items WHERE order_id = ANY(record_ids);
      DELETE FROM orders WHERE id = ANY(record_ids);
      GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
    ELSIF record_type = 'subscription' THEN
      DELETE FROM transactions WHERE source_id = ANY(record_ids);
      DELETE FROM subscriptions WHERE id = ANY(record_ids);
      GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
    ELSIF record_type = 'transaction' THEN
      DELETE FROM transactions WHERE id = ANY(record_ids);
      GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
    ELSIF record_type = 'withdrawal' THEN
      DELETE FROM withdrawals WHERE id = ANY(record_ids);
      GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
    END IF;

    INSERT INTO admin_actions (admin_id, action_type, target_type, metadata)
    VALUES (auth.uid(), 'hard_delete', record_type, jsonb_build_object('record_ids', record_ids, 'deleted_count', v_deleted_count));
  END IF;

  RETURN jsonb_build_object('record_type', record_type, 'count', v_count, 'deleted', CASE WHEN dry_run THEN 0 ELSE v_deleted_count END, 'dry_run', dry_run);
END;
$$;