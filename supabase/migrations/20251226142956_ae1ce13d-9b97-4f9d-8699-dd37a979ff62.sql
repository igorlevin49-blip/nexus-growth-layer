-- Fix race condition in withdrawal balance validation
-- The issue: sync_withdrawal_transaction creates a transaction BEFORE validate_withdrawal_balance runs
-- So the balance already includes the new withdrawal, causing "Insufficient balance" errors

CREATE OR REPLACE FUNCTION public.validate_withdrawal_balance()
RETURNS TRIGGER AS $$
DECLARE
  v_available_cents BIGINT;
BEGIN
  -- Only validate withdrawal transactions
  IF NEW.type = 'withdrawal' THEN
    -- Calculate available balance EXCLUDING the current transaction being inserted
    SELECT 
      COALESCE(SUM(CASE 
        WHEN t.type IN ('commission', 'bonus') AND t.status = 'completed' THEN t.amount_cents
        WHEN t.type = 'adjustment' AND t.status = 'completed' THEN t.amount_cents
        WHEN t.type = 'withdrawal' AND t.status = 'completed' THEN -t.amount_cents
        ELSE 0
      END), 0)
    INTO v_available_cents
    FROM transactions t
    WHERE t.user_id = NEW.user_id
      AND t.currency = 'KZT'
      AND (t.is_archived IS NULL OR t.is_archived = false)
      AND t.id != NEW.id;  -- CRITICAL: Exclude the current transaction to avoid race condition
    
    IF NEW.amount_cents > COALESCE(v_available_cents, 0) THEN
      RAISE EXCEPTION 'Insufficient balance. Available: % KZT, Requested: % KZT', 
        COALESCE(v_available_cents, 0), 
        NEW.amount_cents;
    END IF;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;