-- Fix: target_id is UUID type, not TEXT
CREATE OR REPLACE FUNCTION public.backfill_missing_s1_commissions(
  p_admin_id UUID,
  p_days_back INTEGER DEFAULT 30
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_subscription RECORD;
  v_result JSON;
  v_processed INTEGER := 0;
  v_created INTEGER := 0;
  v_skipped INTEGER := 0;
  v_errors JSON[] := ARRAY[]::JSON[];
BEGIN
  -- Check admin permissions
  IF NOT EXISTS (
    SELECT 1 FROM user_roles 
    WHERE user_id = p_admin_id AND role IN ('admin', 'superadmin')
  ) THEN
    RETURN json_build_object(
      'success', false,
      'error', 'Unauthorized: Admin role required'
    );
  END IF;

  -- Find all paid subscriptions in the last N days that might be missing L1 commissions
  FOR v_subscription IN
    SELECT 
      s.id AS subscription_id,
      s.user_id AS subscriber_id,
      s.amount_kzt,
      s.paid_at,
      p.sponsor_id,
      p.full_name AS subscriber_name,
      sp.subscription_status AS sponsor_status,
      sp.monthly_activation_completed AS sponsor_activated,
      sp.activation_due_from AS sponsor_activation_due_from
    FROM subscriptions s
    JOIN profiles p ON p.id = s.user_id
    LEFT JOIN profiles sp ON sp.id = p.sponsor_id
    WHERE s.status = 'active'
      AND s.paid_at IS NOT NULL
      AND s.paid_at >= NOW() - (p_days_back || ' days')::INTERVAL
      AND s.is_marketing_free_access IS NOT TRUE
      AND p.sponsor_id IS NOT NULL
      -- Exclude subscriptions that already have L1 commission
      AND NOT EXISTS (
        SELECT 1 FROM transactions t
        WHERE t.source_ref = s.id::TEXT
          AND t.structure_type = 'primary'
          AND t.level = 1
          AND t.type = 'commission'
      )
    ORDER BY s.paid_at
  LOOP
    v_processed := v_processed + 1;

    -- Check sponsor eligibility: active subscription AND (activated OR in grace period)
    IF v_subscription.sponsor_status != 'active' THEN
      v_skipped := v_skipped + 1;
      v_errors := array_append(v_errors, json_build_object(
        'subscription_id', v_subscription.subscription_id,
        'reason', 'sponsor_not_active',
        'subscriber_name', v_subscription.subscriber_name
      ));
      CONTINUE;
    END IF;

    -- Check activation OR grace period (grace period = activation_due_from > paid_at of subscription)
    IF NOT (
      COALESCE(v_subscription.sponsor_activated, false) = true 
      OR (v_subscription.sponsor_activation_due_from IS NOT NULL 
          AND v_subscription.sponsor_activation_due_from > v_subscription.paid_at)
    ) THEN
      v_skipped := v_skipped + 1;
      v_errors := array_append(v_errors, json_build_object(
        'subscription_id', v_subscription.subscription_id,
        'reason', 'sponsor_not_activated_at_time',
        'subscriber_name', v_subscription.subscriber_name,
        'sponsor_activation_due_from', v_subscription.sponsor_activation_due_from,
        'paid_at', v_subscription.paid_at
      ));
      CONTINUE;
    END IF;

    -- Award the commission
    SELECT public.award_s1_subscription_commission(
      v_subscription.subscriber_id,
      v_subscription.subscription_id,
      v_subscription.amount_kzt
    ) INTO v_result;

    IF (v_result->>'success')::BOOLEAN THEN
      v_created := v_created + 1;
    ELSE
      v_skipped := v_skipped + 1;
      v_errors := array_append(v_errors, json_build_object(
        'subscription_id', v_subscription.subscription_id,
        'reason', v_result->>'reason',
        'message', v_result->>'message'
      ));
    END IF;
  END LOOP;

  -- Log admin action (use gen_random_uuid() for batch operation)
  INSERT INTO admin_audit (
    admin_id,
    action_type,
    target_type,
    target_id,
    metadata
  ) VALUES (
    p_admin_id,
    'backfill_s1_commissions',
    'system',
    gen_random_uuid(),
    jsonb_build_object(
      'days_back', p_days_back,
      'subscriptions_processed', v_processed,
      'commissions_created', v_created,
      'commissions_skipped', v_skipped
    )
  );

  RETURN json_build_object(
    'success', true,
    'subscriptions_processed', v_processed,
    'commissions_created', v_created,
    'commissions_skipped', v_skipped,
    'errors', v_errors
  );
END;
$$;