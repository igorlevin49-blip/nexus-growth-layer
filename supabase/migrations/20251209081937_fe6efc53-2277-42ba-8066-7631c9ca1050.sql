ALTER TABLE notification_settings 
ADD COLUMN IF NOT EXISTS email_activation_reminder boolean DEFAULT true;