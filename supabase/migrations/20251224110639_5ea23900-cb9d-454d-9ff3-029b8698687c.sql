
-- ============================================
-- ИСПРАВЛЕНИЕ ПРОБЛЕМ С НАЧИСЛЕНИЯМИ КОМИССИЙ
-- ============================================

-- 1. Исправить frozen_until для транзакций с freeze_reason = 'sponsor_inactive'
-- Было: 365 дней заморозки, должно быть: 14 дней
UPDATE transactions 
SET 
  frozen_until = created_at + INTERVAL '14 days',
  updated_at = NOW()
WHERE payload->>'freeze_reason' = 'sponsor_inactive'
  AND frozen_until > created_at + INTERVAL '30 days';

-- 2. Разморозить транзакции где 14 дней уже прошло
UPDATE transactions 
SET 
  status = 'completed',
  frozen_until = NULL,
  updated_at = NOW()
WHERE status = 'frozen'
  AND frozen_until IS NOT NULL
  AND frozen_until <= NOW();

-- 3. Заполнить monthly_activations для активных пользователей за текущий месяц
INSERT INTO monthly_activations (user_id, year, month, is_activated, threshold_kzt, total_amount_kzt)
SELECT 
  p.id, 
  EXTRACT(YEAR FROM NOW())::int, 
  EXTRACT(MONTH FROM NOW())::int, 
  true,
  0,
  0
FROM profiles p
WHERE p.subscription_status = 'active'
  AND p.deleted_at IS NULL
  AND NOT EXISTS (
    SELECT 1 FROM monthly_activations ma 
    WHERE ma.user_id = p.id 
      AND ma.year = EXTRACT(YEAR FROM NOW())::int
      AND ma.month = EXTRACT(MONTH FROM NOW())::int
  )
ON CONFLICT DO NOTHING;

-- 4. Обновить monthly_activation_completed для всех активных пользователей
UPDATE profiles
SET 
  monthly_activation_completed = true,
  updated_at = NOW()
WHERE subscription_status = 'active'
  AND deleted_at IS NULL
  AND (monthly_activation_completed IS NULL OR monthly_activation_completed = false);

-- 5. Создать улучшенную функцию award_s1_subscription_commission
-- с исправленной логикой определения активности спонсора
CREATE OR REPLACE FUNCTION public.award_s1_subscription_commission(
  p_subscription_id UUID,
  p_user_id UUID,
  p_amount_kzt INTEGER
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sponsor_id UUID;
  v_sponsor_active BOOLEAN;
  v_freeze_until TIMESTAMPTZ;
  v_percent NUMERIC;
  v_commission_amount INTEGER;
  v_result JSON;
  v_existing_count INTEGER;
BEGIN
  -- Проверяем, не начислены ли уже комиссии
  SELECT COUNT(*) INTO v_existing_count
  FROM transactions
  WHERE source_id = p_subscription_id
    AND type = 'commission'
    AND structure_type = 'primary';
    
  IF v_existing_count > 0 THEN
    RETURN json_build_object('success', false, 'error', 'commissions_already_exist');
  END IF;

  -- Получаем спонсора пользователя
  SELECT sponsor_id INTO v_sponsor_id
  FROM profiles
  WHERE id = p_user_id;
  
  IF v_sponsor_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'no_sponsor');
  END IF;
  
  -- Проверяем активность спонсора
  -- ИСПРАВЛЕНО: достаточно иметь активную подписку
  SELECT 
    COALESCE(subscription_status = 'active', false)
  INTO v_sponsor_active
  FROM profiles
  WHERE id = v_sponsor_id;
  
  -- Получаем процент для уровня 1
  SELECT percent INTO v_percent
  FROM commission_plan_levels
  WHERE structure_type = 'primary' AND level = 1
  LIMIT 1;
  
  IF v_percent IS NULL THEN
    v_percent := 10; -- По умолчанию 10%
  END IF;
  
  -- Рассчитываем комиссию
  v_commission_amount := ROUND(p_amount_kzt * v_percent / 100);
  
  -- Определяем заморозку: 14 дней для всех новых комиссий
  v_freeze_until := NOW() + INTERVAL '14 days';
  
  -- Создаём транзакцию комиссии
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
    p_subscription_id,
    'subscription_' || p_subscription_id::text,
    1,
    'primary',
    v_freeze_until,
    json_build_object(
      'source_type', 'subscription',
      'from_user_id', p_user_id,
      'original_amount', p_amount_kzt,
      'percent', v_percent,
      'sponsor_active_at_creation', v_sponsor_active
    )
  );
  
  RETURN json_build_object(
    'success', true,
    'sponsor_id', v_sponsor_id,
    'commission_amount', v_commission_amount,
    'frozen_until', v_freeze_until
  );
END;
$$;

-- 6. Обновить функцию get_user_balance для корректного расчёта (всё в KZT)
CREATE OR REPLACE FUNCTION public.get_user_balance(p_user_id UUID)
RETURNS TABLE(
  user_id UUID,
  available_cents BIGINT,
  frozen_cents BIGINT,
  pending_cents BIGINT,
  withdrawn_cents BIGINT,
  updated_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    p_user_id as user_id,
    COALESCE(SUM(
      CASE 
        WHEN t.type IN ('commission', 'bonus', 'adjustment') 
          AND t.status = 'completed' 
          AND t.currency = 'KZT'
        THEN t.amount_cents
        WHEN t.type = 'withdrawal' 
          AND t.status IN ('completed', 'processing')
          AND t.currency = 'KZT'
        THEN -t.amount_cents
        ELSE 0 
      END
    ), 0)::BIGINT as available_cents,
    
    COALESCE(SUM(
      CASE 
        WHEN t.type IN ('commission', 'bonus') 
          AND t.status = 'frozen'
          AND t.currency = 'KZT'
        THEN t.amount_cents
        ELSE 0 
      END
    ), 0)::BIGINT as frozen_cents,
    
    COALESCE(SUM(
      CASE 
        WHEN t.type IN ('commission', 'bonus') 
          AND t.status = 'pending'
          AND t.currency = 'KZT'
        THEN t.amount_cents
        ELSE 0 
      END
    ), 0)::BIGINT as pending_cents,
    
    COALESCE(SUM(
      CASE 
        WHEN t.type = 'withdrawal' 
          AND t.status = 'completed'
          AND t.currency = 'KZT'
        THEN t.amount_cents
        ELSE 0 
      END
    ), 0)::BIGINT as withdrawn_cents,
    
    NOW() as updated_at
  FROM transactions t
  WHERE t.user_id = p_user_id
    AND COALESCE(t.is_archived, false) = false;
END;
$$;
