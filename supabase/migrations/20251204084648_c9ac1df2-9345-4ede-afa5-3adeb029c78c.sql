-- 1. Удаляем триггер дублирующих бонусов
DROP TRIGGER IF EXISTS trigger_subscription_s1_bonus ON subscriptions;

-- 2. Удаляем функцию
DROP FUNCTION IF EXISTS public.create_subscription_with_s1_bonus();

-- 3. Удаляем уже начисленные дублирующие бонусы (type='bonus' с source_ref содержащим 's1_bonus')
DELETE FROM transactions 
WHERE type = 'bonus' 
AND source_ref LIKE '%s1_bonus%';