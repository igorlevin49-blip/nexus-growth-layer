-- Исправляем функцию get_user_balance: вычитаем выводы из доступного баланса
CREATE OR REPLACE FUNCTION public.get_user_balance(p_user_id uuid)
RETURNS TABLE(
  user_id uuid,
  available_cents bigint,
  frozen_cents bigint,
  pending_cents bigint,
  withdrawn_cents bigint,
  updated_at timestamp with time zone
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    p_user_id as user_id,
    
    -- Available: разблокированные комиссии/бонусы МИНУС завершённые выводы
    COALESCE(SUM(
      CASE 
        WHEN t.type IN ('commission', 'bonus', 'adjustment') 
          AND t.status = 'completed' 
          AND (t.frozen_until IS NULL OR t.frozen_until <= NOW())
        THEN t.amount_cents 
        WHEN t.type = 'withdrawal' AND t.status IN ('completed', 'processing')
        THEN -t.amount_cents
        ELSE 0 
      END
    ), 0)::bigint as available_cents,
    
    -- Frozen: комиссии где frozen_until > NOW() ИЛИ status = 'frozen'
    COALESCE(SUM(
      CASE 
        WHEN t.type IN ('commission', 'bonus', 'adjustment') 
          AND (
            t.status = 'frozen'
            OR (t.status = 'completed' AND t.frozen_until IS NOT NULL AND t.frozen_until > NOW())
          )
        THEN t.amount_cents 
        ELSE 0 
      END
    ), 0)::bigint as frozen_cents,
    
    -- Pending: ожидающие транзакции
    COALESCE(SUM(
      CASE 
        WHEN t.type IN ('commission', 'bonus', 'adjustment') 
          AND t.status = 'pending'
        THEN t.amount_cents 
        ELSE 0 
      END
    ), 0)::bigint as pending_cents,
    
    -- Withdrawn: все завершённые выводы
    COALESCE(SUM(
      CASE 
        WHEN t.type = 'withdrawal' AND t.status = 'completed'
        THEN t.amount_cents 
        ELSE 0 
      END
    ), 0)::bigint as withdrawn_cents,
    
    NOW() as updated_at
    
  FROM transactions t
  WHERE t.user_id = p_user_id
    AND t.currency = 'KZT'
    AND (t.is_archived IS NULL OR t.is_archived = false);
END;
$$;

-- Синхронизируем get_all_user_balances для консистентности
CREATE OR REPLACE FUNCTION public.get_all_user_balances()
RETURNS TABLE(
  user_id uuid,
  available_cents bigint,
  frozen_cents bigint,
  pending_cents bigint,
  withdrawn_cents bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    t.user_id,
    
    -- Available: разблокированные комиссии/бонусы МИНУС выводы (processing + completed)
    COALESCE(SUM(
      CASE 
        WHEN t.type IN ('commission', 'bonus', 'adjustment') 
          AND t.status = 'completed' 
          AND (t.frozen_until IS NULL OR t.frozen_until <= NOW())
        THEN t.amount_cents 
        WHEN t.type = 'withdrawal' AND t.status IN ('completed', 'processing')
        THEN -t.amount_cents
        ELSE 0 
      END
    ), 0)::bigint as available_cents,
    
    -- Frozen: комиссии где frozen_until > NOW() ИЛИ status = 'frozen'
    COALESCE(SUM(
      CASE 
        WHEN t.type IN ('commission', 'bonus', 'adjustment') 
          AND (
            t.status = 'frozen'
            OR (t.status = 'completed' AND t.frozen_until IS NOT NULL AND t.frozen_until > NOW())
          )
        THEN t.amount_cents 
        ELSE 0 
      END
    ), 0)::bigint as frozen_cents,
    
    -- Pending
    COALESCE(SUM(
      CASE 
        WHEN t.type IN ('commission', 'bonus', 'adjustment') 
          AND t.status = 'pending'
        THEN t.amount_cents 
        ELSE 0 
      END
    ), 0)::bigint as pending_cents,
    
    -- Withdrawn
    COALESCE(SUM(
      CASE 
        WHEN t.type = 'withdrawal' AND t.status = 'completed'
        THEN t.amount_cents 
        ELSE 0 
      END
    ), 0)::bigint as withdrawn_cents
    
  FROM transactions t
  WHERE t.currency = 'KZT'
    AND (t.is_archived IS NULL OR t.is_archived = false)
  GROUP BY t.user_id;
END;
$$;