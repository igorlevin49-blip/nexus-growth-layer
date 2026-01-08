-- Drop and recreate get_user_balance with _kzt aliases
DROP FUNCTION IF EXISTS public.get_user_balance(uuid);

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
  -- Calculate available balance (commission transactions that are released)
  SELECT COALESCE(SUM(
    CASE 
      WHEN type IN ('commission', 'bonus', 'adjustment', 'refund') AND status = 'completed' THEN amount_cents
      WHEN type = 'withdrawal' AND status = 'completed' THEN -amount_cents
      WHEN type = 'payout' AND status = 'completed' THEN -amount_cents
      ELSE 0
    END
  ), 0) INTO v_available
  FROM transactions
  WHERE user_id = p_user_id;

  -- Calculate frozen balance
  SELECT COALESCE(SUM(amount_cents), 0) INTO v_frozen
  FROM transactions
  WHERE user_id = p_user_id
    AND type = 'commission'
    AND status = 'frozen';

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

-- Drop and recreate get_all_user_balances with _kzt aliases
DROP FUNCTION IF EXISTS public.get_all_user_balances();

CREATE FUNCTION public.get_all_user_balances()
RETURNS TABLE(
  user_id uuid,
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
BEGIN
  RETURN QUERY
  WITH user_transactions AS (
    SELECT 
      t.user_id,
      COALESCE(SUM(
        CASE 
          WHEN t.type IN ('commission', 'bonus', 'adjustment', 'refund') AND t.status = 'completed' THEN t.amount_cents
          WHEN t.type = 'withdrawal' AND t.status = 'completed' THEN -t.amount_cents
          WHEN t.type = 'payout' AND t.status = 'completed' THEN -t.amount_cents
          ELSE 0
        END
      ), 0) AS available,
      COALESCE(SUM(
        CASE WHEN t.type = 'commission' AND t.status = 'frozen' THEN t.amount_cents ELSE 0 END
      ), 0) AS frozen
    FROM transactions t
    GROUP BY t.user_id
  ),
  user_withdrawals AS (
    SELECT 
      w.user_id,
      COALESCE(SUM(CASE WHEN w.status = 'pending' THEN w.amount_cents ELSE 0 END), 0) AS pending,
      COALESCE(SUM(CASE WHEN w.status = 'completed' THEN w.amount_cents ELSE 0 END), 0) AS withdrawn
    FROM withdrawals w
    GROUP BY w.user_id
  )
  SELECT 
    p.id AS user_id,
    COALESCE(ut.available, 0) AS available_cents,
    COALESCE(ut.frozen, 0) AS frozen_cents,
    COALESCE(uw.pending, 0) AS pending_cents,
    COALESCE(uw.withdrawn, 0) AS withdrawn_cents,
    COALESCE(ut.available, 0) AS available_kzt,
    COALESCE(ut.frozen, 0) AS frozen_kzt,
    COALESCE(uw.pending, 0) AS pending_kzt,
    COALESCE(uw.withdrawn, 0) AS withdrawn_kzt
  FROM profiles p
  LEFT JOIN user_transactions ut ON ut.user_id = p.id
  LEFT JOIN user_withdrawals uw ON uw.user_id = p.id
  WHERE p.is_active = true;
END;
$$;