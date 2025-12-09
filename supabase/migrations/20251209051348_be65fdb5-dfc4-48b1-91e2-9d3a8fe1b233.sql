-- 1. Удалить опасную политику INSERT для transactions
DROP POLICY IF EXISTS "System can insert transactions" ON public.transactions;

-- 2. Создать функцию для безопасного доступа к сетевым профилям
CREATE OR REPLACE FUNCTION public.get_network_profiles(p_user_id uuid)
RETURNS TABLE (
  id uuid,
  full_name text,
  avatar_url text,
  referral_code text,
  subscription_status text,
  is_active boolean,
  sponsor_id uuid,
  direct_referrals_count integer,
  monthly_activation_completed boolean,
  created_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Проверяем аутентификацию
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  
  -- Возвращаем только профили из сети пользователя или свой профиль
  RETURN QUERY
  WITH RECURSIVE network AS (
    SELECT pr.id FROM profiles pr WHERE pr.id = p_user_id
    UNION ALL
    SELECT p.id FROM profiles p
    INNER JOIN network n ON p.sponsor_id = n.id
  )
  SELECT 
    p.id, p.full_name, p.avatar_url, p.referral_code,
    p.subscription_status, p.is_active, p.sponsor_id,
    p.direct_referrals_count, p.monthly_activation_completed, p.created_at
  FROM profiles p
  WHERE p.id IN (SELECT network.id FROM network)
    AND p.is_active = true 
    AND p.deleted_at IS NULL;
END;
$$;

-- 3. Добавить триггер валидации meta в payment_methods
CREATE OR REPLACE FUNCTION public.validate_payment_method_meta()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  meta_text text;
BEGIN
  meta_text := NEW.meta::text;
  
  -- Блокировать потенциальные номера карт (13-19 цифр подряд)
  IF meta_text ~ '\d{13,19}' THEN
    RAISE EXCEPTION 'Storing card numbers in meta field is prohibited';
  END IF;
  
  -- Блокировать CVV/CVC паттерны
  IF meta_text ~* '"(cvv|cvc|cv2|security_code)"' THEN
    RAISE EXCEPTION 'Storing CVV/CVC in meta field is prohibited';
  END IF;
  
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS validate_payment_meta_trigger ON public.payment_methods;
CREATE TRIGGER validate_payment_meta_trigger
BEFORE INSERT OR UPDATE ON public.payment_methods
FOR EACH ROW
EXECUTE FUNCTION public.validate_payment_method_meta();

-- 4. Удалить устаревшие данные payment_details из profiles
UPDATE public.profiles SET payment_details = NULL WHERE payment_details IS NOT NULL;