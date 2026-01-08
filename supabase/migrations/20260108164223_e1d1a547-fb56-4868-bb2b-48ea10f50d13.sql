
-- 1. Удаляем обе функции
DROP FUNCTION IF EXISTS public.get_user_balance(uuid);
DROP FUNCTION IF EXISTS public.audit_balance_integrity();

-- 2. Создаём get_user_balance с фильтром is_archived
CREATE FUNCTION public.get_user_balance(p_user_id uuid)
RETURNS TABLE(
  available_cents numeric,
  frozen_cents numeric,
  pending_cents numeric,
  withdrawn_cents numeric,
  available_kzt numeric,
  frozen_kzt numeric,
  pending_kzt numeric,
  withdrawn_kzt numeric
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_available numeric := 0;
  v_frozen numeric := 0;
  v_pending numeric := 0;
  v_withdrawn numeric := 0;
BEGIN
  -- Calculate available balance (commission, bonus, adjustment that are completed - withdrawals)
  SELECT COALESCE(SUM(
    CASE 
      WHEN type IN ('commission', 'bonus', 'adjustment') AND status = 'completed' THEN amount_cents
      WHEN type = 'withdrawal' AND status = 'completed' THEN -amount_cents
      ELSE 0
    END
  ), 0) INTO v_available
  FROM transactions
  WHERE user_id = p_user_id
    AND is_archived = false;

  -- Calculate frozen balance
  SELECT COALESCE(SUM(amount_cents), 0) INTO v_frozen
  FROM transactions
  WHERE user_id = p_user_id
    AND type = 'commission'
    AND status = 'frozen'
    AND is_archived = false;

  -- Calculate pending balance (pending withdrawals)
  SELECT COALESCE(SUM(amount_cents), 0) INTO v_pending
  FROM withdrawals
  WHERE user_id = p_user_id
    AND status = 'pending';

  -- Calculate total withdrawn
  SELECT COALESCE(SUM(amount_cents), 0) INTO v_withdrawn
  FROM withdrawals
  WHERE user_id = p_user_id
    AND status = 'completed';

  RETURN QUERY SELECT 
    v_available AS available_cents,
    v_frozen AS frozen_cents,
    v_pending AS pending_cents,
    v_withdrawn AS withdrawn_cents,
    v_available AS available_kzt,
    v_frozen AS frozen_kzt,
    v_pending AS pending_kzt,
    v_withdrawn AS withdrawn_kzt;
END;
$$;

-- 3. Создаём audit_balance_integrity с учётом adjustment и is_archived
CREATE FUNCTION public.audit_balance_integrity()
RETURNS TABLE(
  user_id uuid,
  email text,
  issue_type text,
  details jsonb
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  WITH user_balances AS (
    SELECT 
      p.id as uid,
      p.email,
      COALESCE(p.balance, 0) as profile_balance,
      -- Доступный баланс = completed (комиссии+бонусы+adjustment) - выводы
      COALESCE((
        SELECT SUM(CASE 
          WHEN t.type IN ('commission', 'bonus', 'adjustment') AND t.status = 'completed' THEN t.amount_cents
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
$$;
