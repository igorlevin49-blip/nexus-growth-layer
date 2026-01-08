-- Step 1: Add personal period columns to monthly_activations
ALTER TABLE monthly_activations
ADD COLUMN IF NOT EXISTS period_start timestamptz,
ADD COLUMN IF NOT EXISTS period_end timestamptz,
ADD COLUMN IF NOT EXISTS period_number integer DEFAULT 0;

-- Create index for faster lookups
CREATE INDEX IF NOT EXISTS idx_monthly_activations_period 
ON monthly_activations(user_id, period_start, period_end);

-- Step 2: Create function to calculate personal activation period
CREATE OR REPLACE FUNCTION get_user_activation_period(
  p_user_id uuid,
  p_check_date timestamptz DEFAULT NOW()
)
RETURNS TABLE(
  period_number integer,
  period_start timestamptz,
  period_end timestamptz,
  is_grace_period boolean,
  days_remaining integer
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_activation_due_from timestamptz;
  v_months_elapsed integer;
  v_period_start timestamptz;
  v_period_end timestamptz;
BEGIN
  -- Get user's activation_due_from date
  SELECT p.activation_due_from INTO v_activation_due_from
  FROM profiles p
  WHERE p.id = p_user_id;
  
  -- If no activation_due_from, user is in grace period (first month)
  IF v_activation_due_from IS NULL THEN
    RETURN QUERY SELECT 
      0::integer AS period_number,
      NULL::timestamptz AS period_start,
      NULL::timestamptz AS period_end,
      true AS is_grace_period,
      NULL::integer AS days_remaining;
    RETURN;
  END IF;
  
  -- If check_date is before activation_due_from, still in grace period
  IF p_check_date < v_activation_due_from THEN
    RETURN QUERY SELECT 
      0::integer AS period_number,
      NULL::timestamptz AS period_start,
      v_activation_due_from AS period_end,
      true AS is_grace_period,
      EXTRACT(DAY FROM (v_activation_due_from - p_check_date))::integer AS days_remaining;
    RETURN;
  END IF;
  
  -- Calculate months elapsed since activation_due_from
  v_months_elapsed := EXTRACT(YEAR FROM age(p_check_date, v_activation_due_from)) * 12 +
                      EXTRACT(MONTH FROM age(p_check_date, v_activation_due_from));
  
  -- Handle edge case: if we're past the day of month but not a full month
  v_period_start := v_activation_due_from + (v_months_elapsed * INTERVAL '1 month');
  
  -- If check_date is before period_start, we need to go back one month
  IF p_check_date < v_period_start THEN
    v_months_elapsed := v_months_elapsed - 1;
    v_period_start := v_activation_due_from + (v_months_elapsed * INTERVAL '1 month');
  END IF;
  
  v_period_end := v_period_start + INTERVAL '1 month';
  
  RETURN QUERY SELECT 
    (v_months_elapsed + 1)::integer AS period_number, -- +1 because period 1 is the first activation period
    v_period_start AS period_start,
    v_period_end AS period_end,
    false AS is_grace_period,
    EXTRACT(DAY FROM (v_period_end - p_check_date))::integer AS days_remaining;
END;
$$;

-- Step 3: Create function to get personal activation status
CREATE OR REPLACE FUNCTION get_personal_activation_status(p_user_id uuid)
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
  v_total_amount numeric := 0;
  v_orders_count integer := 0;
BEGIN
  -- Get current period
  SELECT * INTO v_period FROM get_user_activation_period(p_user_id, NOW());
  
  -- Get activation threshold
  SELECT COALESCE(monthly_activation_required_kzt, 20000) INTO v_threshold
  FROM shop_settings WHERE id = 1;
  
  -- If in grace period, no activation needed
  IF v_period.is_grace_period THEN
    RETURN QUERY SELECT 
      v_period.period_number,
      v_period.period_start,
      v_period.period_end,
      v_period.is_grace_period,
      v_period.days_remaining,
      v_threshold AS required_amount_kzt,
      0::numeric AS current_amount_kzt,
      true AS is_activated,
      0 AS orders_count;
    RETURN;
  END IF;
  
  -- Calculate orders in current personal period
  SELECT 
    COALESCE(SUM(o.total_kzt), 0),
    COUNT(o.id)
  INTO v_total_amount, v_orders_count
  FROM orders o
  WHERE o.user_id = p_user_id
    AND o.status IN ('paid', 'completed', 'delivered')
    AND o.created_at >= v_period.period_start
    AND o.created_at < v_period.period_end;
  
  RETURN QUERY SELECT 
    v_period.period_number,
    v_period.period_start,
    v_period.period_end,
    v_period.is_grace_period,
    v_period.days_remaining,
    v_threshold AS required_amount_kzt,
    v_total_amount AS current_amount_kzt,
    (v_total_amount >= v_threshold) AS is_activated,
    v_orders_count AS orders_count;
END;
$$;

-- Step 4: Update check_activation_status trigger to use personal periods
CREATE OR REPLACE FUNCTION check_activation_status()
RETURNS TRIGGER AS $$
DECLARE
  user_activation_due_from timestamptz;
  user_activation_required boolean;
  threshold_kzt numeric;
  total_amount numeric;
  v_period record;
BEGIN
  -- Get user profile data
  SELECT activation_due_from, is_activation_required
  INTO user_activation_due_from, user_activation_required
  FROM profiles
  WHERE id = NEW.user_id;

  -- If activation is not required yet, nothing to check
  IF NOT COALESCE(user_activation_required, false) THEN
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
  SELECT COALESCE(SUM(total_kzt), 0) INTO total_amount
  FROM orders
  WHERE user_id = NEW.user_id
    AND status IN ('paid', 'completed', 'delivered')
    AND created_at >= v_period.period_start
    AND created_at < v_period.period_end;

  -- Update activation status
  IF total_amount >= threshold_kzt THEN
    UPDATE profiles
    SET monthly_activation_completed = true
    WHERE id = NEW.user_id;
    
    -- Log activation
    INSERT INTO activity_log (user_id, action, details)
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
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- Step 5: Create function to reset activation for users entering new period
CREATE OR REPLACE FUNCTION reset_personal_activations()
RETURNS TABLE(
  user_id uuid,
  full_name text,
  old_period integer,
  new_period integer
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user record;
  v_period record;
  v_last_period_number integer;
BEGIN
  -- Find users who need activation reset
  FOR v_user IN 
    SELECT p.id, p.full_name, p.activation_due_from, p.monthly_activation_completed
    FROM profiles p
    WHERE p.is_active = true
      AND p.is_activation_required = true
      AND p.activation_due_from IS NOT NULL
      AND p.activation_due_from <= NOW()
  LOOP
    -- Get current period
    SELECT * INTO v_period FROM get_user_activation_period(v_user.id, NOW());
    
    -- Skip if in grace period
    IF v_period.is_grace_period THEN
      CONTINUE;
    END IF;
    
    -- Get last recorded period number for this user
    SELECT COALESCE(MAX(ma.period_number), 0) INTO v_last_period_number
    FROM monthly_activations ma
    WHERE ma.user_id = v_user.id;
    
    -- If we're in a new period that wasn't recorded yet, reset activation
    IF v_period.period_number > v_last_period_number THEN
      -- Reset monthly_activation_completed
      UPDATE profiles
      SET monthly_activation_completed = false
      WHERE id = v_user.id
        AND monthly_activation_completed = true;
      
      -- Create new period record
      INSERT INTO monthly_activations (
        user_id, 
        year, 
        month, 
        period_number,
        period_start,
        period_end,
        threshold_kzt,
        total_amount_kzt,
        is_activated
      )
      VALUES (
        v_user.id,
        EXTRACT(YEAR FROM v_period.period_start)::integer,
        EXTRACT(MONTH FROM v_period.period_start)::integer,
        v_period.period_number,
        v_period.period_start,
        v_period.period_end,
        (SELECT COALESCE(monthly_activation_required_kzt, 20000) FROM shop_settings WHERE id = 1),
        0,
        false
      )
      ON CONFLICT (user_id, year, month) DO UPDATE
      SET period_number = EXCLUDED.period_number,
          period_start = EXCLUDED.period_start,
          period_end = EXCLUDED.period_end,
          is_activated = false,
          total_amount_kzt = 0,
          updated_at = NOW();
      
      -- Return info about reset
      user_id := v_user.id;
      full_name := v_user.full_name;
      old_period := v_last_period_number;
      new_period := v_period.period_number;
      RETURN NEXT;
    END IF;
  END LOOP;
END;
$$;

-- Step 6: Update get_monthly_activation_report to include personal periods
DROP FUNCTION IF EXISTS get_monthly_activation_report(integer, integer, text, text, integer, integer);

CREATE FUNCTION get_monthly_activation_report(
  p_year integer,
  p_month integer,
  p_status text DEFAULT 'all',
  p_search text DEFAULT NULL,
  p_limit integer DEFAULT 50,
  p_offset integer DEFAULT 0
)
RETURNS TABLE(
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
BEGIN
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
      AND p.is_activation_required = true
  ),
  user_orders AS (
    SELECT 
      o.user_id AS uid,
      COALESCE(SUM(o.total_kzt), 0) AS total_amount,
      MAX(o.created_at) AS last_order,
      COUNT(o.id) AS order_count
    FROM orders o
    JOIN user_periods up ON up.uid = o.user_id
    WHERE o.status IN ('paid', 'completed', 'delivered')
      AND (
        up.is_grace_period = true 
        OR (o.created_at >= up.period_start AND o.created_at < up.period_end)
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