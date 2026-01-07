-- Fix incorrect backfill amounts for Елена Коханова
-- The amount_cents for KZT stores whole KZT, not cents
-- Current: 550000 (looks like 550,000 KZT) -> Should be: 5500 (5,500 KZT)

UPDATE transactions
SET amount_cents = 5500
WHERE user_id = '5536df5d-9400-4cdd-b476-6d8ea26e0e2e'
  AND type = 'commission'
  AND currency = 'KZT'
  AND amount_cents = 550000
  AND (payload->>'backfill')::boolean = true;