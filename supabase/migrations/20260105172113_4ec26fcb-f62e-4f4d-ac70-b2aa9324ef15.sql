
-- ================================================
-- 1. Триггер для уведомления пользователя о новой комиссии
-- ================================================

CREATE OR REPLACE FUNCTION public.notify_user_on_new_commission()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_amount_formatted TEXT;
  v_frozen_date_formatted TEXT;
  v_message TEXT;
  v_source_type TEXT;
BEGIN
  -- Уведомляем только о комиссиях level=1 (прямые) чтобы не спамить
  IF NEW.type != 'commission' OR NEW.level IS NULL OR NEW.level != 1 THEN
    RETURN NEW;
  END IF;
  
  -- Только для frozen или completed статуса
  IF NEW.status NOT IN ('frozen', 'completed') THEN
    RETURN NEW;
  END IF;
  
  -- Форматируем сумму (amount_cents в KZT уже целые тенге)
  v_amount_formatted := COALESCE(NEW.amount_cents::TEXT, '0') || ' ₸';
  
  -- Форматируем дату разморозки
  IF NEW.frozen_until IS NOT NULL THEN
    v_frozen_date_formatted := TO_CHAR(NEW.frozen_until, 'DD.MM.YYYY');
  ELSE
    v_frozen_date_formatted := NULL;
  END IF;
  
  -- Определяем тип источника для текста
  v_source_type := CASE 
    WHEN NEW.source_ref = 'subscription' THEN 'подписку партнёра'
    WHEN NEW.source_ref = 'order' THEN 'заказ партнёра'
    ELSE 'активность партнёра'
  END;
  
  -- Формируем сообщение
  IF v_frozen_date_formatted IS NOT NULL THEN
    v_message := 'Вам начислена комиссия ' || v_amount_formatted || ' за ' || v_source_type || '.' || E'\n' ||
                 'Дата разморозки: ' || v_frozen_date_formatted || '.';
  ELSE
    v_message := 'Вам начислена комиссия ' || v_amount_formatted || ' за ' || v_source_type || '.' || E'\n' ||
                 'Средства доступны сразу.';
  END IF;
  
  -- Создаём уведомление
  INSERT INTO public.user_modal_notifications (
    user_id,
    type,
    title,
    message,
    show_after
  ) VALUES (
    NEW.user_id,
    'info',
    'Новая комиссия',
    v_message,
    NOW()
  );
  
  RETURN NEW;
END;
$$;

-- Создаём триггер
DROP TRIGGER IF EXISTS tr_notify_on_new_commission ON public.transactions;

CREATE TRIGGER tr_notify_on_new_commission
AFTER INSERT ON public.transactions
FOR EACH ROW
EXECUTE FUNCTION public.notify_user_on_new_commission();

-- ================================================
-- 2. Исправление get_commission_structure_stats
-- Сначала удаляем старую версию, затем создаём новую
-- ================================================

DROP FUNCTION IF EXISTS public.get_commission_structure_stats(UUID, INTEGER, TIMESTAMPTZ, TIMESTAMPTZ);

CREATE FUNCTION public.get_commission_structure_stats(
  p_user_id UUID,
  p_structure_type INTEGER DEFAULT 1,
  p_start_date TIMESTAMPTZ DEFAULT NULL,
  p_end_date TIMESTAMPTZ DEFAULT NULL
)
RETURNS TABLE (
  level INTEGER,
  percent NUMERIC,
  earned_cents BIGINT,
  frozen_cents BIGINT,
  volume_cents BIGINT,
  partners_count INTEGER,
  status TEXT,
  unlock_requirement TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_active BOOLEAN;
  v_monthly_activated BOOLEAN;
BEGIN
  -- Проверяем статус пользователя
  SELECT 
    p.subscription_active,
    COALESCE(p.monthly_activation_completed, FALSE)
  INTO v_user_active, v_monthly_activated
  FROM profiles p
  WHERE p.id = p_user_id;

  RETURN QUERY
  WITH RECURSIVE network AS (
    -- Базовый случай: прямые партнёры
    SELECT 
      r.referred_user_id AS partner_id,
      1 AS lvl
    FROM referrals r
    WHERE r.referrer_id = p_user_id
      AND r.structure_type = p_structure_type
    
    UNION ALL
    
    -- Рекурсивный случай: партнёры партнёров
    SELECT 
      r.referred_user_id AS partner_id,
      n.lvl + 1 AS lvl
    FROM referrals r
    INNER JOIN network n ON r.referrer_id = n.partner_id
    WHERE r.structure_type = p_structure_type
      AND n.lvl < 10
  ),
  -- Получаем правила комиссий
  commission_rules AS (
    SELECT 
      cpl.level AS rule_level,
      cpl.percent AS rule_percent
    FROM commission_plan_levels cpl
    WHERE cpl.plan_id = 'default'
      AND cpl.structure_type = (CASE WHEN p_structure_type = 1 THEN 'primary'::structure_type ELSE 'secondary'::structure_type END)
  ),
  -- Считаем партнёров по уровням
  partners_by_level AS (
    SELECT 
      n.lvl,
      COUNT(DISTINCT n.partner_id) AS cnt
    FROM network n
    GROUP BY n.lvl
  ),
  -- Считаем транзакции по уровням (комиссии этого пользователя от партнёров)
  transactions_by_level AS (
    SELECT 
      t.level AS tx_level,
      SUM(CASE WHEN t.status = 'completed' THEN t.amount_cents ELSE 0 END) AS earned,
      SUM(CASE WHEN t.status = 'frozen' THEN t.amount_cents ELSE 0 END) AS frozen,
      SUM(t.amount_cents) AS volume
    FROM transactions t
    WHERE t.user_id = p_user_id
      AND t.type = 'commission'
      AND t.currency = 'KZT'
      AND t.structure_type = (CASE WHEN p_structure_type = 1 THEN 'primary'::structure_type ELSE 'secondary'::structure_type END)
      AND (p_start_date IS NULL OR t.created_at >= p_start_date)
      AND (p_end_date IS NULL OR t.created_at <= p_end_date)
    GROUP BY t.level
  )
  SELECT 
    cr.rule_level AS level,
    cr.rule_percent AS percent,
    COALESCE(tl.earned, 0)::BIGINT AS earned_cents,
    COALESCE(tl.frozen, 0)::BIGINT AS frozen_cents,
    COALESCE(tl.volume, 0)::BIGINT AS volume_cents,
    COALESCE(pl.cnt, 0)::INTEGER AS partners_count,
    CASE 
      WHEN NOT v_user_active THEN 'locked'
      WHEN NOT v_monthly_activated THEN 'frozen'
      ELSE 'active'
    END::TEXT AS status,
    CASE 
      WHEN NOT v_user_active THEN 'Требуется активная подписка'
      WHEN NOT v_monthly_activated THEN 'Требуется ежемесячная активация'
      ELSE NULL
    END::TEXT AS unlock_requirement
  FROM commission_rules cr
  LEFT JOIN partners_by_level pl ON pl.lvl = cr.rule_level
  LEFT JOIN transactions_by_level tl ON tl.tx_level = cr.rule_level
  ORDER BY cr.rule_level;
END;
$$;
