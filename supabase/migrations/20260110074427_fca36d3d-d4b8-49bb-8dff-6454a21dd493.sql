-- =====================================================
-- FIX: Add grace period check for commission eligibility
-- Both S1 and S2 commission functions should allow commissions
-- if sponsor is in grace period (activation_due_from > NOW())
-- =====================================================

-- 1. Fix award_s1_subscription_commission trigger function
CREATE OR REPLACE FUNCTION public.award_s1_subscription_commission()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_sponsor_id UUID;
  v_current_user_id UUID;
  v_current_level INT := 1;
  v_max_level INT := 5; -- S1 has 5 levels
  v_percent NUMERIC;
  v_commission_amount INT;
  v_subscription_amount INT;
  v_freeze_days INT := 14;
  v_frozen_until TIMESTAMP WITH TIME ZONE;
  v_sponsor_subscription_status TEXT;
  v_sponsor_monthly_activation BOOLEAN;
  v_sponsor_activation_due TIMESTAMPTZ;
  v_sponsor_in_grace_period BOOLEAN;
  v_tx_id UUID;
  v_unlock_levels JSONB;
  v_direct_referrals_count INT;
  v_required_referrals INT;
  v_level_key TEXT;
  v_skip_reason TEXT;
BEGIN
  -- Only process when status changes to 'active'
  IF NEW.status != 'active' OR (OLD IS NOT NULL AND OLD.status = 'active') THEN
    RETURN NEW;
  END IF;

  -- Skip marketing free subscriptions
  IF NEW.is_marketing_free_access = true THEN
    RETURN NEW;
  END IF;

  -- Get subscription amount (already in whole KZT)
  v_subscription_amount := COALESCE(NEW.amount_kzt, 0);
  
  IF v_subscription_amount <= 0 THEN
    RETURN NEW;
  END IF;

  -- Get unlock levels settings for S1
  SELECT value INTO v_unlock_levels
  FROM mlm_settings
  WHERE key = 'unlock_levels';
  
  IF v_unlock_levels IS NULL THEN
    v_unlock_levels := '{"l2": 3, "l3": 5, "l4": 8, "l5": 10}'::jsonb;
  END IF;

  -- Calculate frozen_until date
  v_frozen_until := NOW() + (v_freeze_days || ' days')::INTERVAL;

  -- Start from the subscriber
  v_current_user_id := NEW.user_id;

  -- Walk up the sponsor chain
  WHILE v_current_level <= v_max_level LOOP
    -- Get sponsor
    SELECT sponsor_id INTO v_sponsor_id
    FROM profiles
    WHERE id = v_current_user_id;

    -- Exit if no sponsor
    IF v_sponsor_id IS NULL THEN
      EXIT;
    END IF;

    v_skip_reason := NULL;

    -- Get sponsor's subscription status, monthly activation, and grace period
    SELECT 
      subscription_status, 
      COALESCE(monthly_activation_completed, false),
      activation_due_from
    INTO 
      v_sponsor_subscription_status, 
      v_sponsor_monthly_activation,
      v_sponsor_activation_due
    FROM profiles
    WHERE id = v_sponsor_id;

    -- Check if sponsor is in grace period
    v_sponsor_in_grace_period := (v_sponsor_activation_due IS NOT NULL AND v_sponsor_activation_due > NOW());

    -- Get commission percent for this level from S1 rules
    SELECT percent INTO v_percent
    FROM mlm_commission_rules
    WHERE structure_type = 1
      AND level = v_current_level
      AND is_active = true
    ORDER BY effective_from DESC
    LIMIT 1;

    -- Skip if no commission rule for this level
    IF v_percent IS NULL OR v_percent <= 0 THEN
      v_current_user_id := v_sponsor_id;
      v_current_level := v_current_level + 1;
      CONTINUE;
    END IF;

    -- Check unlock requirements for S1 (levels 2+)
    IF v_current_level >= 2 THEN
      -- Count direct referrals
      SELECT COUNT(*) INTO v_direct_referrals_count
      FROM referrals
      WHERE referrer_id = v_sponsor_id
        AND structure_type = 1;
      
      -- Get requirement for this level
      v_level_key := 'l' || v_current_level::text;
      v_required_referrals := COALESCE((v_unlock_levels->>v_level_key)::int, 0);
      
      IF v_required_referrals > 0 AND v_direct_referrals_count < v_required_referrals THEN
        v_skip_reason := 'level_locked';
      END IF;
    END IF;

    -- Check if sponsor has active subscription
    IF v_skip_reason IS NULL AND v_sponsor_subscription_status != 'active' THEN
      v_skip_reason := 'no_subscription';
    END IF;

    -- Check monthly activation OR grace period
    IF v_skip_reason IS NULL THEN
      IF NOT v_sponsor_monthly_activation AND NOT v_sponsor_in_grace_period THEN
        v_skip_reason := 'not_activated';
      END IF;
    END IF;

    -- Calculate commission in whole KZT
    v_commission_amount := FLOOR(v_subscription_amount * v_percent / 100);

    IF v_commission_amount > 0 THEN
      IF v_skip_reason IS NULL THEN
        -- Create frozen commission transaction (idempotent)
        v_tx_id := NULL;
        INSERT INTO transactions (
          user_id,
          type,
          amount_cents,
          currency,
          status,
          source_id,
          source_ref,
          level,
          structure_type,
          frozen_until,
          payload
        ) VALUES (
          v_sponsor_id,
          'commission',
          v_commission_amount,
          'KZT',
          'frozen',
          NEW.id,
          'subscription_' || NEW.id || '_s1_level_' || v_current_level,
          v_current_level,
          'primary',
          v_frozen_until,
          jsonb_build_object(
            'subscription_id', NEW.id,
            'subscriber_id', NEW.user_id,
            'subscription_amount_kzt', v_subscription_amount,
            'percent', v_percent,
            'structure', 'S1',
            'frozen_days', v_freeze_days,
            'in_grace_period', v_sponsor_in_grace_period
          )
        )
        ON CONFLICT ON CONSTRAINT unique_source_ref DO NOTHING
        RETURNING id INTO v_tx_id;

        -- Log only if the transaction was inserted
        IF v_tx_id IS NOT NULL THEN
          INSERT INTO activity_log (user_id, type, payload)
          VALUES (
            v_sponsor_id,
            'commission_earned',
            jsonb_build_object(
              'amount_kzt', v_commission_amount,
              'source', 'subscription',
              'subscription_id', NEW.id,
              'level', v_current_level,
              'structure', 'S1',
              'status', 'frozen',
              'frozen_until', v_frozen_until,
              'in_grace_period', v_sponsor_in_grace_period
            )
          );
        END IF;
      ELSE
        -- Log skipped commission with reason
        INSERT INTO activity_log (user_id, type, payload)
        VALUES (
          v_sponsor_id,
          'commission_skipped',
          jsonb_build_object(
            'reason', v_skip_reason,
            'subscription_status', v_sponsor_subscription_status,
            'monthly_activation', v_sponsor_monthly_activation,
            'in_grace_period', v_sponsor_in_grace_period,
            'activation_due_from', v_sponsor_activation_due,
            'would_be_amount_kzt', v_commission_amount,
            'subscription_id', NEW.id,
            'level', v_current_level,
            'structure', 'S1'
          )
        );
      END IF;
    END IF;

    -- Move up to next sponsor
    v_current_user_id := v_sponsor_id;
    v_current_level := v_current_level + 1;
  END LOOP;

  RETURN NEW;
END;
$function$;


-- 2. Fix create_commission_transactions trigger function for orders (S2)
-- S2 does NOT require direct referrals, only: active subscription + monthly activation (or grace period)
CREATE OR REPLACE FUNCTION public.create_commission_transactions()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_sponsor_id UUID;
  v_current_user_id UUID;
  v_current_level INT := 1;
  v_max_level INT := 10; -- S2 has 10 levels
  v_percent NUMERIC;
  v_commission_amount INT;
  v_order_total INT;
  v_freeze_days INT := 14;
  v_frozen_until TIMESTAMP WITH TIME ZONE;
  v_sponsor_subscription_status TEXT;
  v_sponsor_monthly_activation BOOLEAN;
  v_sponsor_activation_due TIMESTAMPTZ;
  v_sponsor_in_grace_period BOOLEAN;
  v_tx_id UUID;
  v_skip_reason TEXT;
BEGIN
  -- Only process when status changes to 'paid'
  IF NEW.status != 'paid' OR (OLD IS NOT NULL AND OLD.status = 'paid') THEN
    RETURN NEW;
  END IF;

  -- Get order total (already in whole KZT)
  v_order_total := COALESCE(NEW.total_kzt, 0);
  
  IF v_order_total <= 0 THEN
    RETURN NEW;
  END IF;

  -- Calculate frozen_until date
  v_frozen_until := NOW() + (v_freeze_days || ' days')::INTERVAL;

  -- Start from the order user
  v_current_user_id := NEW.user_id;

  -- Walk up the sponsor chain for secondary structure (P1-P10)
  WHILE v_current_level <= v_max_level LOOP
    -- Get sponsor
    SELECT sponsor_id INTO v_sponsor_id
    FROM profiles
    WHERE id = v_current_user_id;

    -- Exit if no sponsor
    IF v_sponsor_id IS NULL THEN
      EXIT;
    END IF;

    v_skip_reason := NULL;

    -- Get sponsor's subscription status, monthly activation, and grace period
    SELECT 
      subscription_status, 
      COALESCE(monthly_activation_completed, false),
      activation_due_from
    INTO 
      v_sponsor_subscription_status, 
      v_sponsor_monthly_activation,
      v_sponsor_activation_due
    FROM profiles
    WHERE id = v_sponsor_id;

    -- Check if sponsor is in grace period
    v_sponsor_in_grace_period := (v_sponsor_activation_due IS NOT NULL AND v_sponsor_activation_due > NOW());

    -- Get commission percent for this level from secondary structure rules (structure_type = 2)
    SELECT percent INTO v_percent
    FROM mlm_commission_rules
    WHERE structure_type = 2
      AND level = v_current_level
      AND is_active = true
    ORDER BY effective_from DESC
    LIMIT 1;

    -- Skip if no commission rule for this level
    IF v_percent IS NULL OR v_percent <= 0 THEN
      v_current_user_id := v_sponsor_id;
      v_current_level := v_current_level + 1;
      CONTINUE;
    END IF;

    -- S2 does NOT check direct referrals - only subscription and activation
    
    -- Check if sponsor has active subscription (S1 must be active for S2 to work)
    IF v_sponsor_subscription_status != 'active' THEN
      v_skip_reason := 'no_subscription';
    END IF;

    -- Check monthly activation OR grace period
    IF v_skip_reason IS NULL THEN
      IF NOT v_sponsor_monthly_activation AND NOT v_sponsor_in_grace_period THEN
        v_skip_reason := 'not_activated';
      END IF;
    END IF;

    -- Calculate commission in whole KZT
    v_commission_amount := FLOOR(v_order_total * v_percent / 100);

    IF v_commission_amount > 0 THEN
      IF v_skip_reason IS NULL THEN
        -- Create frozen commission transaction (idempotent)
        v_tx_id := NULL;
        INSERT INTO transactions (
          user_id,
          type,
          amount_cents,
          currency,
          status,
          source_id,
          source_ref,
          level,
          structure_type,
          frozen_until,
          payload
        ) VALUES (
          v_sponsor_id,
          'commission',
          v_commission_amount,
          'KZT',
          'frozen',
          NEW.id,
          'order_' || NEW.id || '_level_' || v_current_level || '_secondary',
          v_current_level,
          'secondary',
          v_frozen_until,
          jsonb_build_object(
            'order_id', NEW.id,
            'buyer_id', NEW.user_id,
            'order_amount_kzt', v_order_total,
            'percent', v_percent,
            'structure', 'P' || v_current_level,
            'frozen_days', v_freeze_days,
            'in_grace_period', v_sponsor_in_grace_period
          )
        )
        ON CONFLICT ON CONSTRAINT unique_source_ref DO NOTHING
        RETURNING id INTO v_tx_id;

        -- Log only if the transaction was inserted
        IF v_tx_id IS NOT NULL THEN
          INSERT INTO activity_log (user_id, type, payload)
          VALUES (
            v_sponsor_id,
            'commission_earned',
            jsonb_build_object(
              'amount_kzt', v_commission_amount,
              'source', 'order',
              'order_id', NEW.id,
              'level', v_current_level,
              'structure', 'P' || v_current_level,
              'status', 'frozen',
              'frozen_until', v_frozen_until,
              'in_grace_period', v_sponsor_in_grace_period
            )
          );
        END IF;
      ELSE
        -- Log skipped commission due to ineligibility
        INSERT INTO activity_log (user_id, type, payload)
        VALUES (
          v_sponsor_id,
          'commission_skipped',
          jsonb_build_object(
            'reason', v_skip_reason,
            'subscription_status', v_sponsor_subscription_status,
            'monthly_activation', v_sponsor_monthly_activation,
            'in_grace_period', v_sponsor_in_grace_period,
            'activation_due_from', v_sponsor_activation_due,
            'would_be_amount_kzt', v_commission_amount,
            'order_id', NEW.id,
            'level', v_current_level,
            'structure', 'P' || v_current_level
          )
        );
      END IF;
    END IF;

    -- Move up to next sponsor
    v_current_user_id := v_sponsor_id;
    v_current_level := v_current_level + 1;
  END LOOP;

  RETURN NEW;
END;
$function$;


-- 3. Backfill missing commission for Tulkubay (5,500 KZT for Serik's subscription)
-- Serik Dairabaev paid on 2026-01-09 15:10, Tulkubay was in grace period
INSERT INTO transactions (
  user_id,
  type,
  amount_cents,
  currency,
  status,
  source_id,
  source_ref,
  level,
  structure_type,
  frozen_until,
  payload
)
SELECT 
  '09b2932a-6292-48bb-9382-7aaa6a5c6c55'::uuid, -- Tulkubay
  'commission',
  5500,
  'KZT',
  'frozen',
  'bff68864-14a8-400d-86ea-95240e7d855c'::uuid, -- Serik's subscription
  'subscription_bff68864-14a8-400d-86ea-95240e7d855c_s1_level_1_backfill',
  1,
  'primary',
  NOW() + INTERVAL '14 days',
  jsonb_build_object(
    'subscription_id', 'bff68864-14a8-400d-86ea-95240e7d855c',
    'subscriber_id', 'daf762a0-22c6-4fa3-85fa-2f806fff3082',
    'subscription_amount_kzt', 55000,
    'percent', 10,
    'structure', 'S1',
    'frozen_days', 14,
    'backfill', true,
    'backfill_reason', 'grace_period_not_checked_in_original_trigger'
  )
WHERE NOT EXISTS (
  SELECT 1 FROM transactions 
  WHERE source_id = 'bff68864-14a8-400d-86ea-95240e7d855c'::uuid
    AND user_id = '09b2932a-6292-48bb-9382-7aaa6a5c6c55'::uuid
    AND type = 'commission'
    AND structure_type = 'primary'
    AND level = 1
);

-- Log the backfill
INSERT INTO activity_log (user_id, type, payload)
SELECT 
  '09b2932a-6292-48bb-9382-7aaa6a5c6c55'::uuid,
  'commission_backfill',
  jsonb_build_object(
    'amount_kzt', 5500,
    'source', 'subscription',
    'subscription_id', 'bff68864-14a8-400d-86ea-95240e7d855c',
    'subscriber_id', 'daf762a0-22c6-4fa3-85fa-2f806fff3082',
    'subscriber_name', 'Serik Dairabaev',
    'level', 1,
    'structure', 'S1',
    'reason', 'grace_period_not_checked_in_original_trigger',
    'backfilled_at', NOW()
  )
WHERE NOT EXISTS (
  SELECT 1 FROM activity_log 
  WHERE user_id = '09b2932a-6292-48bb-9382-7aaa6a5c6c55'::uuid
    AND type = 'commission_backfill'
    AND payload->>'subscription_id' = 'bff68864-14a8-400d-86ea-95240e7d855c'
);