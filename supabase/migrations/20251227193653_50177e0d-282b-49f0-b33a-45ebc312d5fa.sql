-- Fix audit function return type
DROP FUNCTION IF EXISTS public.audit_unlock_level_violations_detailed();

CREATE OR REPLACE FUNCTION public.audit_unlock_level_violations_detailed()
RETURNS TABLE (
  transaction_id uuid,
  user_id uuid,
  user_email text,
  user_name text,
  level int,
  amount_cents bigint,
  required_referrals int,
  actual_referrals_at_time int,
  subscriber_id uuid,
  subscriber_name text,
  subscription_id text,
  created_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_unlock_levels jsonb;
BEGIN
  -- Get unlock_levels
  SELECT value INTO v_unlock_levels
  FROM mlm_settings
  WHERE key = 'unlock_levels';
  
  IF v_unlock_levels IS NULL THEN
    v_unlock_levels := '{"l2": 3, "l3": 5, "l4": 8, "l5": 10}'::jsonb;
  END IF;

  RETURN QUERY
  WITH commission_txns AS (
    SELECT 
      t.id AS txn_id,
      t.user_id AS txn_user_id,
      t.level AS txn_level,
      t.amount_cents AS txn_amount_cents,
      t.source_id AS txn_source_id,
      t.source_ref AS txn_source_ref,
      t.created_at AS txn_created_at,
      COALESCE(
        (v_unlock_levels->('l' || t.level::text))::int,
        CASE t.level
          WHEN 2 THEN 3
          WHEN 3 THEN 5
          WHEN 4 THEN 8
          WHEN 5 THEN 10
          ELSE t.level - 1
        END
      ) AS required_refs
    FROM transactions t
    WHERE t.type = 'commission'
      AND t.structure_type = 'primary'
      AND t.level > 1
      AND t.is_test IS NOT TRUE
  )
  SELECT 
    ct.txn_id AS transaction_id,
    ct.txn_user_id AS user_id,
    p.email AS user_email,
    p.full_name AS user_name,
    ct.txn_level AS level,
    ct.txn_amount_cents AS amount_cents,
    ct.required_refs AS required_referrals,
    (
      SELECT COUNT(*)::int
      FROM profiles pr
      WHERE pr.sponsor_id = ct.txn_user_id
        AND pr.subscription_status = 'active'
        AND pr.deleted_at IS NULL
        AND pr.created_at <= ct.txn_created_at
    ) AS actual_referrals_at_time,
    ct.txn_source_id::uuid AS subscriber_id,
    sub_p.full_name AS subscriber_name,
    ct.txn_source_ref AS subscription_id,
    ct.txn_created_at AS created_at
  FROM commission_txns ct
  JOIN profiles p ON p.id = ct.txn_user_id
  LEFT JOIN profiles sub_p ON sub_p.id = ct.txn_source_id::uuid
  WHERE (
    SELECT COUNT(*)
    FROM profiles pr
    WHERE pr.sponsor_id = ct.txn_user_id
      AND pr.subscription_status = 'active'
      AND pr.deleted_at IS NULL
      AND pr.created_at <= ct.txn_created_at
  ) < ct.required_refs
  ORDER BY ct.txn_created_at DESC;
END;
$$;