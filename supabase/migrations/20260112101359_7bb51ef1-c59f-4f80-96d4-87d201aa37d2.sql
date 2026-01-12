-- Fix double penalty: Remove adjustment transactions that duplicate already-failed commissions
-- These adjustments were incorrectly created during unlock violation audits
-- when the original commission was already marked as 'failed'

-- First, let's delete the duplicate adjustments
DELETE FROM transactions
WHERE id IN (
  SELECT a.id
  FROM transactions a
  JOIN transactions c ON c.id::text = a.payload->>'original_transaction_id'
  WHERE a.type = 'adjustment'
    AND a.amount_cents < 0
    AND c.status = 'failed'
);

-- Also fix the audit function to prevent this in the future
-- The fix_unlock_violations function should NOT create adjustments for non-completed commissions
CREATE OR REPLACE FUNCTION fix_unlock_violations(dry_run boolean DEFAULT true)
RETURNS TABLE(
  transaction_id uuid,
  user_id uuid,
  user_name text,
  amount_cents bigint,
  level integer,
  structure_type text,
  source_user_id uuid,
  source_user_name text,
  violation_reason text,
  action_taken text
) 
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  WITH violations AS (
    SELECT 
      t.id as transaction_id,
      t.user_id,
      p.full_name as user_name,
      t.amount_cents,
      t.level,
      t.structure_type::text,
      COALESCE(
        (t.payload->>'source_user_id')::uuid,
        (t.payload->>'subscriber_id')::uuid,
        (t.payload->>'buyer_id')::uuid
      ) as source_user_id,
      t.status as current_status,
      CASE 
        WHEN t.level > 1 AND t.structure_type = 'primary' THEN 'S1 commission above L1 not allowed'
        WHEN t.level > 5 AND t.structure_type = 'secondary' THEN 'S2 commission above L5 not allowed'
        ELSE 'Unknown violation'
      END as violation_reason
    FROM transactions t
    JOIN profiles p ON p.id = t.user_id
    WHERE t.type = 'commission'
      AND t.status = 'completed'
      AND (
        (t.structure_type = 'primary' AND t.level > 1)
        OR (t.structure_type = 'secondary' AND t.level > 5)
      )
  ),
  source_names AS (
    SELECT v.*, sp.full_name as source_user_name
    FROM violations v
    LEFT JOIN profiles sp ON sp.id = v.source_user_id
  )
  SELECT 
    sn.transaction_id,
    sn.user_id,
    sn.user_name,
    sn.amount_cents,
    sn.level,
    sn.structure_type,
    sn.source_user_id,
    sn.source_user_name,
    sn.violation_reason,
    CASE 
      WHEN dry_run THEN 'Would mark as failed (no adjustment needed)'
      ELSE 'Marked as failed'
    END as action_taken
  FROM source_names sn;

  -- If not dry run, mark violations as failed (DO NOT create adjustments)
  IF NOT dry_run THEN
    UPDATE transactions t
    SET 
      status = 'failed',
      payload = jsonb_set(
        COALESCE(t.payload, '{}'::jsonb),
        '{violation_fixed_at}',
        to_jsonb(now()::text)
      ),
      updated_at = now()
    WHERE t.id IN (
      SELECT v.transaction_id
      FROM (
        SELECT t2.id as transaction_id
        FROM transactions t2
        WHERE t2.type = 'commission'
          AND t2.status = 'completed'
          AND (
            (t2.structure_type = 'primary' AND t2.level > 1)
            OR (t2.structure_type = 'secondary' AND t2.level > 5)
          )
      ) v
    );
  END IF;
END;
$$;