-- Fix backfill commissions: set frozen_until = subscription.paid_at + 14 days
-- and update status to 'frozen' if still within freeze period

UPDATE transactions t
SET 
  status = CASE 
    WHEN s.paid_at + interval '14 days' > NOW() THEN 'frozen'::transaction_status
    ELSE 'completed'::transaction_status
  END,
  frozen_until = s.paid_at + interval '14 days',
  payload = COALESCE(t.payload, '{}'::jsonb) || jsonb_build_object(
    'freeze_fixed_at', NOW()::text,
    'fix_reason', 'Backfill commissions fixed: added 14 days freeze'
  ),
  updated_at = NOW()
FROM subscriptions s
WHERE t.source_id = s.id
  AND t.type = 'commission'
  AND t.payload->>'backfill' = 'true'
  AND t.frozen_until IS NULL;

-- Also fix any regular commission transactions that might be missing frozen_until
UPDATE transactions t
SET 
  status = CASE 
    WHEN s.paid_at + interval '14 days' > NOW() THEN 'frozen'::transaction_status
    ELSE t.status
  END,
  frozen_until = COALESCE(t.frozen_until, s.paid_at + interval '14 days'),
  updated_at = NOW()
FROM subscriptions s
WHERE t.source_id = s.id
  AND t.type = 'commission'
  AND t.source_ref = 'subscription'
  AND t.frozen_until IS NULL
  AND s.paid_at IS NOT NULL;