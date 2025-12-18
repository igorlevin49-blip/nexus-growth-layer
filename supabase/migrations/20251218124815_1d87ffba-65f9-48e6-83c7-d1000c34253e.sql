-- Удалить старое ограничение
ALTER TABLE admin_notifications DROP CONSTRAINT IF EXISTS admin_notifications_type_check;

-- Создать новое ограничение с типом 'commission'
ALTER TABLE admin_notifications ADD CONSTRAINT admin_notifications_type_check 
  CHECK (type = ANY (ARRAY['status_achievement', 'payment', 'system', 'commission', 'suspicious_activity']));