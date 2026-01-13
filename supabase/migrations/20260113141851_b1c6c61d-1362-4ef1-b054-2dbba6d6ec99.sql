-- Доначисление пропущенных S1 комиссий для всех пользователей системы
-- Функция backfill_missing_s1_commissions уже существует и готова к использованию
-- Эта миграция добавляет вспомогательную функцию для массового доначисления

-- Создаём функцию для массового доначисления комиссий для конкретного спонсора
CREATE OR REPLACE FUNCTION public.backfill_sponsor_commissions(
  p_admin_id UUID,
  p_sponsor_id UUID,
  p_dry_run BOOLEAN DEFAULT true
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_result JSON;
BEGIN
  -- Вызываем основную функцию backfill с указанием конкретного спонсора
  SELECT backfill_missing_s1_commissions(
    p_admin_id := p_admin_id,
    p_sponsor_id := p_sponsor_id,
    p_dry_run := p_dry_run
  ) INTO v_result;
  
  RETURN v_result;
END;
$$;

-- Функция для получения списка спонсоров с пропущенными комиссиями
CREATE OR REPLACE FUNCTION public.get_sponsors_with_missing_commissions(
  p_admin_id UUID
)
RETURNS TABLE (
  sponsor_id UUID,
  sponsor_name TEXT,
  sponsor_email TEXT,
  missing_count BIGINT,
  missing_amount_cents BIGINT,
  partners_count BIGINT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Проверка прав админа
  IF NOT EXISTS (
    SELECT 1 FROM user_roles 
    WHERE user_id = p_admin_id 
    AND role IN ('admin', 'superadmin')
  ) THEN
    RAISE EXCEPTION 'Access denied: admin role required';
  END IF;

  RETURN QUERY
  WITH missing AS (
    SELECT 
      s.id AS subscription_id,
      s.user_id AS subscriber_id,
      s.amount_kzt,
      p.sponsor_id,
      sp.full_name AS sponsor_name,
      sp.email AS sponsor_email
    FROM subscriptions s
    JOIN profiles p ON p.id = s.user_id
    JOIN profiles sp ON sp.id = p.sponsor_id
    WHERE s.status = 'active'
      AND s.paid_at IS NOT NULL
      AND p.sponsor_id IS NOT NULL
      -- Проверяем что комиссии нет
      AND NOT EXISTS (
        SELECT 1 FROM transactions t
        WHERE t.source_id = s.id
          AND t.source_ref = 'subscription'
          AND t.user_id = p.sponsor_id
          AND t.structure_type = 'S1'
          AND t.level = 1
          AND t.type = 'commission'
      )
  )
  SELECT 
    m.sponsor_id,
    m.sponsor_name,
    m.sponsor_email,
    COUNT(*)::BIGINT AS missing_count,
    SUM((m.amount_kzt * 0.10)::BIGINT * 100)::BIGINT AS missing_amount_cents,
    COUNT(DISTINCT m.subscriber_id)::BIGINT AS partners_count
  FROM missing m
  GROUP BY m.sponsor_id, m.sponsor_name, m.sponsor_email
  ORDER BY missing_count DESC;
END;
$$;

-- Добавляем комментарии
COMMENT ON FUNCTION backfill_sponsor_commissions IS 'Доначисляет пропущенные S1 комиссии для конкретного спонсора';
COMMENT ON FUNCTION get_sponsors_with_missing_commissions IS 'Возвращает список спонсоров с пропущенными комиссиями';