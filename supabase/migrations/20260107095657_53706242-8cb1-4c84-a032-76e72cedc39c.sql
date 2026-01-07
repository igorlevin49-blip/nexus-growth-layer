-- =====================================================
-- СИНХРОНИЗАЦИЯ profiles.monthly_activation_completed
-- =====================================================

-- 1. Функция синхронизации при изменении monthly_activations
CREATE OR REPLACE FUNCTION public.sync_monthly_activation_to_profile()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- При INSERT или UPDATE в monthly_activations
  -- синхронизируем статус в profiles
  UPDATE profiles
  SET 
    monthly_activation_completed = NEW.is_activated,
    updated_at = now()
  WHERE id = NEW.user_id;
  
  RETURN NEW;
END;
$$;

-- 2. Триггер на таблице monthly_activations
DROP TRIGGER IF EXISTS on_monthly_activation_change ON monthly_activations;
CREATE TRIGGER on_monthly_activation_change
  AFTER INSERT OR UPDATE OF is_activated ON monthly_activations
  FOR EACH ROW
  EXECUTE FUNCTION sync_monthly_activation_to_profile();

-- 3. Функция для сброса статуса в начале месяца
CREATE OR REPLACE FUNCTION public.reset_monthly_activation_status()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Сбрасываем флаг для пользователей, у которых нет активации за текущий месяц
  UPDATE profiles
  SET 
    monthly_activation_completed = false,
    updated_at = now()
  WHERE id NOT IN (
    SELECT user_id FROM monthly_activations
    WHERE year = EXTRACT(YEAR FROM CURRENT_DATE)::int
      AND month = EXTRACT(MONTH FROM CURRENT_DATE)::int
      AND is_activated = true
  )
  AND monthly_activation_completed = true;
END;
$$;

-- 4. Исправление текущего рассинхрона (январь 2026)
-- Сбросить для тех, у кого нет активации
UPDATE profiles
SET monthly_activation_completed = false, updated_at = now()
WHERE monthly_activation_completed = true
  AND id NOT IN (
    SELECT user_id FROM monthly_activations
    WHERE year = 2026 AND month = 1 AND is_activated = true
  );

-- Установить для тех, у кого есть активация
UPDATE profiles
SET monthly_activation_completed = true, updated_at = now()
WHERE monthly_activation_completed = false
  AND id IN (
    SELECT user_id FROM monthly_activations
    WHERE year = 2026 AND month = 1 AND is_activated = true
  );