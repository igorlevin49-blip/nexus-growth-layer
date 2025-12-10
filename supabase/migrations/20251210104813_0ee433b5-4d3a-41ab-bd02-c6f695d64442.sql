CREATE OR REPLACE FUNCTION public.process_manual_payout(
  p_user_id UUID,
  p_amount_cents INTEGER,
  p_comment TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin_id UUID;
  v_available_cents BIGINT;
  v_transaction_id UUID;
BEGIN
  -- Get current user (admin)
  v_admin_id := auth.uid();
  
  -- Check if user is admin or superadmin
  IF NOT (has_role(v_admin_id, 'admin'::app_role) OR has_role(v_admin_id, 'superadmin'::app_role)) THEN
    RETURN jsonb_build_object('success', false, 'error', 'UNAUTHORIZED');
  END IF;
  
  -- Validate amount
  IF p_amount_cents <= 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_AMOUNT');
  END IF;
  
  -- Check user balance
  SELECT available_cents INTO v_available_cents
  FROM get_user_balance(p_user_id);
  
  IF v_available_cents < p_amount_cents THEN
    RETURN jsonb_build_object('success', false, 'error', 'INSUFFICIENT_BALANCE');
  END IF;
  
  -- Create withdrawal transaction
  INSERT INTO transactions (
    user_id,
    type,
    amount_cents,
    status,
    currency,
    payload
  ) VALUES (
    p_user_id,
    'withdrawal',
    p_amount_cents,
    'completed',
    'USD',
    jsonb_build_object(
      'manual_payout', true,
      'admin_id', v_admin_id,
      'comment', p_comment,
      'processed_at', now()
    )
  )
  RETURNING id INTO v_transaction_id;
  
  -- Log admin action
  INSERT INTO admin_audit (admin_id, action_type, target_type, target_id, comment, metadata)
  VALUES (
    v_admin_id,
    'manual_payout',
    'user',
    p_user_id,
    p_comment,
    jsonb_build_object('amount_cents', p_amount_cents, 'transaction_id', v_transaction_id)
  );
  
  RETURN jsonb_build_object(
    'success', true,
    'transaction_id', v_transaction_id,
    'amount_cents', p_amount_cents
  );
END;
$$;