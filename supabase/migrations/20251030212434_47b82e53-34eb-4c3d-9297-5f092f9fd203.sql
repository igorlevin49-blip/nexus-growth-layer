-- Add is_test flag to financial tables
ALTER TABLE orders ADD COLUMN IF NOT EXISTS is_test boolean DEFAULT false;
ALTER TABLE subscriptions ADD COLUMN IF NOT EXISTS is_test boolean DEFAULT false;
ALTER TABLE transactions ADD COLUMN IF NOT EXISTS is_test boolean DEFAULT false;
ALTER TABLE withdrawals ADD COLUMN IF NOT EXISTS is_test boolean DEFAULT false;

-- Create indexes for faster filtering
CREATE INDEX IF NOT EXISTS idx_orders_is_test ON orders(is_test);
CREATE INDEX IF NOT EXISTS idx_subscriptions_is_test ON subscriptions(is_test);
CREATE INDEX IF NOT EXISTS idx_transactions_is_test ON transactions(is_test);
CREATE INDEX IF NOT EXISTS idx_withdrawals_is_test ON withdrawals(is_test);

-- Create RPC function for flagging test data
CREATE OR REPLACE FUNCTION flag_test_data(
  p_start_date timestamptz,
  p_end_date timestamptz,
  p_user_ids uuid[],
  p_dry_run boolean DEFAULT true
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_orders_count int;
  v_subscriptions_count int;
  v_transactions_count int;
  v_withdrawals_count int;
BEGIN
  -- Check if user is superadmin
  IF NOT has_role(auth.uid(), 'superadmin'::app_role) THEN
    RAISE EXCEPTION 'Access denied. Superadmin role required.';
  END IF;

  -- Count affected records
  SELECT COUNT(*) INTO v_orders_count
  FROM orders
  WHERE created_at BETWEEN p_start_date AND p_end_date
    AND (p_user_ids IS NULL OR user_id = ANY(p_user_ids))
    AND is_test = false;

  SELECT COUNT(*) INTO v_subscriptions_count
  FROM subscriptions
  WHERE created_at BETWEEN p_start_date AND p_end_date
    AND (p_user_ids IS NULL OR user_id = ANY(p_user_ids))
    AND is_test = false;

  SELECT COUNT(*) INTO v_transactions_count
  FROM transactions
  WHERE created_at BETWEEN p_start_date AND p_end_date
    AND (p_user_ids IS NULL OR user_id = ANY(p_user_ids))
    AND is_test = false;

  SELECT COUNT(*) INTO v_withdrawals_count
  FROM withdrawals
  WHERE created_at BETWEEN p_start_date AND p_end_date
    AND (p_user_ids IS NULL OR user_id = ANY(p_user_ids))
    AND is_test = false;

  -- If not dry run, perform the flagging
  IF NOT p_dry_run THEN
    UPDATE orders
    SET is_test = true
    WHERE created_at BETWEEN p_start_date AND p_end_date
      AND (p_user_ids IS NULL OR user_id = ANY(p_user_ids))
      AND is_test = false;

    UPDATE subscriptions
    SET is_test = true
    WHERE created_at BETWEEN p_start_date AND p_end_date
      AND (p_user_ids IS NULL OR user_id = ANY(p_user_ids))
      AND is_test = false;

    UPDATE transactions
    SET is_test = true
    WHERE created_at BETWEEN p_start_date AND p_end_date
      AND (p_user_ids IS NULL OR user_id = ANY(p_user_ids))
      AND is_test = false;

    UPDATE withdrawals
    SET is_test = true
    WHERE created_at BETWEEN p_start_date AND p_end_date
      AND (p_user_ids IS NULL OR user_id = ANY(p_user_ids))
      AND is_test = false;

    -- Log the action
    INSERT INTO admin_actions (admin_id, action_type, target_type, metadata)
    VALUES (
      auth.uid(),
      'flag_test_data',
      'test_data',
      jsonb_build_object(
        'start_date', p_start_date,
        'end_date', p_end_date,
        'user_ids', p_user_ids,
        'orders_flagged', v_orders_count,
        'subscriptions_flagged', v_subscriptions_count,
        'transactions_flagged', v_transactions_count,
        'withdrawals_flagged', v_withdrawals_count
      )
    );
  END IF;

  RETURN jsonb_build_object(
    'orders', v_orders_count,
    'subscriptions', v_subscriptions_count,
    'transactions', v_transactions_count,
    'withdrawals', v_withdrawals_count,
    'dry_run', p_dry_run
  );
END;
$$;

-- Create RPC function for purging flagged test data
CREATE OR REPLACE FUNCTION purge_test_data(
  p_dry_run boolean DEFAULT true,
  p_confirmation_phrase text DEFAULT ''
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_transactions_count int;
  v_withdrawals_count int;
  v_subscriptions_count int;
  v_orders_count int;
BEGIN
  -- Check if user is superadmin
  IF NOT has_role(auth.uid(), 'superadmin'::app_role) THEN
    RAISE EXCEPTION 'Access denied. Superadmin role required.';
  END IF;

  -- Verify confirmation phrase
  IF NOT p_dry_run AND p_confirmation_phrase != 'УДАЛИТЬ ТЕСТОВЫЕ ДАННЫЕ' THEN
    RAISE EXCEPTION 'Invalid confirmation phrase';
  END IF;

  -- Count affected records
  SELECT COUNT(*) INTO v_transactions_count FROM transactions WHERE is_test = true;
  SELECT COUNT(*) INTO v_withdrawals_count FROM withdrawals WHERE is_test = true;
  SELECT COUNT(*) INTO v_subscriptions_count FROM subscriptions WHERE is_test = true;
  SELECT COUNT(*) INTO v_orders_count FROM orders WHERE is_test = true;

  -- If not dry run, perform deletion in correct order
  IF NOT p_dry_run THEN
    -- 1. Delete transactions (commissions)
    DELETE FROM transactions WHERE is_test = true;
    
    -- 2. Delete withdrawals (payouts)
    DELETE FROM withdrawals WHERE is_test = true;
    
    -- 3. Delete subscriptions (payments)
    DELETE FROM subscriptions WHERE is_test = true;
    
    -- 4. Delete orders
    DELETE FROM order_items WHERE order_id IN (SELECT id FROM orders WHERE is_test = true);
    DELETE FROM orders WHERE is_test = true;

    -- Log the action
    INSERT INTO admin_actions (admin_id, action_type, target_type, metadata)
    VALUES (
      auth.uid(),
      'purge_test_data',
      'test_data',
      jsonb_build_object(
        'transactions_deleted', v_transactions_count,
        'withdrawals_deleted', v_withdrawals_count,
        'subscriptions_deleted', v_subscriptions_count,
        'orders_deleted', v_orders_count
      )
    );
  END IF;

  RETURN jsonb_build_object(
    'transactions', v_transactions_count,
    'withdrawals', v_withdrawals_count,
    'subscriptions', v_subscriptions_count,
    'orders', v_orders_count,
    'dry_run', p_dry_run
  );
END;
$$;