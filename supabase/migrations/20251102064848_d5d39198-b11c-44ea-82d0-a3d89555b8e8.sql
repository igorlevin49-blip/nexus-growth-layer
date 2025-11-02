-- Fix remaining functions to have SET search_path = public

-- Update bind_referral function
CREATE OR REPLACE FUNCTION public.bind_referral(p_ref_code text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_referrer profiles%ROWTYPE;
  v_existing_sponsor uuid;
  v_result jsonb;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'unauthenticated');
  END IF;

  IF p_ref_code IS NULL OR length(trim(p_ref_code)) = 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'empty_code');
  END IF;

  -- Find referrer by referral code
  SELECT p.* INTO v_referrer
  FROM public.profiles p
  WHERE p.referral_code = trim(p_ref_code);

  IF v_referrer.id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'invalid_code');
  END IF;

  IF v_referrer.id = v_user_id THEN
    RETURN jsonb_build_object('success', false, 'error', 'self_referral');
  END IF;

  -- Check existing sponsor
  SELECT sponsor_id INTO v_existing_sponsor
  FROM public.profiles
  WHERE id = v_user_id;

  IF v_existing_sponsor IS NOT NULL AND v_existing_sponsor != v_referrer.id THEN
    RETURN jsonb_build_object('success', false, 'error', 'already_has_sponsor');
  END IF;

  IF v_existing_sponsor = v_referrer.id THEN
    RETURN jsonb_build_object('success', true, 'message', 'already_bound');
  END IF;

  -- Update sponsor
  UPDATE public.profiles
  SET sponsor_id = v_referrer.id,
      referrer_snapshot = jsonb_build_object(
        'id', v_referrer.id,
        'full_name', v_referrer.full_name,
        'email', v_referrer.email
      ),
      updated_at = now()
  WHERE id = v_user_id;

  -- Create referral record
  INSERT INTO public.referrals (referrer_id, referred_user_id, structure_type)
  VALUES (v_referrer.id, v_user_id, 1)
  ON CONFLICT (referred_user_id, structure_type) DO NOTHING;

  RETURN jsonb_build_object('success', true, 'sponsor_name', v_referrer.full_name);
END;
$$;

-- Update cleanup_all_test_users function
CREATE OR REPLACE FUNCTION public.cleanup_all_test_users(
  p_admin_id UUID,
  p_confirmation_phrase TEXT,
  p_dry_run BOOLEAN DEFAULT TRUE
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_count INT;
  v_deleted_users UUID[];
BEGIN
  -- Check if user is superadmin
  IF NOT has_role(p_admin_id, 'superadmin'::app_role) THEN
    RAISE EXCEPTION 'Only superadmin can cleanup all test users';
  END IF;

  -- Verify confirmation phrase
  IF NOT p_dry_run AND p_confirmation_phrase != 'УДАЛИТЬ ВСЕ ТЕСТОВЫЕ АККАУНТЫ' THEN
    RAISE EXCEPTION 'Invalid confirmation phrase';
  END IF;

  -- Find all test users (not egor.smart@mail.ru and not mg-market001@mail.ru)
  SELECT array_agg(id) INTO v_deleted_users
  FROM profiles
  WHERE email NOT IN ('egor.smart@mail.ru', 'mg-market001@mail.ru')
    AND is_active = true;

  v_user_count := COALESCE(array_length(v_deleted_users, 1), 0);

  -- If dry run, return preview
  IF p_dry_run THEN
    RETURN jsonb_build_object(
      'success', true,
      'dry_run', true,
      'users_to_delete', v_user_count,
      'message', 'Будет удалено ' || v_user_count || ' тестовых пользователей'
    );
  END IF;

  -- Perform deletion
  IF v_user_count > 0 THEN
    -- Delete related data in correct order
    DELETE FROM transactions WHERE user_id = ANY(v_deleted_users);
    DELETE FROM withdrawals WHERE user_id = ANY(v_deleted_users);
    DELETE FROM activity_log WHERE user_id = ANY(v_deleted_users);
    DELETE FROM order_items WHERE order_id IN (SELECT id FROM orders WHERE user_id = ANY(v_deleted_users));
    DELETE FROM orders WHERE user_id = ANY(v_deleted_users);
    DELETE FROM subscriptions WHERE user_id = ANY(v_deleted_users);
    DELETE FROM referrals WHERE referrer_id = ANY(v_deleted_users) OR referred_user_id = ANY(v_deleted_users);
    DELETE FROM payment_methods WHERE user_id = ANY(v_deleted_users);
    DELETE FROM auto_withdraw_rules WHERE user_id = ANY(v_deleted_users);
    DELETE FROM notification_settings WHERE user_id = ANY(v_deleted_users);
    DELETE FROM security_events WHERE user_id = ANY(v_deleted_users);
    DELETE FROM user_consents WHERE user_id = ANY(v_deleted_users);
    DELETE FROM user_roles WHERE user_id = ANY(v_deleted_users);
    DELETE FROM profiles WHERE id = ANY(v_deleted_users);

    -- Recalculate referral counts for remaining users
    UPDATE profiles
    SET direct_referrals_count = (
      SELECT COUNT(*) FROM referrals
      WHERE referrer_id = profiles.id AND structure_type = 1
    )
    WHERE email IN ('egor.smart@mail.ru', 'mg-market001@mail.ru');

    -- Log admin action
    INSERT INTO admin_actions (admin_id, action_type, target_type, metadata)
    VALUES (
      p_admin_id,
      'cleanup_all_test_users',
      'system',
      jsonb_build_object(
        'users_deleted', v_user_count,
        'confirmation', p_confirmation_phrase
      )
    );
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'dry_run', false,
    'users_deleted', v_user_count,
    'message', 'Удалено ' || v_user_count || ' тестовых пользователей'
  );
END;
$$;

-- Update create_subscription_with_s1_bonus function  
CREATE OR REPLACE FUNCTION public.create_subscription_with_s1_bonus()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sponsor_id UUID;
  v_bonus_amount_cents BIGINT;
  v_existing_txn UUID;
  v_freeze_days INTEGER := 7;
BEGIN
  -- Only process when subscription becomes active
  IF NEW.status = 'active' AND (OLD.status IS NULL OR OLD.status != 'active') THEN
    -- Get user's sponsor
    SELECT sponsor_id INTO v_sponsor_id
    FROM profiles
    WHERE id = NEW.user_id;
    
    IF v_sponsor_id IS NOT NULL THEN
      -- Calculate 10% bonus (from subscription amount in cents)
      v_bonus_amount_cents := (NEW.amount_usd * 100 * 0.10)::BIGINT;
      
      -- Check if bonus already exists (idempotency)
      SELECT id INTO v_existing_txn
      FROM transactions
      WHERE source_ref = 'subscription_s1_bonus_' || NEW.id::TEXT
      LIMIT 1;
      
      -- Create bonus transaction if not exists
      IF v_existing_txn IS NULL THEN
        INSERT INTO transactions (
          user_id,
          type,
          amount_cents,
          status,
          source_id,
          source_ref,
          level,
          structure_type,
          frozen_until,
          payload
        ) VALUES (
          v_sponsor_id,
          'bonus',
          v_bonus_amount_cents,
          'completed',
          NEW.id,
          'subscription_s1_bonus_' || NEW.id::TEXT,
          1,
          'primary',
          NOW() + (v_freeze_days || ' days')::INTERVAL,
          jsonb_build_object(
            'subscription_id', NEW.id,
            'user_id', NEW.user_id,
            'amount_usd', NEW.amount_usd,
            'bonus_type', 's1_subscription',
            'bonus_percent', 10
          )
        );
      END IF;
    END IF;
  END IF;
  
  RETURN NEW;
END;
$$;

-- Create trigger if not exists
DROP TRIGGER IF EXISTS trigger_subscription_s1_bonus ON subscriptions;
CREATE TRIGGER trigger_subscription_s1_bonus
  AFTER INSERT OR UPDATE ON subscriptions
  FOR EACH ROW
  EXECUTE FUNCTION create_subscription_with_s1_bonus();