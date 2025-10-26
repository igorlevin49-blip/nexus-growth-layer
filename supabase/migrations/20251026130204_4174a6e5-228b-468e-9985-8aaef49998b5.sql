-- Таблица глобальных параметров MLM
CREATE TABLE IF NOT EXISTS public.mlm_settings (
  key text PRIMARY KEY,
  value jsonb NOT NULL,
  description text,
  updated_at timestamptz DEFAULT now()
);

-- Обновить structure_type в mlm_commission_rules, добавить is_active
ALTER TABLE public.mlm_commission_rules 
  DROP CONSTRAINT IF EXISTS mlm_commission_rules_structure_type_check;

ALTER TABLE public.mlm_commission_rules 
  ADD CONSTRAINT mlm_commission_rules_structure_type_check 
  CHECK (structure_type IN (1, 2));

ALTER TABLE public.mlm_commission_rules 
  ADD COLUMN IF NOT EXISTS is_active boolean NOT NULL DEFAULT true;

-- Инициализировать настройки (если не существуют)
INSERT INTO public.mlm_settings (key, value, description) VALUES
  ('monthly_activation', '{"min_usd": 40, "min_kzt": 18000}'::jsonb, 'Порог ежемесячной активации'),
  ('subscription_price_usd', '{"value": 100}'::jsonb, 'Стоимость годовой подписки в USD'),
  ('unlock_levels', '{"l2": 3, "l3": 5, "l4": 8, "l5": 10}'::jsonb, 'Количество прямых рефералов для открытия уровней'),
  ('currency', '{"base": "KZT", "usd_rate": 480}'::jsonb, 'Базовая валюта и курс')
ON CONFLICT (key) DO NOTHING;

-- RLS policies для mlm_settings
ALTER TABLE public.mlm_settings ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone can view settings"
  ON public.mlm_settings FOR SELECT
  USING (true);

CREATE POLICY "Superadmins can manage settings"
  ON public.mlm_settings FOR ALL
  USING (has_role(auth.uid(), 'superadmin'::app_role));

-- Функция для получения статистики по структурам для админа
CREATE OR REPLACE FUNCTION public.get_admin_structure_stats(
  structure_type_param int,
  start_date timestamptz DEFAULT date_trunc('month', now()),
  end_date timestamptz DEFAULT now()
)
RETURNS TABLE(
  level int,
  percent numeric,
  transactions_count bigint,
  total_amount_cents bigint,
  frozen_amount_cents bigint,
  pass_up_count bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  WITH rules AS (
    SELECT mcr.level, mcr.percent
    FROM mlm_commission_rules mcr
    WHERE mcr.structure_type = structure_type_param
      AND mcr.plan_id = 'default'
      AND mcr.is_active = true
    ORDER BY mcr.level
  )
  SELECT 
    r.level,
    r.percent,
    COUNT(t.id)::bigint as transactions_count,
    COALESCE(SUM(CASE WHEN t.status = 'completed' THEN t.amount_cents ELSE 0 END), 0)::bigint as total_amount_cents,
    COALESCE(SUM(CASE WHEN t.frozen_until > now() THEN t.amount_cents ELSE 0 END), 0)::bigint as frozen_amount_cents,
    COALESCE(SUM((t.payload->>'pass_up_applied')::int), 0)::bigint as pass_up_count
  FROM rules r
  LEFT JOIN transactions t ON 
    t.level = r.level 
    AND t.type = 'commission'
    AND (
      (structure_type_param = 1 AND t.structure_type = 'primary') OR
      (structure_type_param = 2 AND t.structure_type = 'secondary')
    )
    AND t.created_at >= start_date
    AND t.created_at <= end_date
  GROUP BY r.level, r.percent
  ORDER BY r.level;
END;
$$;

-- Функция для получения общей статистики для админа
CREATE OR REPLACE FUNCTION public.get_admin_global_stats(
  start_date timestamptz DEFAULT date_trunc('month', now()),
  end_date timestamptz DEFAULT now()
)
RETURNS TABLE(
  total_revenue_cents bigint,
  active_users_count bigint,
  orders_count bigint,
  avg_order_cents bigint,
  subscriptions_count bigint,
  frozen_users_count bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    -- Общий доход (подписки + заказы)
    COALESCE(
      (SELECT SUM(total_usd * 100)::bigint FROM orders 
       WHERE status = 'paid' AND created_at >= start_date AND created_at <= end_date),
      0
    ) as total_revenue_cents,
    
    -- Активные пользователи (с активной подпиской ИЛИ выполненной активацией)
    (SELECT COUNT(DISTINCT id)::bigint FROM profiles 
     WHERE (subscription_status = 'active' OR monthly_activation_completed = true)
    ) as active_users_count,
    
    -- Количество заказов
    (SELECT COUNT(*)::bigint FROM orders 
     WHERE status = 'paid' AND created_at >= start_date AND created_at <= end_date
    ) as orders_count,
    
    -- Средний чек
    COALESCE(
      (SELECT (SUM(total_usd * 100) / NULLIF(COUNT(*), 0))::bigint FROM orders 
       WHERE status = 'paid' AND created_at >= start_date AND created_at <= end_date),
      0
    ) as avg_order_cents,
    
    -- Количество активных подписок
    (SELECT COUNT(*)::bigint FROM profiles WHERE subscription_status = 'active') as subscriptions_count,
    
    -- Количество замороженных пользователей
    (SELECT COUNT(*)::bigint FROM profiles WHERE subscription_status = 'frozen') as frozen_users_count;
END;
$$;