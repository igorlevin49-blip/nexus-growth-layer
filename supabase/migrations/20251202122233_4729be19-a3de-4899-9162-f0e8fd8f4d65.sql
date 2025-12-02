-- Update get_admin_global_stats to include subscriptions revenue
CREATE OR REPLACE FUNCTION public.get_admin_global_stats(
  start_date timestamp with time zone DEFAULT date_trunc('month'::text, now()),
  end_date timestamp with time zone DEFAULT now()
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
SET search_path TO 'public'
AS $function$
BEGIN
  RETURN QUERY
  SELECT 
    -- Общий доход (подписки + заказы)
    COALESCE(
      (SELECT SUM(amount_usd * 100)::bigint FROM subscriptions
       WHERE status = 'active' AND paid_at >= start_date AND paid_at <= end_date),
      0
    ) + 
    COALESCE(
      (SELECT SUM(total_usd * 100)::bigint FROM orders 
       WHERE status = 'paid' AND paid_at >= start_date AND paid_at <= end_date),
      0
    ) as total_revenue_cents,
    
    -- Активные пользователи (с активной подпиской ИЛИ выполненной активацией)
    (SELECT COUNT(DISTINCT id)::bigint FROM profiles 
     WHERE (subscription_status = 'active' OR monthly_activation_completed = true)
    ) as active_users_count,
    
    -- Количество заказов
    (SELECT COUNT(*)::bigint FROM orders 
     WHERE status = 'paid' AND paid_at >= start_date AND paid_at <= end_date
    ) as orders_count,
    
    -- Средний чек (подписки + заказы)
    COALESCE(
      (
        (
          COALESCE((SELECT SUM(amount_usd * 100) FROM subscriptions WHERE status = 'active' AND paid_at >= start_date AND paid_at <= end_date), 0) +
          COALESCE((SELECT SUM(total_usd * 100) FROM orders WHERE status = 'paid' AND paid_at >= start_date AND paid_at <= end_date), 0)
        ) / 
        NULLIF(
          (SELECT COUNT(*) FROM subscriptions WHERE status = 'active' AND paid_at >= start_date AND paid_at <= end_date) +
          (SELECT COUNT(*) FROM orders WHERE status = 'paid' AND paid_at >= start_date AND paid_at <= end_date),
          0
        )
      )::bigint,
      0
    ) as avg_order_cents,
    
    -- Количество активных подписок
    (SELECT COUNT(*)::bigint FROM profiles WHERE subscription_status = 'active') as subscriptions_count,
    
    -- Количество замороженных пользователей
    (SELECT COUNT(*)::bigint FROM profiles WHERE subscription_status = 'frozen') as frozen_users_count;
END;
$function$;