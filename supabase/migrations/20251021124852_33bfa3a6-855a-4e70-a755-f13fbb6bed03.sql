-- Fix security definer view by converting to a function

DROP VIEW IF EXISTS public.user_balances;

-- Create a security invoker function instead of a view
CREATE OR REPLACE FUNCTION public.get_user_balance(p_user_id UUID)
RETURNS TABLE(
  user_id UUID,
  available_cents BIGINT,
  frozen_cents BIGINT,
  pending_cents BIGINT,
  withdrawn_cents BIGINT,
  updated_at TIMESTAMP WITH TIME ZONE
)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT 
    p_user_id as user_id,
    COALESCE(SUM(CASE 
      WHEN t.type IN ('commission', 'bonus') AND t.status = 'completed' AND (t.frozen_until IS NULL OR t.frozen_until <= NOW())
      THEN t.amount_cents 
      WHEN t.type IN ('withdrawal', 'purchase', 'adjustment') AND t.status = 'completed'
      THEN -t.amount_cents
      ELSE 0 
    END), 0) as available_cents,
    COALESCE(SUM(CASE 
      WHEN t.type IN ('commission', 'bonus') AND t.status = 'completed' AND t.frozen_until > NOW()
      THEN t.amount_cents 
      ELSE 0 
    END), 0) as frozen_cents,
    COALESCE(SUM(CASE 
      WHEN t.type IN ('commission', 'bonus') AND t.status IN ('pending', 'processing')
      THEN t.amount_cents 
      ELSE 0 
    END), 0) as pending_cents,
    COALESCE(SUM(CASE 
      WHEN t.type = 'withdrawal' AND t.status = 'completed'
      THEN t.amount_cents 
      ELSE 0 
    END), 0) as withdrawn_cents,
    NOW() as updated_at
  FROM public.transactions t
  WHERE t.user_id = p_user_id
$$;