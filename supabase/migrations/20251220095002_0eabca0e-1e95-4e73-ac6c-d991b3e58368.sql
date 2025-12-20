-- Исправление функции recalculate_monthly_activations
-- Теперь считает сумму из order_items вместо orders.total_kzt
-- Это исправляет проблему когда orders.total_kzt был неправильно рассчитан

DROP FUNCTION IF EXISTS recalculate_monthly_activations(uuid, integer, integer);

CREATE OR REPLACE FUNCTION recalculate_monthly_activations(
  p_admin_id uuid,
  p_year integer DEFAULT NULL,
  p_month integer DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_year integer;
  v_month integer;
  v_threshold numeric;
  v_period_start timestamp with time zone;
  v_period_end timestamp with time zone;
  v_updated integer := 0;
  v_inserted integer := 0;
BEGIN
  -- Use provided year/month or current
  v_year := COALESCE(p_year, EXTRACT(YEAR FROM now())::integer);
  v_month := COALESCE(p_month, EXTRACT(MONTH FROM now())::integer);
  
  -- Get threshold
  SELECT COALESCE(monthly_activation_required_kzt, 20000) INTO v_threshold
  FROM shop_settings WHERE id = 1;
  
  IF v_threshold IS NULL THEN
    v_threshold := 20000;
  END IF;
  
  v_period_start := make_timestamptz(v_year, v_month, 1, 0, 0, 0, 'UTC');
  v_period_end := v_period_start + interval '1 month';
  
  -- Create temp table with order stats - NOW USING order_items for accurate sum
  CREATE TEMP TABLE IF NOT EXISTS tmp_order_stats_recalc (
    user_id uuid,
    total_amount numeric,
    last_order_date timestamp with time zone
  );
  TRUNCATE tmp_order_stats_recalc;
  
  INSERT INTO tmp_order_stats_recalc
  SELECT 
    o.user_id,
    -- Исправление: считаем сумму из order_items, а не orders.total_kzt
    SUM((
      SELECT COALESCE(SUM(oi.price_kzt * oi.qty), 0)
      FROM order_items oi
      WHERE oi.order_id = o.id
    )) as total_amount,
    MAX(COALESCE(o.paid_at, o.created_at)) as last_order_date
  FROM orders o
  WHERE o.status = 'paid'
    AND COALESCE(o.paid_at, o.created_at) >= v_period_start
    AND COALESCE(o.paid_at, o.created_at) < v_period_end
    AND o.user_id IS NOT NULL
  GROUP BY o.user_id;
  
  -- Get last_order_id for each user (separate query to avoid MAX(uuid) error)
  CREATE TEMP TABLE IF NOT EXISTS tmp_last_orders_recalc (
    user_id uuid,
    last_order_id uuid
  );
  TRUNCATE tmp_last_orders_recalc;
  
  INSERT INTO tmp_last_orders_recalc
  SELECT DISTINCT ON (o.user_id) 
    o.user_id,
    o.id as last_order_id
  FROM orders o
  WHERE o.status = 'paid'
    AND COALESCE(o.paid_at, o.created_at) >= v_period_start
    AND COALESCE(o.paid_at, o.created_at) < v_period_end
    AND o.user_id IS NOT NULL
  ORDER BY o.user_id, COALESCE(o.paid_at, o.created_at) DESC;
  
  -- Upsert monthly activations
  INSERT INTO monthly_activations (
    user_id, year, month, total_amount_kzt, threshold_kzt, 
    is_activated, last_order_id, last_order_date
  )
  SELECT 
    os.user_id,
    v_year,
    v_month,
    os.total_amount,
    v_threshold,
    os.total_amount >= v_threshold,
    lo.last_order_id,
    os.last_order_date
  FROM tmp_order_stats_recalc os
  JOIN tmp_last_orders_recalc lo ON lo.user_id = os.user_id
  ON CONFLICT (user_id, year, month)
  DO UPDATE SET
    total_amount_kzt = EXCLUDED.total_amount_kzt,
    threshold_kzt = EXCLUDED.threshold_kzt,
    is_activated = EXCLUDED.is_activated,
    last_order_id = EXCLUDED.last_order_id,
    last_order_date = EXCLUDED.last_order_date,
    updated_at = now();
  
  GET DIAGNOSTICS v_inserted = ROW_COUNT;
  
  -- Update profiles for current month
  IF v_year = EXTRACT(YEAR FROM now())::integer AND v_month = EXTRACT(MONTH FROM now())::integer THEN
    UPDATE profiles p
    SET monthly_activation_completed = (
      SELECT COALESCE(ma.is_activated, false)
      FROM monthly_activations ma
      WHERE ma.user_id = p.id AND ma.year = v_year AND ma.month = v_month
    )
    WHERE p.is_active = true AND p.deleted_at IS NULL;
    
    GET DIAGNOSTICS v_updated = ROW_COUNT;
  END IF;
  
  -- Log admin action
  INSERT INTO admin_actions (admin_id, action_type, target_type, metadata)
  VALUES (p_admin_id, 'recalculate_monthly_activations', 'monthly_activations', 
    json_build_object('year', v_year, 'month', v_month, 'inserted', v_inserted, 'profiles_updated', v_updated));
  
  RETURN json_build_object(
    'success', true,
    'year', v_year,
    'month', v_month,
    'activations_processed', v_inserted,
    'profiles_updated', v_updated,
    'threshold_kzt', v_threshold
  );
END;
$$;