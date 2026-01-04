-- Fix: Add grace period check to S1 commission functions
-- New users in their first month (activation_due_from > NOW()) should receive commissions
-- even if monthly_activation_completed is NULL/false

-- Drop existing functions first to allow return type changes
DROP FUNCTION IF EXISTS public.award_s1_subscription_commission(UUID, UUID, NUMERIC);
DROP FUNCTION IF EXISTS public.backfill_missing_s1_commissions(UUID, INTEGER);

-- 1. Recreate award_s1_subscription_commission with grace period check
CREATE OR REPLACE FUNCTION public.award_s1_subscription_commission(
  p_subscriber_id UUID,
  p_subscription_id UUID,
  p_amount_kzt NUMERIC
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sponsor_id UUID;
  v_sponsor_status TEXT;
  v_sponsor_activated BOOLEAN;
  v_sponsor_activation_due_from TIMESTAMPTZ;
  v_commission_percent NUMERIC;
  v_commission_amount INTEGER;
  v_existing_commission UUID;
  v_new_transaction_id UUID;
  v_subscriber_name TEXT;
  v_result JSON;
BEGIN
  -- Get subscriber's sponsor
  SELECT sponsor_id INTO v_sponsor_id
  FROM profiles
  WHERE id = p_subscriber_id;

  IF v_sponsor_id IS NULL THEN
    RETURN json_build_object(
      'success', false,
      'reason', 'no_sponsor',
      'message', 'Subscriber has no sponsor'
    );
  END IF;

  -- Check if commission already exists for this subscription
  SELECT id INTO v_existing_commission
  FROM transactions
  WHERE source_ref = p_subscription_id::TEXT
    AND structure_type = 'primary'
    AND level = 1
    AND type = 'commission';

  IF v_existing_commission IS NOT NULL THEN
    RETURN json_build_object(
      'success', false,
      'reason', 'already_exists',
      'message', 'Commission already awarded for this subscription',
      'transaction_id', v_existing_commission
    );
  END IF;

  -- Get sponsor status, activation status, and activation_due_from
  SELECT subscription_status, monthly_activation_completed, activation_due_from
  INTO v_sponsor_status, v_sponsor_activated, v_sponsor_activation_due_from
  FROM profiles
  WHERE id = v_sponsor_id;

  -- Check sponsor eligibility: must be active AND (activated OR in grace period)
  -- Grace period = activation_due_from is in the future (first month after subscription)
  IF v_sponsor_status != 'active' THEN
    RETURN json_build_object(
      'success', false,
      'reason', 'sponsor_not_active',
      'message', 'Sponsor subscription is not active'
    );
  END IF;

  -- Check activation OR grace period
  IF NOT (COALESCE(v_sponsor_activated, false) = true 
          OR (v_sponsor_activation_due_from IS NOT NULL AND v_sponsor_activation_due_from > NOW())) THEN
    RETURN json_build_object(
      'success', false,
      'reason', 'sponsor_not_activated',
      'message', 'Sponsor has not completed monthly activation and is not in grace period'
    );
  END IF;

  -- Get L1 commission percent (should be 10%)
  SELECT percent INTO v_commission_percent
  FROM commission_plan_levels
  WHERE structure_type = 'primary' AND level = 1
  LIMIT 1;

  IF v_commission_percent IS NULL THEN
    v_commission_percent := 10; -- Default to 10%
  END IF;

  -- Calculate commission in cents (tenge * 100)
  v_commission_amount := ROUND(p_amount_kzt * v_commission_percent / 100) * 100;

  IF v_commission_amount <= 0 THEN
    RETURN json_build_object(
      'success', false,
      'reason', 'zero_amount',
      'message', 'Calculated commission is zero or negative'
    );
  END IF;

  -- Get subscriber name for payload
  SELECT COALESCE(full_name, email, 'Unknown') INTO v_subscriber_name
  FROM profiles
  WHERE id = p_subscriber_id;

  -- Create commission transaction
  INSERT INTO transactions (
    user_id,
    type,
    amount_cents,
    currency,
    status,
    structure_type,
    level,
    source_ref,
    source_id,
    payload
  ) VALUES (
    v_sponsor_id,
    'commission',
    v_commission_amount,
    'KZT',
    'completed',
    'primary',
    1,
    p_subscription_id::TEXT,
    p_subscriber_id,
    jsonb_build_object(
      'subscriber_id', p_subscriber_id,
      'subscriber_name', v_subscriber_name,
      'subscription_id', p_subscription_id,
      'base_amount_kzt', p_amount_kzt,
      'percent', v_commission_percent,
      'source', 'award_s1_subscription_commission'
    )
  )
  RETURNING id INTO v_new_transaction_id;

  -- Update sponsor balance
  UPDATE profiles
  SET balance = COALESCE(balance, 0) + v_commission_amount,
      updated_at = NOW()
  WHERE id = v_sponsor_id;

  RETURN json_build_object(
    'success', true,
    'transaction_id', v_new_transaction_id,
    'sponsor_id', v_sponsor_id,
    'amount_cents', v_commission_amount,
    'percent', v_commission_percent
  );
END;
$$;

-- 2. Recreate backfill_missing_s1_commissions with grace period logic
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
    -- We check against paid_at to see if sponsor was eligible AT THE TIME of payment
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

  -- Log admin action
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
    'batch',
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