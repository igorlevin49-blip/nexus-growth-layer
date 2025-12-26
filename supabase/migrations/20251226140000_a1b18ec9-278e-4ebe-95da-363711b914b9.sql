
-- Fix historical S1 transactions: update source_id to point to subscription UUID (extracted from source_ref)
-- source_ref format: subscription_{uuid}_s1_level_{n}

UPDATE transactions
SET 
  source_id = substring(source_ref from 'subscription_([0-9a-f-]{36})_s1_level_')::uuid,
  payload = COALESCE(payload, '{}'::jsonb) || jsonb_build_object(
    'subscription_id', substring(source_ref from 'subscription_([0-9a-f-]{36})_s1_level_'),
    'fixed_source_id', true,
    'fixed_at', now()
  )
WHERE 
  source_ref LIKE 'subscription_%_s1_level_%'
  AND source_id IS NOT NULL
  AND source_id != substring(source_ref from 'subscription_([0-9a-f-]{36})_s1_level_')::uuid;

-- Update backfill_missing_s1_commissions to set correct source_id
CREATE OR REPLACE FUNCTION public.backfill_missing_s1_commissions(
  p_admin_id uuid,
  p_days_back integer DEFAULT 30
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_subscription RECORD;
  v_ancestor RECORD;
  v_level integer;
  v_percent numeric;
  v_commission_amount integer;
  v_source_ref text;
  v_existing_count integer;
  v_subscriptions_processed integer := 0;
  v_commissions_created integer := 0;
  v_commissions_skipped integer := 0;
  v_freeze_days integer;
  v_frozen_until timestamptz;
  v_direct_referrals integer;
  v_max_unlocked_level integer;
BEGIN
  -- Verify admin
  IF NOT EXISTS (
    SELECT 1 FROM user_roles 
    WHERE user_id = p_admin_id AND role IN ('admin', 'superadmin')
  ) THEN
    RETURN json_build_object('success', false, 'error', 'Not authorized');
  END IF;

  -- Get freeze days setting
  SELECT COALESCE((value->>'days')::integer, 14)
  INTO v_freeze_days
  FROM mlm_settings
  WHERE key = 'commission_freeze_days';

  -- Process paid subscriptions from the last N days
  FOR v_subscription IN
    SELECT s.id, s.user_id, s.amount_kzt, s.paid_at, p.sponsor_id
    FROM subscriptions s
    JOIN profiles p ON p.id = s.user_id
    WHERE s.status = 'active'
      AND s.paid_at >= NOW() - (p_days_back || ' days')::interval
      AND s.is_marketing_free_access IS NOT TRUE
      AND p.sponsor_id IS NOT NULL
  LOOP
    v_subscriptions_processed := v_subscriptions_processed + 1;

    -- Walk up the sponsor chain for S1
    v_level := 0;
    v_ancestor := ROW(v_subscription.sponsor_id);

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
      
      -- Calculate max unlocked level based on direct referrals
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

      -- Skip if level is not unlocked for this ancestor
      IF v_level > v_max_unlocked_level THEN
        v_commissions_skipped := v_commissions_skipped + 1;
        CONTINUE;
      END IF;

      -- Get commission percent for this level
      SELECT percent INTO v_percent
      FROM mlm_commission_rules
      WHERE structure_type = 1 AND level = v_level AND is_active = true
      LIMIT 1;

      IF v_percent IS NULL THEN
        v_percent := 10; -- Default 10%
      END IF;

      -- Build source_ref
      v_source_ref := 'subscription_' || v_subscription.id::text || '_s1_level_' || v_level::text;

      -- Check if commission already exists
      SELECT COUNT(*) INTO v_existing_count
      FROM transactions
      WHERE source_ref = v_source_ref AND user_id = v_ancestor.id;

      IF v_existing_count > 0 THEN
        v_commissions_skipped := v_commissions_skipped + 1;
        CONTINUE;
      END IF;

      -- Calculate commission (amount_kzt is in whole KZT)
      v_commission_amount := ROUND(v_subscription.amount_kzt * v_percent / 100);

      -- Calculate frozen_until
      v_frozen_until := COALESCE(v_subscription.paid_at, NOW()) + (v_freeze_days || ' days')::interval;

      -- Create commission transaction with CORRECT source_id = subscription.id
      INSERT INTO transactions (
        user_id,
        type,
        amount_cents,
        currency,
        status,
        structure_type,
        level,
        source_id,
        source_ref,
        frozen_until,
        payload
      ) VALUES (
        v_ancestor.id,
        'commission',
        v_commission_amount,
        'KZT',
        CASE WHEN v_frozen_until > NOW() THEN 'frozen' ELSE 'completed' END,
        'primary',
        v_level,
        v_subscription.id,  -- FIXED: now points to subscription.id, not user_id
        v_source_ref,
        CASE WHEN v_frozen_until > NOW() THEN v_frozen_until ELSE NULL END,
        jsonb_build_object(
          'subscription_id', v_subscription.id,
          'subscriber_id', v_subscription.user_id,
          'amount_kzt', v_subscription.amount_kzt,
          'percent', v_percent,
          'backfilled', true,
          'backfilled_at', NOW()
        )
      );

      v_commissions_created := v_commissions_created + 1;
    END LOOP;
  END LOOP;

  -- Log admin action
  INSERT INTO admin_actions (admin_id, action_type, target_type, metadata)
  VALUES (
    p_admin_id,
    'backfill_s1_commissions',
    'transactions',
    jsonb_build_object(
      'days_back', p_days_back,
      'subscriptions_processed', v_subscriptions_processed,
      'commissions_created', v_commissions_created,
      'commissions_skipped', v_commissions_skipped
    )
  );

  RETURN json_build_object(
    'success', true,
    'subscriptions_processed', v_subscriptions_processed,
    'commissions_created', v_commissions_created,
    'commissions_skipped', v_commissions_skipped
  );
END;
$$;
