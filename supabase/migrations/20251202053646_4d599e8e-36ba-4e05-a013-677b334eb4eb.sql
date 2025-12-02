-- Исправляем security warnings: устанавливаем search_path для функции
DROP TRIGGER IF EXISTS trigger_notify_admins_on_status ON public.user_status_achievements;
DROP FUNCTION IF EXISTS notify_admins_on_status_achievement();

CREATE OR REPLACE FUNCTION notify_admins_on_status_achievement()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
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
$$;

-- Создаём триггер заново
CREATE TRIGGER trigger_notify_admins_on_status
  AFTER INSERT ON public.user_status_achievements
  FOR EACH ROW
  EXECUTE FUNCTION notify_admins_on_status_achievement();