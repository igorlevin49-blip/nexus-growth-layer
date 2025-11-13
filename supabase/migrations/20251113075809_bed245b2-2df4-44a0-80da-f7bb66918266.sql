
-- Function to recalculate missing commissions for subscriptions and orders
-- This fixes cases where sponsor_id was added after payment was made

CREATE OR REPLACE FUNCTION public.admin_recalculate_commissions()
RETURNS TABLE(
  recalculated_subscriptions INTEGER,
  recalculated_orders INTEGER,
  total_commissions_created INTEGER,
  details JSONB
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_subscription RECORD;
  v_order RECORD;
  v_sponsor_id UUID;
  v_current_user_id UUID;
  v_current_level INTEGER;
  v_commission_percent NUMERIC;
  v_commission_cents BIGINT;
  v_sponsor_is_active BOOLEAN;
  v_freeze_reason TEXT;
  v_unique_ref TEXT;
  v_subscription_count INTEGER := 0;
  v_order_count INTEGER := 0;
  v_total_commissions INTEGER := 0;
  v_hold_days INTEGER := 7;
  v_details JSONB := '[]'::JSONB;
BEGIN
  -- Check if user is admin or superadmin
  IF NOT (has_role(auth.uid(), 'admin') OR has_role(auth.uid(), 'superadmin')) THEN
    RAISE EXCEPTION 'UNAUTHORIZED';
  END IF;

  -- ====================================
  -- PART 1: Recalculate Subscription Commissions (S1)
  -- ====================================
  FOR v_subscription IN
    SELECT s.id, s.user_id, s.amount_usd, s.paid_at, p.sponsor_id, p.full_name, p.email
    FROM subscriptions s
    JOIN profiles p ON p.id = s.user_id
    WHERE s.status = 'active'
      AND s.paid_at IS NOT NULL
      AND p.sponsor_id IS NOT NULL
      AND NOT EXISTS (
        SELECT 1 FROM transactions t 
        WHERE t.source_ref LIKE 'subscription_' || s.id::TEXT || '%'
        AND t.type = 'commission'
      )
  LOOP
    -- Get sponsor details
    SELECT 
      id,
      subscription_active AND monthly_activation_completed as is_active
    INTO v_sponsor_id, v_sponsor_is_active
    FROM profiles
    WHERE id = v_subscription.sponsor_id;

    -- Set S1 commission (10%)
    v_commission_percent := 10;
    v_commission_cents := (v_subscription.amount_usd * 100 * v_commission_percent / 100)::BIGINT;

    -- Determine freeze reason if sponsor not active
    IF NOT v_sponsor_is_active THEN
      v_freeze_reason := 'sponsor_inactive';
    ELSE
      v_freeze_reason := NULL;
    END IF;

    -- Create unique reference
    v_unique_ref := 'subscription_' || v_subscription.id || '_s1_recalc';

    -- Insert S1 commission
    INSERT INTO transactions (
      user_id,
      type,
      amount_cents,
      status,
      source_id,
      source_ref,
      level,
      structure_type,
      frozen_until,
      currency,
      payload
    ) VALUES (
      v_sponsor_id,
      'commission',
      v_commission_cents,
      'completed',
      v_subscription.id,
      v_unique_ref,
      1,
      'primary',
      CASE 
        WHEN v_freeze_reason IS NOT NULL THEN NOW() + INTERVAL '365 days'
        ELSE NOW() + (v_hold_days || ' days')::INTERVAL
      END,
      'USD',
      jsonb_build_object(
        'subscription_id', v_subscription.id,
        'buyer_id', v_subscription.user_id,
        'buyer_name', v_subscription.full_name,
        'structure', 's1',
        'percent', v_commission_percent,
        'freeze_reason', v_freeze_reason,
        'recalculated', true,
        'recalculated_at', NOW()
      )
    ) ON CONFLICT (source_ref) DO NOTHING;

    v_subscription_count := v_subscription_count + 1;
    v_total_commissions := v_total_commissions + 1;

    v_details := v_details || jsonb_build_object(
      'type', 'subscription',
      'subscription_id', v_subscription.id,
      'user_email', v_subscription.email,
      'sponsor_id', v_sponsor_id,
      'commission_cents', v_commission_cents
    );
  END LOOP;

  -- ====================================
  -- PART 2: Recalculate Order Commissions (P1-P10)
  -- ====================================
  FOR v_order IN
    SELECT o.id, o.user_id, o.total_usd, o.paid_at, p.sponsor_id, p.full_name, p.email
    FROM orders o
    JOIN profiles p ON p.id = o.user_id
    WHERE o.status = 'paid'
      AND o.paid_at IS NOT NULL
      AND p.sponsor_id IS NOT NULL
      AND NOT EXISTS (
        SELECT 1 FROM transactions t 
        WHERE t.source_ref LIKE 'order_' || o.id::TEXT || '%'
        AND t.type = 'commission'
      )
  LOOP
    -- Initialize for traversing sponsor chain
    v_current_user_id := v_order.user_id;
    v_current_level := 1;

    -- Traverse up to 10 levels for primary structure
    WHILE v_current_level <= 10 AND v_current_user_id IS NOT NULL LOOP
      -- Get sponsor
      SELECT sponsor_id INTO v_current_user_id 
      FROM profiles 
      WHERE id = v_current_user_id;

      IF v_current_user_id IS NOT NULL THEN
        -- Get commission percentage for this level
        SELECT percent INTO v_commission_percent 
        FROM commission_plan_levels 
        WHERE plan_id = 'default' 
          AND structure_type = 'primary' 
          AND level = v_current_level;

        IF v_commission_percent IS NOT NULL AND v_commission_percent > 0 THEN
          -- Calculate commission
          v_commission_cents := (v_order.total_usd * 100 * v_commission_percent / 100)::BIGINT;

          -- Create unique reference
          v_unique_ref := 'order_' || v_order.id || '_level_' || v_current_level || '_primary_recalc';

          -- Insert commission
          INSERT INTO transactions (
            user_id,
            type,
            amount_cents,
            status,
            source_id,
            source_ref,
            level,
            structure_type,
            frozen_until,
            currency,
            payload
          ) VALUES (
            v_current_user_id,
            'commission',
            v_commission_cents,
            'completed',
            v_order.id,
            v_unique_ref,
            v_current_level,
            'primary',
            NOW() + (v_hold_days || ' days')::INTERVAL,
            'USD',
            jsonb_build_object(
              'order_id', v_order.id,
              'buyer_id', v_order.user_id,
              'buyer_name', v_order.full_name,
              'level', v_current_level,
              'structure', 'primary',
              'percent', v_commission_percent,
              'recalculated', true,
              'recalculated_at', NOW()
            )
          ) ON CONFLICT (source_ref) DO NOTHING;

          v_total_commissions := v_total_commissions + 1;
        END IF;

        v_current_level := v_current_level + 1;
      END IF;
    END LOOP;

    v_order_count := v_order_count + 1;

    v_details := v_details || jsonb_build_object(
      'type', 'order',
      'order_id', v_order.id,
      'user_email', v_order.email,
      'levels_processed', v_current_level - 1
    );
  END LOOP;

  -- Return summary
  RETURN QUERY SELECT 
    v_subscription_count,
    v_order_count,
    v_total_commissions,
    v_details;
END;
$$;
