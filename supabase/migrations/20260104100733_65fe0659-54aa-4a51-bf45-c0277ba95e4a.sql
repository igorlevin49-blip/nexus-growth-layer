-- Step 1: Fix award_s1_subscription_commission function
-- Commission should be calculated as: amount_kzt * percent / 100
-- Result is stored in WHOLE KZT (not cents!)

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
  v_commission_kzt INTEGER;
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

  -- Get L1 commission percent from mlm_commission_rules (structure_type = 1 for S1)
  SELECT percent INTO v_commission_percent
  FROM mlm_commission_rules
  WHERE structure_type = 1 
    AND level = 1
    AND plan_id = 'default'
    AND is_active = true
  ORDER BY effective_from DESC
  LIMIT 1;

  IF v_commission_percent IS NULL THEN
    v_commission_percent := 10; -- Default to 10%
  END IF;

  -- Calculate commission in WHOLE KZT: amount_kzt * percent / 100
  -- Example: 55000 KZT * 10 / 100 = 5500 KZT
  v_commission_kzt := ROUND(p_amount_kzt * v_commission_percent / 100);

  -- Sanity check: commission should never exceed base amount
  IF v_commission_kzt > p_amount_kzt THEN
    RETURN json_build_object(
      'success', false,
      'reason', 'invalid_commission',
      'message', 'Commission exceeds base amount - calculation error',
      'calculated', v_commission_kzt,
      'base', p_amount_kzt
    );
  END IF;

  IF v_commission_kzt <= 0 THEN
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

  -- Create commission transaction (amount in whole KZT)
  INSERT INTO transactions (
    user_id,
    type,
    amount_cents,  -- Actually stores whole KZT for KZT currency
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
    v_commission_kzt,
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
      'commission_kzt', v_commission_kzt,
      'source', 'award_s1_subscription_commission'
    )
  )
  RETURNING id INTO v_new_transaction_id;

  -- Update sponsor balance (in whole KZT)
  UPDATE profiles
  SET balance = COALESCE(balance, 0) + v_commission_kzt,
      updated_at = NOW()
  WHERE id = v_sponsor_id;

  RETURN json_build_object(
    'success', true,
    'transaction_id', v_new_transaction_id,
    'sponsor_id', v_sponsor_id,
    'amount_kzt', v_commission_kzt,
    'percent', v_commission_percent
  );
END;
$$;