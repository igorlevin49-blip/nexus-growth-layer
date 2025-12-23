-- Fix validate_withdrawal_balance function to not divide by 100 in error message
-- Since amount_cents stores actual KZT (tenge), not cents for KZT
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
        COALESCE(v_available_cents, 0), 
        NEW.amount_cents;
    END IF;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

COMMENT ON FUNCTION public.validate_withdrawal_balance() IS 'Validates that user has sufficient available balance before allowing withdrawal transaction';