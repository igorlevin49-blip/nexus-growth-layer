-- Add payment_intent_id for idempotency
ALTER TABLE subscriptions ADD COLUMN IF NOT EXISTS payment_intent_id UUID DEFAULT gen_random_uuid();
ALTER TABLE subscriptions ADD COLUMN IF NOT EXISTS payment_type TEXT DEFAULT 'online' CHECK (payment_type IN ('online', 'manual'));
ALTER TABLE subscriptions ADD COLUMN IF NOT EXISTS paid_at TIMESTAMP WITH TIME ZONE;
ALTER TABLE subscriptions ADD COLUMN IF NOT EXISTS approved_by UUID REFERENCES auth.users(id);
ALTER TABLE subscriptions ADD COLUMN IF NOT EXISTS approval_comment TEXT;
ALTER TABLE subscriptions ADD COLUMN IF NOT EXISTS payment_proof_url TEXT;

ALTER TABLE orders ADD COLUMN IF NOT EXISTS payment_intent_id UUID DEFAULT gen_random_uuid();
ALTER TABLE orders ADD COLUMN IF NOT EXISTS payment_type TEXT DEFAULT 'online' CHECK (payment_type IN ('online', 'manual'));
ALTER TABLE orders ADD COLUMN IF NOT EXISTS paid_at TIMESTAMP WITH TIME ZONE;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS approved_by UUID REFERENCES auth.users(id);
ALTER TABLE orders ADD COLUMN IF NOT EXISTS approval_comment TEXT;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS payment_proof_url TEXT;

-- Create admin_audit table if not exists
CREATE TABLE IF NOT EXISTS admin_audit (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  admin_id UUID REFERENCES auth.users(id) NOT NULL,
  action_type TEXT NOT NULL,
  target_type TEXT NOT NULL,
  target_id UUID NOT NULL,
  metadata JSONB DEFAULT '{}'::jsonb,
  comment TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Enable RLS on admin_audit
ALTER TABLE admin_audit ENABLE ROW LEVEL SECURITY;

-- Policy for admins to view audit logs
CREATE POLICY "Admins can view audit logs"
ON admin_audit FOR SELECT
TO authenticated
USING (has_role(auth.uid(), 'admin'::app_role) OR has_role(auth.uid(), 'superadmin'::app_role));

-- Policy for admins to insert audit logs
CREATE POLICY "Admins can insert audit logs"
ON admin_audit FOR INSERT
TO authenticated
WITH CHECK (has_role(auth.uid(), 'admin'::app_role) OR has_role(auth.uid(), 'superadmin'::app_role));

-- Create index for faster lookups
CREATE INDEX IF NOT EXISTS idx_admin_audit_admin_id ON admin_audit(admin_id);
CREATE INDEX IF NOT EXISTS idx_admin_audit_target_id ON admin_audit(target_id);
CREATE INDEX IF NOT EXISTS idx_admin_audit_created_at ON admin_audit(created_at DESC);

-- Create index for payment_intent_id for idempotency checks
CREATE UNIQUE INDEX IF NOT EXISTS idx_subscriptions_payment_intent_id ON subscriptions(payment_intent_id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_orders_payment_intent_id ON orders(payment_intent_id);

-- Function to manually approve subscription payment
CREATE OR REPLACE FUNCTION approve_subscription_payment(
  p_subscription_id UUID,
  p_admin_id UUID,
  p_comment TEXT,
  p_payment_proof_url TEXT DEFAULT NULL
) RETURNS JSONB AS $$
DECLARE
  v_subscription RECORD;
  v_user_id UUID;
  v_active_subscription_exists BOOLEAN;
BEGIN
  -- Check if admin has proper role
  IF NOT (has_role(p_admin_id, 'admin'::app_role) OR has_role(p_admin_id, 'superadmin'::app_role)) THEN
    RETURN jsonb_build_object('success', false, 'error', 'UNAUTHORIZED', 'message', 'Требуется роль администратора');
  END IF;

  -- Get subscription details
  SELECT * INTO v_subscription FROM subscriptions WHERE id = p_subscription_id;
  
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_FOUND', 'message', 'Подписка не найдена');
  END IF;

  -- Check if already processed (idempotency)
  IF v_subscription.status IN ('active', 'paid') THEN
    RETURN jsonb_build_object('success', false, 'error', 'ALREADY_PROCESSED', 'message', 'Подписка уже активирована');
  END IF;

  -- Check if user already has active subscription
  SELECT EXISTS(
    SELECT 1 FROM subscriptions 
    WHERE user_id = v_subscription.user_id 
    AND status = 'active' 
    AND expires_at > now()
    AND id != p_subscription_id
  ) INTO v_active_subscription_exists;

  IF v_active_subscription_exists THEN
    RETURN jsonb_build_object('success', false, 'error', 'ALREADY_ACTIVE_SUBSCRIPTION', 'message', 'У пользователя уже есть активная подписка');
  END IF;

  -- Update subscription
  UPDATE subscriptions SET
    status = 'active',
    payment_type = 'manual',
    paid_at = now(),
    approved_by = p_admin_id,
    approval_comment = p_comment,
    payment_proof_url = p_payment_proof_url,
    payment_confirmed_by = p_admin_id,
    payment_confirmed_at = now(),
    started_at = now(),
    expires_at = now() + interval '1 year',
    updated_at = now()
  WHERE id = p_subscription_id;

  -- Update profile
  UPDATE profiles SET
    subscription_status = 'active',
    subscription_expires_at = now() + interval '1 year',
    updated_at = now()
  WHERE id = v_subscription.user_id;

  -- Log activity
  INSERT INTO activity_log (user_id, type, payload)
  VALUES (
    v_subscription.user_id,
    'subscription_activated',
    jsonb_build_object(
      'subscription_id', p_subscription_id,
      'amount_usd', v_subscription.amount_usd,
      'approved_by', p_admin_id,
      'approval_type', 'manual',
      'expires_at', now() + interval '1 year'
    )
  );

  -- Log admin action
  INSERT INTO admin_audit (admin_id, action_type, target_type, target_id, metadata, comment)
  VALUES (
    p_admin_id,
    'approve_payment',
    'subscription',
    p_subscription_id,
    jsonb_build_object(
      'user_id', v_subscription.user_id,
      'amount_usd', v_subscription.amount_usd,
      'payment_type', 'manual'
    ),
    p_comment
  );

  RETURN jsonb_build_object('success', true, 'message', 'Подписка успешно одобрена и активирована');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- Function to manually approve activation order
CREATE OR REPLACE FUNCTION approve_activation_order(
  p_order_id UUID,
  p_admin_id UUID,
  p_comment TEXT,
  p_payment_proof_url TEXT DEFAULT NULL
) RETURNS JSONB AS $$
DECLARE
  v_order RECORD;
  v_has_activation BOOLEAN;
  v_activation_sum NUMERIC;
  v_required_sum NUMERIC;
  v_already_activated BOOLEAN;
BEGIN
  -- Check if admin has proper role
  IF NOT (has_role(p_admin_id, 'admin'::app_role) OR has_role(p_admin_id, 'superadmin'::app_role)) THEN
    RETURN jsonb_build_object('success', false, 'error', 'UNAUTHORIZED', 'message', 'Требуется роль администратора');
  END IF;

  -- Get order details
  SELECT * INTO v_order FROM orders WHERE id = p_order_id;
  
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_FOUND', 'message', 'Заказ не найден');
  END IF;

  -- Check if already processed (idempotency)
  IF v_order.status = 'paid' THEN
    RETURN jsonb_build_object('success', false, 'error', 'ALREADY_PROCESSED', 'message', 'Заказ уже оплачен');
  END IF;

  -- Check if order has activation products
  SELECT EXISTS(
    SELECT 1 FROM order_items 
    WHERE order_id = p_order_id AND is_activation_snapshot = true
  ) INTO v_has_activation;

  IF NOT v_has_activation THEN
    RETURN jsonb_build_object('success', false, 'error', 'NO_ACTIVATION_PRODUCTS', 'message', 'Заказ не содержит активационных товаров');
  END IF;

  -- Get required activation sum
  SELECT monthly_activation_required_usd INTO v_required_sum FROM shop_settings WHERE id = 1;

  -- Check if user already activated this month
  SELECT EXISTS(
    SELECT 1 FROM orders o
    JOIN order_items oi ON oi.order_id = o.id
    WHERE o.user_id = v_order.user_id
    AND o.status = 'paid'
    AND oi.is_activation_snapshot = true
    AND DATE_TRUNC('month', o.created_at) = DATE_TRUNC('month', NOW())
    AND o.id != p_order_id
  ) INTO v_already_activated;

  IF v_already_activated THEN
    RETURN jsonb_build_object('success', false, 'error', 'ALREADY_ACTIVATED_PERIOD', 'message', 'Активация за текущий период уже выполнена');
  END IF;

  -- Update order
  UPDATE orders SET
    status = 'paid',
    payment_type = 'manual',
    paid_at = now(),
    approved_by = p_admin_id,
    approval_comment = p_comment,
    payment_proof_url = p_payment_proof_url,
    updated_at = now()
  WHERE id = p_order_id;

  -- Calculate total activation sum for current month
  SELECT COALESCE(SUM(oi.price_usd * oi.qty), 0) INTO v_activation_sum
  FROM order_items oi
  JOIN orders o ON o.id = oi.order_id
  WHERE o.user_id = v_order.user_id
  AND o.status = 'paid'
  AND oi.is_activation_snapshot = true
  AND DATE_TRUNC('month', o.created_at) = DATE_TRUNC('month', NOW());

  -- Update profile if activation requirement is met
  IF v_activation_sum >= v_required_sum THEN
    UPDATE profiles SET
      subscription_status = 'active',
      monthly_activation_completed = true,
      next_activation_date = (DATE_TRUNC('month', NOW()) + INTERVAL '1 month')::DATE,
      updated_at = now()
    WHERE id = v_order.user_id;

    -- Log activity
    INSERT INTO activity_log (user_id, type, payload)
    VALUES (
      v_order.user_id,
      'activation',
      jsonb_build_object(
        'order_id', p_order_id,
        'approved_by', p_admin_id,
        'approval_type', 'manual',
        'status', 'completed'
      )
    );
  END IF;

  -- Log admin action
  INSERT INTO admin_audit (admin_id, action_type, target_type, target_id, metadata, comment)
  VALUES (
    p_admin_id,
    'approve_payment',
    'order',
    p_order_id,
    jsonb_build_object(
      'user_id', v_order.user_id,
      'amount_usd', v_order.total_usd,
      'payment_type', 'manual',
      'has_activation', v_has_activation
    ),
    p_comment
  );

  RETURN jsonb_build_object('success', true, 'message', 'Заказ успешно одобрен и оплачен');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- Function to reject payment
CREATE OR REPLACE FUNCTION reject_payment(
  p_record_type TEXT,
  p_record_id UUID,
  p_admin_id UUID,
  p_comment TEXT
) RETURNS JSONB AS $$
BEGIN
  -- Check if admin has proper role
  IF NOT (has_role(p_admin_id, 'admin'::app_role) OR has_role(p_admin_id, 'superadmin'::app_role)) THEN
    RETURN jsonb_build_object('success', false, 'error', 'UNAUTHORIZED', 'message', 'Требуется роль администратора');
  END IF;

  IF p_record_type = 'subscription' THEN
    UPDATE subscriptions SET
      status = 'cancelled',
      approved_by = p_admin_id,
      approval_comment = p_comment,
      updated_at = now()
    WHERE id = p_record_id AND status = 'pending';

    IF NOT FOUND THEN
      RETURN jsonb_build_object('success', false, 'error', 'NOT_FOUND', 'message', 'Подписка не найдена или уже обработана');
    END IF;

  ELSIF p_record_type = 'order' THEN
    UPDATE orders SET
      status = 'cancelled',
      approved_by = p_admin_id,
      approval_comment = p_comment,
      updated_at = now()
    WHERE id = p_record_id AND status = 'pending';

    IF NOT FOUND THEN
      RETURN jsonb_build_object('success', false, 'error', 'NOT_FOUND', 'message', 'Заказ не найден или уже обработан');
    END IF;
  ELSE
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_TYPE', 'message', 'Неверный тип записи');
  END IF;

  -- Log admin action
  INSERT INTO admin_audit (admin_id, action_type, target_type, target_id, comment)
  VALUES (p_admin_id, 'reject_payment', p_record_type, p_record_id, p_comment);

  RETURN jsonb_build_object('success', true, 'message', 'Платёж отклонён');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;