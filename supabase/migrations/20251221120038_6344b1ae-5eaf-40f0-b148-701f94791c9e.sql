
-- Fix commission triggers to allow first-month subscribers to receive commissions
-- They should not require monthly_activation_completed during their first month (when activation_due_from > NOW())

-- Update award_s1_subscription_commission function
CREATE OR REPLACE FUNCTION public.award_s1_subscription_commission()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  v_subscriber_id uuid;
  v_amount_kzt numeric;
  v_sponsor_id uuid;
  v_current_sponsor_id uuid;
  v_commission_percent numeric;
  v_commission_amount numeric;
  v_level int := 1;
  v_max_levels int := 5;
  v_sponsor_subscription_status text;
  v_sponsor_monthly_activation boolean;
  v_sponsor_activation_due_from timestamptz;
  v_freeze_days int := 14;
  v_frozen_until timestamptz;
  v_is_test boolean;
  v_is_marketing_free boolean;
BEGIN
  -- Only process when subscription becomes active
  IF NEW.status != 'active' OR (OLD IS NOT NULL AND OLD.status = 'active') THEN
    RETURN NEW;
  END IF;

  v_subscriber_id := NEW.user_id;
  v_amount_kzt := NEW.amount_kzt;
  v_is_test := COALESCE(NEW.is_test, false);
  v_is_marketing_free := COALESCE(NEW.is_marketing_free_access, false);
  
  -- Skip commission for marketing free access subscriptions
  IF v_is_marketing_free THEN
    INSERT INTO activity_log (user_id, type, payload)
    VALUES (v_subscriber_id, 'commission_skipped', jsonb_build_object(
      'reason', 'marketing_free_access',
      'subscription_id', NEW.id
    ));
    RETURN NEW;
  END IF;

  -- Get freeze days from settings
  SELECT COALESCE((value::text)::int, 14)
  INTO v_freeze_days
  FROM mlm_settings
  WHERE key = 'commission_freeze_days';
  
  v_frozen_until := NOW() + (v_freeze_days || ' days')::interval;

  -- Get first sponsor from profiles
  SELECT sponsor_id INTO v_sponsor_id
  FROM profiles
  WHERE id = v_subscriber_id;

  IF v_sponsor_id IS NULL THEN
    INSERT INTO activity_log (user_id, type, payload)
    VALUES (v_subscriber_id, 'commission_skipped', jsonb_build_object(
      'reason', 'no_sponsor',
      'subscription_id', NEW.id
    ));
    RETURN NEW;
  END IF;

  v_current_sponsor_id := v_sponsor_id;

  -- Loop through sponsor chain up to max levels
  WHILE v_current_sponsor_id IS NOT NULL AND v_level <= v_max_levels LOOP
    -- Get commission percent for this level
    SELECT percent INTO v_commission_percent
    FROM mlm_commission_rules
    WHERE structure_type = 1 
      AND level = v_level 
      AND is_active = true
    ORDER BY effective_from DESC
    LIMIT 1;

    IF v_commission_percent IS NULL THEN
      v_level := v_level + 1;
      SELECT sponsor_id INTO v_current_sponsor_id
      FROM profiles
      WHERE id = v_current_sponsor_id;
      CONTINUE;
    END IF;

    -- Check sponsor eligibility: active subscription AND (first month OR monthly activation completed)
    SELECT subscription_status, COALESCE(monthly_activation_completed, false), activation_due_from
    INTO v_sponsor_subscription_status, v_sponsor_monthly_activation, v_sponsor_activation_due_from
    FROM profiles
    WHERE id = v_current_sponsor_id;

    -- Eligible if: active subscription AND (first month when activation_due_from > NOW() OR monthly activation completed)
    IF v_sponsor_subscription_status = 'active' 
       AND (v_sponsor_activation_due_from > NOW() OR v_sponsor_monthly_activation = true) THEN
      
      v_commission_amount := ROUND((v_amount_kzt * v_commission_percent / 100) * 100);

      -- Create frozen commission transaction
      INSERT INTO transactions (
        user_id,
        type,
        amount_cents,
        currency,
        status,
        frozen_until,
        source_id,
        source_ref,
        level,
        structure_type,
        is_test,
        payload
      ) VALUES (
        v_current_sponsor_id,
        'commission',
        v_commission_amount::bigint,
        'KZT',
        'frozen',
        v_frozen_until,
        NEW.id,
        'subscription',
        v_level,
        'primary',
        v_is_test,
        jsonb_build_object(
          'subscription_id', NEW.id,
          'subscriber_id', v_subscriber_id,
          'percent', v_commission_percent,
          'base_amount', v_amount_kzt,
          'structure_type', 1
        )
      );

      INSERT INTO activity_log (user_id, type, payload)
      VALUES (v_current_sponsor_id, 'commission_earned', jsonb_build_object(
        'amount', v_commission_amount,
        'currency', 'KZT',
        'level', v_level,
        'structure_type', 1,
        'source_type', 'subscription',
        'source_id', NEW.id,
        'subscriber_id', v_subscriber_id,
        'frozen_until', v_frozen_until
      ));
    ELSE
      -- Log why commission was skipped
      INSERT INTO activity_log (user_id, type, payload)
      VALUES (v_current_sponsor_id, 'commission_skipped', jsonb_build_object(
        'reason', CASE 
          WHEN v_sponsor_subscription_status != 'active' THEN 'inactive_subscription'
          WHEN v_sponsor_activation_due_from IS NULL THEN 'activation_due_from_null'
          WHEN v_sponsor_activation_due_from <= NOW() AND v_sponsor_monthly_activation = false THEN 'monthly_activation_not_completed'
          ELSE 'unknown'
        END,
        'subscription_status', v_sponsor_subscription_status,
        'monthly_activation', v_sponsor_monthly_activation,
        'activation_due_from', v_sponsor_activation_due_from,
        'level', v_level,
        'subscription_id', NEW.id,
        'subscriber_id', v_subscriber_id
      ));
    END IF;

    v_level := v_level + 1;
    
    -- Get next sponsor in chain
    SELECT sponsor_id INTO v_current_sponsor_id
    FROM profiles
    WHERE id = v_current_sponsor_id;
  END LOOP;

  RETURN NEW;
END;
$$;

-- Update create_commission_transactions function for orders
CREATE OR REPLACE FUNCTION public.create_commission_transactions()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  v_buyer_id uuid;
  v_order_total_kzt numeric;
  v_sponsor_id uuid;
  v_current_sponsor_id uuid;
  v_commission_percent numeric;
  v_commission_amount numeric;
  v_level int := 1;
  v_max_levels int := 10;
  v_sponsor_subscription_status text;
  v_sponsor_monthly_activation boolean;
  v_sponsor_activation_due_from timestamptz;
  v_freeze_days int := 14;
  v_frozen_until timestamptz;
  v_is_test boolean;
BEGIN
  -- Only process when order becomes paid
  IF NEW.status != 'paid' OR (OLD IS NOT NULL AND OLD.status = 'paid') THEN
    RETURN NEW;
  END IF;

  v_buyer_id := NEW.user_id;
  v_order_total_kzt := NEW.total_kzt;
  v_is_test := COALESCE(NEW.is_test, false);

  -- Get freeze days from settings
  SELECT COALESCE((value::text)::int, 14)
  INTO v_freeze_days
  FROM mlm_settings
  WHERE key = 'commission_freeze_days';
  
  v_frozen_until := NOW() + (v_freeze_days || ' days')::interval;

  -- Get first sponsor from profiles
  SELECT sponsor_id INTO v_sponsor_id
  FROM profiles
  WHERE id = v_buyer_id;

  IF v_sponsor_id IS NULL THEN
    INSERT INTO activity_log (user_id, type, payload)
    VALUES (v_buyer_id, 'commission_skipped', jsonb_build_object(
      'reason', 'no_sponsor',
      'order_id', NEW.id
    ));
    RETURN NEW;
  END IF;

  v_current_sponsor_id := v_sponsor_id;

  -- Loop through sponsor chain up to max levels
  WHILE v_current_sponsor_id IS NOT NULL AND v_level <= v_max_levels LOOP
    -- Get commission percent for this level (structure_type = 2 for orders/products)
    SELECT percent INTO v_commission_percent
    FROM mlm_commission_rules
    WHERE structure_type = 2 
      AND level = v_level 
      AND is_active = true
    ORDER BY effective_from DESC
    LIMIT 1;

    IF v_commission_percent IS NULL THEN
      v_level := v_level + 1;
      SELECT sponsor_id INTO v_current_sponsor_id
      FROM profiles
      WHERE id = v_current_sponsor_id;
      CONTINUE;
    END IF;

    -- Check sponsor eligibility: active subscription AND (first month OR monthly activation completed)
    SELECT subscription_status, COALESCE(monthly_activation_completed, false), activation_due_from
    INTO v_sponsor_subscription_status, v_sponsor_monthly_activation, v_sponsor_activation_due_from
    FROM profiles
    WHERE id = v_current_sponsor_id;

    -- Eligible if: active subscription AND (first month when activation_due_from > NOW() OR monthly activation completed)
    IF v_sponsor_subscription_status = 'active' 
       AND (v_sponsor_activation_due_from > NOW() OR v_sponsor_monthly_activation = true) THEN
      
      v_commission_amount := ROUND((v_order_total_kzt * v_commission_percent / 100) * 100);

      -- Create frozen commission transaction
      INSERT INTO transactions (
        user_id,
        type,
        amount_cents,
        currency,
        status,
        frozen_until,
        source_id,
        source_ref,
        level,
        structure_type,
        is_test,
        payload
      ) VALUES (
        v_current_sponsor_id,
        'commission',
        v_commission_amount::bigint,
        'KZT',
        'frozen',
        v_frozen_until,
        NEW.id,
        'order',
        v_level,
        'secondary',
        v_is_test,
        jsonb_build_object(
          'order_id', NEW.id,
          'buyer_id', v_buyer_id,
          'percent', v_commission_percent,
          'base_amount', v_order_total_kzt,
          'structure_type', 2
        )
      );

      INSERT INTO activity_log (user_id, type, payload)
      VALUES (v_current_sponsor_id, 'commission_earned', jsonb_build_object(
        'amount', v_commission_amount,
        'currency', 'KZT',
        'level', v_level,
        'structure_type', 2,
        'source_type', 'order',
        'source_id', NEW.id,
        'buyer_id', v_buyer_id,
        'frozen_until', v_frozen_until
      ));
    ELSE
      -- Log why commission was skipped
      INSERT INTO activity_log (user_id, type, payload)
      VALUES (v_current_sponsor_id, 'commission_skipped', jsonb_build_object(
        'reason', CASE 
          WHEN v_sponsor_subscription_status != 'active' THEN 'inactive_subscription'
          WHEN v_sponsor_activation_due_from IS NULL THEN 'activation_due_from_null'
          WHEN v_sponsor_activation_due_from <= NOW() AND v_sponsor_monthly_activation = false THEN 'monthly_activation_not_completed'
          ELSE 'unknown'
        END,
        'subscription_status', v_sponsor_subscription_status,
        'monthly_activation', v_sponsor_monthly_activation,
        'activation_due_from', v_sponsor_activation_due_from,
        'level', v_level,
        'order_id', NEW.id,
        'buyer_id', v_buyer_id
      ));
    END IF;

    v_level := v_level + 1;
    
    -- Get next sponsor in chain
    SELECT sponsor_id INTO v_current_sponsor_id
    FROM profiles
    WHERE id = v_current_sponsor_id;
  END LOOP;

  RETURN NEW;
END;
$$;
