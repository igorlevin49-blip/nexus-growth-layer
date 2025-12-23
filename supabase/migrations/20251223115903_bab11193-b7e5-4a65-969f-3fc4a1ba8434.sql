-- 1. Create function to validate withdrawal balance BEFORE allowing transaction
CREATE OR REPLACE FUNCTION public.validate_withdrawal_balance()
RETURNS TRIGGER AS $$
DECLARE
  v_available_cents BIGINT;
BEGIN
  -- Only check for withdrawal transactions
  IF NEW.type = 'withdrawal' THEN
    -- Get current available balance
    SELECT available_cents INTO v_available_cents
    FROM public.get_user_balance(NEW.user_id);
    
    -- Raise exception if insufficient funds
    IF NEW.amount_cents > COALESCE(v_available_cents, 0) THEN
      RAISE EXCEPTION 'Insufficient balance. Available: % KZT, Requested: % KZT', 
        COALESCE(v_available_cents, 0) / 100, 
        NEW.amount_cents / 100;
    END IF;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- 2. Create trigger to check balance before withdrawal insert
DROP TRIGGER IF EXISTS check_withdrawal_balance ON public.transactions;
CREATE TRIGGER check_withdrawal_balance
BEFORE INSERT ON public.transactions
FOR EACH ROW
EXECUTE FUNCTION public.validate_withdrawal_balance();

-- 3. Cancel stuck processing withdrawals for user with negative balance
-- Use 'failed' status which is valid for transaction_status enum
UPDATE public.transactions 
SET status = 'failed', updated_at = NOW()
WHERE user_id = 'a8a8a3f8-ca1a-4061-8fff-69af8a3e04b5'
  AND type = 'withdrawal'
  AND status = 'processing';

-- For withdrawals table, 'cancelled' IS valid in withdrawal_status enum
UPDATE public.withdrawals
SET status = 'cancelled', processed_at = NOW()
WHERE user_id = 'a8a8a3f8-ca1a-4061-8fff-69af8a3e04b5'
  AND status = 'processing';

-- 4. Add comment for documentation
COMMENT ON FUNCTION public.validate_withdrawal_balance() IS 'Validates that user has sufficient available balance before allowing withdrawal transaction';