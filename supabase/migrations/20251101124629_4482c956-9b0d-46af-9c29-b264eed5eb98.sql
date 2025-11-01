-- 1. Add UNIQUE constraint on referrals to prevent duplicates
ALTER TABLE referrals 
ADD CONSTRAINT unique_invited_user 
UNIQUE (referred_user_id, structure_type);

-- 2. Create improved function to get referral network from referrals table
CREATE OR REPLACE FUNCTION public.get_referral_network_from_table(
  root_user_id UUID,
  max_level INTEGER DEFAULT 10
)
RETURNS TABLE(
  user_id UUID,
  partner_id UUID,
  level INTEGER,
  full_name TEXT,
  email TEXT,
  avatar_url TEXT,
  subscription_status TEXT,
  monthly_activation_met BOOLEAN,
  referral_code TEXT,
  created_at TIMESTAMP WITH TIME ZONE,
  direct_referrals INTEGER,
  total_team INTEGER,
  monthly_volume NUMERIC
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  is_admin_user BOOLEAN;
BEGIN
  -- Check if requesting user is admin/superadmin
  is_admin_user := has_role(auth.uid(), 'admin'::app_role) OR has_role(auth.uid(), 'superadmin'::app_role);
  
  RETURN QUERY
  WITH RECURSIVE network AS (
    -- Root user
    SELECT 
      root_user_id as user_id,
      p.id as partner_id,
      0 as level,
      p.full_name,
      CASE 
        WHEN is_admin_user OR p.id = auth.uid() THEN p.email
        ELSE NULL
      END as email,
      p.avatar_url,
      p.subscription_status,
      p.monthly_activation_completed as monthly_activation_met,
      p.referral_code,
      p.created_at
    FROM public.profiles p
    WHERE p.id = root_user_id
    
    UNION ALL
    
    -- Recursive: get children through referrals table (structure_type = 1)
    SELECT
      root_user_id as user_id,
      p.id as partner_id,
      n.level + 1 as level,
      p.full_name,
      CASE 
        WHEN is_admin_user OR p.id = auth.uid() THEN p.email
        ELSE NULL
      END as email,
      p.avatar_url,
      p.subscription_status,
      p.monthly_activation_completed as monthly_activation_met,
      p.referral_code,
      p.created_at
    FROM public.profiles p
    INNER JOIN public.referrals r ON r.referred_user_id = p.id
    INNER JOIN network n ON n.partner_id = r.referrer_id
    WHERE n.level < max_level 
      AND r.structure_type = 1
  ),
  stats AS (
    SELECT 
      n.partner_id,
      COUNT(DISTINCT CASE WHEN r2.referrer_id = n.partner_id AND r2.structure_type = 1 THEN r2.referred_user_id END) as direct_refs,
      COUNT(DISTINCT p2.id) as total_team_count,
      COALESCE(SUM(CASE 
        WHEN o.status = 'paid' 
        AND DATE_TRUNC('month', o.created_at) = DATE_TRUNC('month', NOW())
        THEN oi.price_usd * oi.qty 
      END), 0) as monthly_vol
    FROM network n
    LEFT JOIN public.referrals r2 ON r2.referrer_id = n.partner_id AND r2.structure_type = 1
    LEFT JOIN LATERAL (
      WITH RECURSIVE sub_network AS (
        SELECT id FROM public.profiles 
        WHERE id IN (SELECT referred_user_id FROM public.referrals WHERE referrer_id = n.partner_id AND structure_type = 1)
        UNION ALL
        SELECT p.id FROM public.profiles p
        INNER JOIN public.referrals r ON r.referred_user_id = p.id AND r.structure_type = 1
        INNER JOIN sub_network sn ON r.referrer_id = sn.id
      )
      SELECT id FROM sub_network
    ) p2 ON true
    LEFT JOIN public.orders o ON o.user_id = p2.id
    LEFT JOIN public.order_items oi ON oi.order_id = o.id
    GROUP BY n.partner_id
  )
  SELECT 
    n.user_id,
    n.partner_id,
    n.level,
    n.full_name,
    n.email,
    n.avatar_url,
    n.subscription_status,
    n.monthly_activation_met,
    n.referral_code,
    n.created_at,
    COALESCE(s.direct_refs, 0)::INTEGER as direct_referrals,
    COALESCE(s.total_team_count, 0)::INTEGER as total_team,
    COALESCE(s.monthly_vol, 0) as monthly_volume
  FROM network n
  LEFT JOIN stats s ON s.partner_id = n.partner_id
  WHERE n.level > 0
  ORDER BY n.level, n.created_at;
END;
$$;

-- 3. Update approve_activation_order to auto-add activation item if missing
CREATE OR REPLACE FUNCTION public.approve_activation_order(
  p_order_id UUID,
  p_admin_id UUID,
  p_comment TEXT,
  p_payment_proof_url TEXT DEFAULT NULL
)
RETURNS JSONB
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

  -- If no activation item, auto-add it
  IF NOT v_has_activation THEN
    -- Get activation product or create synthetic item
    SELECT * INTO v_activation_product 
    FROM products 
    WHERE is_activation = true 
    ORDER BY created_at DESC 
    LIMIT 1;

    IF v_activation_product.id IS NOT NULL THEN
      -- Add real product
      INSERT INTO order_items (
        order_id,
        product_id,
        qty,
        price_usd,
        price_kzt,
        is_activation_snapshot
      ) VALUES (
        p_order_id,
        v_activation_product.id,
        1,
        v_order.total_usd,
        v_order.total_kzt,
        true
      );
    ELSE
      -- Add synthetic activation item
      INSERT INTO order_items (
        order_id,
        product_id,
        qty,
        price_usd,
        price_kzt,
        is_activation_snapshot
      ) VALUES (
        p_order_id,
        NULL,
        1,
        v_order.total_usd,
        v_order.total_kzt,
        true
      );
    END IF;
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
      'has_activation', true,
      'auto_added_item', NOT v_has_activation
    ),
    p_comment
  );

  RETURN jsonb_build_object('success', true, 'message', 'Заказ успешно одобрен и оплачен');
END;
$$;