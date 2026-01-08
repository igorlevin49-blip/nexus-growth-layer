-- Fix all functions that incorrectly use 'completed' and 'delivered' enum values
-- These values don't exist in order_status enum, causing errors

-- 1. Fix check_activation_status trigger function
CREATE OR REPLACE FUNCTION public.check_activation_status()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  user_activation_due_from timestamptz;
  threshold_kzt numeric;
  total_amount numeric;
  v_period record;
BEGIN
  -- Get user profile data
  SELECT activation_due_from
  INTO user_activation_due_from
  FROM profiles
  WHERE id = NEW.user_id;

  -- If no activation_due_from set, activation check not needed yet
  IF user_activation_due_from IS NULL THEN
    RETURN NEW;
  END IF;

  -- Get current personal period
  SELECT * INTO v_period FROM get_user_activation_period(NEW.user_id, NOW());
  
  -- If in grace period, mark as activated
  IF v_period.is_grace_period THEN
    UPDATE profiles
    SET monthly_activation_completed = true
    WHERE id = NEW.user_id;
    RETURN NEW;
  END IF;

  -- Get threshold
  SELECT COALESCE(monthly_activation_required_kzt, 20000) INTO threshold_kzt
  FROM shop_settings WHERE id = 1;

  -- Calculate total orders in current personal period
  -- Use ::text cast to avoid enum validation errors
  SELECT COALESCE(SUM(total_kzt), 0) INTO total_amount
  FROM orders
  WHERE user_id = NEW.user_id
    AND status::text IN ('paid', 'completed', 'delivered')
    AND created_at >= v_period.period_start
    AND created_at < v_period.period_end;

  -- Update activation status
  IF total_amount >= threshold_kzt THEN
    UPDATE profiles
    SET monthly_activation_completed = true
    WHERE id = NEW.user_id;
    
    -- Log activation
    INSERT INTO activity_log (user_id, type, payload)
    VALUES (
      NEW.user_id,
      'monthly_activation_completed',
      jsonb_build_object(
        'period_number', v_period.period_number,
        'period_start', v_period.period_start,
        'period_end', v_period.period_end,
        'total_amount', total_amount,
        'threshold', threshold_kzt
      )
    );
  END IF;

  RETURN NEW;
END;
$$;

-- 2. DROP and recreate get_personal_activation_status with matching signature
DROP FUNCTION IF EXISTS public.get_personal_activation_status(uuid);

CREATE FUNCTION public.get_personal_activation_status(p_user_id uuid)
RETURNS TABLE(
  period_number integer,
  period_start timestamptz,
  period_end timestamptz,
  is_grace_period boolean,
  days_remaining integer,
  required_amount_kzt numeric,
  current_amount_kzt numeric,
  is_activated boolean,
  orders_count integer
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_period record;
  v_threshold numeric;
  v_total numeric;
  v_orders_count integer;
BEGIN
  -- Get current period for user
  SELECT * INTO v_period FROM get_user_activation_period(p_user_id, NOW());
  
  -- Get threshold
  SELECT COALESCE(monthly_activation_required_kzt, 20000) INTO v_threshold
  FROM shop_settings WHERE id = 1;
  
  -- Calculate total orders in period using ::text cast to avoid enum errors
  SELECT COALESCE(SUM(o.total_kzt), 0), COUNT(*)::integer
  INTO v_total, v_orders_count
  FROM orders o
  WHERE o.user_id = p_user_id
    AND o.status::text IN ('paid', 'completed', 'delivered')
    AND o.created_at >= v_period.period_start
    AND o.created_at < v_period.period_end;
  
  RETURN QUERY SELECT 
    v_period.period_number,
    v_period.period_start,
    v_period.period_end,
    v_period.is_grace_period,
    v_period.days_remaining,
    v_threshold,
    v_total,
    (v_period.is_grace_period OR v_total >= v_threshold),
    v_orders_count;
END;
$$;

-- 3. Fix get_monthly_activation_report function (with personal periods)
CREATE OR REPLACE FUNCTION public.get_monthly_activation_report(
  p_year integer,
  p_month integer
)
RETURNS TABLE(
  user_id uuid,
  full_name text,
  email text,
  partner_id text,
  activation_due_from timestamptz,
  period_start timestamptz,
  period_end timestamptz,
  period_number integer,
  is_grace_period boolean,
  total_orders numeric,
  threshold_kzt numeric,
  is_activated boolean,
  subscription_status text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_threshold numeric;
  v_report_date timestamptz;
BEGIN
  -- Get the threshold
  SELECT COALESCE(monthly_activation_required_kzt, 20000) INTO v_threshold
  FROM shop_settings WHERE id = 1;
  
  -- Create a reference date in the middle of the requested month
  v_report_date := make_timestamptz(p_year, p_month, 15, 12, 0, 0, 'UTC');
  
  RETURN QUERY
  WITH user_periods AS (
    SELECT 
      p.id as uid,
      p.full_name,
      p.email,
      p.partner_id,
      p.activation_due_from,
      p.subscription_status,
      (get_user_activation_period(p.id, v_report_date)).*
    FROM profiles p
    WHERE p.activation_due_from IS NOT NULL
      AND p.subscription_status = 'active'
  ),
  user_orders AS (
    SELECT 
      up.uid,
      COALESCE(SUM(o.total_kzt), 0) as order_total
    FROM user_periods up
    LEFT JOIN orders o ON o.user_id = up.uid
      AND o.status::text IN ('paid', 'completed', 'delivered')
      AND o.created_at >= up.period_start
      AND o.created_at < up.period_end
    GROUP BY up.uid
  )
  SELECT 
    up.uid,
    up.full_name,
    up.email,
    up.partner_id,
    up.activation_due_from,
    up.period_start,
    up.period_end,
    up.period_number,
    up.is_grace_period,
    uo.order_total,
    v_threshold,
    (up.is_grace_period OR uo.order_total >= v_threshold),
    up.subscription_status
  FROM user_periods up
  JOIN user_orders uo ON uo.uid = up.uid
  ORDER BY up.full_name;
END;
$$;