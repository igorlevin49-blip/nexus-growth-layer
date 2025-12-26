
-- Fix type casting in process_manual_payout function
CREATE OR REPLACE FUNCTION public.process_manual_payout(p_user_id uuid, p_amount_cents bigint, p_comment text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_balance_record RECORD;
  v_withdrawal_id UUID;
  v_transaction_id UUID;
BEGIN
  -- Check available balance
  SELECT * INTO v_balance_record
  FROM get_user_balance(p_user_id);
  
  IF v_balance_record.available_cents < p_amount_cents THEN
    RETURN json_build_object(
      'success', false,
      'error', 'Недостаточно средств на балансе'
    );
  END IF;
  
  -- Create withdrawal record with explicit type cast
  INSERT INTO withdrawals (
    user_id,
    amount_cents,
    fee_cents,
    status
  ) VALUES (
    p_user_id,
    p_amount_cents,
    0,
    'completed'::withdrawal_status
  )
  RETURNING id INTO v_withdrawal_id;
  
  -- Create withdrawal transaction in KZT with explicit type cast
  INSERT INTO transactions (
    user_id,
    type,
    amount_cents,
    currency,
    status,
    source_id,
    source_ref,
    payload
  ) VALUES (
    p_user_id,
    'withdrawal'::transaction_type,
    p_amount_cents,
    'KZT',
    'completed'::transaction_status,
    v_withdrawal_id,
    'manual_payout_' || v_withdrawal_id,
    jsonb_build_object('comment', p_comment)
  )
  RETURNING id INTO v_transaction_id;
  
  -- Update withdrawal with transaction_id
  UPDATE withdrawals
  SET transaction_id = v_transaction_id,
      processed_at = now()
  WHERE id = v_withdrawal_id;
  
  RETURN json_build_object(
    'success', true,
    'withdrawal_id', v_withdrawal_id,
    'transaction_id', v_transaction_id
  );
END;
$function$;
