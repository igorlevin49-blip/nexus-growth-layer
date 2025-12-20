-- Удалить старую версию функции process_manual_payout с integer параметром
-- чтобы устранить конфликт перегрузки функций
DROP FUNCTION IF EXISTS public.process_manual_payout(UUID, INTEGER, TEXT);