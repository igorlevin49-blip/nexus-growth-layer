-- Drop existing functions first to change return types
DROP FUNCTION IF EXISTS get_partner_orders_for_month(uuid, integer, integer);
DROP FUNCTION IF EXISTS get_monthly_activation_report(integer, integer, text, text, integer, integer);
DROP FUNCTION IF EXISTS get_monthly_activation_count(integer, integer, text, text);

-- Fix get_monthly_activation_report to use COALESCE for dates
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
  orders_count bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_threshold numeric;
  v_period_start timestamp with time zone;
  v_period_end timestamp with time zone;
BEGIN
  SELECT COALESCE(monthly_activation_required_kzt, 20000) INTO v_threshold
  FROM shop_settings WHERE id = 1;
  
  IF v_threshold IS NULL THEN
    v_threshold := 20000;
  END IF;

  v_period_start := make_timestamptz(p_year, p_month, 1, 0, 0, 0, 'UTC');
  v_period_end := v_period_start + interval '1 month';

  RETURN QUERY
  WITH order_stats AS (
    SELECT 
      o.user_id,
      SUM(o.total_kzt) as total_amount,
      COUNT(*) as order_count,
      MAX(COALESCE(o.paid_at, o.created_at)) as last_order
    FROM orders o
    WHERE o.status = 'paid'
      AND COALESCE(o.paid_at, o.created_at) >= v_period_start
      AND COALESCE(o.paid_at, o.created_at) < v_period_end
      AND o.user_id IS NOT NULL
    GROUP BY o.user_id
  )
  SELECT 
    p.id as user_id,
    p.full_name,
    p.email,
    p.referral_code,
    COALESCE(os.total_amount, 0) as total_amount_kzt,
    v_threshold as threshold_kzt,
    COALESCE(os.total_amount, 0) >= v_threshold as is_activated,
    os.last_order as last_order_date,
    COALESCE(os.order_count, 0) as orders_count
  FROM profiles p
  LEFT JOIN order_stats os ON os.user_id = p.id
  WHERE 
    p.is_active = true
    AND p.deleted_at IS NULL
    AND (p.is_archived IS NULL OR p.is_archived = false)
    AND (os.total_amount IS NOT NULL OR p_status = 'all')
    AND (
      p_status = 'all'
      OR (p_status = 'activated' AND COALESCE(os.total_amount, 0) >= v_threshold)
      OR (p_status = 'not_activated' AND COALESCE(os.total_amount, 0) < v_threshold)
    )
    AND (
      p_search IS NULL 
      OR p_search = ''
      OR p.full_name ILIKE '%' || p_search || '%'
      OR p.email ILIKE '%' || p_search || '%'
      OR p.referral_code ILIKE '%' || p_search || '%'
    )
  ORDER BY COALESCE(os.total_amount, 0) DESC, p.full_name
  LIMIT p_limit
  OFFSET p_offset;
END;
$$;

-- Fix get_partner_orders_for_month to use COALESCE for dates
CREATE OR REPLACE FUNCTION get_partner_orders_for_month(
  p_user_id uuid,
  p_year integer,
  p_month integer
)
RETURNS TABLE (
  order_id uuid,
  order_date timestamp with time zone,
  total_kzt numeric,
  total_usd numeric,
  status text,
  items json
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_period_start timestamp with time zone;
  v_period_end timestamp with time zone;
BEGIN
  v_period_start := make_timestamptz(p_year, p_month, 1, 0, 0, 0, 'UTC');
  v_period_end := v_period_start + interval '1 month';

  RETURN QUERY
  SELECT 
    o.id as order_id,
    COALESCE(o.paid_at, o.created_at) as order_date,
    o.total_kzt,
    o.total_usd,
    o.status::text,
    COALESCE(
      (
        SELECT json_agg(json_build_object(
          'product_id', oi.product_id,
          'title', COALESCE(pr.title, 'Товар удален'),
          'qty', oi.qty,
          'price_kzt', oi.price_kzt,
          'is_activation', oi.is_activation_snapshot
        ))
        FROM order_items oi
        LEFT JOIN products pr ON pr.id = oi.product_id
        WHERE oi.order_id = o.id
      ),
      '[]'::json
    ) as items
  FROM orders o
  WHERE o.user_id = p_user_id
    AND o.status = 'paid'
    AND COALESCE(o.paid_at, o.created_at) >= v_period_start
    AND COALESCE(o.paid_at, o.created_at) < v_period_end
  ORDER BY COALESCE(o.paid_at, o.created_at) DESC;
END;
$$;

-- Fix get_monthly_activation_count
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
  v_threshold numeric;
  v_period_start timestamp with time zone;
  v_period_end timestamp with time zone;
  v_total integer;
  v_activated integer;
  v_not_activated integer;
BEGIN
  SELECT COALESCE(monthly_activation_required_kzt, 20000) INTO v_threshold
  FROM shop_settings WHERE id = 1;
  
  IF v_threshold IS NULL THEN
    v_threshold := 20000;
  END IF;

  v_period_start := make_timestamptz(p_year, p_month, 1, 0, 0, 0, 'UTC');
  v_period_end := v_period_start + interval '1 month';

  WITH order_stats AS (
    SELECT 
      o.user_id,
      SUM(o.total_kzt) as total_amount
    FROM orders o
    WHERE o.status = 'paid'
      AND COALESCE(o.paid_at, o.created_at) >= v_period_start
      AND COALESCE(o.paid_at, o.created_at) < v_period_end
      AND o.user_id IS NOT NULL
    GROUP BY o.user_id
  ),
  filtered_profiles AS (
    SELECT 
      p.id,
      COALESCE(os.total_amount, 0) as total_amount
    FROM profiles p
    LEFT JOIN order_stats os ON os.user_id = p.id
    WHERE 
      p.is_active = true
      AND p.deleted_at IS NULL
      AND (p.is_archived IS NULL OR p.is_archived = false)
      AND (os.total_amount IS NOT NULL OR p_status = 'all')
      AND (
        p_search IS NULL 
        OR p_search = ''
        OR p.full_name ILIKE '%' || p_search || '%'
        OR p.email ILIKE '%' || p_search || '%'
        OR p.referral_code ILIKE '%' || p_search || '%'
      )
  )
  SELECT 
    COUNT(*)::integer,
    COUNT(*) FILTER (WHERE total_amount >= v_threshold)::integer,
    COUNT(*) FILTER (WHERE total_amount < v_threshold)::integer
  INTO v_total, v_activated, v_not_activated
  FROM filtered_profiles;

  RETURN json_build_object(
    'total', v_total,
    'activated', v_activated,
    'not_activated', v_not_activated,
    'threshold_kzt', v_threshold
  );
END;
$$;

-- Update trigger to handle order updates for monthly activation
CREATE OR REPLACE FUNCTION update_monthly_activation_on_order()
RETURNS TRIGGER AS $$
DECLARE
  v_year integer;
  v_month integer;
  v_threshold numeric;
  v_total numeric;
  v_last_order_id uuid;
  v_last_order_date timestamp with time zone;
  v_order_date timestamp with time zone;
BEGIN
  -- Only process when order becomes paid
  IF NEW.status = 'paid' AND (OLD IS NULL OR OLD.status IS DISTINCT FROM 'paid') THEN
    -- Use paid_at or created_at
    v_order_date := COALESCE(NEW.paid_at, NEW.created_at);
    v_year := EXTRACT(YEAR FROM v_order_date)::integer;
    v_month := EXTRACT(MONTH FROM v_order_date)::integer;
    
    -- Get threshold
    SELECT COALESCE(monthly_activation_required_kzt, 20000) INTO v_threshold
    FROM shop_settings WHERE id = 1;
    
    IF v_threshold IS NULL THEN
      v_threshold := 20000;
    END IF;
    
    -- Calculate total for this month
    SELECT 
      COALESCE(SUM(total_kzt), 0),
      MAX(COALESCE(paid_at, created_at))
    INTO v_total, v_last_order_date
    FROM orders
    WHERE user_id = NEW.user_id
      AND status = 'paid'
      AND EXTRACT(YEAR FROM COALESCE(paid_at, created_at)) = v_year
      AND EXTRACT(MONTH FROM COALESCE(paid_at, created_at)) = v_month;
    
    -- Get last order id
    SELECT id INTO v_last_order_id
    FROM orders
    WHERE user_id = NEW.user_id
      AND status = 'paid'
      AND EXTRACT(YEAR FROM COALESCE(paid_at, created_at)) = v_year
      AND EXTRACT(MONTH FROM COALESCE(paid_at, created_at)) = v_month
    ORDER BY COALESCE(paid_at, created_at) DESC
    LIMIT 1;
    
    -- Upsert monthly activation
    INSERT INTO monthly_activations (
      user_id, year, month, total_amount_kzt, threshold_kzt, 
      is_activated, last_order_id, last_order_date
    )
    VALUES (
      NEW.user_id, v_year, v_month, v_total, v_threshold,
      v_total >= v_threshold, v_last_order_id, v_last_order_date
    )
    ON CONFLICT (user_id, year, month)
    DO UPDATE SET
      total_amount_kzt = EXCLUDED.total_amount_kzt,
      is_activated = EXCLUDED.is_activated,
      last_order_id = EXCLUDED.last_order_id,
      last_order_date = EXCLUDED.last_order_date,
      updated_at = now();
    
    -- Update profile for current month only
    IF v_year = EXTRACT(YEAR FROM now())::integer AND v_month = EXTRACT(MONTH FROM now())::integer THEN
      UPDATE profiles
      SET monthly_activation_completed = (v_total >= v_threshold)
      WHERE id = NEW.user_id;
    END IF;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_update_monthly_activation_on_order ON orders;
CREATE TRIGGER trg_update_monthly_activation_on_order
AFTER INSERT OR UPDATE ON orders
FOR EACH ROW
EXECUTE FUNCTION update_monthly_activation_on_order();