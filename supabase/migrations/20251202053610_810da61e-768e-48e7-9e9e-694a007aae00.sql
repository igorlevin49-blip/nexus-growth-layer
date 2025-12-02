-- Таблица для хранения достижений статусов пользователей
CREATE TABLE IF NOT EXISTS public.user_status_achievements (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  level INTEGER NOT NULL,
  status_name TEXT NOT NULL,
  achieved_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  shown BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Таблица для уведомлений администраторов
CREATE TABLE IF NOT EXISTS public.admin_notifications (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  admin_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  type TEXT NOT NULL CHECK (type IN ('status_achievement', 'payment', 'system')),
  title TEXT NOT NULL,
  message TEXT NOT NULL,
  read BOOLEAN NOT NULL DEFAULT false,
  metadata JSONB DEFAULT '{}'::jsonb,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Индексы для производительности
CREATE INDEX IF NOT EXISTS idx_user_status_achievements_user_id ON public.user_status_achievements(user_id);
CREATE INDEX IF NOT EXISTS idx_user_status_achievements_shown ON public.user_status_achievements(shown);
CREATE INDEX IF NOT EXISTS idx_admin_notifications_admin_id ON public.admin_notifications(admin_id);
CREATE INDEX IF NOT EXISTS idx_admin_notifications_read ON public.admin_notifications(read);
CREATE INDEX IF NOT EXISTS idx_admin_notifications_created_at ON public.admin_notifications(created_at DESC);

-- RLS политики для user_status_achievements
ALTER TABLE public.user_status_achievements ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own achievements"
  ON public.user_status_achievements
  FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "System can insert achievements"
  ON public.user_status_achievements
  FOR INSERT
  WITH CHECK (true);

CREATE POLICY "Users can update their own shown status"
  ON public.user_status_achievements
  FOR UPDATE
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- RLS политики для admin_notifications
ALTER TABLE public.admin_notifications ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Admins can view their notifications"
  ON public.admin_notifications
  FOR SELECT
  USING (
    auth.uid() = admin_id AND 
    (has_role(auth.uid(), 'admin'::app_role) OR has_role(auth.uid(), 'superadmin'::app_role))
  );

CREATE POLICY "System can insert notifications"
  ON public.admin_notifications
  FOR INSERT
  WITH CHECK (true);

CREATE POLICY "Admins can update their notifications"
  ON public.admin_notifications
  FOR UPDATE
  USING (
    auth.uid() = admin_id AND 
    (has_role(auth.uid(), 'admin'::app_role) OR has_role(auth.uid(), 'superadmin'::app_role))
  )
  WITH CHECK (
    auth.uid() = admin_id AND 
    (has_role(auth.uid(), 'admin'::app_role) OR has_role(auth.uid(), 'superadmin'::app_role))
  );

-- Функция для отправки уведомления админам при получении нового статуса
CREATE OR REPLACE FUNCTION notify_admins_on_status_achievement()
RETURNS TRIGGER AS $$
DECLARE
  admin_record RECORD;
  user_profile RECORD;
BEGIN
  -- Получаем информацию о пользователе
  SELECT full_name, email, referral_code, first_name, last_name
  INTO user_profile
  FROM profiles
  WHERE id = NEW.user_id;

  -- Отправляем уведомление всем супер-админам
  FOR admin_record IN 
    SELECT DISTINCT user_id 
    FROM user_roles 
    WHERE role = 'superadmin'
  LOOP
    INSERT INTO admin_notifications (admin_id, type, title, message, metadata)
    VALUES (
      admin_record.user_id,
      'status_achievement',
      'Новое достижение партнёра',
      format(
        'Партнёр %s (%s, ID: %s) получил новый статус: %s (Уровень %s)',
        COALESCE(user_profile.full_name, user_profile.first_name || ' ' || user_profile.last_name, 'Без имени'),
        COALESCE(user_profile.email, 'email не указан'),
        SUBSTRING(NEW.user_id::text, 1, 8),
        NEW.status_name,
        NEW.level
      ),
      jsonb_build_object(
        'user_id', NEW.user_id,
        'level', NEW.level,
        'status_name', NEW.status_name,
        'achieved_at', NEW.achieved_at,
        'referral_code', user_profile.referral_code
      )
    );
  END LOOP;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Триггер для автоматического уведомления админов
CREATE TRIGGER trigger_notify_admins_on_status
  AFTER INSERT ON public.user_status_achievements
  FOR EACH ROW
  EXECUTE FUNCTION notify_admins_on_status_achievement();

-- Включаем realtime для уведомлений
ALTER PUBLICATION supabase_realtime ADD TABLE public.user_status_achievements;
ALTER PUBLICATION supabase_realtime ADD TABLE public.admin_notifications;