-- Fix orders payment_type constraint to include 'cash'
ALTER TABLE orders DROP CONSTRAINT IF EXISTS orders_payment_type_check;
ALTER TABLE orders ADD CONSTRAINT orders_payment_type_check 
  CHECK (payment_type = ANY (ARRAY['online', 'manual', 'cash']));

-- Also fix activity_log type constraint to include 'activation' and other types
ALTER TABLE activity_log DROP CONSTRAINT IF EXISTS activity_log_type_check;
-- Remove constraint entirely to allow flexible activity types
-- Or add all known types if constraint is needed