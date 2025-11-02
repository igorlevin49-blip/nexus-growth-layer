-- ==========================================
-- КРИТИЧЕСКИЕ ИСПРАВЛЕНИЯ БЕЗОПАСНОСТИ RLS
-- ==========================================

-- 1. PROFILES: Усиление защиты персональных данных
-- Запрет просмотра email и телефона других пользователей
DROP POLICY IF EXISTS "Users can view own profile" ON profiles;
CREATE POLICY "Users can view own profile"
ON profiles FOR SELECT
TO authenticated
USING (
  id = auth.uid() 
  OR has_role(auth.uid(), 'admin'::app_role)
  OR has_role(auth.uid(), 'superadmin'::app_role)
);

-- 2. PAYMENT_METHODS: Строгий доступ только к своим методам
DROP POLICY IF EXISTS "Users manage own payment methods" ON payment_methods;
CREATE POLICY "Users view own payment methods"
ON payment_methods FOR SELECT
TO authenticated
USING (user_id = auth.uid());

CREATE POLICY "Users insert own payment methods"
ON payment_methods FOR INSERT
TO authenticated
WITH CHECK (user_id = auth.uid());

CREATE POLICY "Users update own payment methods"
ON payment_methods FOR UPDATE
TO authenticated
USING (user_id = auth.uid())
WITH CHECK (user_id = auth.uid());

CREATE POLICY "Users delete own payment methods"
ON payment_methods FOR DELETE
TO authenticated
USING (user_id = auth.uid());

CREATE POLICY "Admins view all payment methods"
ON payment_methods FOR SELECT
TO authenticated
USING (
  has_role(auth.uid(), 'admin'::app_role)
  OR has_role(auth.uid(), 'superadmin'::app_role)
);

-- 3. TRANSACTIONS: Защита финансовой истории
DROP POLICY IF EXISTS "Users can view own transactions" ON transactions;
DROP POLICY IF EXISTS "System can update all transactions" ON transactions;

CREATE POLICY "Users view own transactions"
ON transactions FOR SELECT
TO authenticated
USING (
  user_id = auth.uid()
  OR has_role(auth.uid(), 'admin'::app_role)
  OR has_role(auth.uid(), 'superadmin'::app_role)
);

CREATE POLICY "Users insert own transactions"
ON transactions FOR INSERT
TO authenticated
WITH CHECK (user_id = auth.uid());

-- Только система может обновлять транзакции (через service_role)
CREATE POLICY "Service role can update transactions"
ON transactions FOR UPDATE
TO service_role
USING (true);

-- 4. WITHDRAWALS: Строгий доступ только к своим выводам
DROP POLICY IF EXISTS "Users manage own withdrawals" ON withdrawals;

CREATE POLICY "Users view own withdrawals"
ON withdrawals FOR SELECT
TO authenticated
USING (
  user_id = auth.uid()
  OR has_role(auth.uid(), 'admin'::app_role)
  OR has_role(auth.uid(), 'superadmin'::app_role)
);

CREATE POLICY "Users create own withdrawals"
ON withdrawals FOR INSERT
TO authenticated
WITH CHECK (user_id = auth.uid());

CREATE POLICY "Admins update withdrawals"
ON withdrawals FOR UPDATE
TO authenticated
USING (
  has_role(auth.uid(), 'admin'::app_role)
  OR has_role(auth.uid(), 'superadmin'::app_role)
);

-- 5. ORDERS: Защита истории покупок
DROP POLICY IF EXISTS "Users manage own orders" ON orders;

CREATE POLICY "Users view own orders"
ON orders FOR SELECT
TO authenticated
USING (
  user_id = auth.uid()
  OR has_role(auth.uid(), 'admin'::app_role)
  OR has_role(auth.uid(), 'superadmin'::app_role)
);

CREATE POLICY "Users create own orders"
ON orders FOR INSERT
TO authenticated
WITH CHECK (user_id = auth.uid());

CREATE POLICY "Admins update orders"
ON orders FOR UPDATE
TO authenticated
USING (
  has_role(auth.uid(), 'admin'::app_role)
  OR has_role(auth.uid(), 'superadmin'::app_role)
);

-- 6. ADMIN_ACTIONS & ADMIN_AUDIT: Защита от подделки логов
DROP POLICY IF EXISTS "Admins can insert actions" ON admin_actions;
DROP POLICY IF EXISTS "Admins can view actions" ON admin_actions;

-- Только вставка и чтение, БЕЗ обновления и удаления
CREATE POLICY "Admins insert own actions"
ON admin_actions FOR INSERT
TO authenticated
WITH CHECK (
  admin_id = auth.uid()
  AND (
    has_role(auth.uid(), 'admin'::app_role)
    OR has_role(auth.uid(), 'superadmin'::app_role)
  )
);

CREATE POLICY "Admins view all actions"
ON admin_actions FOR SELECT
TO authenticated
USING (
  has_role(auth.uid(), 'admin'::app_role)
  OR has_role(auth.uid(), 'superadmin'::app_role)
);

-- Явный запрет UPDATE и DELETE для всех
CREATE POLICY "Nobody can update admin actions"
ON admin_actions FOR UPDATE
TO authenticated
USING (false);

CREATE POLICY "Nobody can delete admin actions"
ON admin_actions FOR DELETE
TO authenticated
USING (false);

-- То же самое для admin_audit
DROP POLICY IF EXISTS "Admins can insert audit" ON admin_audit;
DROP POLICY IF EXISTS "Admins can view audit" ON admin_audit;

CREATE POLICY "Admins insert own audit"
ON admin_audit FOR INSERT
TO authenticated
WITH CHECK (
  admin_id = auth.uid()
  AND (
    has_role(auth.uid(), 'admin'::app_role)
    OR has_role(auth.uid(), 'superadmin'::app_role)
  )
);

CREATE POLICY "Admins view all audit"
ON admin_audit FOR SELECT
TO authenticated
USING (
  has_role(auth.uid(), 'admin'::app_role)
  OR has_role(auth.uid(), 'superadmin'::app_role)
);

CREATE POLICY "Nobody can update admin audit"
ON admin_audit FOR UPDATE
TO authenticated
USING (false);

CREATE POLICY "Nobody can delete admin audit"
ON admin_audit FOR DELETE
TO authenticated
USING (false);

-- 7. REFERRALS: Ограничение доступа к структуре сети
DROP POLICY IF EXISTS "Users can view network" ON referrals;

CREATE POLICY "Users view own referrals"
ON referrals FOR SELECT
TO authenticated
USING (
  referrer_id = auth.uid()
  OR referred_user_id = auth.uid()
  OR has_role(auth.uid(), 'admin'::app_role)
  OR has_role(auth.uid(), 'superadmin'::app_role)
);

-- 8. ACTIVITY_LOG: Ограничение доступа к активности
DROP POLICY IF EXISTS "Users can view network activity" ON activity_log;

CREATE POLICY "Users view own activity"
ON activity_log FOR SELECT
TO authenticated
USING (
  user_id = auth.uid()
  OR has_role(auth.uid(), 'admin'::app_role)
  OR has_role(auth.uid(), 'superadmin'::app_role)
);

-- 9. SUBSCRIPTIONS: Защита данных о подписках
DROP POLICY IF EXISTS "Users manage own subscriptions" ON subscriptions;

CREATE POLICY "Users view own subscriptions"
ON subscriptions FOR SELECT
TO authenticated
USING (
  user_id = auth.uid()
  OR has_role(auth.uid(), 'admin'::app_role)
  OR has_role(auth.uid(), 'superadmin'::app_role)
);

CREATE POLICY "Users create own subscriptions"
ON subscriptions FOR INSERT
TO authenticated
WITH CHECK (user_id = auth.uid());

CREATE POLICY "Admins update subscriptions"
ON subscriptions FOR UPDATE
TO authenticated
USING (
  has_role(auth.uid(), 'admin'::app_role)
  OR has_role(auth.uid(), 'superadmin'::app_role)
);