-- =====================================================
-- Функция сверки комиссий S1 (reconciliation)
-- =====================================================

CREATE OR REPLACE FUNCTION public.reconcile_s1_commissions(
  p_sponsor_id UUID,
  p_depth INTEGER DEFAULT 5,
  p_from_date TIMESTAMPTZ DEFAULT NULL,
  p_to_date TIMESTAMPTZ DEFAULT NULL
)
RETURNS TABLE (
  subscriber_id UUID,
  subscriber_name TEXT,
  subscriber_email TEXT,
  level INTEGER,
  subscription_id UUID,
  subscription_status TEXT,
  paid_at TIMESTAMPTZ,
  amount_kzt NUMERIC,
  is_marketing_free_access BOOLEAN,
  expected_commission_kzt NUMERIC,
  actual_transaction_id UUID,
  actual_status TEXT,
  actual_amount_kzt NUMERIC,
  missing_reason TEXT,
  details JSONB
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_from_date TIMESTAMPTZ;
  v_to_date TIMESTAMPTZ;
BEGIN
  -- Установка дат по умолчанию (последние 365 дней)
  v_from_date := COALESCE(p_from_date, NOW() - INTERVAL '365 days');
  v_to_date := COALESCE(p_to_date, NOW());

  RETURN QUERY
  WITH RECURSIVE network AS (
    -- Прямые рефералы спонсора (уровень 1)
    SELECT 
      r.referred_user_id AS user_id,
      1 AS lvl
    FROM referrals r
    WHERE r.referrer_id = p_sponsor_id
      AND r.structure_type = 1
    
    UNION ALL
    
    -- Рекурсивно собираем все уровни до p_depth
    SELECT 
      r.referred_user_id,
      n.lvl + 1
    FROM referrals r
    INNER JOIN network n ON r.referrer_id = n.user_id
    WHERE n.lvl < p_depth
      AND r.structure_type = 1
  ),
  -- Все подписки в сети спонсора
  network_subscriptions AS (
    SELECT 
      n.user_id,
      n.lvl,
      p.full_name,
      p.email,
      s.id AS subscription_id,
      s.status,
      s.paid_at,
      s.amount_kzt,
      COALESCE(s.is_marketing_free_access, false) AS is_marketing_free_access,
      s.started_at,
      s.expires_at
    FROM network n
    INNER JOIN profiles p ON p.id = n.user_id
    INNER JOIN subscriptions s ON s.user_id = n.user_id
    WHERE s.status IN ('active', 'expired', 'paid')
      AND s.paid_at IS NOT NULL
      AND s.paid_at BETWEEN v_from_date AND v_to_date
  ),
  -- Комиссии спонсора по этим подпискам
  sponsor_commissions AS (
    SELECT 
      t.id AS transaction_id,
      t.source_id,
      t.source_ref,
      t.status,
      t.amount_cents AS amount_kzt,
      t.level,
      t.payload,
      -- Извлекаем subscription_id из разных форматов
      COALESCE(
        t.source_id::TEXT,
        (t.payload->>'subscription_id')::TEXT,
        CASE 
          WHEN t.source_ref LIKE 'subscription:%' THEN SPLIT_PART(t.source_ref, ':', 2)
          ELSE NULL
        END
      ) AS extracted_subscription_id
    FROM transactions t
    WHERE t.user_id = p_sponsor_id
      AND t.type = 'commission'
      AND t.structure_type = 'primary'
      AND t.created_at BETWEEN v_from_date AND v_to_date
  ),
  -- Получаем правила комиссий
  commission_rules AS (
    SELECT 
      level,
      percent
    FROM mlm_commission_rules
    WHERE structure_type = 1
      AND is_active = true
      AND plan_id = 'default'
  )
  SELECT 
    ns.user_id AS subscriber_id,
    ns.full_name AS subscriber_name,
    ns.email AS subscriber_email,
    ns.lvl AS level,
    ns.subscription_id,
    ns.status AS subscription_status,
    ns.paid_at,
    ns.amount_kzt,
    ns.is_marketing_free_access,
    CASE 
      WHEN ns.is_marketing_free_access THEN 0
      ELSE ROUND(ns.amount_kzt * COALESCE(cr.percent, 0) / 100)
    END AS expected_commission_kzt,
    sc.transaction_id AS actual_transaction_id,
    sc.status AS actual_status,
    sc.amount_kzt AS actual_amount_kzt,
    -- Определяем причину отсутствия комиссии
    CASE
      WHEN ns.is_marketing_free_access THEN 'marketing_free_access'
      WHEN sc.transaction_id IS NOT NULL THEN NULL
      WHEN NOT EXISTS (
        SELECT 1 FROM subscriptions sp 
        WHERE sp.user_id = p_sponsor_id 
          AND sp.status = 'active'
          AND sp.paid_at <= ns.paid_at
      ) THEN 'sponsor_no_active_subscription_at_payment'
      WHEN ns.lvl > 5 THEN 'level_exceeds_depth'
      WHEN cr.percent IS NULL OR cr.percent = 0 THEN 'no_commission_rule_for_level'
      ELSE 'missing_commission_unknown'
    END AS missing_reason,
    jsonb_build_object(
      'subscription_started_at', ns.started_at,
      'subscription_expires_at', ns.expires_at,
      'commission_rule_percent', cr.percent,
      'matched_transaction_source_ref', sc.source_ref
    ) AS details
  FROM network_subscriptions ns
  LEFT JOIN commission_rules cr ON cr.level = ns.lvl
  LEFT JOIN sponsor_commissions sc ON (
    sc.extracted_subscription_id = ns.subscription_id::TEXT
    OR sc.source_id = ns.subscription_id
  )
  ORDER BY ns.lvl, ns.paid_at DESC;
END;
$$;

-- Функция для получения сводки по сверке
CREATE OR REPLACE FUNCTION public.reconcile_s1_commissions_summary(
  p_sponsor_id UUID,
  p_depth INTEGER DEFAULT 5,
  p_from_date TIMESTAMPTZ DEFAULT NULL,
  p_to_date TIMESTAMPTZ DEFAULT NULL
)
RETURNS TABLE (
  total_subscriptions BIGINT,
  marketing_free_count BIGINT,
  paid_subscriptions BIGINT,
  with_commission BIGINT,
  missing_commission BIGINT,
  expected_total_kzt NUMERIC,
  actual_total_kzt NUMERIC,
  difference_kzt NUMERIC,
  missing_reasons JSONB
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  WITH reconciliation AS (
    SELECT * FROM reconcile_s1_commissions(p_sponsor_id, p_depth, p_from_date, p_to_date)
  )
  SELECT 
    COUNT(*)::BIGINT AS total_subscriptions,
    COUNT(*) FILTER (WHERE r.is_marketing_free_access)::BIGINT AS marketing_free_count,
    COUNT(*) FILTER (WHERE NOT r.is_marketing_free_access)::BIGINT AS paid_subscriptions,
    COUNT(*) FILTER (WHERE r.actual_transaction_id IS NOT NULL)::BIGINT AS with_commission,
    COUNT(*) FILTER (WHERE r.actual_transaction_id IS NULL AND NOT r.is_marketing_free_access)::BIGINT AS missing_commission,
    COALESCE(SUM(r.expected_commission_kzt), 0) AS expected_total_kzt,
    COALESCE(SUM(r.actual_amount_kzt) FILTER (WHERE r.actual_transaction_id IS NOT NULL), 0) AS actual_total_kzt,
    COALESCE(SUM(r.expected_commission_kzt), 0) - COALESCE(SUM(r.actual_amount_kzt) FILTER (WHERE r.actual_transaction_id IS NOT NULL), 0) AS difference_kzt,
    (
      SELECT jsonb_object_agg(reason, cnt)
      FROM (
        SELECT 
          COALESCE(rec.missing_reason, 'has_commission') AS reason,
          COUNT(*) AS cnt
        FROM reconciliation rec
        GROUP BY rec.missing_reason
      ) grouped
    ) AS missing_reasons
  FROM reconciliation r;
END;
$$;