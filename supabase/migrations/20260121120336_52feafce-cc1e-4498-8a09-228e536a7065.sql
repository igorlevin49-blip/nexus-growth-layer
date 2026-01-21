-- Fix process_manual_payout to use available_kzt instead of available_cents
CREATE OR REPLACE FUNCTION public.process_manual_payout(
  p_user_id uuid, 
  p_amount_cents bigint, 
  p_comment text
)
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
  -- Check available balance (use available_kzt instead of available_cents)
  SELECT * INTO v_balance_record
  FROM get_user_balance(p_user_id);
  
  IF v_balance_record.available_kzt < p_amount_cents THEN
    RETURN json_build_object(
      'success', false,
      'error', 'Недостаточно средств на балансе. Доступно: ' || v_balance_record.available_kzt || ' ₸'
    );
  END IF;
  
  -- Create withdrawal record (table still uses amount_cents column)
  INSERT INTO withdrawals (
    user_id, amount_cents, fee_cents, status, processed_at
  ) VALUES (
    p_user_id, p_amount_cents, 0, 'completed'::withdrawal_status, now()
  )
  RETURNING id INTO v_withdrawal_id;
  
  -- Get transaction_id created by trigger
  SELECT id INTO v_transaction_id
  FROM transactions
  WHERE source_ref = 'withdrawal:' || v_withdrawal_id::text
  LIMIT 1;
  
  -- Update withdrawal with transaction_id and add comment
  IF v_transaction_id IS NOT NULL THEN
    UPDATE withdrawals SET transaction_id = v_transaction_id WHERE id = v_withdrawal_id;
    UPDATE transactions 
    SET payload = COALESCE(payload, '{}'::jsonb) || jsonb_build_object('comment', p_comment)
    WHERE id = v_transaction_id;
  END IF;
  
  RETURN json_build_object(
    'success', true,
    'withdrawal_id', v_withdrawal_id,
    'transaction_id', v_transaction_id,
    'amount_kzt', p_amount_cents
  );
END;
$function$;