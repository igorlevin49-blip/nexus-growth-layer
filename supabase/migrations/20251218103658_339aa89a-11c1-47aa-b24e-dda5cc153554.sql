-- =====================================================
-- Fix: Auto-reverse monthly activation on order cancel/delete
-- =====================================================

-- Step 1: Update the trigger function to handle order status changes FROM paid
CREATE OR REPLACE FUNCTION public.update_monthly_activation_on_order()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_year integer;
  v_month integer;
  v_threshold numeric;
  v_total numeric;
  v_order_date timestamptz;
  v_last_order_date timestamptz;
  v_last_order_id uuid;
  v_orders_count integer;
BEGIN
  -- Get threshold from settings
  SELECT COALESCE(monthly_activation_required_kzt, 20000)
  INTO v_threshold
  FROM shop_settings
  WHERE id = 1;

  -- CASE 1: Order transitions TO paid status (activation)
  IF NEW.status = 'paid' AND (OLD IS NULL OR OLD.status IS DISTINCT FROM 'paid') THEN
    v_order_date := COALESCE(NEW.paid_at, NEW.created_at);
    v_year := EXTRACT(YEAR FROM v_order_date)::integer;
    v_month := EXTRACT(MONTH FROM v_order_date)::integer;

    -- Calculate total for the month including this order
    SELECT 
      COALESCE(SUM(total_kzt), 0),
      COUNT(*),
      MAX(COALESCE(paid_at, created_at))
    INTO v_total, v_orders_count, v_last_order_date
    FROM orders
    WHERE user_id = NEW.user_id
      AND status = 'paid'
      AND EXTRACT(YEAR FROM COALESCE(paid_at, created_at)) = v_year
      AND EXTRACT(MONTH FROM COALESCE(paid_at, created_at)) = v_month;

    -- Get the last order id
    SELECT id INTO v_last_order_id
    FROM orders
    WHERE user_id = NEW.user_id
      AND status = 'paid'
      AND EXTRACT(YEAR FROM COALESCE(paid_at, created_at)) = v_year
      AND EXTRACT(MONTH FROM COALESCE(paid_at, created_at)) = v_month
    ORDER BY COALESCE(paid_at, created_at) DESC
    LIMIT 1;

    -- Upsert monthly_activations
    INSERT INTO monthly_activations (
      user_id, year, month, total_amount_kzt, threshold_kzt, 
      is_activated, last_order_date, last_order_id
    )
    VALUES (
      NEW.user_id, v_year, v_month, v_total, v_threshold,
      v_total >= v_threshold, v_last_order_date, v_last_order_id
    )
    ON CONFLICT (user_id, year, month)
    DO UPDATE SET
      total_amount_kzt = EXCLUDED.total_amount_kzt,
      is_activated = EXCLUDED.is_activated,
      last_order_date = EXCLUDED.last_order_date,
      last_order_id = EXCLUDED.last_order_id,
      updated_at = now();

    -- Update profile for current month
    IF v_year = EXTRACT(YEAR FROM now())::integer AND v_month = EXTRACT(MONTH FROM now())::integer THEN
      UPDATE profiles
      SET monthly_activation_completed = (v_total >= v_threshold),
          updated_at = now()
      WHERE id = NEW.user_id;
    END IF;

    RETURN NEW;
  END IF;

  -- CASE 2: Order transitions FROM paid to another status (cancellation/reversal)
  IF OLD IS NOT NULL AND OLD.status = 'paid' AND NEW.status IS DISTINCT FROM 'paid' THEN
    v_order_date := COALESCE(OLD.paid_at, OLD.created_at);
    v_year := EXTRACT(YEAR FROM v_order_date)::integer;
    v_month := EXTRACT(MONTH FROM v_order_date)::integer;

    -- Recalculate total EXCLUDING this order (since it's no longer paid)
    SELECT 
      COALESCE(SUM(total_kzt), 0),
      COUNT(*),
      MAX(COALESCE(paid_at, created_at))
    INTO v_total, v_orders_count, v_last_order_date
    FROM orders
    WHERE user_id = OLD.user_id
      AND status = 'paid'
      AND id != OLD.id  -- Exclude the cancelled order
      AND EXTRACT(YEAR FROM COALESCE(paid_at, created_at)) = v_year
      AND EXTRACT(MONTH FROM COALESCE(paid_at, created_at)) = v_month;

    -- Get the last order id (excluding cancelled order)
    SELECT id INTO v_last_order_id
    FROM orders
    WHERE user_id = OLD.user_id
      AND status = 'paid'
      AND id != OLD.id
      AND EXTRACT(YEAR FROM COALESCE(paid_at, created_at)) = v_year
      AND EXTRACT(MONTH FROM COALESCE(paid_at, created_at)) = v_month
    ORDER BY COALESCE(paid_at, created_at) DESC
    LIMIT 1;

    -- Update monthly_activations with recalculated values
    UPDATE monthly_activations
    SET total_amount_kzt = v_total,
        is_activated = v_total >= threshold_kzt,
        last_order_date = v_last_order_date,
        last_order_id = v_last_order_id,
        updated_at = now()
    WHERE user_id = OLD.user_id 
      AND year = v_year 
      AND month = v_month;

    -- Update profile for current month
    IF v_year = EXTRACT(YEAR FROM now())::integer AND v_month = EXTRACT(MONTH FROM now())::integer THEN
      UPDATE profiles
      SET monthly_activation_completed = (v_total >= v_threshold),
          updated_at = now()
      WHERE id = OLD.user_id;
    END IF;

    RETURN NEW;
  END IF;

  RETURN NEW;
END;
$$;

-- Step 2: Create helper function to recalculate activation for a user/month
CREATE OR REPLACE FUNCTION public.recalculate_user_monthly_activation(
  p_user_id uuid,
  p_year integer,
  p_month integer
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_threshold numeric;
  v_total numeric;
  v_last_order_date timestamptz;
  v_last_order_id uuid;
BEGIN
  -- Get threshold
  SELECT COALESCE(monthly_activation_required_kzt, 20000)
  INTO v_threshold
  FROM shop_settings
  WHERE id = 1;

  -- Calculate totals
  SELECT 
    COALESCE(SUM(total_kzt), 0),
    MAX(COALESCE(paid_at, created_at))
  INTO v_total, v_last_order_date
  FROM orders
  WHERE user_id = p_user_id
    AND status = 'paid'
    AND EXTRACT(YEAR FROM COALESCE(paid_at, created_at)) = p_year
    AND EXTRACT(MONTH FROM COALESCE(paid_at, created_at)) = p_month;

  -- Get last order id
  SELECT id INTO v_last_order_id
  FROM orders
  WHERE user_id = p_user_id
    AND status = 'paid'
    AND EXTRACT(YEAR FROM COALESCE(paid_at, created_at)) = p_year
    AND EXTRACT(MONTH FROM COALESCE(paid_at, created_at)) = p_month
  ORDER BY COALESCE(paid_at, created_at) DESC
  LIMIT 1;

  -- Update or delete monthly_activations record
  IF v_total > 0 THEN
    UPDATE monthly_activations
    SET total_amount_kzt = v_total,
        is_activated = v_total >= v_threshold,
        last_order_date = v_last_order_date,
        last_order_id = v_last_order_id,
        updated_at = now()
    WHERE user_id = p_user_id 
      AND year = p_year 
      AND month = p_month;
  ELSE
    -- No paid orders left - set to zero
    UPDATE monthly_activations
    SET total_amount_kzt = 0,
        is_activated = false,
        last_order_date = NULL,
        last_order_id = NULL,
        updated_at = now()
    WHERE user_id = p_user_id 
      AND year = p_year 
      AND month = p_month;
  END IF;

  -- Update profile for current month
  IF p_year = EXTRACT(YEAR FROM now())::integer AND p_month = EXTRACT(MONTH FROM now())::integer THEN
    UPDATE profiles
    SET monthly_activation_completed = (v_total >= v_threshold),
        updated_at = now()
    WHERE id = p_user_id;
  END IF;
END;
$$;

-- Step 3: Update hard_delete_records to recalculate activation after order deletion
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
  v_details jsonb := '[]'::jsonb;
  v_admin_id uuid;
  v_order_user_id uuid;
  v_order_date timestamptz;
  v_order_status text;
  v_order_year integer;
  v_order_month integer;
BEGIN
  -- Verify confirmation phrase
  IF confirmation_phrase != 'DELETE PERMANENTLY' THEN
    RETURN json_build_object(
      'success', false,
      'error', 'Invalid confirmation phrase. Must be: DELETE PERMANENTLY'
    );
  END IF;

  -- Get current user
  v_admin_id := auth.uid();
  
  -- Verify superadmin role
  IF NOT EXISTS (
    SELECT 1 FROM user_roles 
    WHERE user_id = v_admin_id AND role = 'superadmin'
  ) THEN
    RETURN json_build_object(
      'success', false,
      'error', 'Only superadmin can permanently delete records'
    );
  END IF;

  -- Process based on record type
  IF record_type = 'orders' THEN
    FOREACH v_record_id IN ARRAY record_ids
    LOOP
      -- Get order data BEFORE deletion for activation recalculation
      SELECT user_id, COALESCE(paid_at, created_at), status
      INTO v_order_user_id, v_order_date, v_order_status
      FROM orders WHERE id = v_record_id;

      IF v_order_user_id IS NOT NULL THEN
        v_order_year := EXTRACT(YEAR FROM v_order_date)::integer;
        v_order_month := EXTRACT(MONTH FROM v_order_date)::integer;

        IF NOT dry_run THEN
          -- Clear reference in monthly_activations first
          UPDATE monthly_activations 
          SET last_order_id = NULL, updated_at = now()
          WHERE last_order_id = v_record_id;

          -- Delete related transactions
          DELETE FROM transactions WHERE source_id = v_record_id;
          
          -- Delete order items
          DELETE FROM order_items WHERE order_id = v_record_id;
          
          -- Delete the order
          DELETE FROM orders WHERE id = v_record_id;

          -- Recalculate monthly activation if order was paid
          IF v_order_status = 'paid' THEN
            PERFORM recalculate_user_monthly_activation(v_order_user_id, v_order_year, v_order_month);
          END IF;

          -- Log the action
          INSERT INTO admin_audit (admin_id, target_type, target_id, action_type, metadata)
          VALUES (v_admin_id, 'order', v_record_id::text, 'hard_delete', 
            jsonb_build_object('user_id', v_order_user_id, 'was_paid', v_order_status = 'paid'));
        END IF;

        v_deleted_count := v_deleted_count + 1;
        v_details := v_details || jsonb_build_object(
          'id', v_record_id, 
          'type', 'order',
          'was_paid', v_order_status = 'paid',
          'user_id', v_order_user_id
        );
      END IF;
    END LOOP;

  ELSIF record_type = 'subscriptions' THEN
    FOREACH v_record_id IN ARRAY record_ids
    LOOP
      IF EXISTS (SELECT 1 FROM subscriptions WHERE id = v_record_id) THEN
        IF NOT dry_run THEN
          DELETE FROM transactions WHERE source_id = v_record_id;
          DELETE FROM subscriptions WHERE id = v_record_id;
          
          INSERT INTO admin_audit (admin_id, target_type, target_id, action_type)
          VALUES (v_admin_id, 'subscription', v_record_id::text, 'hard_delete');
        END IF;
        
        v_deleted_count := v_deleted_count + 1;
        v_details := v_details || jsonb_build_object('id', v_record_id, 'type', 'subscription');
      END IF;
    END LOOP;

  ELSIF record_type = 'withdrawals' THEN
    FOREACH v_record_id IN ARRAY record_ids
    LOOP
      IF EXISTS (SELECT 1 FROM withdrawals WHERE id = v_record_id) THEN
        IF NOT dry_run THEN
          DELETE FROM transactions WHERE source_id = v_record_id;
          DELETE FROM withdrawals WHERE id = v_record_id;
          
          INSERT INTO admin_audit (admin_id, target_type, target_id, action_type)
          VALUES (v_admin_id, 'withdrawal', v_record_id::text, 'hard_delete');
        END IF;
        
        v_deleted_count := v_deleted_count + 1;
        v_details := v_details || jsonb_build_object('id', v_record_id, 'type', 'withdrawal');
      END IF;
    END LOOP;

  ELSIF record_type = 'transactions' THEN
    FOREACH v_record_id IN ARRAY record_ids
    LOOP
      IF EXISTS (SELECT 1 FROM transactions WHERE id = v_record_id) THEN
        IF NOT dry_run THEN
          DELETE FROM transactions WHERE id = v_record_id;
          
          INSERT INTO admin_audit (admin_id, target_type, target_id, action_type)
          VALUES (v_admin_id, 'transaction', v_record_id::text, 'hard_delete');
        END IF;
        
        v_deleted_count := v_deleted_count + 1;
        v_details := v_details || jsonb_build_object('id', v_record_id, 'type', 'transaction');
      END IF;
    END LOOP;

  ELSE
    RETURN json_build_object(
      'success', false,
      'error', 'Unknown record type: ' || record_type
    );
  END IF;

  RETURN json_build_object(
    'success', true,
    'dry_run', dry_run,
    'deleted_count', v_deleted_count,
    'details', v_details
  );
END;
$$;