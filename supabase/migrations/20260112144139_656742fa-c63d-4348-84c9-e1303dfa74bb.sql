-- Этап 1: Удаление 88 неправильных backfill транзакций
DELETE FROM transactions 
WHERE type = 'commission' 
  AND created_at >= '2026-01-12'
  AND payload->>'backfill' = 'true';

-- Этап 2: Исправление функции award_s1_subscription_commission
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
  v_commission_kzt numeric;
  v_amount_kzt numeric;
  v_subscription_id uuid;
  v_subscription_user_id uuid;
  v_freeze_months integer;
BEGIN
  IF NEW.type != 'subscription' OR NEW.status != 'completed' THEN
    RETURN NEW;
  END IF;

  v_subscription_id := (NEW.payload->>'subscription_id')::uuid;
  IF v_subscription_id IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT user_id INTO v_subscription_user_id
  FROM subscriptions
  WHERE id = v_subscription_id;

  IF v_subscription_user_id IS NULL THEN
    RETURN NEW;
  END IF;

  v_amount_kzt := NEW.amount_cents;

  SELECT COALESCE((value->>'months')::integer, 1) INTO v_freeze_months
  FROM mlm_settings
  WHERE key = 'commission_freeze_period';

  v_current_user_id := v_subscription_user_id;

  WHILE v_level < v_max_level LOOP
    SELECT sponsor_id INTO v_sponsor_id
    FROM profiles
    WHERE id = v_current_user_id;

    IF v_sponsor_id IS NULL THEN
      EXIT;
    END IF;

    v_level := v_level + 1;

    SELECT percent INTO v_percent
    FROM mlm_rules
    WHERE structure = 'S1' AND level = v_level;

    IF v_percent IS NOT NULL AND v_percent > 0 THEN
      -- ИСПРАВЛЕНИЕ: деление на 100
      v_commission_kzt := ROUND(v_amount_kzt * v_percent / 100);

      INSERT INTO transactions (
        user_id, type, amount_cents, currency, status, payload, unfreeze_at
      ) VALUES (
        v_sponsor_id,
        'commission',
        v_commission_kzt,
        'KZT',
        'frozen',
        jsonb_build_object(
          'source', 'subscription',
          'subscription_id', v_subscription_id,
          'from_user_id', v_subscription_user_id,
          'level', v_level,
          'percent', v_percent,
          'structure', 'S1',
          'original_transaction_id', NEW.id
        ),
        NOW() + (v_freeze_months || ' months')::interval
      );

      INSERT INTO activity_log (user_id, action, details)
      VALUES (
        v_sponsor_id,
        'commission_awarded',
        jsonb_build_object(
          'amount_kzt', v_commission_kzt,
          'level', v_level,
          'structure', 'S1',
          'from_user_id', v_subscription_user_id,
          'subscription_id', v_subscription_id
        )
      );
    END IF;

    v_current_user_id := v_sponsor_id;
  END LOOP;

  RETURN NEW;
END;
$$;

-- Этап 3: DROP и пересоздание backfill функции
DROP FUNCTION IF EXISTS public.backfill_missing_s1_commissions(uuid, integer);

CREATE FUNCTION public.backfill_missing_s1_commissions(
  p_admin_id uuid,
  p_days_back integer DEFAULT 30
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_subscription RECORD;
  v_sponsor_id uuid;
  v_current_user_id uuid;
  v_level integer;
  v_max_level integer := 5;
  v_percent numeric;
  v_commission_kzt numeric;
  v_freeze_months integer;
  v_subscriptions_processed integer := 0;
  v_commissions_created integer := 0;
  v_commissions_skipped integer := 0;
  v_existing_count integer;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM user_roles 
    WHERE user_id = p_admin_id AND role = 'admin'
  ) THEN
    RAISE EXCEPTION 'Access denied: admin role required';
  END IF;

  SELECT COALESCE((value->>'months')::integer, 1) INTO v_freeze_months
  FROM mlm_settings
  WHERE key = 'commission_freeze_period';

  FOR v_subscription IN
    SELECT 
      s.id as subscription_id,
      s.user_id,
      s.amount_kzt,
      s.paid_at
    FROM subscriptions s
    WHERE s.status = 'active'
      AND s.paid_at IS NOT NULL
      AND s.paid_at >= NOW() - (p_days_back || ' days')::interval
    ORDER BY s.paid_at
  LOOP
    v_subscriptions_processed := v_subscriptions_processed + 1;
    v_current_user_id := v_subscription.user_id;
    v_level := 0;

    WHILE v_level < v_max_level LOOP
      SELECT sponsor_id INTO v_sponsor_id
      FROM profiles
      WHERE id = v_current_user_id;

      IF v_sponsor_id IS NULL THEN
        EXIT;
      END IF;

      v_level := v_level + 1;

      SELECT COUNT(*) INTO v_existing_count
      FROM transactions
      WHERE type = 'commission'
        AND user_id = v_sponsor_id
        AND payload->>'subscription_id' = v_subscription.subscription_id::text
        AND payload->>'level' = v_level::text;

      IF v_existing_count > 0 THEN
        v_commissions_skipped := v_commissions_skipped + 1;
        v_current_user_id := v_sponsor_id;
        CONTINUE;
      END IF;

      SELECT percent INTO v_percent
      FROM mlm_rules
      WHERE structure = 'S1' AND level = v_level;

      IF v_percent IS NOT NULL AND v_percent > 0 THEN
        -- ИСПРАВЛЕНИЕ: деление на 100
        v_commission_kzt := ROUND(v_subscription.amount_kzt * v_percent / 100);

        INSERT INTO transactions (
          user_id, type, amount_cents, currency, status, payload, unfreeze_at
        ) VALUES (
          v_sponsor_id,
          'commission',
          v_commission_kzt,
          'KZT',
          'frozen',
          jsonb_build_object(
            'source', 'subscription',
            'subscription_id', v_subscription.subscription_id,
            'from_user_id', v_subscription.user_id,
            'level', v_level,
            'percent', v_percent,
            'structure', 'S1',
            'backfill', true,
            'backfill_date', NOW()
          ),
          v_subscription.paid_at + (v_freeze_months || ' months')::interval
        );

        v_commissions_created := v_commissions_created + 1;
      END IF;

      v_current_user_id := v_sponsor_id;
    END LOOP;
  END LOOP;

  RETURN jsonb_build_object(
    'success', true,
    'subscriptions_processed', v_subscriptions_processed,
    'commissions_created', v_commissions_created,
    'commissions_skipped', v_commissions_skipped
  );
END;
$$;