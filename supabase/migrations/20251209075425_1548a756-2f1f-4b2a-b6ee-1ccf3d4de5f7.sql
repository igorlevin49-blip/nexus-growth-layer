-- Add telegram_chat_id to profiles for linking Telegram accounts
ALTER TABLE public.profiles 
ADD COLUMN IF NOT EXISTS telegram_chat_id text;

-- Create table to track sent activation reminders
CREATE TABLE public.activation_reminder_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  channel text NOT NULL CHECK (channel IN ('telegram', 'email')),
  days_before integer NOT NULL,
  recipient text NOT NULL,
  success boolean DEFAULT true,
  error_message text,
  sent_date date NOT NULL DEFAULT CURRENT_DATE,
  sent_at timestamptz DEFAULT now(),
  created_at timestamptz DEFAULT now(),
  UNIQUE(user_id, channel, days_before, sent_date)
);

-- Enable RLS
ALTER TABLE public.activation_reminder_logs ENABLE ROW LEVEL SECURITY;

-- RLS policies
CREATE POLICY "System can insert reminder logs"
ON public.activation_reminder_logs FOR INSERT
WITH CHECK (true);

CREATE POLICY "Users can view their own reminder logs"
ON public.activation_reminder_logs FOR SELECT
USING (auth.uid() = user_id);

CREATE POLICY "Admins can view all reminder logs"
ON public.activation_reminder_logs FOR SELECT
USING (has_role(auth.uid(), 'admin'::app_role) OR has_role(auth.uid(), 'superadmin'::app_role));

-- Create index for efficient querying
CREATE INDEX idx_activation_reminder_logs_user_date 
ON public.activation_reminder_logs(user_id, sent_date);

CREATE INDEX idx_profiles_telegram_chat_id 
ON public.profiles(telegram_chat_id) WHERE telegram_chat_id IS NOT NULL;