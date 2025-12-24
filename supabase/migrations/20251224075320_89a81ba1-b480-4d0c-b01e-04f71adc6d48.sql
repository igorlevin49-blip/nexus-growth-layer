
-- ============================================================
-- COMPREHENSIVE FIX: Duplicate triggers and unique constraint errors
-- ============================================================

-- 1. DROP ALL DUPLICATE TRIGGERS ON subscriptions
DROP TRIGGER IF EXISTS award_s1_on_subscription_paid ON public.subscriptions;
DROP TRIGGER IF EXISTS trg_award_s1_subscription_commission ON public.subscriptions;
DROP TRIGGER IF EXISTS trigger_award_s1_subscription_commission ON public.subscriptions;
DROP TRIGGER IF EXISTS award_s1_subscription_commission_trigger ON public.subscriptions;

-- 2. DROP ALL DUPLICATE TRIGGERS ON orders
DROP TRIGGER IF EXISTS trg_create_commission_transactions ON public.orders;
DROP TRIGGER IF EXISTS trigger_create_commission_transactions ON public.orders;
DROP TRIGGER IF EXISTS create_commission_transactions_trigger ON public.orders;
DROP TRIGGER IF EXISTS award_commissions_on_order_paid ON public.orders;

-- 3. DROP old backfill function to recreate with different return type
DROP FUNCTION IF EXISTS public.backfill_missing_s1_commissions(uuid, integer);

-- 4. RECREATE award_s1_subscription_commission WITH:
--    - Unique source_ref per subscription + level
--    - ON CONFLICT DO NOTHING for idempotency
--    - Correct status check (active)
CREATE OR REPLACE FUNCTION public.award_s1_subscription_commission()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sponsor_id uuid;
  v_current_user_id uuid;
  v_level integer := 0;
  v_max_level integer := 5;
  v_percent numeric;
  v_amount_cents integer;
  v_commission_cents integer;
  v_frozen_until timestamptz;
  v_sponsor_active boolean;
  v_sponsor_activated boolean;
BEGIN
  -- Only trigger when status changes TO 'active'
  IF NEW.status != 'active' OR (OLD IS NOT NULL AND OLD.status = 'active') THEN
    RETURN NEW;
  END IF;

  -- Skip test subscriptions
  IF NEW.is_test = true THEN
    RETURN NEW;
  END IF;

  -- Skip marketing free access
  IF NEW.is_marketing_free_access = true THEN
    RETURN NEW;
  END IF;

  v_amount_cents := NEW.amount_kzt;
  v_frozen_until := now() + interval '14 days';
  v_current_user_id := NEW.user_id;

  -- Get sponsor of the subscriber
  SELECT sponsor_id INTO v_sponsor_id
  FROM public.profiles
  WHERE id = v_current_user_id;

  -- Walk up the sponsor chain
  WHILE v_sponsor_id IS NOT NULL AND v_level < v_max_level LOOP
    v_level := v_level + 1;

    -- Check sponsor's subscription status
    SELECT 
      (subscription_status = 'active'),
      monthly_activation_completed
    INTO v_sponsor_active, v_sponsor_activated
    FROM public.profiles
    WHERE id = v_sponsor_id;

    -- Only award if sponsor is active and has monthly activation
    IF v_sponsor_active AND v_sponsor_activated THEN
      -- Get commission percent for this level (S1 = structure_type 1)
      SELECT percent INTO v_percent
      FROM public.mlm_commission_rules
      WHERE structure_type = 1
        AND level = v_level
        AND is_active = true
      ORDER BY effective_from DESC
      LIMIT 1;

      IF v_percent IS NOT NULL AND v_percent > 0 THEN
        v_commission_cents := ROUND(v_amount_cents * v_percent / 100);

        IF v_commission_cents > 0 THEN
          -- Insert with unique source_ref and ON CONFLICT DO NOTHING
          INSERT INTO public.transactions (
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
            'primary',
            v_frozen_until,
            jsonb_build_object(
              'source_type', 'subscription',
              'source_user_id', NEW.user_id,
              'percent', v_percent,
              'base_amount', v_amount_cents
            )
          )
          ON CONFLICT ON CONSTRAINT unique_source_ref DO NOTHING;
        END IF;
      END IF;
    END IF;

    -- Move to next sponsor
    SELECT sponsor_id INTO v_sponsor_id
    FROM public.profiles
    WHERE id = v_sponsor_id;
  END LOOP;

  RETURN NEW;
END;
$$;

-- 5. CREATE SINGLE TRIGGER for subscriptions with proper WHEN clause
CREATE TRIGGER trg_award_s1_subscription_commission
  AFTER UPDATE OF status ON public.subscriptions
  FOR EACH ROW
  WHEN (OLD.status IS DISTINCT FROM NEW.status AND NEW.status = 'active')
  EXECUTE FUNCTION public.award_s1_subscription_commission();

-- 6. RECREATE create_commission_transactions WITH ON CONFLICT DO NOTHING
CREATE OR REPLACE FUNCTION public.create_commission_transactions()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sponsor_id uuid;
  v_current_user_id uuid;
  v_level integer := 0;
  v_max_level integer := 5;
  v_percent numeric;
  v_amount_cents integer;
  v_commission_cents integer;
  v_frozen_until timestamptz;
  v_sponsor_active boolean;
  v_sponsor_activated boolean;
BEGIN
  -- Only trigger when status changes TO 'paid'
  IF NEW.status != 'paid' OR (OLD IS NOT NULL AND OLD.status = 'paid') THEN
    RETURN NEW;
  END IF;

  -- Skip test orders
  IF NEW.is_test = true THEN
    RETURN NEW;
  END IF;

  v_amount_cents := NEW.total_kzt;
  v_frozen_until := now() + interval '14 days';
  v_current_user_id := NEW.user_id;

  -- Get sponsor of the buyer
  SELECT sponsor_id INTO v_sponsor_id
  FROM public.profiles
  WHERE id = v_current_user_id;

  -- Walk up the sponsor chain (P-structure = structure_type 2)
  WHILE v_sponsor_id IS NOT NULL AND v_level < v_max_level LOOP
    v_level := v_level + 1;

    -- Check sponsor's subscription and activation
    SELECT 
      (subscription_status = 'active'),
      monthly_activation_completed
    INTO v_sponsor_active, v_sponsor_activated
    FROM public.profiles
    WHERE id = v_sponsor_id;

    -- Only award if sponsor qualifies
    IF v_sponsor_active AND v_sponsor_activated THEN
      -- Get commission percent for this level (P-structure = 2)
      SELECT percent INTO v_percent
      FROM public.mlm_commission_rules
      WHERE structure_type = 2
        AND level = v_level
        AND is_active = true
      ORDER BY effective_from DESC
      LIMIT 1;

      IF v_percent IS NOT NULL AND v_percent > 0 THEN
        v_commission_cents := ROUND(v_amount_cents * v_percent / 100);

        IF v_commission_cents > 0 THEN
          -- Insert with unique source_ref and ON CONFLICT DO NOTHING
          INSERT INTO public.transactions (
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
            'secondary',
            v_frozen_until,
            jsonb_build_object(
              'source_type', 'order',
              'source_user_id', NEW.user_id,
              'percent', v_percent,
              'base_amount', v_amount_cents
            )
          )
          ON CONFLICT ON CONSTRAINT unique_source_ref DO NOTHING;
        END IF;
      END IF;
    END IF;

    -- Move to next sponsor
    SELECT sponsor_id INTO v_sponsor_id
    FROM public.profiles
    WHERE id = v_sponsor_id;
  END LOOP;

  RETURN NEW;
END;
$$;

-- 7. CREATE SINGLE TRIGGER for orders with proper WHEN clause
CREATE TRIGGER trg_create_commission_transactions
  AFTER UPDATE OF status ON public.orders
  FOR EACH ROW
  WHEN (OLD.status IS DISTINCT FROM NEW.status AND NEW.status = 'paid')
  EXECUTE FUNCTION public.create_commission_transactions();

-- 8. CREATE backfill function with new source_ref format
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
  v_subscription record;
  v_sponsor_id uuid;
  v_current_user_id uuid;
  v_level integer;
  v_max_level integer := 5;
  v_percent numeric;
  v_amount_cents integer;
  v_commission_cents integer;
  v_frozen_until timestamptz;
  v_sponsor_active boolean;
  v_sponsor_activated boolean;
  v_total_commissions integer := 0;
  v_processed_subscriptions integer := 0;
  v_skipped_subscriptions integer := 0;
  v_source_ref text;
BEGIN
  -- Verify admin
  IF NOT EXISTS (
    SELECT 1 FROM public.user_roles 
    WHERE user_id = p_admin_id AND role IN ('admin', 'superadmin')
  ) THEN
    RETURN json_build_object('success', false, 'error', 'Unauthorized');
  END IF;

  -- Process active subscriptions from the last N days
  FOR v_subscription IN
    SELECT s.id, s.user_id, s.amount_kzt, s.paid_at
    FROM public.subscriptions s
    WHERE s.status = 'active'
      AND s.paid_at >= (now() - (p_days_back || ' days')::interval)
      AND s.is_test IS NOT TRUE
      AND s.is_marketing_free_access IS NOT TRUE
    ORDER BY s.paid_at ASC
  LOOP
    v_current_user_id := v_subscription.user_id;
    v_amount_cents := v_subscription.amount_kzt;
    v_frozen_until := COALESCE(v_subscription.paid_at, now()) + interval '14 days';
    v_level := 0;

    -- Get sponsor
    SELECT sponsor_id INTO v_sponsor_id
    FROM public.profiles
    WHERE id = v_current_user_id;

    IF v_sponsor_id IS NULL THEN
      v_skipped_subscriptions := v_skipped_subscriptions + 1;
      CONTINUE;
    END IF;

    v_processed_subscriptions := v_processed_subscriptions + 1;

    -- Walk up sponsor chain
    WHILE v_sponsor_id IS NOT NULL AND v_level < v_max_level LOOP
      v_level := v_level + 1;
      v_source_ref := 'subscription_' || v_subscription.id || '_s1_level_' || v_level;

      -- Check if commission already exists
      IF EXISTS (
        SELECT 1 FROM public.transactions 
        WHERE source_ref = v_source_ref
      ) THEN
        -- Move to next sponsor
        SELECT sponsor_id INTO v_sponsor_id
        FROM public.profiles
        WHERE id = v_sponsor_id;
        CONTINUE;
      END IF;

      -- Check sponsor qualifications
      SELECT 
        (subscription_status = 'active'),
        monthly_activation_completed
      INTO v_sponsor_active, v_sponsor_activated
      FROM public.profiles
      WHERE id = v_sponsor_id;

      IF v_sponsor_active AND v_sponsor_activated THEN
        SELECT percent INTO v_percent
        FROM public.mlm_commission_rules
        WHERE structure_type = 1
          AND level = v_level
          AND is_active = true
        ORDER BY effective_from DESC
        LIMIT 1;

        IF v_percent IS NOT NULL AND v_percent > 0 THEN
          v_commission_cents := ROUND(v_amount_cents * v_percent / 100);

          IF v_commission_cents > 0 THEN
            INSERT INTO public.transactions (
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
              v_subscription.id,
              v_source_ref,
              v_level,
              'primary',
              v_frozen_until,
              jsonb_build_object(
                'source_type', 'subscription',
                'source_user_id', v_subscription.user_id,
                'percent', v_percent,
                'base_amount', v_amount_cents,
                'backfilled', true,
                'backfilled_at', now()
              )
            )
            ON CONFLICT ON CONSTRAINT unique_source_ref DO NOTHING;

            v_total_commissions := v_total_commissions + 1;
          END IF;
        END IF;
      END IF;

      -- Move to next sponsor
      SELECT sponsor_id INTO v_sponsor_id
      FROM public.profiles
      WHERE id = v_sponsor_id;
    END LOOP;
  END LOOP;

  -- Log admin action
  INSERT INTO public.admin_actions (
    admin_id,
    action_type,
    target_type,
    metadata
  ) VALUES (
    p_admin_id,
    'backfill_s1_commissions',
    'system',
    jsonb_build_object(
      'days_back', p_days_back,
      'processed_subscriptions', v_processed_subscriptions,
      'skipped_subscriptions', v_skipped_subscriptions,
      'total_commissions_created', v_total_commissions
    )
  );

  RETURN json_build_object(
    'success', true,
    'processed_subscriptions', v_processed_subscriptions,
    'skipped_subscriptions', v_skipped_subscriptions,
    'total_commissions_created', v_total_commissions
  );
END;
$$;
