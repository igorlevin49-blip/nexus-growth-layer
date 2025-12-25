-- Отменяем зависшие processing выводы старше 24 часов
UPDATE withdrawals 
SET status = 'cancelled', processed_at = NOW()
WHERE status = 'processing' 
  AND created_at < NOW() - INTERVAL '24 hours';

-- Отменяем соответствующие транзакции (используем 'failed' т.к. 'cancelled' нет в enum)
UPDATE transactions
SET status = 'failed', updated_at = NOW()
WHERE type = 'withdrawal' 
  AND status = 'processing'
  AND created_at < NOW() - INTERVAL '24 hours';