-- Удаляем старую функцию backfill_missing_s1_commissions
DROP FUNCTION IF EXISTS public.backfill_missing_s1_commissions(UUID, INTEGER);

-- 1. Исправить функцию award_s1_subscription_commission - добавить заморозку на 14 дней
CREATE OR REPLACE FUNCTION public.award_s1_subscription_commission(
  p_subscriber_id UUID,
  p_subscription_id UUID,
  p_subscription_amount INTEGER,
  p_subscription_paid_at TIMESTAMPTZ DEFAULT NOW()
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sponsor_id UUID;
  v_s1_rate NUMERIC;
  v_commission INTEGER;
  v_frozen_until TIMESTAMPTZ;
  v_result JSONB;
BEGIN
  -- Получаем спонсора подписчика
  SELECT sponsor_id INTO v_sponsor_id
  FROM profiles
  WHERE id = p_subscriber_id;

  IF v_sponsor_id IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'reason', 'no_sponsor',
      'subscriber_id', p_subscriber_id
    );
  END IF;

  -- Получаем ставку S1 из настроек
  SELECT COALESCE(
    (SELECT (value->>'s1_rate')::NUMERIC FROM mlm_settings WHERE key = 'commission_rates'),
    10
  ) INTO v_s1_rate;

  -- Рассчитываем комиссию
  v_commission := ROUND(p_subscription_amount * v_s1_rate / 100);
  
  -- Рассчитываем дату разморозки (14 дней от даты оплаты подписки)
  v_frozen_until := p_subscription_paid_at + INTERVAL '14 days';

  -- Создаём транзакцию с заморозкой
  INSERT INTO transactions (
    user_id,
    type,
    amount,
    status,
    source_user_id,
    source_type,
    source_id,
    frozen_until,
    description
  ) VALUES (
    v_sponsor_id,
    'commission',
    v_commission,
    'frozen',
    p_subscriber_id,
    'subscription',
    p_subscription_id,
    v_frozen_until,
    'S1 комиссия за подписку партнёра (заморожена на 14 дней)'
  );

  RETURN jsonb_build_object(
    'success', true,
    'sponsor_id', v_sponsor_id,
    'commission', v_commission,
    'frozen_until', v_frozen_until,
    'rate', v_s1_rate
  );
END;
$$;

-- 2. Создать функцию backfill_missing_s1_commissions заново
CREATE OR REPLACE FUNCTION public.backfill_missing_s1_commissions(
  p_admin_id UUID,
  p_days_back INTEGER DEFAULT 30
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_subscription RECORD;
  v_result JSONB;
  v_processed INTEGER := 0;
  v_created INTEGER := 0;
  v_skipped INTEGER := 0;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM profiles 
    WHERE id = p_admin_id 
    AND role IN ('admin', 'super_admin')
  ) THEN
    RAISE EXCEPTION 'Only admins can run this function';
  END IF;

  FOR v_subscription IN
    SELECT 
      s.id as subscription_id,
      s.user_id,
      s.amount,
      s.paid_at
    FROM subscriptions s
    WHERE s.status = 'paid'
    AND s.paid_at >= NOW() - (p_days_back || ' days')::INTERVAL
    AND NOT EXISTS (
      SELECT 1 FROM transactions t
      WHERE t.source_id = s.id
      AND t.source_type = 'subscription'
      AND t.type = 'commission'
    )
  LOOP
    v_processed := v_processed + 1;
    
    v_result := award_s1_subscription_commission(
      v_subscription.user_id,
      v_subscription.subscription_id,
      v_subscription.amount,
      v_subscription.paid_at
    );
    
    IF (v_result->>'success')::BOOLEAN THEN
      v_created := v_created + 1;
    ELSE
      v_skipped := v_skipped + 1;
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'success', true,
    'subscriptions_processed', v_processed,
    'commissions_created', v_created,
    'commissions_skipped', v_skipped
  );
END;
$$;

-- 3. Исправить функцию get_referral_network_from_table - учитывать grace period
CREATE OR REPLACE FUNCTION public.get_referral_network_from_table(
  p_user_id UUID,
  p_structure_type INTEGER DEFAULT 1
)
RETURNS TABLE (
  user_id UUID,
  full_name TEXT,
  email TEXT,
  phone TEXT,
  level INTEGER,
  status TEXT,
  subscription_status TEXT,
  sponsor_id UUID,
  referral_code TEXT,
  created_at TIMESTAMPTZ,
  subscription_paid_until TIMESTAMPTZ,
  has_paid_subscription BOOLEAN,
  monthly_activation_met BOOLEAN,
  monthly_activation_amount INTEGER,
  activation_due_from TIMESTAMPTZ,
  total_purchases INTEGER,
  avatar_url TEXT,
  commission_amount INTEGER,
  no_commission_reason TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_s1_rate NUMERIC;
  v_subscription_amount INTEGER;
BEGIN
  SELECT COALESCE(
    (SELECT (value->>'s1_rate')::NUMERIC FROM mlm_settings WHERE key = 'commission_rates'),
    10
  ) INTO v_s1_rate;
  
  SELECT COALESCE(
    (SELECT (value->>'subscription_amount')::INTEGER FROM mlm_settings WHERE key = 'subscription_settings'),
    55000
  ) INTO v_subscription_amount;

  RETURN QUERY
  WITH RECURSIVE network AS (
    SELECT 
      p.id,
      COALESCE(p.full_name, p.email) as full_name,
      p.email,
      p.phone,
      1 as level,
      p.status,
      p.subscription_status,
      p.sponsor_id,
      p.referral_code,
      p.created_at,
      p.subscription_paid_until,
      p.has_paid_subscription,
      p.monthly_activation_met,
      COALESCE(p.monthly_activation_amount, 0) as monthly_activation_amount,
      p.activation_due_from,
      COALESCE(p.total_purchases, 0) as total_purchases,
      p.avatar_url
    FROM profiles p
    WHERE p.sponsor_id = p_user_id
    
    UNION ALL
    
    SELECT 
      p.id,
      COALESCE(p.full_name, p.email) as full_name,
      p.email,
      p.phone,
      n.level + 1,
      p.status,
      p.subscription_status,
      p.sponsor_id,
      p.referral_code,
      p.created_at,
      p.subscription_paid_until,
      p.has_paid_subscription,
      p.monthly_activation_met,
      COALESCE(p.monthly_activation_amount, 0) as monthly_activation_amount,
      p.activation_due_from,
      COALESCE(p.total_purchases, 0) as total_purchases,
      p.avatar_url
    FROM profiles p
    INNER JOIN network n ON p.sponsor_id = n.id
    WHERE n.level < 10
  )
  SELECT 
    nwa.id as user_id,
    nwa.full_name,
    nwa.email,
    nwa.phone,
    nwa.level,
    nwa.status,
    nwa.subscription_status,
    nwa.sponsor_id,
    nwa.referral_code,
    nwa.created_at,
    nwa.subscription_paid_until,
    nwa.has_paid_subscription,
    nwa.monthly_activation_met,
    nwa.monthly_activation_amount,
    nwa.activation_due_from,
    nwa.total_purchases,
    nwa.avatar_url,
    CASE 
      WHEN p_structure_type = 1 AND nwa.level = 1 AND nwa.has_paid_subscription 
      THEN ROUND(v_subscription_amount * v_s1_rate / 100)::INTEGER
      ELSE 0
    END as commission_amount,
    CASE
      WHEN p_structure_type = 1 AND nwa.level = 1 THEN
        CASE
          WHEN NOT nwa.has_paid_subscription THEN 'no_subscription'
          WHEN nwa.activation_due_from IS NOT NULL AND nwa.activation_due_from > CURRENT_TIMESTAMP THEN NULL
          WHEN NOT nwa.monthly_activation_met THEN 'no_payment_this_month'
          ELSE NULL
        END
      WHEN p_structure_type = 1 AND nwa.level > 1 THEN 'wrong_level'
      ELSE NULL
    END as no_commission_reason
  FROM network nwa
  ORDER BY nwa.level, nwa.created_at;
END;
$$;

-- 4. Исправить существующие транзакции Ермека Канафина
DO $$
DECLARE
  v_ermek_id UUID;
  v_total_to_revert INTEGER := 0;
BEGIN
  SELECT id INTO v_ermek_id 
  FROM profiles 
  WHERE email = 'ermek_kanafin@mail.ru';

  IF v_ermek_id IS NULL THEN
    RAISE NOTICE 'Ermek not found';
    RETURN;
  END IF;

  UPDATE transactions t
  SET 
    status = 'frozen',
    frozen_until = (
      SELECT s.paid_at + INTERVAL '14 days'
      FROM subscriptions s
      WHERE s.id = t.source_id
    ),
    description = 'S1 комиссия за подписку партнёра (заморожена на 14 дней)'
  WHERE t.user_id = v_ermek_id
  AND t.type = 'commission'
  AND t.source_type = 'subscription'
  AND t.status = 'completed'
  AND t.frozen_until IS NULL;

  SELECT COALESCE(SUM(amount), 0) INTO v_total_to_revert
  FROM transactions
  WHERE user_id = v_ermek_id
  AND type = 'commission'
  AND source_type = 'subscription'
  AND status = 'frozen';

  UPDATE profiles
  SET balance = GREATEST(0, balance - v_total_to_revert)
  WHERE id = v_ermek_id;

  RAISE NOTICE 'Ermek balance reduced by % KZT', v_total_to_revert;
END;
$$;