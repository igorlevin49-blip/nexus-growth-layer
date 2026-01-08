-- Fix check_activation_status function - remove reference to non-existent is_activation_required column
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