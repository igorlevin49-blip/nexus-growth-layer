-- Fix source_ref uniqueness in commission functions
-- The previous migration incorrectly used constant strings instead of unique identifiers

-- Update award_s1_subscription_commission function
CREATE OR REPLACE FUNCTION public.award_s1_subscription_commission()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sponsor_id uuid;
  v_current_user_id uuid;
  v_level int := 0;
  v_percent numeric;
  v_commission_cents bigint;
  v_sponsor_subscription_status text;
  v_sponsor_monthly_activation boolean;
  v_sponsor_activation_due_from timestamptz;
  v_freeze_days int;
  v_frozen_until timestamptz;
BEGIN
  -- Only process when subscription becomes active
  IF NEW.status != 'active' OR OLD.status = 'active' THEN
    RETURN NEW;
  END IF;

  -- Get freeze period from settings
  SELECT COALESCE((value->>'days')::int, 14)
  INTO v_freeze_days
  FROM mlm_settings
  WHERE key = 'commission_freeze_period';

  v_frozen_until := NOW() + (v_freeze_days || ' days')::interval;
  v_current_user_id := NEW.user_id;

  -- Walk up the sponsor chain for 5 levels (S1 structure)
  WHILE v_level < 5 LOOP
    -- Get sponsor of current user
    SELECT sponsor_id INTO v_sponsor_id
    FROM profiles
    WHERE id = v_current_user_id;

    -- No more sponsors in chain
    IF v_sponsor_id IS NULL THEN
      EXIT;
    END IF;

    v_level := v_level + 1;

    -- Get sponsor's subscription status and activation info
    SELECT subscription_status, COALESCE(monthly_activation_completed, false), activation_due_from
    INTO v_sponsor_subscription_status, v_sponsor_monthly_activation, v_sponsor_activation_due_from
    FROM profiles
    WHERE id = v_sponsor_id;

    -- Sponsor eligible: active subscription AND (first month OR activation completed)
    IF v_sponsor_subscription_status = 'active' 
       AND (v_sponsor_activation_due_from > NOW() OR v_sponsor_monthly_activation = true) THEN
      
      -- Get commission percent for this level
      SELECT percent INTO v_percent
      FROM commission_plan_levels
      WHERE structure_type = 'secondary' AND level = v_level;

      IF v_percent IS NOT NULL AND v_percent > 0 THEN
        v_commission_cents := ROUND(NEW.amount_kzt * v_percent / 100);

        IF v_commission_cents > 0 THEN
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
            v_commission_cents,
            'KZT',
            'frozen',
            NEW.id,
            'subscription_' || NEW.id || '_s1_level_' || v_level,
            v_level,
            'secondary',
            v_frozen_until,
            jsonb_build_object(
              'from_user_id', NEW.user_id,
              'subscription_id', NEW.id,
              'percent', v_percent,
              'structure', 'S1'
            )
          );
        END IF;
      END IF;
    END IF;

    v_current_user_id := v_sponsor_id;
  END LOOP;

  RETURN NEW;
END;
$$;

-- Update create_commission_transactions function
CREATE OR REPLACE FUNCTION public.create_commission_transactions()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sponsor_id uuid;
  v_current_user_id uuid;
  v_level int := 0;
  v_max_level int;
  v_percent numeric;
  v_commission_cents bigint;
  v_sponsor_subscription_status text;
  v_sponsor_monthly_activation boolean;
  v_sponsor_activation_due_from timestamptz;
  v_freeze_days int;
  v_frozen_until timestamptz;
BEGIN
  -- Only process when order becomes paid
  IF NEW.status != 'paid' OR OLD.status = 'paid' THEN
    RETURN NEW;
  END IF;

  -- Skip if no user
  IF NEW.user_id IS NULL THEN
    RETURN NEW;
  END IF;

  -- Get freeze period and max level from settings
  SELECT COALESCE((value->>'days')::int, 14)
  INTO v_freeze_days
  FROM mlm_settings
  WHERE key = 'commission_freeze_period';

  SELECT COALESCE(MAX(level), 10)
  INTO v_max_level
  FROM commission_plan_levels
  WHERE structure_type = 'primary';

  v_frozen_until := NOW() + (v_freeze_days || ' days')::interval;
  v_current_user_id := NEW.user_id;

  -- Walk up the sponsor chain
  WHILE v_level < v_max_level LOOP
    -- Get sponsor of current user
    SELECT sponsor_id INTO v_sponsor_id
    FROM profiles
    WHERE id = v_current_user_id;

    -- No more sponsors in chain
    IF v_sponsor_id IS NULL THEN
      EXIT;
    END IF;

    v_level := v_level + 1;

    -- Get sponsor's subscription status and activation info
    SELECT subscription_status, COALESCE(monthly_activation_completed, false), activation_due_from
    INTO v_sponsor_subscription_status, v_sponsor_monthly_activation, v_sponsor_activation_due_from
    FROM profiles
    WHERE id = v_sponsor_id;

    -- Sponsor eligible: active subscription AND (first month OR activation completed)
    IF v_sponsor_subscription_status = 'active' 
       AND (v_sponsor_activation_due_from > NOW() OR v_sponsor_monthly_activation = true) THEN
      
      -- Get commission percent for this level
      SELECT percent INTO v_percent
      FROM commission_plan_levels
      WHERE structure_type = 'primary' AND level = v_level;

      IF v_percent IS NOT NULL AND v_percent > 0 THEN
        v_commission_cents := ROUND(NEW.total_kzt * v_percent / 100);

        IF v_commission_cents > 0 THEN
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
            v_commission_cents,
            'KZT',
            'frozen',
            NEW.id,
            'order_' || NEW.id || '_p_level_' || v_level,
            v_level,
            'primary',
            v_frozen_until,
            jsonb_build_object(
              'from_user_id', NEW.user_id,
              'order_id', NEW.id,
              'percent', v_percent,
              'structure', 'P1-P10'
            )
          );
        END IF;
      END IF;
    END IF;

    v_current_user_id := v_sponsor_id;
  END LOOP;

  RETURN NEW;
END;
$$;