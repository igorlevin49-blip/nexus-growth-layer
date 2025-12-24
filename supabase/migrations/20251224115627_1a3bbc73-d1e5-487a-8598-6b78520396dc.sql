-- Fix get_user_balance function to correctly calculate frozen vs available based on frozen_until date
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
    -- Available: completed commissions where freeze period has passed or no freeze
    COALESCE(SUM(
      CASE 
        WHEN t.type IN ('commission', 'bonus', 'adjustment') 
          AND t.status = 'completed' 
          AND (t.frozen_until IS NULL OR t.frozen_until <= NOW())
        THEN t.amount_cents 
        ELSE 0 
      END
    ), 0)::bigint as available_cents,
    
    -- Frozen: completed commissions where freeze period is still active
    COALESCE(SUM(
      CASE 
        WHEN t.type IN ('commission', 'bonus', 'adjustment') 
          AND t.status = 'completed' 
          AND t.frozen_until > NOW()
        THEN t.amount_cents 
        ELSE 0 
      END
    ), 0)::bigint as frozen_cents,
    
    -- Pending: transactions with pending/processing/frozen status
    COALESCE(SUM(
      CASE 
        WHEN t.type IN ('commission', 'bonus', 'adjustment') 
          AND t.status IN ('pending', 'processing', 'frozen')
        THEN t.amount_cents 
        ELSE 0 
      END
    ), 0)::bigint as pending_cents,
    
    -- Withdrawn: completed withdrawals (stored as negative in transactions)
    COALESCE(ABS(SUM(
      CASE 
        WHEN t.type = 'withdrawal' AND t.status = 'completed'
        THEN t.amount_cents 
        ELSE 0 
      END
    )), 0)::bigint as withdrawn_cents,
    
    NOW() as updated_at
  FROM transactions t
  WHERE t.user_id = p_user_id
    AND t.currency = 'KZT'
    AND (t.is_archived IS NULL OR t.is_archived = false);
END;
$$;