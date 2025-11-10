-- =======================
-- MIGRATION: Payment Status Fix
-- =======================

-- 1. Add provider_tx_id to orders if missing
ALTER TABLE public.orders 
ADD COLUMN IF NOT EXISTS provider_tx_id TEXT;

-- 2. Add provider_tx_id to subscriptions if missing  
ALTER TABLE public.subscriptions
ADD COLUMN IF NOT EXISTS provider_tx_id TEXT;

-- 3. Create unified payment completion handler
CREATE OR REPLACE FUNCTION public.process_payment_completion(
  p_record_type TEXT, -- 'subscription' | 'order'
  p_record_id UUID,
  p_provider_tx_id TEXT DEFAULT NULL,
  p_payment_method TEXT DEFAULT 'online', -- 'online' | 'manual'
  p_admin_id UUID DEFAULT NULL,
  p_comment TEXT DEFAULT NULL,
  p_payment_proof_url TEXT DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_user_id UUID;
  v_amount_usd NUMERIC;
  v_has_activation BOOLEAN;
  v_activation_sum NUMERIC;
  v_required_sum NUMERIC;
  v_activation_period_start TIMESTAMPTZ;
  v_activation_period_end TIMESTAMPTZ;
  v_user_activation_due_from TIMESTAMPTZ;
  v_already_processed BOOLEAN := FALSE;
BEGIN
  -- Validate record type
  IF p_record_type NOT IN ('subscription', 'order') THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_TYPE');
  END IF;

  -- IDEMPOTENCY: Check if already processed
  IF p_record_type = 'subscription' THEN
    SELECT 
      status = 'active' OR status = 'paid',
      user_id,
      amount_usd
    INTO v_already_processed, v_user_id, v_amount_usd
    FROM subscriptions
    WHERE id = p_record_id;
  ELSE
    SELECT 
      status = 'paid',
      user_id,
      total_usd
    INTO v_already_processed, v_user_id, v_amount_usd
    FROM orders
    WHERE id = p_record_id;
  END IF;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_FOUND');
  END IF;

  -- Already processed - return success (idempotent)
  IF v_already_processed THEN
    RETURN jsonb_build_object('success', true, 'message', 'Already processed', 'idempotent', true);
  END IF;

  -- ===== SUBSCRIPTION PROCESSING =====
  IF p_record_type = 'subscription' THEN
    -- Check if user already has active subscription
    IF EXISTS(
      SELECT 1 FROM subscriptions 
      WHERE user_id = v_user_id 
      AND status = 'active' 
      AND expires_at > now()
      AND id != p_record_id
    ) THEN
      RETURN jsonb_build_object('success', false, 'error', 'ALREADY_ACTIVE_SUBSCRIPTION');
    END IF;

    -- Update subscription to active
    UPDATE subscriptions SET
      status = 'active',
      payment_type = p_payment_method,
      paid_at = now(),
      provider_tx_id = p_provider_tx_id,
      approved_by = p_admin_id,
      approval_comment = p_comment,
      payment_proof_url = p_payment_proof_url,
      payment_confirmed_by = COALESCE(p_admin_id, auth.uid()),
      payment_confirmed_at = now(),
      started_at = now(),
      expires_at = now() + interval '1 year',
      updated_at = now()
    WHERE id = p_record_id;

    -- Update profile
    UPDATE profiles SET
      subscription_status = 'active',
      subscription_expires_at = now() + interval '1 year',
      activation_due_from = now() + interval '1 month',
      updated_at = now()
    WHERE id = v_user_id;

    -- Log activity
    INSERT INTO activity_log (user_id, type, payload)
    VALUES (
      v_user_id,
      'subscription_activated',
      jsonb_build_object(
        'subscription_id', p_record_id,
        'amount_usd', v_amount_usd,
        'payment_method', p_payment_method,
        'expires_at', now() + interval '1 year'
      )
    );

    -- Trigger S1 commission (will be handled by trigger)
    
    RETURN jsonb_build_object('success', true, 'message', 'Подписка активирована');
  END IF;

  -- ===== ORDER PROCESSING =====
  IF p_record_type = 'order' THEN
    -- Check if order has activation products
    SELECT EXISTS(
      SELECT 1 FROM order_items 
      WHERE order_id = p_record_id AND is_activation_snapshot = true
    ) INTO v_has_activation;

    -- Update order to paid
    UPDATE orders SET
      status = 'paid',
      payment_type = p_payment_method,
      paid_at = now(),
      provider_tx_id = p_provider_tx_id,
      approved_by = p_admin_id,
      approval_comment = p_comment,
      payment_proof_url = p_payment_proof_url,
      updated_at = now()
    WHERE id = p_record_id;

    -- If has activation, process activation logic
    IF v_has_activation THEN
      -- Get settings
      SELECT monthly_activation_required_usd INTO v_required_sum FROM shop_settings WHERE id = 1;
      SELECT activation_due_from INTO v_user_activation_due_from FROM profiles WHERE id = v_user_id;

      -- Calculate activation period
      IF v_user_activation_due_from IS NOT NULL AND NOW() >= v_user_activation_due_from THEN
        v_activation_period_start := v_user_activation_due_from + 
          (FLOOR(EXTRACT(EPOCH FROM (NOW() - v_user_activation_due_from)) / (30 * 24 * 60 * 60)) * INTERVAL '1 month');
        v_activation_period_end := v_activation_period_start + INTERVAL '1 month';

        -- Calculate activation sum for period
        SELECT COALESCE(SUM(oi.price_usd * oi.qty), 0) INTO v_activation_sum
        FROM order_items oi
        JOIN orders o ON o.id = oi.order_id
        WHERE o.user_id = v_user_id
        AND o.status = 'paid'
        AND oi.is_activation_snapshot = TRUE
        AND o.created_at >= v_activation_period_start
        AND o.created_at < v_activation_period_end;

        -- Update profile if requirement met
        IF v_activation_sum >= v_required_sum THEN
          UPDATE profiles SET
            subscription_status = 'active',
            monthly_activation_completed = true,
            next_activation_date = v_activation_period_end::DATE,
            updated_at = now()
          WHERE id = v_user_id;

          INSERT INTO activity_log (user_id, type, payload)
          VALUES (
            v_user_id,
            'activation',
            jsonb_build_object(
              'order_id', p_record_id,
              'payment_method', p_payment_method,
              'status', 'completed'
            )
          );
        END IF;
      END IF;
    END IF;

    RETURN jsonb_build_object('success', true, 'message', 'Заказ оплачен');
  END IF;

  RETURN jsonb_build_object('success', false, 'error', 'UNKNOWN_ERROR');
END;
$$;

-- 4. Update approve_subscription_payment to use unified handler
CREATE OR REPLACE FUNCTION public.approve_subscription_payment(
  p_subscription_id UUID,
  p_admin_id UUID,
  p_comment TEXT,
  p_payment_proof_url TEXT DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_result jsonb;
BEGIN
  -- Check admin role
  IF NOT (has_role(p_admin_id, 'admin'::app_role) OR has_role(p_admin_id, 'superadmin'::app_role)) THEN
    RETURN jsonb_build_object('success', false, 'error', 'UNAUTHORIZED');
  END IF;

  -- Call unified handler
  v_result := process_payment_completion(
    'subscription',
    p_subscription_id,
    NULL, -- no provider_tx_id for manual
    'manual',
    p_admin_id,
    p_comment,
    p_payment_proof_url
  );

  -- Log admin action
  IF (v_result->>'success')::boolean THEN
    INSERT INTO admin_audit (admin_id, action_type, target_type, target_id, comment)
    VALUES (p_admin_id, 'approve_payment', 'subscription', p_subscription_id, p_comment);
  END IF;

  RETURN v_result;
END;
$$;

-- 5. Update approve_activation_order to use unified handler
CREATE OR REPLACE FUNCTION public.approve_activation_order(
  p_order_id UUID,
  p_admin_id UUID,
  p_comment TEXT,
  p_payment_proof_url TEXT DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_result jsonb;
BEGIN
  -- Check admin role
  IF NOT (has_role(p_admin_id, 'admin'::app_role) OR has_role(p_admin_id, 'superadmin'::app_role)) THEN
    RETURN jsonb_build_object('success', false, 'error', 'UNAUTHORIZED');
  END IF;

  -- Call unified handler
  v_result := process_payment_completion(
    'order',
    p_order_id,
    NULL, -- no provider_tx_id for manual
    'manual',
    p_admin_id,
    p_comment,
    p_payment_proof_url
  );

  -- Log admin action
  IF (v_result->>'success')::boolean THEN
    INSERT INTO admin_audit (admin_id, action_type, target_type, target_id, comment)
    VALUES (p_admin_id, 'approve_payment', 'order', p_order_id, p_comment);
  END IF;

  RETURN v_result;
END;
$$;

-- 6. Rollback false paid orders (find orders with status=paid but no proof)
-- Find orders marked as paid without provider_tx_id or admin approval
DO $$
DECLARE
  v_rollback_count INT := 0;
BEGIN
  -- Rollback orders
  WITH rollback_orders AS (
    UPDATE orders
    SET 
      status = 'pending',
      paid_at = NULL,
      updated_at = now()
    WHERE status = 'paid'
      AND provider_tx_id IS NULL
      AND approved_by IS NULL
      AND created_at >= now() - interval '30 days'
    RETURNING id, user_id, total_usd
  )
  SELECT COUNT(*) INTO v_rollback_count FROM rollback_orders;

  -- Log the rollback
  IF v_rollback_count > 0 THEN
    RAISE NOTICE 'Rolled back % false paid orders', v_rollback_count;
  END IF;
END $$;

-- 7. Update RLS policies to prevent frontend from setting status=paid
DROP POLICY IF EXISTS "Users create own orders" ON public.orders;
CREATE POLICY "Users create own orders"
  ON public.orders
  FOR INSERT
  WITH CHECK (
    user_id = auth.uid() AND
    status IN ('draft', 'pending') -- Can only create draft/pending
  );

DROP POLICY IF EXISTS "Users can manage items in their draft orders" ON public.order_items;
CREATE POLICY "Users can manage items in their draft orders"
  ON public.order_items
  FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM orders
      WHERE orders.id = order_items.order_id
      AND orders.user_id = auth.uid()
      AND orders.status IN ('draft', 'pending') -- Can only edit draft/pending
    )
  );

-- 8. Similar for subscriptions
DROP POLICY IF EXISTS "Users create own subscriptions" ON public.subscriptions;
CREATE POLICY "Users create own subscriptions"
  ON public.subscriptions
  FOR INSERT
  WITH CHECK (
    user_id = auth.uid() AND
    status = 'pending' -- Can only create pending
  );

COMMENT ON FUNCTION public.process_payment_completion IS 
'Unified payment completion handler. Processes both webhook and manual approvals. Ensures idempotency and proper side effects (subscriptions, activations, commissions).';