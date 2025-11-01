-- Расширяем check constraint для activity_log.type
ALTER TABLE activity_log DROP CONSTRAINT IF EXISTS activity_log_type_check;

ALTER TABLE activity_log ADD CONSTRAINT activity_log_type_check 
CHECK (type = ANY (ARRAY[
  'invite'::text, 
  'activation'::text, 
  'freeze'::text, 
  'unfreeze'::text, 
  'purchase'::text, 
  'registration'::text,
  'subscription_activated'::text,
  'manual_payment_approved'::text,
  'manual_payment_rejected'::text,
  'admin_action'::text
]));

-- Добавляем колонку is_archived в profiles если её нет
DO $$ 
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'public' 
    AND table_name = 'profiles' 
    AND column_name = 'is_archived'
  ) THEN
    ALTER TABLE profiles ADD COLUMN is_archived BOOLEAN DEFAULT false;
  END IF;
END $$;

-- Обновляем RLS политику для profiles, чтобы заблокировать вход удалённым/архивным пользователям
DROP POLICY IF EXISTS "Users can view their own profile" ON profiles;

CREATE POLICY "Users can view their own profile"
ON profiles
FOR SELECT
TO authenticated
USING (
  auth.uid() = id 
  AND is_active = true 
  AND deleted_at IS NULL
  AND (is_archived IS NULL OR is_archived = false)
);