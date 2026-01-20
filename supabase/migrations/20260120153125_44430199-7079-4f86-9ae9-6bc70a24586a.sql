-- Fix get_user_balance to include adjustment transactions in available balance
CREATE OR REPLACE FUNCTION public.get_user_balance(p_user_id uuid)
RETURNS TABLE(
  available_kzt bigint,
  frozen_kzt bigint,
  pending_kzt bigint,
  withdrawn_kzt bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT
    -- Available: completed commissions (not from free subscriptions) + completed adjustments - completed withdrawals
    COALESCE(SUM(
      CASE 
        WHEN t.type = 'commission' 
             AND t.status = 'completed' 
             AND (t.frozen_until IS NULL OR t.frozen_until <= NOW())
             AND COALESCE(t.is_archived, false) = false
             -- Exclude commissions from free subscriptions
             AND NOT (
               t.type = 'commission' 
               AND t.structure_type = 'primary' 
               AND EXISTS (
                 SELECT 1 FROM subscriptions s 
                 WHERE s.id = t.source_id 
                 AND COALESCE(s.is_marketing_free_access, false) = true
               )
             )
        THEN t.amount_cents 
        WHEN t.type = 'adjustment' AND t.status = 'completed'
             AND COALESCE(t.is_archived, false) = false
        THEN t.amount_cents
        WHEN t.type = 'withdrawal' AND t.status = 'completed'
             AND COALESCE(t.is_archived, false) = false
        THEN -t.amount_cents
        ELSE 0 
      END
    ), 0)::bigint AS available_kzt,
    
    -- Frozen: commissions that are frozen (not yet unfrozen)
    COALESCE(SUM(
      CASE 
        WHEN t.type = 'commission' 
             AND t.status IN ('completed', 'frozen')
             AND t.frozen_until IS NOT NULL 
             AND t.frozen_until > NOW()
             AND COALESCE(t.is_archived, false) = false
             -- Exclude commissions from free subscriptions
             AND NOT EXISTS (
               SELECT 1 FROM subscriptions s 
               WHERE s.id = t.source_id 
               AND COALESCE(s.is_marketing_free_access, false) = true
             )
        THEN t.amount_cents 
        ELSE 0 
      END
    ), 0)::bigint AS frozen_kzt,
    
    -- Pending: withdrawals that are pending
    COALESCE(SUM(
      CASE 
        WHEN t.type = 'withdrawal' AND t.status = 'pending'
             AND COALESCE(t.is_archived, false) = false
        THEN t.amount_cents 
        ELSE 0 
      END
    ), 0)::bigint AS pending_kzt,
    
    -- Withdrawn: total completed withdrawals
    COALESCE(SUM(
      CASE 
        WHEN t.type = 'withdrawal' AND t.status = 'completed'
             AND COALESCE(t.is_archived, false) = false
        THEN t.amount_cents 
        ELSE 0 
      END
    ), 0)::bigint AS withdrawn_kzt
  FROM transactions t
  WHERE t.user_id = p_user_id;
END;
$$;

-- Fix get_all_user_balances to include adjustment transactions
CREATE OR REPLACE FUNCTION public.get_all_user_balances()
RETURNS TABLE(
  user_id uuid,
  available_kzt bigint,
  frozen_kzt bigint,
  pending_kzt bigint,
  withdrawn_kzt bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT
    t.user_id,
    -- Available: completed commissions (not from free subscriptions) + completed adjustments - completed withdrawals
    COALESCE(SUM(
      CASE 
        WHEN t.type = 'commission' 
             AND t.status = 'completed' 
             AND (t.frozen_until IS NULL OR t.frozen_until <= NOW())
             AND COALESCE(t.is_archived, false) = false
             -- Exclude commissions from free subscriptions
             AND NOT EXISTS (
               SELECT 1 FROM subscriptions s 
               WHERE s.id = t.source_id 
               AND COALESCE(s.is_marketing_free_access, false) = true
             )
        THEN t.amount_cents 
        WHEN t.type = 'adjustment' AND t.status = 'completed'
             AND COALESCE(t.is_archived, false) = false
        THEN t.amount_cents
        WHEN t.type = 'withdrawal' AND t.status = 'completed'
             AND COALESCE(t.is_archived, false) = false
        THEN -t.amount_cents
        ELSE 0 
      END
    ), 0)::bigint AS available_kzt,
    
    -- Frozen: commissions that are frozen
    COALESCE(SUM(
      CASE 
        WHEN t.type = 'commission' 
             AND t.status IN ('completed', 'frozen')
             AND t.frozen_until IS NOT NULL 
             AND t.frozen_until > NOW()
             AND COALESCE(t.is_archived, false) = false
             -- Exclude commissions from free subscriptions
             AND NOT EXISTS (
               SELECT 1 FROM subscriptions s 
               WHERE s.id = t.source_id 
               AND COALESCE(s.is_marketing_free_access, false) = true
             )
        THEN t.amount_cents 
        ELSE 0 
      END
    ), 0)::bigint AS frozen_kzt,
    
    -- Pending: withdrawals that are pending
    COALESCE(SUM(
      CASE 
        WHEN t.type = 'withdrawal' AND t.status = 'pending'
             AND COALESCE(t.is_archived, false) = false
        THEN t.amount_cents 
        ELSE 0 
      END
    ), 0)::bigint AS pending_kzt,
    
    -- Withdrawn: total completed withdrawals
    COALESCE(SUM(
      CASE 
        WHEN t.type = 'withdrawal' AND t.status = 'completed'
             AND COALESCE(t.is_archived, false) = false
        THEN t.amount_cents 
        ELSE 0 
      END
    ), 0)::bigint AS withdrawn_kzt
  FROM transactions t
  GROUP BY t.user_id;
END;
$$;