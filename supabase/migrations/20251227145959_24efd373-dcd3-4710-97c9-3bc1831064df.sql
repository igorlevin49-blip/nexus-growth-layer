-- Fix process_manual_payout to not create duplicate transactions
-- The trigger sync_withdrawal_transaction already creates the transaction

CREATE OR REPLACE FUNCTION public.process_manual_payout(p_user_id uuid, p_amount_cents bigint, p_comment text)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_balance_record RECORD;
  v_withdrawal_id UUID;
  v_transaction_id UUID;
BEGIN
  -- Check available balance FIRST before any inserts
  SELECT * INTO v_balance_record
  FROM get_user_balance(p_user_id);
  
  IF v_balance_record.available_cents < p_amount_cents THEN
    RETURN json_build_object(
      'success', false,
      'error', 'Недостаточно средств на балансе. Доступно: ' || v_balance_record.available_cents || ' тиын'
    );
  END IF;
  
  -- Create withdrawal record with 'completed' status
  -- The trigger sync_withdrawal_transaction will automatically create the transaction
  INSERT INTO withdrawals (
    user_id,
    amount_cents,
    fee_cents,
    status,
    processed_at
  ) VALUES (
    p_user_id,
    p_amount_cents,
    0,
    'completed'::withdrawal_status,
    now()
  )
  RETURNING id INTO v_withdrawal_id;
  
  -- Get transaction_id created by sync_withdrawal_transaction trigger
  SELECT id INTO v_transaction_id
  FROM transactions
  WHERE source_ref = 'withdrawal:' || v_withdrawal_id::text
  LIMIT 1;
  
  -- Update withdrawal with transaction_id
  IF v_transaction_id IS NOT NULL THEN
    UPDATE withdrawals
    SET transaction_id = v_transaction_id
    WHERE id = v_withdrawal_id;
    
    -- Update transaction with comment in payload
    UPDATE transactions
    SET payload = COALESCE(payload, '{}'::jsonb) || jsonb_build_object('comment', p_comment)
    WHERE id = v_transaction_id;
  END IF;
  
  RETURN json_build_object(
    'success', true,
    'withdrawal_id', v_withdrawal_id,
    'transaction_id', v_transaction_id,
    'amount_cents', p_amount_cents
  );
END;
$$;

-- Also fix create_user_withdrawal to follow the same pattern
CREATE OR REPLACE FUNCTION public.create_user_withdrawal(p_user_id uuid, p_amount_cents bigint, p_method_id uuid)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_balance_record RECORD;
  v_withdrawal_id UUID;
  v_has_pending BOOLEAN;
BEGIN
  -- Check for existing pending/processing withdrawals
  SELECT EXISTS(
    SELECT 1 FROM withdrawals 
    WHERE user_id = p_user_id 
    AND status IN ('pending', 'processing')
  ) INTO v_has_pending;
  
  IF v_has_pending THEN
    RETURN json_build_object(
      'success', false,
      'message', 'У вас уже есть заявка на вывод в обработке'
    );
  END IF;
  
  -- Check available balance
  SELECT * INTO v_balance_record
  FROM get_user_balance(p_user_id);
  
  IF v_balance_record.available_cents < p_amount_cents THEN
    RETURN json_build_object(
      'success', false,
      'message', 'Недостаточно средств на балансе. Доступно: ' || v_balance_record.available_cents || ' тиын'
    );
  END IF;
  
  -- Create withdrawal with pending status
  -- Note: sync_withdrawal_transaction trigger creates transaction only for completed status
  INSERT INTO withdrawals (
    user_id,
    amount_cents,
    fee_cents,
    method_id,
    status
  ) VALUES (
    p_user_id,
    p_amount_cents,
    0,
    p_method_id,
    'pending'::withdrawal_status
  )
  RETURNING id INTO v_withdrawal_id;
  
  RETURN json_build_object(
    'success', true,
    'withdrawal_id', v_withdrawal_id,
    'message', 'Заявка на вывод создана'
  );
END;
$$;

-- Update sync_withdrawal_transaction trigger to be idempotent
CREATE OR REPLACE FUNCTION public.sync_withdrawal_transaction()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_transaction_id UUID;
  v_existing_tx_id UUID;
BEGIN
  -- Only process completed withdrawals
  IF NEW.status = 'completed' THEN
    -- Check if transaction already exists for this withdrawal
    SELECT id INTO v_existing_tx_id
    FROM transactions
    WHERE source_ref = 'withdrawal:' || NEW.id::text
    LIMIT 1;
    
    -- Only create if not exists
    IF v_existing_tx_id IS NULL THEN
      INSERT INTO transactions (
        user_id,
        type,
        amount_cents,
        currency,
        status,
        source_ref,
        source_id
      ) VALUES (
        NEW.user_id,
        'withdrawal',
        NEW.amount_cents,
        'KZT',
        'completed',
        'withdrawal:' || NEW.id::text,
        NEW.id
      )
      RETURNING id INTO v_transaction_id;
      
      -- Update withdrawal with transaction_id
      NEW.transaction_id := v_transaction_id;
    END IF;
  END IF;
  
  RETURN NEW;
END;
$$;

-- Make sure the trigger fires BEFORE INSERT to allow setting transaction_id
DROP TRIGGER IF EXISTS sync_withdrawal_transaction_trigger ON withdrawals;
CREATE TRIGGER sync_withdrawal_transaction_trigger
  BEFORE INSERT OR UPDATE ON withdrawals
  FOR EACH ROW
  EXECUTE FUNCTION sync_withdrawal_transaction();

-- Remove check_withdrawal_balance trigger if it exists (redundant, causes issues)
DROP TRIGGER IF EXISTS check_withdrawal_balance_trigger ON transactions;
DROP FUNCTION IF EXISTS check_withdrawal_balance();