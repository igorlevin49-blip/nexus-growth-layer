-- Fix payment activation failures caused by duplicate commission inserts

-- 1) Remove duplicate trigger that calls award_s1_subscription_commission twice
DROP TRIGGER IF EXISTS award_s1_commission_trigger ON public.subscriptions;

-- 2) Make commission-creation functions idempotent (safe on repeated calls)

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
  v_max_level INT := 10;
  v_percent NUMERIC;
  v_commission_amount INT;
  v_subscription_amount INT;
  v_freeze_days INT := 14;
  v_frozen_until TIMESTAMP WITH TIME ZONE;
  v_sponsor_subscription_status TEXT;
  v_sponsor_monthly_activation BOOLEAN;
  v_tx_id UUID;
BEGIN
  -- Only process when status changes to 'active'
  IF NEW.status != 'active' OR (OLD IS NOT NULL AND OLD.status = 'active') THEN
    RETURN NEW;
  END IF;

  -- Get subscription amount (already in whole KZT)
  v_subscription_amount := NEW.amount_kzt;
  
  IF v_subscription_amount <= 0 THEN
    RETURN NEW;
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

    -- Get sponsor's subscription status and monthly activation
    SELECT subscription_status, COALESCE(monthly_activation_completed, false)
    INTO v_sponsor_subscription_status, v_sponsor_monthly_activation
    FROM profiles
    WHERE id = v_sponsor_id;

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

    -- Calculate commission in whole KZT
    v_commission_amount := FLOOR(v_subscription_amount * v_percent / 100);

    IF v_commission_amount > 0 THEN
      -- Check if sponsor is eligible (active subscription + monthly activation)
      IF v_sponsor_subscription_status = 'active' AND v_sponsor_monthly_activation = true THEN
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
            'frozen_days', v_freeze_days
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
              'frozen_until', v_frozen_until
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
            'reason', 'sponsor_not_eligible',
            'subscription_status', v_sponsor_subscription_status,
            'monthly_activation', v_sponsor_monthly_activation,
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
  v_max_level INT := 10;
  v_percent NUMERIC;
  v_commission_amount INT;
  v_order_total INT;
  v_freeze_days INT := 14;
  v_frozen_until TIMESTAMP WITH TIME ZONE;
  v_sponsor_subscription_status TEXT;
  v_sponsor_monthly_activation BOOLEAN;
  v_tx_id UUID;
BEGIN
  -- Only process when status changes to 'paid'
  IF NEW.status != 'paid' OR (OLD IS NOT NULL AND OLD.status = 'paid') THEN
    RETURN NEW;
  END IF;

  -- Get order total (already in whole KZT)
  v_order_total := NEW.total_kzt;
  
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

    -- Get sponsor's subscription status and monthly activation
    SELECT subscription_status, COALESCE(monthly_activation_completed, false)
    INTO v_sponsor_subscription_status, v_sponsor_monthly_activation
    FROM profiles
    WHERE id = v_sponsor_id;

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

    -- Calculate commission in whole KZT
    v_commission_amount := FLOOR(v_order_total * v_percent / 100);

    IF v_commission_amount > 0 THEN
      -- Check if sponsor is eligible (active subscription + monthly activation)
      IF v_sponsor_subscription_status = 'active' AND v_sponsor_monthly_activation = true THEN
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
            'frozen_days', v_freeze_days
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
              'frozen_until', v_frozen_until
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
            'reason', 'sponsor_not_eligible',
            'subscription_status', v_sponsor_subscription_status,
            'monthly_activation', v_sponsor_monthly_activation,
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
