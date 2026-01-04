-- Fix admin_adjust_balance to use KZT (not cents)
CREATE OR REPLACE FUNCTION public.admin_adjust_balance(
  p_user_id UUID,
  p_amount_kzt INTEGER,  -- Amount in whole KZT (positive = credit, negative = debit)
  p_reason TEXT,
  p_admin_id UUID
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_is_admin BOOLEAN;
  v_new_transaction_id UUID;
  v_user_name TEXT;
  v_old_balance NUMERIC;
  v_new_balance NUMERIC;
BEGIN
  -- Check if caller is admin
  SELECT EXISTS (
    SELECT 1 FROM user_roles 
    WHERE user_id = p_admin_id 
    AND role IN ('admin', 'superadmin')
  ) INTO v_is_admin;

  IF NOT v_is_admin THEN
    RETURN json_build_object('success', false, 'error', 'UNAUTHORIZED');
  END IF;

  IF p_amount_kzt = 0 THEN
    RETURN json_build_object('success', false, 'error', 'ZERO_AMOUNT');
  END IF;

  IF p_reason IS NULL OR LENGTH(TRIM(p_reason)) < 3 THEN
    RETURN json_build_object('success', false, 'error', 'REASON_REQUIRED');
  END IF;

  -- Get user info
  SELECT full_name, COALESCE(balance, 0) INTO v_user_name, v_old_balance
  FROM profiles WHERE id = p_user_id;

  IF v_user_name IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'USER_NOT_FOUND');
  END IF;

  -- Calculate new balance
  v_new_balance := v_old_balance + p_amount_kzt;

  -- Create transaction record
  INSERT INTO transactions (
    user_id,
    type,
    amount_cents,  -- Stores whole KZT for KZT currency
    currency,
    status,
    payload
  ) VALUES (
    p_user_id,
    CASE WHEN p_amount_kzt > 0 THEN 'balance_adjustment' ELSE 'balance_deduction' END,
    ABS(p_amount_kzt),
    'KZT',
    'completed',
    jsonb_build_object(
      'admin_id', p_admin_id,
      'reason', p_reason,
      'direction', CASE WHEN p_amount_kzt > 0 THEN 'credit' ELSE 'debit' END,
      'old_balance_kzt', v_old_balance,
      'new_balance_kzt', v_new_balance,
      'adjustment_kzt', p_amount_kzt
    )
  )
  RETURNING id INTO v_new_transaction_id;

  -- Update balance
  UPDATE profiles
  SET balance = v_new_balance,
      updated_at = NOW()
  WHERE id = p_user_id;

  RETURN json_build_object(
    'success', true,
    'transaction_id', v_new_transaction_id,
    'old_balance_kzt', v_old_balance,
    'new_balance_kzt', v_new_balance
  );
END;
$$;