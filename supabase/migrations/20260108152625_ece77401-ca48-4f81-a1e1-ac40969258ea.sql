
-- Пересоздать функцию без cancelled
DROP FUNCTION IF EXISTS audit_marketing_free_commissions();

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
    AND t.status = 'frozen' OR t.status = 'completed'  -- Только активные транзакции
    AND s.is_marketing_free_access = true
  ORDER BY t.created_at DESC;
END;
$function$;

-- Также исправить audit_unlock_levels_violations
CREATE OR REPLACE FUNCTION public.audit_unlock_levels_violations()
RETURNS TABLE(user_id uuid, user_email text, user_name text, level integer, direct_referrals_count integer, required_referrals integer, violation_count integer, total_wrong_amount_cents bigint)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_unlock_levels jsonb;
BEGIN
  SELECT value INTO v_unlock_levels
  FROM mlm_settings
  WHERE key = 'unlock_levels';
  
  IF v_unlock_levels IS NULL THEN
    v_unlock_levels := '{"l2": 3, "l3": 5, "l4": 8, "l5": 10}'::jsonb;
  END IF;

  RETURN QUERY
  WITH unlock_reqs AS (
    SELECT 
      2 as lvl, COALESCE((v_unlock_levels->>'l2')::integer, 3) as required
    UNION ALL SELECT 3, COALESCE((v_unlock_levels->>'l3')::integer, 5)
    UNION ALL SELECT 4, COALESCE((v_unlock_levels->>'l4')::integer, 8)
    UNION ALL SELECT 5, COALESCE((v_unlock_levels->>'l5')::integer, 10)
  ),
  user_direct_counts AS (
    SELECT 
      r.referrer_id as uid,
      COUNT(*) as direct_count
    FROM referrals r
    WHERE r.structure_type = 1
    GROUP BY r.referrer_id
  )
  SELECT 
    t.user_id,
    p.email,
    p.full_name,
    t.level,
    COALESCE(udc.direct_count, 0)::integer,
    ur.required::integer,
    COUNT(*)::integer as violation_count,
    SUM(t.amount_cents)::bigint as total_wrong_amount
  FROM transactions t
  JOIN unlock_reqs ur ON t.level = ur.lvl
  LEFT JOIN user_direct_counts udc ON t.user_id = udc.uid
  LEFT JOIN profiles p ON p.id = t.user_id
  WHERE t.type = 'commission'
    AND t.structure_type = 'primary'
    AND t.level > 1
    AND (t.status = 'frozen' OR t.status = 'completed')  -- Только активные
    AND COALESCE(udc.direct_count, 0) < ur.required
  GROUP BY t.user_id, p.email, p.full_name, t.level, udc.direct_count, ur.required
  ORDER BY total_wrong_amount DESC;
END;
$function$;
