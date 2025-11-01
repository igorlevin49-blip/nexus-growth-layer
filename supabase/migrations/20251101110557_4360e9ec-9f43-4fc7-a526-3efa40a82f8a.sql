-- Add soft delete and active status to profiles
ALTER TABLE profiles 
ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMP WITH TIME ZONE,
ADD COLUMN IF NOT EXISTS is_active BOOLEAN DEFAULT true NOT NULL;

-- Create indexes for active users lookup
CREATE INDEX IF NOT EXISTS idx_profiles_active ON profiles(is_active) WHERE is_active = true;
CREATE INDEX IF NOT EXISTS idx_profiles_deleted ON profiles(deleted_at) WHERE deleted_at IS NOT NULL;

-- Update RLS policy to prevent deleted users from accessing data
DROP POLICY IF EXISTS "Users can view their own profile" ON profiles;
CREATE POLICY "Users can view their own profile"
ON profiles FOR SELECT
USING (
  auth.uid() = id 
  AND is_active = true 
  AND deleted_at IS NULL
);

-- Function to soft delete user
CREATE OR REPLACE FUNCTION soft_delete_user(p_user_id UUID, p_admin_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT (has_role(p_admin_id, 'admin'::app_role) OR has_role(p_admin_id, 'superadmin'::app_role)) THEN
    RETURN jsonb_build_object('success', false, 'error', 'UNAUTHORIZED');
  END IF;

  UPDATE profiles 
  SET 
    is_active = false,
    deleted_at = NOW(),
    updated_at = NOW()
  WHERE id = p_user_id;

  INSERT INTO admin_actions (admin_id, action_type, target_type, target_id, metadata)
  VALUES (
    p_admin_id,
    'soft_delete_user',
    'user',
    p_user_id,
    jsonb_build_object('deleted_at', NOW())
  );

  RETURN jsonb_build_object('success', true);
END;
$$;

-- Function to restore user
CREATE OR REPLACE FUNCTION restore_user(p_user_id UUID, p_admin_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT (has_role(p_admin_id, 'admin'::app_role) OR has_role(p_admin_id, 'superadmin'::app_role)) THEN
    RETURN jsonb_build_object('success', false, 'error', 'UNAUTHORIZED');
  END IF;

  UPDATE profiles 
  SET 
    is_active = true,
    deleted_at = NULL,
    updated_at = NOW()
  WHERE id = p_user_id;

  INSERT INTO admin_actions (admin_id, action_type, target_type, target_id, metadata)
  VALUES (
    p_admin_id,
    'restore_user',
    'user',
    p_user_id,
    jsonb_build_object('restored_at', NOW())
  );

  RETURN jsonb_build_object('success', true);
END;
$$;

-- Function to cleanup test data (keep only superadmin)
CREATE OR REPLACE FUNCTION cleanup_test_data(
  p_superadmin_email TEXT,
  p_admin_id UUID,
  p_confirmation_phrase TEXT,
  p_dry_run BOOLEAN DEFAULT true
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_superadmin_id UUID;
  v_users_count INT;
  v_orders_count INT;
  v_subscriptions_count INT;
  v_transactions_count INT;
  v_withdrawals_count INT;
  v_referrals_count INT;
  v_activity_count INT;
BEGIN
  IF NOT has_role(p_admin_id, 'superadmin'::app_role) THEN
    RAISE EXCEPTION 'Only superadmin can cleanup test data';
  END IF;

  IF NOT p_dry_run AND p_confirmation_phrase != 'ОЧИСТИТЬ ТЕСТОВЫЕ ДАННЫЕ' THEN
    RAISE EXCEPTION 'Invalid confirmation phrase';
  END IF;

  SELECT id INTO v_superadmin_id FROM profiles WHERE email = p_superadmin_email;
  
  IF v_superadmin_id IS NULL THEN
    RAISE EXCEPTION 'Superadmin user not found: %', p_superadmin_email;
  END IF;

  SELECT COUNT(*) INTO v_users_count FROM profiles WHERE id != v_superadmin_id AND is_active = true;
  SELECT COUNT(*) INTO v_orders_count FROM orders WHERE user_id != v_superadmin_id;
  SELECT COUNT(*) INTO v_subscriptions_count FROM subscriptions WHERE user_id != v_superadmin_id;
  SELECT COUNT(*) INTO v_transactions_count FROM transactions WHERE user_id != v_superadmin_id;
  SELECT COUNT(*) INTO v_withdrawals_count FROM withdrawals WHERE user_id != v_superadmin_id;
  SELECT COUNT(*) INTO v_referrals_count FROM referrals WHERE referrer_id != v_superadmin_id AND referred_user_id != v_superadmin_id;
  SELECT COUNT(*) INTO v_activity_count FROM activity_log WHERE user_id != v_superadmin_id;

  IF NOT p_dry_run THEN
    DELETE FROM transactions WHERE user_id != v_superadmin_id;
    DELETE FROM withdrawals WHERE user_id != v_superadmin_id;
    DELETE FROM activity_log WHERE user_id != v_superadmin_id;
    DELETE FROM order_items WHERE order_id IN (SELECT id FROM orders WHERE user_id != v_superadmin_id);
    DELETE FROM orders WHERE user_id != v_superadmin_id;
    DELETE FROM subscriptions WHERE user_id != v_superadmin_id;
    DELETE FROM referrals WHERE referrer_id != v_superadmin_id AND referred_user_id != v_superadmin_id;
    DELETE FROM payment_methods WHERE user_id != v_superadmin_id;
    DELETE FROM auto_withdraw_rules WHERE user_id != v_superadmin_id;
    DELETE FROM notification_settings WHERE user_id != v_superadmin_id;
    DELETE FROM security_events WHERE user_id != v_superadmin_id;
    DELETE FROM user_consents WHERE user_id != v_superadmin_id;
    
    UPDATE profiles 
    SET is_active = false, deleted_at = NOW(), updated_at = NOW()
    WHERE id != v_superadmin_id AND is_active = true;
    
    DELETE FROM user_roles WHERE user_id != v_superadmin_id;

    INSERT INTO admin_actions (admin_id, action_type, target_type, metadata)
    VALUES (
      p_admin_id,
      'cleanup_test_data',
      'system',
      jsonb_build_object(
        'superadmin_email', p_superadmin_email,
        'users_deleted', v_users_count,
        'orders_deleted', v_orders_count,
        'subscriptions_deleted', v_subscriptions_count,
        'transactions_deleted', v_transactions_count,
        'withdrawals_deleted', v_withdrawals_count,
        'referrals_deleted', v_referrals_count,
        'activity_deleted', v_activity_count
      )
    );
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'dry_run', p_dry_run,
    'superadmin_id', v_superadmin_id,
    'users', v_users_count,
    'orders', v_orders_count,
    'subscriptions', v_subscriptions_count,
    'transactions', v_transactions_count,
    'withdrawals', v_withdrawals_count,
    'referrals', v_referrals_count,
    'activity', v_activity_count
  );
END;
$$;