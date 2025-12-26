
-- Delete ALL incorrect commissions for marketing_free_access subscriptions
DELETE FROM transactions t
USING subscriptions s
WHERE t.source_id = s.id
  AND t.type = 'commission'
  AND s.is_marketing_free_access = true;

-- Create audit function for future detection
CREATE OR REPLACE FUNCTION public.audit_marketing_free_commissions()
RETURNS TABLE (
  transaction_id uuid,
  user_id uuid,
  user_email text,
  amount_cents integer,
  subscription_id uuid,
  subscriber_name text,
  issue text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    t.id as transaction_id,
    t.user_id,
    p.email as user_email,
    t.amount_cents,
    s.id as subscription_id,
    sp.full_name as subscriber_name,
    'Commission paid for marketing_free_access subscription'::text as issue
  FROM transactions t
  JOIN subscriptions s ON s.id = t.source_id
  JOIN profiles p ON p.id = t.user_id
  JOIN profiles sp ON sp.id = s.user_id
  WHERE t.type = 'commission'
    AND s.is_marketing_free_access = true;
END;
$$;
