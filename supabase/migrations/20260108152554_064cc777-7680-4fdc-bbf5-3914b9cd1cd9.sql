
-- Сначала удалить функции
DROP FUNCTION IF EXISTS audit_marketing_free_commissions();

-- Пересоздать функцию audit_marketing_free_commissions - исключить failed транзакции
CREATE OR REPLACE FUNCTION public.audit_marketing_free_commissions()
RETURNS TABLE(
  user_id uuid, 
  user_email text, 
  subscription_id uuid, 
  subscriber_name text, 
  transaction_id uuid, 
  amount_cents integer, 
  issue text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  RETURN QUERY
  SELECT 
    t.user_id,
    p.email,
    s.id as subscription_id,
    sp.full_name as subscriber_name,
    t.id as transaction_id,
    t.amount_cents::integer,
    'Commission paid for marketing_free_access subscription'::text as issue
  FROM transactions t
  JOIN subscriptions s ON s.id = t.source_id
  JOIN profiles p ON p.id = t.user_id
  JOIN profiles sp ON sp.id = s.user_id
  WHERE t.type = 'commission'
    AND t.structure_type = 'primary'
    AND t.status NOT IN ('failed', 'cancelled')  -- Исключаем уже исправленные
    AND s.is_marketing_free_access = true
  ORDER BY t.created_at DESC;
END;
$function$;
