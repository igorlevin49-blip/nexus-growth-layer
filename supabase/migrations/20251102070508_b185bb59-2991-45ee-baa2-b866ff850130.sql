-- ==========================================
-- ИСПРАВЛЕНИЕ ДУБЛИРУЮЩИХСЯ ПОЛИТИК
-- ==========================================

-- Удаляем старые дублирующиеся политики
DROP POLICY IF EXISTS "Users can manage their own payment methods" ON payment_methods;
DROP POLICY IF EXISTS "Users can view their own transactions" ON transactions;
DROP POLICY IF EXISTS "System can update transactions" ON transactions;
DROP POLICY IF EXISTS "Users can view their own withdrawals" ON withdrawals;
DROP POLICY IF EXISTS "Users can create their own withdrawals" ON withdrawals;
DROP POLICY IF EXISTS "Admins can update withdrawals" ON withdrawals;
DROP POLICY IF EXISTS "Users can view their own orders" ON orders;
DROP POLICY IF EXISTS "Users can create their own orders" ON orders;
DROP POLICY IF EXISTS "Users can update their own draft orders" ON orders;
DROP POLICY IF EXISTS "Admins can update orders" ON orders;
DROP POLICY IF EXISTS "Users can view own subscription" ON subscriptions;
DROP POLICY IF EXISTS "Users can create own subscription" ON subscriptions;
DROP POLICY IF EXISTS "Admins can update subscriptions" ON subscriptions;
DROP POLICY IF EXISTS "Users can view their own referral network" ON referrals;
DROP POLICY IF EXISTS "Users can view activity in their network" ON activity_log;
DROP POLICY IF EXISTS "Admins can view all actions" ON admin_actions;
DROP POLICY IF EXISTS "Admins can view audit logs" ON admin_audit;
DROP POLICY IF EXISTS "Admins can insert audit logs" ON admin_audit;

-- PROFILES: Оставляем только безопасные политики (другие уже существуют)
-- Уже есть: "Users can view own profile"

-- PAYMENT_METHODS: Оставляем раздельные политики (уже созданы)
-- Уже есть: Users view/insert/update/delete own payment methods, Admins view all

-- TRANSACTIONS: Безопасные политики (уже созданы)
-- Уже есть: Users view/insert own, Service role can update

-- WITHDRAWALS: Безопасные политики (уже созданы)
-- Уже есть: Users view/create own, Admins update

-- ORDERS: Безопасные политики (уже созданы)
-- Уже есть: Users view/create own, Admins update

-- SUBSCRIPTIONS: Безопасные политики (уже созданы)
-- Уже есть: Users view/create own, Admins update

-- REFERRALS: Безопасные политики (уже созданы)
-- Уже есть: Users view own referrals

-- ACTIVITY_LOG: Безопасные политики (уже созданы)
-- Уже есть: Users view own activity

-- ADMIN_ACTIONS: Безопасные политики (уже созданы)
-- Уже есть: Admins insert/view own, Nobody can update/delete

-- ADMIN_AUDIT: Безопасные политики (уже созданы)
-- Уже есть: Admins insert/view own, Nobody can update/delete