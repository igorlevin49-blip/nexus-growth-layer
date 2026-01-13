
-- Обновляем RPC функцию admin_audit_user_commissions чтобы она возвращала _kzt вместо _cents

DROP FUNCTION IF EXISTS public.admin_audit_user_commissions(uuid, uuid);

CREATE OR REPLACE FUNCTION public.admin_audit_user_commissions(
  p_admin_id uuid,
  p_user_id uuid
)
RETURNS TABLE (
  partner_id uuid,
  partner_name text,
  partner_email text,
  level integer,
  subscription_id uuid,
  subscription_amount_kzt numeric,
  commission_received boolean,
  commission_amount_kzt bigint,  -- Переименовано с _cents
  expected_percent numeric,
  expected_commission_kzt bigint,  -- Переименовано с _cents
  actual_vs_expected text,
  no_commission_reason text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Проверка прав администратора
  IF NOT EXISTS (
    SELECT 1 FROM user_roles 
    WHERE user_id = p_admin_id AND role IN ('admin', 'superadmin')
  ) THEN
    RAISE EXCEPTION 'Access denied: admin role required';
  END IF;

  RETURN QUERY
  WITH user_partners AS (
    -- Получаем всех прямых партнёров пользователя (уровень 1)
    SELECT 
      p.id AS partner_id,
      p.full_name AS partner_name,
      p.email AS partner_email,
      1 AS level
    FROM profiles p
    WHERE p.sponsor_id = p_user_id
      AND p.deleted_at IS NULL
      AND (p.is_archived IS NOT TRUE)
  ),
  partner_subscriptions AS (
    -- Получаем все оплаченные подписки партнёров
    SELECT 
      up.partner_id,
      up.partner_name,
      up.partner_email,
      up.level,
      s.id AS subscription_id,
      s.amount_kzt AS subscription_amount_kzt,
      s.paid_at,
      s.is_marketing_free_access
    FROM user_partners up
    INNER JOIN subscriptions s ON s.user_id = up.partner_id
    WHERE s.status = 'active'
      AND s.paid_at IS NOT NULL
      AND (s.is_test IS NOT TRUE)
  ),
  commission_rules AS (
    -- Получаем процент для S1 Level 1
    SELECT percent FROM commission_plan_levels
    WHERE structure_type = 'primary' AND level = 1 AND plan_id = 'default'
    LIMIT 1
  ),
  existing_commissions AS (
    -- Существующие комиссии для этого пользователя
    SELECT 
      t.source_id AS subscription_id,
      t.amount_cents AS commission_amount_kzt,  -- amount_cents хранит целые тенге!
      t.level
    FROM transactions t
    WHERE t.user_id = p_user_id
      AND t.type = 'commission'
      AND t.structure_type = 'primary'
      AND t.level = 1
      AND t.source_ref LIKE 'sub_%'
  )
  SELECT 
    ps.partner_id,
    ps.partner_name,
    ps.partner_email,
    ps.level,
    ps.subscription_id,
    ps.subscription_amount_kzt,
    (ec.commission_amount_kzt IS NOT NULL) AS commission_received,
    COALESCE(ec.commission_amount_kzt, 0)::bigint AS commission_amount_kzt,
    COALESCE(cr.percent, 10)::numeric AS expected_percent,
    (ps.subscription_amount_kzt * COALESCE(cr.percent, 10) / 100)::bigint AS expected_commission_kzt,
    CASE
      WHEN ps.is_marketing_free_access = true THEN 'N/A'
      WHEN ec.commission_amount_kzt IS NULL THEN 'MISSING'
      WHEN ec.commission_amount_kzt = (ps.subscription_amount_kzt * COALESCE(cr.percent, 10) / 100)::bigint THEN 'OK'
      WHEN ec.commission_amount_kzt < (ps.subscription_amount_kzt * COALESCE(cr.percent, 10) / 100)::bigint THEN 'UNDERPAID'
      ELSE 'OVERPAID'
    END AS actual_vs_expected,
    CASE
      WHEN ps.is_marketing_free_access = true THEN 'marketing_free_access'
      WHEN ec.commission_amount_kzt IS NULL THEN 'unknown'
      ELSE NULL
    END AS no_commission_reason
  FROM partner_subscriptions ps
  CROSS JOIN commission_rules cr
  LEFT JOIN existing_commissions ec ON ec.subscription_id = ps.subscription_id
  ORDER BY ps.paid_at DESC;
END;
$$;
