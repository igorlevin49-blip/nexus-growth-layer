-- Fix get_monthly_activation_report to show partners with activation_due_from in the selected month
CREATE OR REPLACE FUNCTION get_monthly_activation_report(
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
  last_order_date timestamp with time zone,
  orders_count bigint,
  activation_due_from timestamp with time zone
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    p.id as user_id,
    p.full_name,
    p.email,
    p.referral_code,
    COALESCE(ma.total_amount_kzt, 0) as total_amount_kzt,
    COALESCE(ma.threshold_kzt, (SELECT monthly_activation_required_kzt FROM shop_settings WHERE id = 1)) as threshold_kzt,
    COALESCE(ma.is_activated, false) as is_activated,
    ma.last_order_date,
    (
      SELECT COUNT(*)
      FROM orders o
      WHERE o.user_id = p.id
        AND o.status = 'paid'
        AND date_trunc('month', o.paid_at) = date_trunc('month', make_timestamptz(p_year, p_month, 1, 0, 0, 0))
    ) as orders_count,
    p.activation_due_from
  FROM profiles p
  LEFT JOIN monthly_activations ma ON ma.user_id = p.id 
    AND ma.year = p_year 
    AND ma.month = p_month
  WHERE p.deleted_at IS NULL
    AND p.is_active = true
    -- Show partners whose activation_due_from is within or before the selected month
    AND p.activation_due_from IS NOT NULL
    AND p.activation_due_from < make_timestamptz(
      CASE WHEN p_month = 12 THEN p_year + 1 ELSE p_year END,
      CASE WHEN p_month = 12 THEN 1 ELSE p_month + 1 END,
      1, 0, 0, 0
    )
    AND (
      p_status = 'all'
      OR (p_status = 'activated' AND COALESCE(ma.is_activated, false) = true)
      OR (p_status = 'not_activated' AND COALESCE(ma.is_activated, false) = false)
    )
    AND (
      p_search IS NULL
      OR p.full_name ILIKE '%' || p_search || '%'
      OR p.email ILIKE '%' || p_search || '%'
      OR p.referral_code ILIKE '%' || p_search || '%'
    )
  ORDER BY p.full_name
  LIMIT p_limit
  OFFSET p_offset;
END;
$$;

-- Fix get_monthly_activation_count to use the same filtering logic
CREATE OR REPLACE FUNCTION get_monthly_activation_count(
  p_year integer,
  p_month integer,
  p_status text DEFAULT 'all',
  p_search text DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_total integer;
  v_activated integer;
  v_not_activated integer;
  v_threshold numeric;
BEGIN
  SELECT monthly_activation_required_kzt INTO v_threshold FROM shop_settings WHERE id = 1;

  SELECT 
    COUNT(*),
    COUNT(*) FILTER (WHERE COALESCE(ma.is_activated, false) = true),
    COUNT(*) FILTER (WHERE COALESCE(ma.is_activated, false) = false)
  INTO v_total, v_activated, v_not_activated
  FROM profiles p
  LEFT JOIN monthly_activations ma ON ma.user_id = p.id 
    AND ma.year = p_year 
    AND ma.month = p_month
  WHERE p.deleted_at IS NULL
    AND p.is_active = true
    -- Use the same filter as the report function
    AND p.activation_due_from IS NOT NULL
    AND p.activation_due_from < make_timestamptz(
      CASE WHEN p_month = 12 THEN p_year + 1 ELSE p_year END,
      CASE WHEN p_month = 12 THEN 1 ELSE p_month + 1 END,
      1, 0, 0, 0
    )
    AND (
      p_search IS NULL
      OR p.full_name ILIKE '%' || p_search || '%'
      OR p.email ILIKE '%' || p_search || '%'
      OR p.referral_code ILIKE '%' || p_search || '%'
    );

  RETURN json_build_object(
    'total', v_total,
    'activated', v_activated,
    'not_activated', v_not_activated,
    'threshold_kzt', v_threshold
  );
END;
$$;