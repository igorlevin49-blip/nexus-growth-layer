
-- ============================================================================
-- УНИФИКАЦИЯ MLM-НАСТРОЕК: Шаг 2 - Создание новых функций
-- ============================================================================

-- ============================================================================
-- Функция award_s1_subscription_commission
-- ============================================================================
CREATE OR REPLACE FUNCTION public.award_s1_subscription_commission(
  p_subscriber_id uuid,
  p_subscription_amount numeric,
  p_subscription_id uuid,
  p_subscription_paid_at timestamp with time zone DEFAULT now()
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_current_sponsor_id uuid;
  v_level integer := 0;
  v_max_levels integer := 5;
  v_commission_rate numeric;
  v_commission_amount integer;
  v_freeze_days integer := 14;
  v_frozen_until timestamptz;
  v_commissions_created integer := 0;
  v_commissions_skipped integer := 0;
  v_unlock_levels jsonb;
  v_required_referrals integer;
  v_actual_referrals integer;
  v_sponsor_subscription_status text;
  v_is_marketing_free boolean := false;
BEGIN
  -- Проверяем маркетинговую подписку
  SELECT is_marketing_free_access INTO v_is_marketing_free
  FROM subscriptions WHERE id = p_subscription_id;
  
  IF v_is_marketing_free THEN
    RETURN json_build_object('success', true, 'message', 'Marketing free - no commissions', 'commissions_created', 0, 'commissions_skipped', 0);
  END IF;

  -- Настройки разблокировки
  SELECT value INTO v_unlock_levels FROM mlm_settings WHERE key = 'unlock_levels';
  IF v_unlock_levels IS NULL THEN v_unlock_levels := '{"l1": 0, "l2": 3, "l3": 5, "l4": 8, "l5": 10}'::jsonb; END IF;

  -- Период заморозки
  SELECT COALESCE((value->>'days')::integer, 14) INTO v_freeze_days FROM mlm_settings WHERE key = 'commission_freeze_period';

  -- Спонсор подписчика
  SELECT sponsor_id INTO v_current_sponsor_id FROM profiles WHERE id = p_subscriber_id;
  IF v_current_sponsor_id IS NULL THEN
    RETURN json_build_object('success', true, 'message', 'No sponsor', 'commissions_created', 0, 'commissions_skipped', 0);
  END IF;

  WHILE v_current_sponsor_id IS NOT NULL AND v_level < v_max_levels LOOP
    v_level := v_level + 1;

    -- Процент из mlm_commission_rules
    SELECT percent INTO v_commission_rate FROM mlm_commission_rules WHERE structure_type = 1 AND level = v_level AND is_active = true;
    IF v_commission_rate IS NULL OR v_commission_rate <= 0 THEN
      v_commissions_skipped := v_commissions_skipped + 1;
      SELECT sponsor_id INTO v_current_sponsor_id FROM profiles WHERE id = v_current_sponsor_id;
      CONTINUE;
    END IF;

    -- Требования разблокировки (L1 всегда = 0)
    v_required_referrals := COALESCE((v_unlock_levels->('l' || v_level::text))::integer, 0);

    -- Активные рефералы спонсора
    SELECT COUNT(*) INTO v_actual_referrals FROM profiles
    WHERE sponsor_id = v_current_sponsor_id AND is_active = true AND created_at < COALESCE(p_subscription_paid_at, now());

    IF v_actual_referrals < v_required_referrals THEN
      v_commissions_skipped := v_commissions_skipped + 1;
      SELECT sponsor_id INTO v_current_sponsor_id FROM profiles WHERE id = v_current_sponsor_id;
      CONTINUE;
    END IF;

    -- Статус подписки спонсора
    SELECT subscription_status INTO v_sponsor_subscription_status FROM profiles WHERE id = v_current_sponsor_id;
    IF v_sponsor_subscription_status != 'active' THEN
      v_commissions_skipped := v_commissions_skipped + 1;
      SELECT sponsor_id INTO v_current_sponsor_id FROM profiles WHERE id = v_current_sponsor_id;
      CONTINUE;
    END IF;

    -- Расчёт комиссии
    v_commission_amount := ROUND(p_subscription_amount * v_commission_rate / 100);
    IF v_commission_amount <= 0 THEN
      v_commissions_skipped := v_commissions_skipped + 1;
      SELECT sponsor_id INTO v_current_sponsor_id FROM profiles WHERE id = v_current_sponsor_id;
      CONTINUE;
    END IF;

    v_frozen_until := COALESCE(p_subscription_paid_at, now()) + (v_freeze_days || ' days')::interval;

    INSERT INTO transactions (user_id, type, amount_cents, currency, status, frozen_until, source_id, source_ref, level, structure_type, payload)
    VALUES (v_current_sponsor_id, 'commission', v_commission_amount, 'KZT', 'frozen', v_frozen_until, p_subscription_id,
      'S1_' || p_subscription_id || '_L' || v_level, v_level, 1,
      jsonb_build_object('subscriber_id', p_subscriber_id, 'subscription_amount', p_subscription_amount, 'commission_rate', v_commission_rate))
    ON CONFLICT (user_id, source_ref) WHERE source_ref IS NOT NULL DO NOTHING;

    IF FOUND THEN v_commissions_created := v_commissions_created + 1; ELSE v_commissions_skipped := v_commissions_skipped + 1; END IF;

    SELECT sponsor_id INTO v_current_sponsor_id FROM profiles WHERE id = v_current_sponsor_id;
  END LOOP;

  RETURN json_build_object('success', true, 'commissions_created', v_commissions_created, 'commissions_skipped', v_commissions_skipped);
END;
$$;

-- ============================================================================
-- Функция create_commission_transactions (S2)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.create_commission_transactions(
  p_order_id uuid,
  p_buyer_id uuid,
  p_order_amount_kzt numeric
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_current_sponsor_id uuid;
  v_level integer := 0;
  v_max_levels integer := 10;
  v_commission_rate numeric;
  v_commission_amount integer;
  v_freeze_days integer := 14;
  v_frozen_until timestamptz;
  v_commissions_created integer := 0;
  v_commissions_skipped integer := 0;
  v_unlock_levels jsonb;
  v_required_referrals integer;
  v_actual_referrals integer;
  v_sponsor_subscription_status text;
  v_sponsor_activation_met boolean;
  v_order_paid_at timestamptz;
BEGIN
  SELECT paid_at INTO v_order_paid_at FROM orders WHERE id = p_order_id;
  SELECT value INTO v_unlock_levels FROM mlm_settings WHERE key = 'unlock_levels';
  IF v_unlock_levels IS NULL THEN v_unlock_levels := '{"l1": 0, "l2": 3, "l3": 5, "l4": 8, "l5": 10}'::jsonb; END IF;
  SELECT COALESCE((value->>'days')::integer, 14) INTO v_freeze_days FROM mlm_settings WHERE key = 'commission_freeze_period';

  SELECT sponsor_id INTO v_current_sponsor_id FROM profiles WHERE id = p_buyer_id;
  IF v_current_sponsor_id IS NULL THEN
    RETURN json_build_object('success', true, 'message', 'No sponsor', 'commissions_created', 0, 'commissions_skipped', 0);
  END IF;

  WHILE v_current_sponsor_id IS NOT NULL AND v_level < v_max_levels LOOP
    v_level := v_level + 1;

    SELECT percent INTO v_commission_rate FROM mlm_commission_rules WHERE structure_type = 2 AND level = v_level AND is_active = true;
    IF v_commission_rate IS NULL OR v_commission_rate <= 0 THEN
      v_commissions_skipped := v_commissions_skipped + 1;
      SELECT sponsor_id INTO v_current_sponsor_id FROM profiles WHERE id = v_current_sponsor_id;
      CONTINUE;
    END IF;

    IF v_level <= 5 THEN
      v_required_referrals := COALESCE((v_unlock_levels->('l' || v_level::text))::integer, 0);
      SELECT COUNT(*) INTO v_actual_referrals FROM profiles WHERE sponsor_id = v_current_sponsor_id AND is_active = true AND created_at < COALESCE(v_order_paid_at, now());
      IF v_actual_referrals < v_required_referrals THEN
        v_commissions_skipped := v_commissions_skipped + 1;
        SELECT sponsor_id INTO v_current_sponsor_id FROM profiles WHERE id = v_current_sponsor_id;
        CONTINUE;
      END IF;
    END IF;

    SELECT subscription_status, monthly_activation_completed INTO v_sponsor_subscription_status, v_sponsor_activation_met FROM profiles WHERE id = v_current_sponsor_id;
    IF v_sponsor_subscription_status != 'active' THEN
      v_commissions_skipped := v_commissions_skipped + 1;
      SELECT sponsor_id INTO v_current_sponsor_id FROM profiles WHERE id = v_current_sponsor_id;
      CONTINUE;
    END IF;
    IF v_sponsor_activation_met IS NOT TRUE THEN
      v_commissions_skipped := v_commissions_skipped + 1;
      SELECT sponsor_id INTO v_current_sponsor_id FROM profiles WHERE id = v_current_sponsor_id;
      CONTINUE;
    END IF;

    v_commission_amount := ROUND(p_order_amount_kzt * v_commission_rate / 100);
    IF v_commission_amount <= 0 THEN
      v_commissions_skipped := v_commissions_skipped + 1;
      SELECT sponsor_id INTO v_current_sponsor_id FROM profiles WHERE id = v_current_sponsor_id;
      CONTINUE;
    END IF;

    v_frozen_until := COALESCE(v_order_paid_at, now()) + (v_freeze_days || ' days')::interval;

    INSERT INTO transactions (user_id, type, amount_cents, currency, status, frozen_until, source_id, source_ref, level, structure_type, payload)
    VALUES (v_current_sponsor_id, 'commission', v_commission_amount, 'KZT', 'frozen', v_frozen_until, p_order_id,
      'S2_' || p_order_id || '_L' || v_level, v_level, 2,
      jsonb_build_object('buyer_id', p_buyer_id, 'order_amount', p_order_amount_kzt, 'commission_rate', v_commission_rate))
    ON CONFLICT (user_id, source_ref) WHERE source_ref IS NOT NULL DO NOTHING;

    IF FOUND THEN v_commissions_created := v_commissions_created + 1; ELSE v_commissions_skipped := v_commissions_skipped + 1; END IF;
    SELECT sponsor_id INTO v_current_sponsor_id FROM profiles WHERE id = v_current_sponsor_id;
  END LOOP;

  RETURN json_build_object('success', true, 'commissions_created', v_commissions_created, 'commissions_skipped', v_commissions_skipped);
END;
$$;

-- ============================================================================
-- Функция get_commission_structure_stats
-- ============================================================================
CREATE OR REPLACE FUNCTION public.get_commission_structure_stats(
  p_user_id uuid,
  p_structure_type integer DEFAULT 1,
  p_start_date timestamptz DEFAULT NULL,
  p_end_date timestamptz DEFAULT NULL
)
RETURNS TABLE (level integer, percent numeric, earned_cents bigint, frozen_cents bigint, volume_cents bigint, partners_count bigint, status text, unlock_requirement text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_max_levels integer;
  v_unlock_levels jsonb;
  v_direct_referrals integer;
BEGIN
  v_max_levels := CASE WHEN p_structure_type = 1 THEN 5 ELSE 10 END;
  SELECT value INTO v_unlock_levels FROM mlm_settings WHERE key = 'unlock_levels';
  IF v_unlock_levels IS NULL THEN v_unlock_levels := '{"l1": 0, "l2": 3, "l3": 5, "l4": 8, "l5": 10}'::jsonb; END IF;
  SELECT COUNT(*) INTO v_direct_referrals FROM profiles WHERE sponsor_id = p_user_id AND is_active = true;

  RETURN QUERY
  WITH commission_rules AS (
    SELECT mcr.level, mcr.percent FROM mlm_commission_rules mcr WHERE mcr.structure_type = p_structure_type AND mcr.is_active = true
  ),
  levels_data AS (SELECT generate_series(1, v_max_levels) as lvl),
  transactions_stats AS (
    SELECT t.level as t_level,
      SUM(CASE WHEN t.status = 'completed' THEN t.amount_cents ELSE 0 END) as earned,
      SUM(CASE WHEN t.status = 'frozen' THEN t.amount_cents ELSE 0 END) as frozen,
      SUM(t.amount_cents) as volume
    FROM transactions t WHERE t.user_id = p_user_id AND t.type = 'commission' AND t.structure_type = p_structure_type
      AND (p_start_date IS NULL OR t.created_at >= p_start_date) AND (p_end_date IS NULL OR t.created_at <= p_end_date)
    GROUP BY t.level
  ),
  partners_at_level AS (
    SELECT r.level as p_level, COUNT(*) as partners FROM (
      WITH RECURSIVE network AS (
        SELECT id, 1 as level FROM profiles WHERE sponsor_id = p_user_id AND is_active = true
        UNION ALL
        SELECT p.id, n.level + 1 FROM profiles p INNER JOIN network n ON p.sponsor_id = n.id WHERE p.is_active = true AND n.level < v_max_levels
      ) SELECT level FROM network
    ) r GROUP BY r.level
  )
  SELECT ld.lvl::integer, COALESCE(cr.percent, 0)::numeric, COALESCE(ts.earned, 0)::bigint, COALESCE(ts.frozen, 0)::bigint, COALESCE(ts.volume, 0)::bigint, COALESCE(pal.partners, 0)::bigint,
    CASE WHEN ld.lvl = 1 THEN 'active' WHEN v_direct_referrals >= COALESCE((v_unlock_levels->('l' || ld.lvl::text))::integer, 0) THEN 'active' ELSE 'locked' END::text,
    CASE WHEN ld.lvl = 1 THEN NULL ELSE 'Нужно ' || COALESCE((v_unlock_levels->('l' || ld.lvl::text))::integer, 0) || ' личников' END::text
  FROM levels_data ld LEFT JOIN commission_rules cr ON cr.level = ld.lvl LEFT JOIN transactions_stats ts ON ts.t_level = ld.lvl LEFT JOIN partners_at_level pal ON pal.p_level = ld.lvl
  ORDER BY ld.lvl;
END;
$$;

-- ============================================================================
-- Функция get_referral_network_from_table
-- ============================================================================
CREATE OR REPLACE FUNCTION public.get_referral_network_from_table(
  root_user_id uuid,
  p_max_levels integer DEFAULT 10,
  p_structure_type integer DEFAULT 1
)
RETURNS TABLE (id uuid, full_name text, avatar_url text, level integer, parent_id uuid, subscription_status text, subscription_expires_at timestamptz, personal_activation_volume numeric, has_commission_received boolean, no_commission_reason text, commission_frozen_until timestamptz, is_activated boolean, created_at timestamptz)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_unlock_levels jsonb;
  v_root_direct_referrals integer;
BEGIN
  SELECT value INTO v_unlock_levels FROM mlm_settings WHERE key = 'unlock_levels';
  IF v_unlock_levels IS NULL THEN v_unlock_levels := '{"l1": 0, "l2": 3, "l3": 5, "l4": 8, "l5": 10}'::jsonb; END IF;
  SELECT COUNT(*) INTO v_root_direct_referrals FROM profiles WHERE sponsor_id = root_user_id AND is_active = true;

  RETURN QUERY
  WITH RECURSIVE network AS (
    SELECT p.id, p.full_name, p.avatar_url, 1 as level, root_user_id as parent_id, p.subscription_status, p.subscription_expires_at, COALESCE(ma.total_amount_kzt, 0)::numeric as pav, p.monthly_activation_completed as is_act, p.created_at
    FROM profiles p LEFT JOIN monthly_activations ma ON ma.user_id = p.id AND ma.year = EXTRACT(YEAR FROM now()) AND ma.month = EXTRACT(MONTH FROM now())
    WHERE p.sponsor_id = root_user_id AND p.is_active = true
    UNION ALL
    SELECT p.id, p.full_name, p.avatar_url, n.level + 1, n.id, p.subscription_status, p.subscription_expires_at, COALESCE(ma.total_amount_kzt, 0)::numeric, p.monthly_activation_completed, p.created_at
    FROM profiles p INNER JOIN network n ON p.sponsor_id = n.id LEFT JOIN monthly_activations ma ON ma.user_id = p.id AND ma.year = EXTRACT(YEAR FROM now()) AND ma.month = EXTRACT(MONTH FROM now())
    WHERE p.is_active = true AND n.level < p_max_levels
  ),
  network_with_commissions AS (
    SELECT n.*, EXISTS (SELECT 1 FROM transactions t WHERE t.user_id = root_user_id AND t.type = 'commission' AND t.structure_type = p_structure_type AND t.level = n.level AND (t.payload->>'subscriber_id' = n.id::text OR t.payload->>'buyer_id' = n.id::text)) as has_comm,
      (SELECT t.frozen_until FROM transactions t WHERE t.user_id = root_user_id AND t.type = 'commission' AND t.structure_type = p_structure_type AND t.level = n.level AND t.status = 'frozen' AND (t.payload->>'subscriber_id' = n.id::text OR t.payload->>'buyer_id' = n.id::text) ORDER BY t.created_at DESC LIMIT 1) as frozen_until
    FROM network n
  )
  SELECT nwc.id, nwc.full_name, nwc.avatar_url, nwc.level, nwc.parent_id, nwc.subscription_status, nwc.subscription_expires_at, nwc.pav,
    nwc.has_comm,
    CASE 
      WHEN nwc.level = 1 THEN CASE WHEN nwc.subscription_status != 'active' THEN 'partner_no_subscription' WHEN NOT nwc.has_comm THEN 'no_subscription_payment' ELSE NULL END
      WHEN nwc.level <= 5 THEN CASE WHEN v_root_direct_referrals < COALESCE((v_unlock_levels->('l' || nwc.level::text))::integer, 0) THEN 'level_not_unlocked' WHEN nwc.subscription_status != 'active' THEN 'partner_no_subscription' WHEN NOT nwc.has_comm THEN 'no_subscription_payment' ELSE NULL END
      ELSE CASE WHEN nwc.subscription_status != 'active' THEN 'partner_no_subscription' WHEN NOT nwc.is_act THEN 'partner_no_activation' WHEN NOT nwc.has_comm THEN 'no_order_payment' ELSE NULL END
    END,
    nwc.frozen_until, nwc.is_act, nwc.created_at
  FROM network_with_commissions nwc ORDER BY nwc.level, nwc.created_at;
END;
$$;

-- ============================================================================
-- Функция backfill_missing_s1_commissions
-- ============================================================================
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
  v_result json;
  v_total_processed integer := 0;
  v_total_created integer := 0;
  v_total_skipped integer := 0;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM user_roles WHERE user_id = p_admin_id AND role IN ('admin', 'super_admin')) THEN
    RETURN json_build_object('success', false, 'message', 'Access denied');
  END IF;

  FOR v_subscription IN
    SELECT s.id, s.user_id, s.amount_kzt, s.paid_at FROM subscriptions s
    WHERE s.status = 'active' AND s.paid_at IS NOT NULL AND s.paid_at >= now() - (p_days_back || ' days')::interval AND s.is_marketing_free_access IS NOT TRUE
    ORDER BY s.paid_at
  LOOP
    v_total_processed := v_total_processed + 1;
    SELECT award_s1_subscription_commission(v_subscription.user_id, v_subscription.amount_kzt, v_subscription.id, v_subscription.paid_at) INTO v_result;
    v_total_created := v_total_created + COALESCE((v_result->>'commissions_created')::integer, 0);
    v_total_skipped := v_total_skipped + COALESCE((v_result->>'commissions_skipped')::integer, 0);
  END LOOP;

  INSERT INTO admin_audit (admin_id, action_type, target_type, target_id, metadata)
  VALUES (p_admin_id, 'backfill_s1_commissions', 'system', 'batch', jsonb_build_object('days_back', p_days_back, 'subscriptions_processed', v_total_processed, 'commissions_created', v_total_created, 'commissions_skipped', v_total_skipped));

  RETURN json_build_object('success', true, 'subscriptions_processed', v_total_processed, 'commissions_created', v_total_created, 'commissions_skipped', v_total_skipped);
END;
$$;
