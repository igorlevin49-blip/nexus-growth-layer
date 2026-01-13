
-- Fix get_monthly_activation_report to properly account for orders in grace period
-- The issue: orders paid BEFORE activation_due_from should count toward the first activation period

CREATE OR REPLACE FUNCTION public.get_monthly_activation_report(
  p_year integer,
  p_month integer,
  p_status text DEFAULT 'all',
  p_search text DEFAULT NULL,
  p_limit integer DEFAULT 50,
  p_offset integer DEFAULT 0
)
RETURNS TABLE (
  user_id uuid,
  full_name text,
  email text,
  referral_code text,
  total_amount_kzt numeric,
  threshold_kzt numeric,
  is_activated boolean,
  last_order_date timestamptz,
  orders_count bigint,
  activation_due_from timestamptz,
  admin_comment text,
  period_number integer,
  period_start timestamptz,
  period_end timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_month_start timestamptz;
  v_month_end timestamptz;
BEGIN
  -- Calculate the calendar month boundaries
  v_month_start := make_timestamptz(p_year, p_month, 1, 0, 0, 0);
  v_month_end := v_month_start + INTERVAL '1 month';

  RETURN QUERY
  WITH user_periods AS (
    SELECT 
      p.id AS uid,
      p.full_name,
      p.email,
      p.referral_code,
      p.activation_due_from,
      gp.period_number,
      gp.period_start,
      gp.period_end,
      gp.is_grace_period
    FROM profiles p
    CROSS JOIN LATERAL get_user_activation_period(p.id, 
      make_timestamptz(p_year, p_month, 15, 12, 0, 0)
    ) gp
    WHERE p.is_active = true
      AND p.subscription_status = 'active'
      AND p.activation_due_from IS NOT NULL
  ),
  user_orders AS (
    SELECT 
      o.user_id AS uid,
      COALESCE(SUM(o.total_kzt), 0) AS total_amount,
      MAX(o.paid_at) AS last_order,
      COUNT(o.id) AS order_count
    FROM orders o
    JOIN user_periods up ON up.uid = o.user_id
    WHERE o.status = 'paid'
      AND o.paid_at IS NOT NULL
      AND (
        -- Grace period: count orders from start of activation_due_from month up to activation_due_from
        (up.is_grace_period = true AND o.paid_at < up.period_end)
        -- Regular period: count orders within the period
        OR (up.is_grace_period = false AND o.paid_at >= up.period_start AND o.paid_at < up.period_end)
        -- ALSO: For first activation period (period_number = 1), include orders from grace period
        -- that were paid in the calendar month BEFORE activation_due_from but after user registration
        OR (
          up.period_number = 1 
          AND up.is_grace_period = false
          AND o.paid_at >= (up.period_start - INTERVAL '1 month')  -- Include previous month
          AND o.paid_at < up.period_end
        )
      )
    GROUP BY o.user_id
  ),
  activation_data AS (
    SELECT 
      ma.user_id AS uid,
      ma.admin_comment,
      ma.threshold_kzt AS ma_threshold
    FROM monthly_activations ma
    WHERE ma.year = p_year AND ma.month = p_month
  )
  SELECT 
    up.uid AS user_id,
    up.full_name,
    up.email,
    up.referral_code,
    COALESCE(uo.total_amount, 0) AS total_amount_kzt,
    COALESCE(ad.ma_threshold, (SELECT COALESCE(monthly_activation_required_kzt, 20000) FROM shop_settings WHERE id = 1)) AS threshold_kzt,
    CASE 
      WHEN up.is_grace_period THEN true
      ELSE COALESCE(uo.total_amount, 0) >= COALESCE(ad.ma_threshold, (SELECT COALESCE(monthly_activation_required_kzt, 20000) FROM shop_settings WHERE id = 1))
    END AS is_activated,
    uo.last_order AS last_order_date,
    COALESCE(uo.order_count, 0) AS orders_count,
    up.activation_due_from,
    ad.admin_comment,
    up.period_number,
    up.period_start,
    up.period_end
  FROM user_periods up
  LEFT JOIN user_orders uo ON uo.uid = up.uid
  LEFT JOIN activation_data ad ON ad.uid = up.uid
  WHERE (
    p_status = 'all'
    OR (p_status = 'activated' AND (up.is_grace_period OR COALESCE(uo.total_amount, 0) >= COALESCE(ad.ma_threshold, 20000)))
    OR (p_status = 'not_activated' AND NOT up.is_grace_period AND COALESCE(uo.total_amount, 0) < COALESCE(ad.ma_threshold, 20000))
  )
  AND (
    p_search IS NULL
    OR up.full_name ILIKE '%' || p_search || '%'
    OR up.email ILIKE '%' || p_search || '%'
    OR up.referral_code ILIKE '%' || p_search || '%'
  )
  ORDER BY up.full_name
  LIMIT p_limit
  OFFSET p_offset;
END;
$$;
