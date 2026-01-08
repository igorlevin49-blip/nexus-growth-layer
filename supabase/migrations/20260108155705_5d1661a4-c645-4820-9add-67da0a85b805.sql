
-- Сначала удалить функцию
DROP FUNCTION IF EXISTS audit_balance_integrity();

-- Пересоздать с правильной логикой
CREATE OR REPLACE FUNCTION public.audit_balance_integrity()
RETURNS TABLE(
  user_id uuid, 
  user_email text, 
  issue_type text, 
  details jsonb
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  RETURN QUERY
  WITH user_balances AS (
    SELECT 
      p.id as uid,
      p.email,
      COALESCE(p.balance, 0) as profile_balance,
      -- Доступный баланс = completed комиссии - выводы (исключаем failed)
      COALESCE((
        SELECT SUM(CASE 
          WHEN t.type = 'commission' AND t.status = 'completed' THEN t.amount_cents
          WHEN t.type = 'withdrawal' AND t.status = 'completed' THEN -t.amount_cents
          ELSE 0
        END)
        FROM transactions t
        WHERE t.user_id = p.id
          AND t.is_archived = false
      ), 0) as calculated_available,
      -- Замороженный баланс
      COALESCE((
        SELECT SUM(t.amount_cents)
        FROM transactions t
        WHERE t.user_id = p.id
          AND t.type = 'commission'
          AND t.status = 'frozen'
          AND t.is_archived = false
      ), 0) as frozen_cents,
      -- Выведенные средства
      COALESCE((
        SELECT SUM(t.amount_cents)
        FROM transactions t
        WHERE t.user_id = p.id
          AND t.type = 'withdrawal'
          AND t.status = 'completed'
          AND t.is_archived = false
      ), 0) as withdrawn_cents
    FROM profiles p
    WHERE p.deleted_at IS NULL
  )
  SELECT 
    ub.uid,
    ub.email,
    'balance_mismatch'::text,
    jsonb_build_object(
      'calculated_available', ub.calculated_available,
      'profile_balance', ub.profile_balance,
      'difference', ub.profile_balance - ub.calculated_available,
      'frozen_cents', ub.frozen_cents,
      'withdrawn_cents', ub.withdrawn_cents
    )
  FROM user_balances ub
  WHERE ABS(ub.profile_balance - ub.calculated_available) > 100  -- Разница больше 1 тенге
  ORDER BY ABS(ub.profile_balance - ub.calculated_available) DESC;
END;
$function$;
