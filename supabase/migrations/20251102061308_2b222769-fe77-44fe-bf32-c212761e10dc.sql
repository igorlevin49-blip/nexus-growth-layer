-- Add activation_due_from column to profiles
ALTER TABLE public.profiles
ADD COLUMN IF NOT EXISTS activation_due_from timestamptz DEFAULT NULL;

-- Update handle_subscription_confirmation to set activation_due_from
CREATE OR REPLACE FUNCTION public.handle_subscription_confirmation()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- If subscription just became active
  IF NEW.status = 'active' AND (OLD.status IS NULL OR OLD.status != 'active') THEN
    -- Update profile with subscription info and activation due date
    UPDATE profiles
    SET 
      subscription_status = 'active',
      subscription_expires_at = NEW.expires_at,
      -- Activation required from start of next month after payment
      activation_due_from = CASE 
        WHEN NEW.paid_at IS NOT NULL THEN (NEW.paid_at + interval '1 month')::timestamptz
        ELSE (now() + interval '1 month')::timestamptz
      END,
      updated_at = NOW()
    WHERE id = NEW.user_id;
    
    -- Log activity
    INSERT INTO activity_log (user_id, type, payload)
    VALUES (
      NEW.user_id,
      'subscription_activated',
      jsonb_build_object(
        'subscription_id', NEW.id,
        'amount_usd', NEW.amount_usd,
        'confirmed_by', NEW.payment_confirmed_by,
        'expires_at', NEW.expires_at,
        'activation_due_from', CASE 
          WHEN NEW.paid_at IS NOT NULL THEN (NEW.paid_at + interval '1 month')::timestamptz
          ELSE (now() + interval '1 month')::timestamptz
        END
      )
    );
  END IF;
  
  RETURN NEW;
END;
$$;

-- Update check_activation_status to respect personal activation period
CREATE OR REPLACE FUNCTION public.check_activation_status()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  activation_sum NUMERIC;
  required_sum NUMERIC;
  target_user_id UUID;
  user_activation_due_from TIMESTAMPTZ;
  activation_period_start TIMESTAMPTZ;
  activation_period_end TIMESTAMPTZ;
BEGIN
  -- Only process paid orders
  IF NEW.status = 'paid' THEN
    target_user_id := NEW.user_id;
    
    -- Get required activation sum
    SELECT monthly_activation_required_usd INTO required_sum
    FROM shop_settings WHERE id = 1;
    
    -- Get user's activation_due_from date
    SELECT activation_due_from INTO user_activation_due_from
    FROM profiles
    WHERE id = target_user_id;
    
    -- If activation is not yet required, skip
    IF user_activation_due_from IS NULL OR NOW() < user_activation_due_from THEN
      RETURN NEW;
    END IF;
    
    -- Calculate current activation period boundaries
    -- Period starts from activation_due_from and repeats monthly
    activation_period_start := user_activation_due_from + 
      (FLOOR(EXTRACT(EPOCH FROM (NOW() - user_activation_due_from)) / (30 * 24 * 60 * 60)) * INTERVAL '1 month');
    activation_period_end := activation_period_start + INTERVAL '1 month';
    
    -- Calculate activation sum for current personal period
    SELECT COALESCE(SUM(oi.price_usd * oi.qty), 0) INTO activation_sum
    FROM order_items oi
    JOIN orders o ON o.id = oi.order_id
    WHERE o.user_id = target_user_id
      AND o.status = 'paid'
      AND oi.is_activation_snapshot = TRUE
      AND o.created_at >= activation_period_start
      AND o.created_at < activation_period_end;
    
    -- Update profile if activation requirement is met
    IF activation_sum >= required_sum THEN
      UPDATE profiles
      SET 
        subscription_status = 'active',
        monthly_activation_completed = TRUE,
        next_activation_date = activation_period_end::DATE,
        updated_at = NOW()
      WHERE id = target_user_id;
    END IF;
  END IF;
  
  RETURN NEW;
END;
$$;

-- Update approve_activation_order to validate activation period
CREATE OR REPLACE FUNCTION public.approve_activation_order(
  p_order_id uuid, 
  p_admin_id uuid, 
  p_comment text, 
  p_payment_proof_url text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order RECORD;
  v_has_activation BOOLEAN;
  v_activation_sum NUMERIC;
  v_required_sum NUMERIC;
  v_already_activated BOOLEAN;
  v_activation_product RECORD;
  v_user_activation_due_from TIMESTAMPTZ;
  v_activation_period_start TIMESTAMPTZ;
  v_activation_period_end TIMESTAMPTZ;
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

  -- Get user's activation_due_from
  SELECT activation_due_from INTO v_user_activation_due_from
  FROM profiles
  WHERE id = v_order.user_id;
  
  -- Validate that activation period has started
  IF v_user_activation_due_from IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'NO_SUBSCRIPTION', 'message', 'Сначала необходима активная подписка');
  END IF;
  
  IF NOW() < v_user_activation_due_from THEN
    RETURN jsonb_build_object(
      'success', false, 
      'error', 'ACTIVATION_NOT_REQUIRED_YET', 
      'message', 'Первая месячная активация не требуется до ' || to_char(v_user_activation_due_from, 'DD.MM.YYYY'),
      'activation_due_from', v_user_activation_due_from
    );
  END IF;

  -- Check if order has activation products
  SELECT EXISTS(
    SELECT 1 FROM order_items 
    WHERE order_id = p_order_id AND is_activation_snapshot = true
  ) INTO v_has_activation;

  -- If no activation item, auto-add it
  IF NOT v_has_activation THEN
    SELECT * INTO v_activation_product 
    FROM products 
    WHERE is_activation = true 
    ORDER BY created_at DESC 
    LIMIT 1;

    IF v_activation_product.id IS NOT NULL THEN
      INSERT INTO order_items (
        order_id, product_id, qty, price_usd, price_kzt, is_activation_snapshot
      ) VALUES (
        p_order_id, v_activation_product.id, 1, v_order.total_usd, v_order.total_kzt, true
      );
    ELSE
      INSERT INTO order_items (
        order_id, product_id, qty, price_usd, price_kzt, is_activation_snapshot
      ) VALUES (
        p_order_id, NULL, 1, v_order.total_usd, v_order.total_kzt, true
      );
    END IF;
  END IF;

  -- Get required activation sum
  SELECT monthly_activation_required_usd INTO v_required_sum FROM shop_settings WHERE id = 1;

  -- Calculate current activation period
  v_activation_period_start := v_user_activation_due_from + 
    (FLOOR(EXTRACT(EPOCH FROM (NOW() - v_user_activation_due_from)) / (30 * 24 * 60 * 60)) * INTERVAL '1 month');
  v_activation_period_end := v_activation_period_start + INTERVAL '1 month';

  -- Check if user already activated in current period
  SELECT EXISTS(
    SELECT 1 FROM orders o
    JOIN order_items oi ON oi.order_id = o.id
    WHERE o.user_id = v_order.user_id
    AND o.status = 'paid'
    AND oi.is_activation_snapshot = true
    AND o.created_at >= v_activation_period_start
    AND o.created_at < v_activation_period_end
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

  -- Calculate total activation sum for current period
  SELECT COALESCE(SUM(oi.price_usd * oi.qty), 0) INTO v_activation_sum
  FROM order_items oi
  JOIN orders o ON o.id = oi.order_id
  WHERE o.user_id = v_order.user_id
  AND o.status = 'paid'
  AND oi.is_activation_snapshot = true
  AND o.created_at >= v_activation_period_start
  AND o.created_at < v_activation_period_end;

  -- Update profile if activation requirement is met
  IF v_activation_sum >= v_required_sum THEN
    UPDATE profiles SET
      subscription_status = 'active',
      monthly_activation_completed = true,
      next_activation_date = v_activation_period_end::DATE,
      updated_at = now()
    WHERE id = v_order.user_id;

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
      'has_activation', true,
      'auto_added_item', NOT v_has_activation
    ),
    p_comment
  );

  RETURN jsonb_build_object('success', true, 'message', 'Заказ успешно одобрен и оплачен');
END;
$$;