
-- ============================================================================
-- УНИФИКАЦИЯ MLM-НАСТРОЕК: ЕДИНЫЙ ИСТОЧНИК ПРАВДЫ
-- Шаг 1: Удаление старых функций и обновление настроек
-- ============================================================================

-- ШАГ 1: Обновить unlock_levels - добавить l1:0
UPDATE mlm_settings 
SET value = '{"l1": 0, "l2": 3, "l3": 5, "l4": 8, "l5": 10}'::jsonb,
    updated_at = now()
WHERE key = 'unlock_levels';

-- ШАГ 2: Удалить дублирующие настройки
DELETE FROM mlm_settings WHERE key IN ('s1_commission_rates', 's1_unlock_requirements');

-- ШАГ 3: Обновить commission_plan_levels на правильные проценты
UPDATE commission_plan_levels SET percent = 10 WHERE structure_type = 'primary' AND level IN (1,2,3,4,5);
UPDATE commission_plan_levels SET percent = 10 WHERE structure_type = 'secondary' AND level = 1;
UPDATE commission_plan_levels SET percent = 5 WHERE structure_type = 'secondary' AND level BETWEEN 2 AND 9;
UPDATE commission_plan_levels SET percent = 10 WHERE structure_type = 'secondary' AND level = 10;
DELETE FROM commission_plan_levels WHERE structure_type = 'primary' AND level > 5;

-- ШАГ 4: Удалить все версии функций для пересоздания
DROP FUNCTION IF EXISTS public.award_s1_subscription_commission(uuid, numeric, uuid, timestamp with time zone);
DROP FUNCTION IF EXISTS public.award_s1_subscription_commission(uuid, numeric, uuid);
DROP FUNCTION IF EXISTS public.award_s1_subscription_commission(numeric, uuid, uuid);
DROP FUNCTION IF EXISTS public.create_commission_transactions(uuid, uuid, numeric);
DROP FUNCTION IF EXISTS public.get_commission_structure_stats(uuid, integer, timestamptz, timestamptz);
DROP FUNCTION IF EXISTS public.get_referral_network_from_table(uuid, integer, integer);
DROP FUNCTION IF EXISTS public.backfill_missing_s1_commissions(uuid, integer);
