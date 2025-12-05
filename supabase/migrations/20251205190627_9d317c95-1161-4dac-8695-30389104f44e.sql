-- Create a function to get balances for multiple users at once
CREATE OR REPLACE FUNCTION public.get_all_user_balances()
RETURNS TABLE(
  user_id UUID,
  available_cents BIGINT,
  frozen_cents BIGINT,
  pending_cents BIGINT,
  withdrawn_cents BIGINT
)
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT 
    p.id AS user_id,
    COALESCE(SUM(
      CASE 
        WHEN t.type IN ('commission', 'bonus', 'adjustment') AND t.status = 'completed' THEN t.amount_cents
        WHEN t.type = 'withdrawal' AND t.status = 'completed' THEN -t.amount_cents
        ELSE 0
      END
    ), 0)::BIGINT AS available_cents,
    COALESCE(SUM(
      CASE 
        WHEN t.status = 'frozen' THEN t.amount_cents
        ELSE 0
      END
    ), 0)::BIGINT AS frozen_cents,
    COALESCE(SUM(
      CASE 
        WHEN t.status IN ('pending', 'processing') THEN t.amount_cents
        ELSE 0
      END
    ), 0)::BIGINT AS pending_cents,
    COALESCE(SUM(
      CASE 
        WHEN t.type = 'withdrawal' AND t.status = 'completed' THEN t.amount_cents
        ELSE 0
      END
    ), 0)::BIGINT AS withdrawn_cents
  FROM profiles p
  LEFT JOIN transactions t ON t.user_id = p.id AND COALESCE(t.is_archived, false) = false
  GROUP BY p.id;
$$;