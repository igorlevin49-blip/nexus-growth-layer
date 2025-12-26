-- Fix get_user_balance function - correct frozen calculation
CREATE OR REPLACE FUNCTION public.get_user_balance(p_user_id uuid)
RETURNS TABLE(
  user_id uuid,
  available_cents bigint,
  frozen_cents bigint,
  pending_cents bigint,
  withdrawn_cents bigint,
  updated_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    p_user_id as user_id,
    COALESCE(SUM(
      CASE 
        WHEN t.type IN ('commission', 'bonus', 'adjustment') AND t.status = 'completed'
        THEN t.amount_cents
        WHEN t.type = 'withdrawal' AND t.status = 'completed'
        THEN -t.amount_cents
        ELSE 0
      END
    ), 0)::bigint AS available_cents,
    COALESCE(SUM(
      CASE 
        WHEN t.type IN ('commission', 'bonus', 'adjustment') AND t.status = 'frozen'
        THEN t.amount_cents
        ELSE 0
      END
    ), 0)::bigint AS frozen_cents,
    COALESCE(SUM(
      CASE 
        WHEN t.type IN ('commission', 'bonus', 'adjustment') AND t.status = 'pending'
        THEN t.amount_cents
        ELSE 0
      END
    ), 0)::bigint AS pending_cents,
    COALESCE(SUM(
      CASE 
        WHEN t.type = 'withdrawal' AND t.status = 'completed'
        THEN t.amount_cents
        ELSE 0
      END
    ), 0)::bigint AS withdrawn_cents,
    NOW() as updated_at
  FROM transactions t
  WHERE t.user_id = p_user_id
    AND (t.is_archived IS NULL OR t.is_archived = false);
END;
$$;

-- Fix get_all_user_balances function - same logic
CREATE OR REPLACE FUNCTION public.get_all_user_balances()
RETURNS TABLE(
  user_id uuid,
  available_cents bigint,
  frozen_cents bigint,
  pending_cents bigint,
  withdrawn_cents bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    t.user_id,
    COALESCE(SUM(
      CASE 
        WHEN t.type IN ('commission', 'bonus', 'adjustment') AND t.status = 'completed'
        THEN t.amount_cents
        WHEN t.type = 'withdrawal' AND t.status = 'completed'
        THEN -t.amount_cents
        ELSE 0
      END
    ), 0)::bigint AS available_cents,
    COALESCE(SUM(
      CASE 
        WHEN t.type IN ('commission', 'bonus', 'adjustment') AND t.status = 'frozen'
        THEN t.amount_cents
        ELSE 0
      END
    ), 0)::bigint AS frozen_cents,
    COALESCE(SUM(
      CASE 
        WHEN t.type IN ('commission', 'bonus', 'adjustment') AND t.status = 'pending'
        THEN t.amount_cents
        ELSE 0
      END
    ), 0)::bigint AS pending_cents,
    COALESCE(SUM(
      CASE 
        WHEN t.type = 'withdrawal' AND t.status = 'completed'
        THEN t.amount_cents
        ELSE 0
      END
    ), 0)::bigint AS withdrawn_cents
  FROM transactions t
  WHERE t.is_archived IS NULL OR t.is_archived = false
  GROUP BY t.user_id;
END;
$$;