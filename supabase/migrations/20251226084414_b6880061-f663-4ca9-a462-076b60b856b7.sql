-- Stage 2: Add sync trigger for withdrawals -> transactions
-- This ensures every withdrawal has a corresponding transaction

CREATE OR REPLACE FUNCTION public.sync_withdrawal_transaction()
RETURNS TRIGGER AS $$
DECLARE
  v_existing_tx_id uuid;
BEGIN
  -- Only process for processing/completed withdrawals without transaction_id
  IF NEW.status IN ('processing', 'completed') AND NEW.transaction_id IS NULL THEN
    -- Check if transaction already exists for this withdrawal
    SELECT id INTO v_existing_tx_id
    FROM transactions
    WHERE source_ref = 'withdrawal:' || NEW.id::text
       OR source_ref = 'withdrawal_' || NEW.id::text
       OR source_ref = 'auto_withdrawal_' || NEW.id::text
       OR source_ref = 'manual_payout_' || NEW.id::text
       OR source_id = NEW.id
    LIMIT 1;
    
    IF v_existing_tx_id IS NULL THEN
      -- Create transaction if it doesn't exist
      INSERT INTO transactions (
        user_id, 
        type, 
        amount_cents, 
        currency, 
        status, 
        source_id,
        source_ref
      ) VALUES (
        NEW.user_id, 
        'withdrawal', 
        NEW.amount_cents, 
        'KZT', 
        NEW.status,
        NEW.id,
        'withdrawal:' || NEW.id::text
      );
      
      RAISE NOTICE 'Auto-created transaction for withdrawal %', NEW.id;
    END IF;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- Drop existing trigger if exists and create new one
DROP TRIGGER IF EXISTS sync_withdrawal_transaction_trigger ON withdrawals;

CREATE TRIGGER sync_withdrawal_transaction_trigger
  AFTER INSERT ON withdrawals
  FOR EACH ROW
  EXECUTE FUNCTION sync_withdrawal_transaction();

-- Stage 3: Unify source_ref format - update existing records
UPDATE transactions 
SET source_ref = 'withdrawal:' || source_id::text
WHERE type = 'withdrawal' 
  AND source_id IS NOT NULL
  AND source_ref NOT LIKE 'withdrawal:%';

-- Stage 5: Add audit_balance_integrity function
CREATE OR REPLACE FUNCTION public.audit_balance_integrity()
RETURNS TABLE (
  issue_type text,
  user_id uuid,
  user_email text,
  details jsonb
) AS $$
BEGIN
  -- Find withdrawals without corresponding transactions
  RETURN QUERY
  SELECT 
    'withdrawal_without_transaction'::text as issue_type,
    w.user_id,
    p.email::text as user_email,
    jsonb_build_object(
      'withdrawal_id', w.id,
      'amount_cents', w.amount_cents,
      'status', w.status,
      'created_at', w.created_at
    ) as details
  FROM withdrawals w
  LEFT JOIN transactions t ON (
    t.source_id = w.id 
    OR t.source_ref LIKE '%' || w.id::text || '%'
  )
  LEFT JOIN profiles p ON p.id = w.user_id
  WHERE w.status IN ('processing', 'completed')
    AND t.id IS NULL
    AND w.is_archived IS NOT TRUE;

  -- Find users with negative balances
  RETURN QUERY
  SELECT 
    'negative_balance'::text as issue_type,
    b.user_id,
    p.email::text as user_email,
    jsonb_build_object(
      'available_cents', b.available_cents,
      'frozen_cents', b.frozen_cents,
      'withdrawn_cents', b.withdrawn_cents
    ) as details
  FROM get_all_user_balances() b
  JOIN profiles p ON p.id = b.user_id
  WHERE b.available_cents < 0;

  -- Find withdrawals with amount mismatch vs transaction
  RETURN QUERY
  SELECT 
    'amount_mismatch'::text as issue_type,
    w.user_id,
    p.email::text as user_email,
    jsonb_build_object(
      'withdrawal_id', w.id,
      'withdrawal_amount', w.amount_cents,
      'transaction_amount', t.amount_cents,
      'difference', w.amount_cents - t.amount_cents
    ) as details
  FROM withdrawals w
  JOIN transactions t ON (
    t.source_id = w.id 
    OR t.source_ref = 'withdrawal:' || w.id::text
  )
  JOIN profiles p ON p.id = w.user_id
  WHERE w.amount_cents != t.amount_cents
    AND w.is_archived IS NOT TRUE
    AND t.is_archived IS NOT TRUE;

  -- Find duplicate transactions for same withdrawal
  RETURN QUERY
  SELECT 
    'duplicate_withdrawal_transactions'::text as issue_type,
    t.user_id,
    p.email::text as user_email,
    jsonb_build_object(
      'withdrawal_id', w.id,
      'transaction_count', COUNT(t.id),
      'total_amount', SUM(t.amount_cents)
    ) as details
  FROM withdrawals w
  JOIN transactions t ON (
    t.source_id = w.id 
    OR t.source_ref LIKE '%' || w.id::text || '%'
  )
  JOIN profiles p ON p.id = w.user_id
  WHERE t.type = 'withdrawal'
    AND w.is_archived IS NOT TRUE
    AND t.is_archived IS NOT TRUE
  GROUP BY w.id, t.user_id, p.email
  HAVING COUNT(t.id) > 1;

END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;