
-- ============================================
-- FIX: Исправление триггера award_s1_subscription_commission
-- Проблема: Триггер проверял status = 'approved', но process_payment_completion ставит 'active'
-- ============================================

-- Удаляем старый триггер
DROP TRIGGER IF EXISTS trg_award_s1_subscription_commission ON public.subscriptions;

-- Создаём исправленную функцию триггера
CREATE OR REPLACE FUNCTION public.award_s1_subscription_commission()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sponsor_id uuid;
  v_current_user_id uuid;
  v_level integer := 1;
  v_percent numeric;
  v_commission_cents integer;
  v_subscription_amount_kzt integer;
  v_freeze_days integer := 14;
  v_max_levels integer := 5;
BEGIN
  -- ИСПРАВЛЕНО: Проверяем переход в 'active' вместо 'approved'
  IF NEW.status != 'active' OR OLD.status = 'active' THEN
    RETURN NEW;
  END IF;

  -- Пропускаем маркетинговые бесплатные подписки
  IF NEW.is_marketing_free_access = true THEN
    RETURN NEW;
  END IF;

  -- Пропускаем тестовые подписки
  IF NEW.is_test = true THEN
    RETURN NEW;
  END IF;

  -- Получаем сумму подписки в KZT
  v_subscription_amount_kzt := NEW.amount_kzt;
  
  -- Если сумма 0 или null, выходим
  IF v_subscription_amount_kzt IS NULL OR v_subscription_amount_kzt <= 0 THEN
    RETURN NEW;
  END IF;

  -- Получаем спонсора пользователя
  SELECT sponsor_id INTO v_sponsor_id
  FROM public.profiles
  WHERE id = NEW.user_id;

  v_current_user_id := NEW.user_id;

  -- Идём по цепочке спонсоров до 5 уровней
  WHILE v_sponsor_id IS NOT NULL AND v_level <= v_max_levels LOOP
    -- Получаем процент для текущего уровня структуры S1
    SELECT percent INTO v_percent
    FROM public.mlm_commission_rules
    WHERE structure_type = 1 
      AND level = v_level 
      AND is_active = true
    ORDER BY effective_from DESC
    LIMIT 1;

    -- Если процент найден, создаём комиссию
    IF v_percent IS NOT NULL AND v_percent > 0 THEN
      v_commission_cents := FLOOR(v_subscription_amount_kzt * v_percent / 100);

      IF v_commission_cents > 0 THEN
        INSERT INTO public.transactions (
          user_id,
          type,
          amount_cents,
          currency,
          status,
          frozen_until,
          level,
          structure_type,
          source_id,
          source_ref,
          payload
        ) VALUES (
          v_sponsor_id,
          'commission',
          v_commission_cents,
          'KZT',
          'frozen',
          NOW() + (v_freeze_days || ' days')::interval,
          v_level,
          'primary',
          NEW.id,
          'subscription',
          jsonb_build_object(
            'from_user_id', NEW.user_id,
            'subscription_id', NEW.id,
            'level', v_level,
            'percent', v_percent,
            'base_amount', v_subscription_amount_kzt
          )
        );
      END IF;
    END IF;

    -- Переходим к следующему уровню
    v_current_user_id := v_sponsor_id;
    
    SELECT sponsor_id INTO v_sponsor_id
    FROM public.profiles
    WHERE id = v_current_user_id;

    v_level := v_level + 1;
  END LOOP;

  RETURN NEW;
END;
$$;

-- Создаём новый триггер
CREATE TRIGGER trg_award_s1_subscription_commission
  AFTER UPDATE ON public.subscriptions
  FOR EACH ROW
  EXECUTE FUNCTION public.award_s1_subscription_commission();

-- ============================================
-- BACKFILL: Функция для начисления пропущенных комиссий
-- ============================================

CREATE OR REPLACE FUNCTION public.backfill_missing_s1_commissions(
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
  v_percent numeric;
  v_commission_cents integer;
  v_freeze_days integer := 14;
  v_max_levels integer := 5;
  v_subscriptions_processed integer := 0;
  v_commissions_created integer := 0;
  v_commissions_skipped integer := 0;
BEGIN
  -- Проверяем права администратора
  IF NOT EXISTS (
    SELECT 1 FROM public.user_roles 
    WHERE user_id = p_admin_id AND role IN ('admin', 'superadmin')
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Not authorized');
  END IF;

  -- Находим все активные подписки за последние N дней
  FOR v_subscription IN
    SELECT s.id, s.user_id, s.amount_kzt, s.paid_at
    FROM public.subscriptions s
    WHERE s.status = 'active'
      AND s.paid_at >= NOW() - (p_days_back || ' days')::interval
      AND s.is_marketing_free_access IS NOT TRUE
      AND s.is_test IS NOT TRUE
      AND s.amount_kzt > 0
    ORDER BY s.paid_at ASC
  LOOP
    v_subscriptions_processed := v_subscriptions_processed + 1;

    -- Получаем спонсора пользователя
    SELECT sponsor_id INTO v_sponsor_id
    FROM public.profiles
    WHERE id = v_subscription.user_id;

    v_current_user_id := v_subscription.user_id;
    v_level := 1;

    -- Идём по цепочке спонсоров до 5 уровней
    WHILE v_sponsor_id IS NOT NULL AND v_level <= v_max_levels LOOP
      -- Проверяем, есть ли уже комиссия для этой подписки и этого спонсора
      IF EXISTS (
        SELECT 1 FROM public.transactions
        WHERE source_id = v_subscription.id
          AND source_ref = 'subscription'
          AND user_id = v_sponsor_id
          AND level = v_level
          AND type = 'commission'
      ) THEN
        v_commissions_skipped := v_commissions_skipped + 1;
      ELSE
        -- Получаем процент для текущего уровня
        SELECT percent INTO v_percent
        FROM public.mlm_commission_rules
        WHERE structure_type = 1 
          AND level = v_level 
          AND is_active = true
        ORDER BY effective_from DESC
        LIMIT 1;

        IF v_percent IS NOT NULL AND v_percent > 0 THEN
          v_commission_cents := FLOOR(v_subscription.amount_kzt * v_percent / 100);

          IF v_commission_cents > 0 THEN
            INSERT INTO public.transactions (
              user_id,
              type,
              amount_cents,
              currency,
              status,
              frozen_until,
              level,
              structure_type,
              source_id,
              source_ref,
              payload,
              created_at
            ) VALUES (
              v_sponsor_id,
              'commission',
              v_commission_cents,
              'KZT',
              'frozen',
              v_subscription.paid_at + (v_freeze_days || ' days')::interval,
              v_level,
              'primary',
              v_subscription.id,
              'subscription',
              jsonb_build_object(
                'from_user_id', v_subscription.user_id,
                'subscription_id', v_subscription.id,
                'level', v_level,
                'percent', v_percent,
                'base_amount', v_subscription.amount_kzt,
                'backfilled', true
              ),
              v_subscription.paid_at
            );
            v_commissions_created := v_commissions_created + 1;
          END IF;
        END IF;
      END IF;

      -- Переходим к следующему уровню
      v_current_user_id := v_sponsor_id;
      
      SELECT sponsor_id INTO v_sponsor_id
      FROM public.profiles
      WHERE id = v_current_user_id;

      v_level := v_level + 1;
    END LOOP;
  END LOOP;

  -- Логируем действие
  INSERT INTO public.admin_audit (
    admin_id, action_type, target_type, target_id, comment, metadata
  ) VALUES (
    p_admin_id, 'backfill_s1_commissions', 'system', 'subscriptions',
    'Backfilled missing S1 commissions',
    jsonb_build_object(
      'days_back', p_days_back,
      'subscriptions_processed', v_subscriptions_processed,
      'commissions_created', v_commissions_created,
      'commissions_skipped', v_commissions_skipped
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'subscriptions_processed', v_subscriptions_processed,
    'commissions_created', v_commissions_created,
    'commissions_skipped', v_commissions_skipped
  );
END;
$$;
