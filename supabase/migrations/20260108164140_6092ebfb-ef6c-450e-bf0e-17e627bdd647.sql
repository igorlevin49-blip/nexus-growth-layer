
-- Синхронизируем балансы для всех пользователей с расхождениями
WITH balance_calc AS (
  SELECT 
    t.user_id,
    SUM(CASE 
      WHEN t.type IN ('commission', 'bonus', 'adjustment') AND t.status = 'completed' 
      THEN t.amount_cents ELSE 0 
    END) -
    SUM(CASE 
      WHEN t.type = 'withdrawal' AND t.status = 'completed' 
      THEN t.amount_cents ELSE 0 
    END) AS correct_balance
  FROM transactions t
  WHERE t.is_archived = false
  GROUP BY t.user_id
),
discrepancies AS (
  SELECT 
    p.id,
    p.email,
    p.balance AS old_balance,
    COALESCE(bc.correct_balance, 0) AS new_balance
  FROM profiles p
  LEFT JOIN balance_calc bc ON bc.user_id = p.id
  WHERE ABS(COALESCE(p.balance, 0) - COALESCE(bc.correct_balance, 0)) > 0.01
),
updated AS (
  UPDATE profiles p
  SET balance = d.new_balance,
      updated_at = now()
  FROM discrepancies d
  WHERE p.id = d.id
  RETURNING p.id, d.email, d.old_balance, d.new_balance
)
INSERT INTO activity_log (user_id, type, payload)
SELECT 
  u.id,
  'balance_sync_adjustment',
  jsonb_build_object(
    'old_balance', u.old_balance,
    'new_balance', u.new_balance,
    'reason', 'Синхронизация с учётом adjustment транзакций',
    'synced_at', now()
  )
FROM updated u;
