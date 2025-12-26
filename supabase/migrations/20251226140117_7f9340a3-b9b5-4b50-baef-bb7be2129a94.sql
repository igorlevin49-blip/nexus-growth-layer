
-- Delete commissions for free marketing access subscriptions
DELETE FROM transactions t
USING subscriptions s
WHERE t.source_id = s.id
  AND t.type = 'commission'
  AND t.structure_type = 'primary'
  AND s.is_marketing_free_access = true;

-- Drop and recreate the function with correct signature
DROP FUNCTION IF EXISTS public.award_s1_subscription_commission(uuid, uuid, integer);

CREATE FUNCTION public.award_s1_subscription_commission(
  p_user_id uuid,
  p_subscription_id uuid,
  p_amount_kzt integer
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_ancestor RECORD;
  v_level integer := 0;
  v_percent numeric;
  v_commission_amount integer;
  v_source_ref text;
  v_existing_count integer;
  v_freeze_days integer;
  v_frozen_until timestamptz;
  v_commissions_created integer := 0;
  v_direct_referrals integer;
  v_max_unlocked_level integer;
  v_subscription_is_free boolean;
BEGIN
  -- Check if subscription is marketing free access
  SELECT is_marketing_free_access INTO v_subscription_is_free
  FROM subscriptions
  WHERE id = p_subscription_id;

  -- Never award commissions for free marketing access subscriptions
  IF v_subscription_is_free = true THEN
    RETURN json_build_object(
      'success', true,
      'commissions_created', 0,
      'reason', 'free_marketing_access'
    );
  END IF;

  -- Get freeze days setting
  SELECT COALESCE((value->>'days')::integer, 14)
  INTO v_freeze_days
  FROM mlm_settings
  WHERE key = 'commission_freeze_days';

  -- Get sponsor_id for the user
  SELECT sponsor_id INTO v_ancestor
  FROM profiles
  WHERE id = p_user_id;

  IF v_ancestor.sponsor_id IS NULL THEN
    RETURN json_build_object('success', true, 'commissions_created', 0, 'reason', 'no_sponsor');
  END IF;

  -- Walk up sponsor chain for S1 (max 5 levels)
  WHILE v_ancestor.sponsor_id IS NOT NULL AND v_level < 5 LOOP
    v_level := v_level + 1;

    -- Get ancestor details
    SELECT id, sponsor_id, direct_referrals_count
    INTO v_ancestor
    FROM profiles
    WHERE id = v_ancestor.sponsor_id;

    EXIT WHEN v_ancestor.id IS NULL;

    -- Check unlock_levels for this ancestor
    v_direct_referrals := COALESCE(v_ancestor.direct_referrals_count, 0);
    
    -- Calculate max unlocked level
    IF v_direct_referrals >= 5 THEN
      v_max_unlocked_level := 5;
    ELSIF v_direct_referrals >= 4 THEN
      v_max_unlocked_level := 4;
    ELSIF v_direct_referrals >= 3 THEN
      v_max_unlocked_level := 3;
    ELSIF v_direct_referrals >= 2 THEN
      v_max_unlocked_level := 2;
    ELSIF v_direct_referrals >= 1 THEN
      v_max_unlocked_level := 1;
    ELSE
      v_max_unlocked_level := 0;
    END IF;

    -- Skip if level is not unlocked
    IF v_level > v_max_unlocked_level THEN
      CONTINUE;
    END IF;

    -- Get commission percent
    SELECT percent INTO v_percent
    FROM mlm_commission_rules
    WHERE structure_type = 1 AND level = v_level AND is_active = true
    LIMIT 1;

    IF v_percent IS NULL THEN
      v_percent := 10;
    END IF;

    -- Build source_ref
    v_source_ref := 'subscription_' || p_subscription_id::text || '_s1_level_' || v_level::text;

    -- Check if commission already exists
    SELECT COUNT(*) INTO v_existing_count
    FROM transactions
    WHERE source_ref = v_source_ref AND user_id = v_ancestor.id;

    IF v_existing_count > 0 THEN
      CONTINUE;
    END IF;

    -- Calculate commission
    v_commission_amount := ROUND(p_amount_kzt * v_percent / 100);

    -- Calculate frozen_until
    v_frozen_until := NOW() + (v_freeze_days || ' days')::interval;

    -- Create commission with correct source_id = subscription.id
    INSERT INTO transactions (
      user_id, type, amount_cents, currency, status, structure_type,
      level, source_id, source_ref, frozen_until, payload
    ) VALUES (
      v_ancestor.id, 'commission', v_commission_amount, 'KZT', 'frozen', 'primary',
      v_level, p_subscription_id, v_source_ref, v_frozen_until,
      jsonb_build_object(
        'subscription_id', p_subscription_id,
        'subscriber_id', p_user_id,
        'amount_kzt', p_amount_kzt,
        'percent', v_percent
      )
    );

    v_commissions_created := v_commissions_created + 1;
  END LOOP;

  RETURN json_build_object('success', true, 'commissions_created', v_commissions_created);
END;
$$;
