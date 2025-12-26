-- Шаг 1: Удалить 19 ошибочных USD транзакций
DELETE FROM transactions 
WHERE currency = 'USD' 
  AND type = 'commission' 
  AND amount_cents = 1000;

-- Шаг 2: Исправить функцию recalculate_all_s1_commissions
CREATE OR REPLACE FUNCTION public.recalculate_all_s1_commissions(p_admin_id uuid)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_subscription RECORD;
  v_sponsor_id uuid;
  v_commission_percent numeric;
  v_commission_amount integer;
  v_existing_commission uuid;
  v_processed integer := 0;
  v_created integer := 0;
  v_skipped integer := 0;
  v_freeze_days integer;
  v_frozen_until timestamptz;
BEGIN
  -- Check admin role
  IF NOT EXISTS (
    SELECT 1 FROM user_roles 
    WHERE user_id = p_admin_id 
    AND role IN ('admin', 'superadmin')
  ) THEN
    RETURN json_build_object('success', false, 'error', 'Not authorized');
  END IF;

  -- Get freeze period from settings
  SELECT COALESCE((value::text)::integer, 14)
  INTO v_freeze_days
  FROM mlm_settings
  WHERE key = 'commission_freeze_days';

  -- Get commission percent for S1 level 1
  SELECT percent INTO v_commission_percent
  FROM mlm_commission_rules
  WHERE structure_type = 1 AND level = 1 AND is_active = true
  LIMIT 1;

  IF v_commission_percent IS NULL THEN
    v_commission_percent := 10; -- Default 10%
  END IF;

  -- Process all paid subscriptions
  FOR v_subscription IN
    SELECT s.id, s.user_id, s.amount_kzt, s.paid_at
    FROM subscriptions s
    WHERE s.status = 'active'
      AND s.paid_at IS NOT NULL
      AND (s.is_archived IS NULL OR s.is_archived = false)
      AND (s.is_marketing_free_access IS NULL OR s.is_marketing_free_access = false)
    ORDER BY s.paid_at
  LOOP
    v_processed := v_processed + 1;

    -- Get sponsor
    SELECT sponsor_id INTO v_sponsor_id
    FROM profiles
    WHERE id = v_subscription.user_id;

    IF v_sponsor_id IS NULL THEN
      v_skipped := v_skipped + 1;
      CONTINUE;
    END IF;

    -- Check if commission already exists
    SELECT id INTO v_existing_commission
    FROM transactions
    WHERE source_ref = v_subscription.id::text
      AND user_id = v_sponsor_id
      AND type = 'commission'
      AND structure_type = 'primary'
      AND level = 1
    LIMIT 1;

    IF v_existing_commission IS NOT NULL THEN
      v_skipped := v_skipped + 1;
      CONTINUE;
    END IF;

    -- Calculate commission: amount_kzt * percent / 100
    v_commission_amount := ROUND(v_subscription.amount_kzt * v_commission_percent / 100)::integer;

    IF v_commission_amount <= 0 THEN
      v_skipped := v_skipped + 1;
      CONTINUE;
    END IF;

    -- Calculate freeze date
    v_frozen_until := v_subscription.paid_at + (v_freeze_days || ' days')::interval;

    -- Create commission transaction with currency = 'KZT'
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
      payload,
      created_at
    ) VALUES (
      v_sponsor_id,
      'commission',
      v_commission_amount,
      'KZT',
      CASE WHEN v_frozen_until > now() THEN 'frozen' ELSE 'completed' END,
      'primary',
      1,
      v_subscription.user_id,
      v_subscription.id::text,
      CASE WHEN v_frozen_until > now() THEN v_frozen_until ELSE NULL END,
      jsonb_build_object(
        'subscription_id', v_subscription.id,
        'subscriber_id', v_subscription.user_id,
        'percent', v_commission_percent,
        'recalculated', true,
        'recalculated_at', now()
      ),
      v_subscription.paid_at
    );

    v_created := v_created + 1;
  END LOOP;

  -- Log admin action
  INSERT INTO admin_audit (admin_id, action_type, target_type, target_id, metadata)
  VALUES (
    p_admin_id,
    'recalculate_s1_commissions',
    'system',
    'all',
    jsonb_build_object(
      'subscriptions_processed', v_processed,
      'commissions_created', v_created,
      'commissions_skipped', v_skipped
    )
  );

  RETURN json_build_object(
    'success', true,
    'subscriptions_processed', v_processed,
    'commissions_created', v_created,
    'commissions_skipped', v_skipped
  );
END;
$$;

-- Шаг 3: Исправить get_user_balance - добавить фильтр currency = 'KZT'
CREATE OR REPLACE FUNCTION public.get_user_balance(p_user_id uuid)
RETURNS TABLE(
  user_id uuid,
  available_cents bigint,
  frozen_cents bigint,
  pending_cents bigint,
  withdrawn_cents bigint,
  updated_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    p_user_id as user_id,
    -- Available: completed commissions + bonuses + adjustments - completed withdrawals
    COALESCE(SUM(CASE 
      WHEN t.type IN ('commission', 'bonus') AND t.status = 'completed' THEN t.amount_cents
      WHEN t.type = 'adjustment' AND t.status = 'completed' THEN t.amount_cents
      WHEN t.type = 'withdrawal' AND t.status = 'completed' THEN -t.amount_cents
      ELSE 0
    END), 0)::bigint as available_cents,
    -- Frozen: frozen commissions
    COALESCE(SUM(CASE 
      WHEN t.type IN ('commission', 'bonus') AND t.status = 'frozen' THEN t.amount_cents
      ELSE 0
    END), 0)::bigint as frozen_cents,
    -- Pending: pending withdrawals
    COALESCE(SUM(CASE 
      WHEN t.type = 'withdrawal' AND t.status IN ('pending', 'processing') THEN t.amount_cents
      ELSE 0
    END), 0)::bigint as pending_cents,
    -- Withdrawn: completed withdrawals total
    COALESCE(SUM(CASE 
      WHEN t.type = 'withdrawal' AND t.status = 'completed' THEN t.amount_cents
      ELSE 0
    END), 0)::bigint as withdrawn_cents,
    now() as updated_at
  FROM transactions t
  WHERE t.user_id = p_user_id
    AND t.currency = 'KZT'
    AND (t.is_archived IS NULL OR t.is_archived = false);
END;
$$;

-- Шаг 4: Исправить get_all_user_balances - добавить фильтр currency = 'KZT'
CREATE OR REPLACE FUNCTION public.get_all_user_balances()
RETURNS TABLE(
  user_id uuid,
  available_cents bigint,
  frozen_cents bigint,
  pending_cents bigint,
  withdrawn_cents bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    t.user_id,
    COALESCE(SUM(CASE 
      WHEN t.type IN ('commission', 'bonus') AND t.status = 'completed' THEN t.amount_cents
      WHEN t.type = 'adjustment' AND t.status = 'completed' THEN t.amount_cents
      WHEN t.type = 'withdrawal' AND t.status = 'completed' THEN -t.amount_cents
      ELSE 0
    END), 0)::bigint as available_cents,
    COALESCE(SUM(CASE 
      WHEN t.type IN ('commission', 'bonus') AND t.status = 'frozen' THEN t.amount_cents
      ELSE 0
    END), 0)::bigint as frozen_cents,
    COALESCE(SUM(CASE 
      WHEN t.type = 'withdrawal' AND t.status IN ('pending', 'processing') THEN t.amount_cents
      ELSE 0
    END), 0)::bigint as pending_cents,
    COALESCE(SUM(CASE 
      WHEN t.type = 'withdrawal' AND t.status = 'completed' THEN t.amount_cents
      ELSE 0
    END), 0)::bigint as withdrawn_cents
  FROM transactions t
  WHERE t.currency = 'KZT'
    AND (t.is_archived IS NULL OR t.is_archived = false)
  GROUP BY t.user_id;
END;
$$;