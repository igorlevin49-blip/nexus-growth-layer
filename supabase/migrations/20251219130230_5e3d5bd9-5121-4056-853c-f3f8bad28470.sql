-- Add admin_comment column to monthly_activations table
ALTER TABLE monthly_activations ADD COLUMN IF NOT EXISTS admin_comment TEXT;

-- Drop and recreate the function with new return type
DROP FUNCTION IF EXISTS get_monthly_activation_report(INTEGER, INTEGER, TEXT, TEXT, INTEGER, INTEGER);

CREATE OR REPLACE FUNCTION get_monthly_activation_report(
  p_year INTEGER,
  p_month INTEGER,
  p_status TEXT DEFAULT 'all',
  p_search TEXT DEFAULT NULL,
  p_limit INTEGER DEFAULT 50,
  p_offset INTEGER DEFAULT 0
)
RETURNS TABLE (
  user_id UUID,
  full_name TEXT,
  email TEXT,
  referral_code TEXT,
  total_amount_kzt NUMERIC,
  threshold_kzt NUMERIC,
  is_activated BOOLEAN,
  last_order_date TIMESTAMPTZ,
  orders_count BIGINT,
  activation_due_from TIMESTAMPTZ,
  admin_comment TEXT
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    ma.user_id,
    p.full_name,
    p.email,
    p.referral_code,
    ma.total_amount_kzt,
    ma.threshold_kzt,
    ma.is_activated,
    ma.last_order_date,
    (
      SELECT COUNT(*)::BIGINT
      FROM orders o
      WHERE o.user_id = ma.user_id
        AND o.status = 'paid'
        AND EXTRACT(YEAR FROM o.paid_at) = p_year
        AND EXTRACT(MONTH FROM o.paid_at) = p_month
    ) AS orders_count,
    p.activation_due_from,
    ma.admin_comment
  FROM monthly_activations ma
  JOIN profiles p ON p.id = ma.user_id
  WHERE ma.year = p_year
    AND ma.month = p_month
    AND (
      p_status = 'all'
      OR (p_status = 'activated' AND ma.is_activated = true)
      OR (p_status = 'not_activated' AND ma.is_activated = false)
    )
    AND (
      p_search IS NULL
      OR p.full_name ILIKE '%' || p_search || '%'
      OR p.email ILIKE '%' || p_search || '%'
      OR p.referral_code ILIKE '%' || p_search || '%'
    )
  ORDER BY ma.is_activated ASC, ma.total_amount_kzt DESC
  LIMIT p_limit
  OFFSET p_offset;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;