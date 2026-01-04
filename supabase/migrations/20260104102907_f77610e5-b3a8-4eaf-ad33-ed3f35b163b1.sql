-- Исправляем функцию award_s1_subscription_commission для работы с реальной структурой transactions
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

  -- Создаём транзакцию с заморозкой (используем реальную структуру таблицы)
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
    v_commission,  -- amount_cents в KZT (целые)
    'KZT',
    'frozen',
    p_subscription_id,
    'subscription',
    1,  -- S1 = уровень 1
    'S',  -- структура S
    v_frozen_until,
    jsonb_build_object(
      'subscriber_id', p_subscriber_id,
      'description', 'S1 комиссия за подписку партнёра (заморожена на 14 дней)'
    )
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

-- Исправляем существующие транзакции Ермека (используя правильные колонки)
DO $$
DECLARE
  v_ermek_id UUID;
  v_total_to_revert BIGINT := 0;
BEGIN
  SELECT id INTO v_ermek_id 
  FROM profiles 
  WHERE email = 'ermek_kanafin@mail.ru';

  IF v_ermek_id IS NULL THEN
    RAISE NOTICE 'Ermek not found';
    RETURN;
  END IF;

  -- Обновляем транзакции: устанавливаем frozen статус и frozen_until
  UPDATE transactions t
  SET 
    status = 'frozen',
    frozen_until = (
      SELECT s.paid_at + INTERVAL '14 days'
      FROM subscriptions s
      WHERE s.id = t.source_id
    ),
    payload = COALESCE(payload, '{}'::jsonb) || '{"description": "S1 комиссия за подписку партнёра (заморожена на 14 дней)"}'::jsonb
  WHERE t.user_id = v_ermek_id
  AND t.type = 'commission'
  AND t.source_ref = 'subscription'
  AND t.status = 'completed'
  AND t.frozen_until IS NULL;

  -- Считаем сколько нужно вернуть с баланса
  SELECT COALESCE(SUM(amount_cents), 0) INTO v_total_to_revert
  FROM transactions
  WHERE user_id = v_ermek_id
  AND type = 'commission'
  AND source_ref = 'subscription'
  AND status = 'frozen';

  -- Возвращаем средства с баланса
  UPDATE profiles
  SET balance = GREATEST(0, balance - v_total_to_revert)
  WHERE id = v_ermek_id;

  RAISE NOTICE 'Ermek balance reduced by % KZT', v_total_to_revert;
END;
$$;