-- Таблица системных уведомлений
CREATE TABLE public.system_notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title text NOT NULL,
  message text NOT NULL,
  type text NOT NULL DEFAULT 'info', -- info, warning, promotion, reminder
  channels text[] NOT NULL DEFAULT '{}', -- email, telegram, modal
  target_audience text NOT NULL DEFAULT 'all', -- all, active, inactive, custom
  target_user_ids uuid[] DEFAULT NULL,
  scheduled_at timestamp with time zone DEFAULT NULL,
  sent_at timestamp with time zone DEFAULT NULL,
  created_by uuid REFERENCES auth.users(id),
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  status text NOT NULL DEFAULT 'draft' -- draft, scheduled, sending, sent, failed
);

ALTER TABLE public.system_notifications ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Superadmins can manage system notifications"
ON public.system_notifications FOR ALL
USING (has_role(auth.uid(), 'superadmin'::app_role));

-- Таблица логов отправки
CREATE TABLE public.system_notification_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  notification_id uuid REFERENCES public.system_notifications(id) ON DELETE CASCADE,
  user_id uuid NOT NULL,
  channel text NOT NULL,
  recipient text NOT NULL,
  success boolean DEFAULT false,
  error_message text,
  created_at timestamp with time zone DEFAULT now()
);

ALTER TABLE public.system_notification_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Superadmins can view notification logs"
ON public.system_notification_logs FOR SELECT
USING (has_role(auth.uid(), 'superadmin'::app_role));

CREATE POLICY "System can insert notification logs"
ON public.system_notification_logs FOR INSERT
WITH CHECK (true);

-- Таблица модальных уведомлений для пользователей
CREATE TABLE public.user_modal_notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  notification_id uuid REFERENCES public.system_notifications(id) ON DELETE CASCADE,
  title text NOT NULL,
  message text NOT NULL,
  type text DEFAULT 'info',
  read boolean DEFAULT false,
  dismissed boolean DEFAULT false,
  show_after timestamp with time zone DEFAULT now(),
  created_at timestamp with time zone DEFAULT now()
);

ALTER TABLE public.user_modal_notifications ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their modal notifications"
ON public.user_modal_notifications FOR SELECT
USING (auth.uid() = user_id);

CREATE POLICY "Users can update their modal notifications"
ON public.user_modal_notifications FOR UPDATE
USING (auth.uid() = user_id);

CREATE POLICY "System can insert modal notifications"
ON public.user_modal_notifications FOR INSERT
WITH CHECK (true);

-- Индексы для производительности
CREATE INDEX idx_system_notifications_status ON public.system_notifications(status);
CREATE INDEX idx_system_notifications_scheduled ON public.system_notifications(scheduled_at) WHERE status = 'scheduled';
CREATE INDEX idx_user_modal_notifications_user ON public.user_modal_notifications(user_id, dismissed, show_after);
CREATE INDEX idx_notification_logs_notification ON public.system_notification_logs(notification_id);