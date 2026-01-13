-- Удаляем старые версии функций
DROP FUNCTION IF EXISTS backfill_missing_s1_commissions(uuid, integer);
DROP FUNCTION IF EXISTS backfill_missing_s1_commissions(uuid);
DROP FUNCTION IF EXISTS backfill_missing_s1_commissions(uuid, uuid, boolean);

-- =============================================
-- Функция доначисления пропущенных комиссий
-- =============================================
CREATE OR REPLACE FUNCTION backfill_missing_s1_commissions(
  p_admin_id uuid,
  p_sponsor_id uuid DEFAULT NULL,
  p_dry_run boolean DEFAULT true
)
RETURNS jsonb AS $$
DECLARE
  v_result jsonb;
  v_created_count integer := 0;
  v_skipped_count integer := 0;
  v_total_amount numeric := 0;
  v_details jsonb := '[]'::jsonb;
  v_rec record;
  v_new_tx_id uuid;
  v_freeze_days integer;
  v_sponsor_active boolean;
  v_direct_referrals integer;
  v_required_referrals integer;
BEGIN
  -- Проверяем права админа
  IF NOT EXISTS (
    SELECT 1 FROM user_roles 
    WHERE user_id = p_admin_id 
      AND role IN ('admin', 'superadmin')
  ) THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Access denied: admin role required'
    );
  END IF;

  -- Получаем период заморозки из настроек
  SELECT COALESCE((value->>'days')::integer, 30) INTO v_freeze_days
  FROM mlm_settings
  WHERE key = 'commission_freeze_period';

  -- Проходим по всем пропущенным комиссиям
  FOR v_rec IN 
    WITH targets AS (
      SELECT DISTINCT p.id AS sponsor_id
      FROM profiles p
      WHERE p.subscription_active = true
        AND (p_sponsor_id IS NULL OR p.id = p_sponsor_id)
    ),
    missing AS (
      SELECT 
        t.sponsor_id,
        r.subscriber_id,
        r.subscriber_name,
        r.network_level,
        r.subscription_id,
        r.paid_at,
        r.amount_kzt,
        r.expected_commission_kzt,
        r.missing_reason
      FROM targets t
      CROSS JOIN LATERAL reconcile_s1_commissions(t.sponsor_id, 5, NULL, NULL) r
      WHERE r.missing_reason = 'missing_commission'
        AND r.expected_commission_kzt > 0
    )
    SELECT * FROM missing
  LOOP
    -- Проверяем, был ли спонсор активен на момент оплаты
    SELECT EXISTS (
      SELECT 1 FROM subscriptions
      WHERE user_id = v_rec.sponsor_id
        AND status = 'active'
        AND started_at <= v_rec.paid_at
    ) INTO v_sponsor_active;

    IF NOT v_sponsor_active THEN
      v_skipped_count := v_skipped_count + 1;
      v_details := v_details || jsonb_build_object(
        'action', 'skipped',
        'reason', 'sponsor_inactive_at_payment',
        'sponsor_id', v_rec.sponsor_id,
        'subscriber_id', v_rec.subscriber_id,
        'subscription_id', v_rec.subscription_id
      );
      CONTINUE;
    END IF;

    -- Проверяем разблокировку уровня
    SELECT 
      COALESCE((value->>('level_' || v_rec.network_level::text))::integer, v_rec.network_level)
    INTO v_required_referrals
    FROM mlm_settings
    WHERE key = 'unlock_levels';

    SELECT COUNT(*) INTO v_direct_referrals
    FROM referrals
    WHERE referrer_id = v_rec.sponsor_id
      AND structure_type = 1
      AND created_at <= v_rec.paid_at;

    IF v_direct_referrals < v_required_referrals THEN
      v_skipped_count := v_skipped_count + 1;
      v_details := v_details || jsonb_build_object(
        'action', 'skipped',
        'reason', 'level_not_unlocked',
        'level', v_rec.network_level,
        'required', v_required_referrals,
        'had', v_direct_referrals,
        'sponsor_id', v_rec.sponsor_id,
        'subscriber_id', v_rec.subscriber_id
      );
      CONTINUE;
    END IF;

    -- Проверяем, нет ли уже такой транзакции
    IF EXISTS (
      SELECT 1 FROM transactions
      WHERE user_id = v_rec.sponsor_id
        AND source_id = v_rec.subscription_id
        AND type = 'commission'
        AND structure_type = 'primary'
        AND level = v_rec.network_level
    ) THEN
      v_skipped_count := v_skipped_count + 1;
      v_details := v_details || jsonb_build_object(
        'action', 'skipped',
        'reason', 'already_exists',
        'sponsor_id', v_rec.sponsor_id,
        'subscription_id', v_rec.subscription_id
      );
      CONTINUE;
    END IF;

    -- Создаём транзакцию (если не dry_run)
    IF NOT p_dry_run THEN
      INSERT INTO transactions (
        user_id,
        type,
        structure_type,
        level,
        currency,
        amount_cents,
        source_id,
        source_ref,
        status,
        frozen_until,
        payload,
        created_at
      ) VALUES (
        v_rec.sponsor_id,
        'commission',
        'primary',
        v_rec.network_level,
        'KZT',
        v_rec.expected_commission_kzt,
        v_rec.subscription_id,
        'backfill:subscription:' || v_rec.subscription_id || ':s1:l' || v_rec.network_level,
        'completed',
        NULL,
        jsonb_build_object(
          'subscription_id', v_rec.subscription_id,
          'from_user_id', v_rec.subscriber_id,
          'from_user_name', v_rec.subscriber_name,
          'base_amount_kzt', v_rec.amount_kzt,
          'percent', (v_rec.expected_commission_kzt * 100 / NULLIF(v_rec.amount_kzt, 0)),
          'backfill', true,
          'backfill_date', now(),
          'backfill_admin_id', p_admin_id
        ),
        v_rec.paid_at
      )
      RETURNING id INTO v_new_tx_id;
    END IF;

    v_created_count := v_created_count + 1;
    v_total_amount := v_total_amount + v_rec.expected_commission_kzt;
    
    v_details := v_details || jsonb_build_object(
      'action', CASE WHEN p_dry_run THEN 'would_create' ELSE 'created' END,
      'transaction_id', v_new_tx_id,
      'sponsor_id', v_rec.sponsor_id,
      'subscriber_id', v_rec.subscriber_id,
      'subscriber_name', v_rec.subscriber_name,
      'subscription_id', v_rec.subscription_id,
      'level', v_rec.network_level,
      'amount', v_rec.expected_commission_kzt
    );
  END LOOP;

  -- Логируем действие админа
  IF NOT p_dry_run AND v_created_count > 0 THEN
    INSERT INTO admin_actions (
      admin_id, action_type, target_type, target_id, metadata
    ) VALUES (
      p_admin_id,
      'backfill_s1_commissions',
      'bulk',
      COALESCE(p_sponsor_id::text, 'all'),
      jsonb_build_object(
        'created_count', v_created_count,
        'skipped_count', v_skipped_count,
        'total_amount', v_total_amount,
        'dry_run', p_dry_run
      )
    );
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'dry_run', p_dry_run,
    'created_count', v_created_count,
    'skipped_count', v_skipped_count,
    'total_amount_kzt', v_total_amount,
    'details', v_details
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =============================================
-- Исправление триггера award_s1_subscription_commission
-- =============================================
CREATE OR REPLACE FUNCTION award_s1_subscription_commission()
RETURNS TRIGGER AS $$
DECLARE
  v_sponsor_id uuid;
  v_current_level integer := 0;
  v_max_level integer := 5;
  v_percent numeric;
  v_commission_amount numeric;
  v_freeze_days integer;
  v_freeze_until timestamptz;
  v_direct_referrals integer;
  v_required_referrals integer;
  v_sponsor_active boolean;
  v_new_tx_id uuid;
BEGIN
  -- Проверяем, что это оплата подписки
  IF NEW.status != 'active' OR NEW.paid_at IS NULL THEN
    RETURN NEW;
  END IF;

  -- Проверяем, что это не бесплатный доступ
  IF COALESCE(NEW.is_marketing_free_access, false) = true THEN
    RETURN NEW;
  END IF;

  -- Получаем период заморозки
  SELECT COALESCE((value->>'days')::integer, 30) INTO v_freeze_days
  FROM mlm_settings
  WHERE key = 'commission_freeze_period';

  v_freeze_until := NEW.paid_at + (v_freeze_days || ' days')::interval;

  -- Находим первого спонсора
  SELECT sponsor_id INTO v_sponsor_id
  FROM profiles
  WHERE id = NEW.user_id;

  -- Идём по цепочке спонсоров
  WHILE v_sponsor_id IS NOT NULL AND v_current_level < v_max_level LOOP
    v_current_level := v_current_level + 1;

    -- Получаем процент для уровня
    SELECT percent INTO v_percent
    FROM mlm_commission_rules
    WHERE structure_type = 1
      AND level = v_current_level
      AND is_active = true
      AND plan_id = 'default';

    IF v_percent IS NULL OR v_percent <= 0 THEN
      SELECT sponsor_id INTO v_sponsor_id
      FROM profiles
      WHERE id = v_sponsor_id;
      CONTINUE;
    END IF;

    -- Проверяем, активен ли спонсор
    SELECT subscription_active INTO v_sponsor_active
    FROM profiles
    WHERE id = v_sponsor_id;

    IF NOT COALESCE(v_sponsor_active, false) THEN
      INSERT INTO activity_log (user_id, type, payload)
      VALUES (
        v_sponsor_id,
        'commission_skipped',
        jsonb_build_object(
          'reason', 'sponsor_inactive',
          'subscription_id', NEW.id,
          'from_user_id', NEW.user_id,
          'level', v_current_level
        )
      );
      
      SELECT sponsor_id INTO v_sponsor_id
      FROM profiles
      WHERE id = v_sponsor_id;
      CONTINUE;
    END IF;

    -- Проверяем разблокировку уровня
    SELECT 
      COALESCE((value->>('level_' || v_current_level::text))::integer, v_current_level)
    INTO v_required_referrals
    FROM mlm_settings
    WHERE key = 'unlock_levels';

    SELECT COUNT(*) INTO v_direct_referrals
    FROM referrals
    WHERE referrer_id = v_sponsor_id
      AND structure_type = 1;

    IF v_direct_referrals < v_required_referrals THEN
      INSERT INTO activity_log (user_id, type, payload)
      VALUES (
        v_sponsor_id,
        'commission_skipped',
        jsonb_build_object(
          'reason', 'level_locked',
          'subscription_id', NEW.id,
          'from_user_id', NEW.user_id,
          'level', v_current_level,
          'required_referrals', v_required_referrals,
          'actual_referrals', v_direct_referrals
        )
      );
      
      SELECT sponsor_id INTO v_sponsor_id
      FROM profiles
      WHERE id = v_sponsor_id;
      CONTINUE;
    END IF;

    -- Проверяем дубли
    IF EXISTS (
      SELECT 1 FROM transactions
      WHERE user_id = v_sponsor_id
        AND source_id = NEW.id
        AND type = 'commission'
        AND structure_type = 'primary'
        AND level = v_current_level
    ) THEN
      SELECT sponsor_id INTO v_sponsor_id
      FROM profiles
      WHERE id = v_sponsor_id;
      CONTINUE;
    END IF;

    -- Рассчитываем комиссию
    v_commission_amount := NEW.amount_kzt * v_percent / 100;

    -- Создаём транзакцию
    BEGIN
      INSERT INTO transactions (
        user_id,
        type,
        structure_type,
        level,
        currency,
        amount_cents,
        source_id,
        source_ref,
        status,
        frozen_until,
        payload
      ) VALUES (
        v_sponsor_id,
        'commission',
        'primary',
        v_current_level,
        'KZT',
        v_commission_amount,
        NEW.id,
        'subscription:' || NEW.id || ':s1:l' || v_current_level,
        'frozen',
        v_freeze_until,
        jsonb_build_object(
          'subscription_id', NEW.id,
          'from_user_id', NEW.user_id,
          'base_amount_kzt', NEW.amount_kzt,
          'percent', v_percent
        )
      )
      RETURNING id INTO v_new_tx_id;

      INSERT INTO activity_log (user_id, type, payload)
      VALUES (
        v_sponsor_id,
        'commission_created',
        jsonb_build_object(
          'transaction_id', v_new_tx_id,
          'subscription_id', NEW.id,
          'from_user_id', NEW.user_id,
          'level', v_current_level,
          'amount', v_commission_amount,
          'frozen_until', v_freeze_until
        )
      );
    EXCEPTION WHEN OTHERS THEN
      INSERT INTO activity_log (user_id, type, payload)
      VALUES (
        v_sponsor_id,
        'commission_error',
        jsonb_build_object(
          'error', SQLERRM,
          'subscription_id', NEW.id,
          'from_user_id', NEW.user_id,
          'level', v_current_level
        )
      );
    END;

    SELECT sponsor_id INTO v_sponsor_id
    FROM profiles
    WHERE id = v_sponsor_id;
  END LOOP;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Убеждаемся, что триггер существует
DROP TRIGGER IF EXISTS trg_award_s1_subscription_commission ON subscriptions;
CREATE TRIGGER trg_award_s1_subscription_commission
  AFTER UPDATE ON subscriptions
  FOR EACH ROW
  WHEN (OLD.status IS DISTINCT FROM NEW.status AND NEW.status = 'active' AND NEW.paid_at IS NOT NULL)
  EXECUTE FUNCTION award_s1_subscription_commission();

-- Уникальный индекс для защиты от дублей
CREATE UNIQUE INDEX IF NOT EXISTS idx_transactions_commission_unique
ON transactions (user_id, source_id, type, structure_type, level)
WHERE type = 'commission' AND source_id IS NOT NULL;

GRANT EXECUTE ON FUNCTION backfill_missing_s1_commissions TO authenticated;