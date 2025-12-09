-- ============================================
-- 1. СРОЧНОЕ ИСПРАВЛЕНИЕ: Восстановить аккаунт MG-MARKET
-- ============================================

-- Удалить ошибочные записи в referrals где MG-MARKET указан как referred_user_id
DELETE FROM public.referrals 
WHERE referred_user_id = 'b1120d61-d942-4e7d-a0c9-90708aa5cd3f';

-- Сбросить sponsor_id у MG-MARKET (он должен быть корневым аккаунтом без спонсора)
UPDATE public.profiles 
SET 
  sponsor_id = NULL,
  referrer_snapshot = NULL,
  updated_at = NOW()
WHERE id = 'b1120d61-d942-4e7d-a0c9-90708aa5cd3f';

-- Записать в activity_log факт восстановления
INSERT INTO public.activity_log (user_id, type, payload)
VALUES (
  'b1120d61-d942-4e7d-a0c9-90708aa5cd3f',
  'account_restored',
  jsonb_build_object(
    'reason', 'Удалена ошибочная привязка к спонсору',
    'restored_at', NOW(),
    'previous_sponsor_id', '0fbb8788-b84a-4c9a-850b-f24b0757c840'
  )
);

-- ============================================
-- 2. ЗАЩИТА: Обновить функцию bind_referral
-- ============================================

CREATE OR REPLACE FUNCTION public.bind_referral(p_ref_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
  v_referrer profiles%ROWTYPE;
  v_existing_sponsor uuid;
  v_user_created_at timestamptz;
  v_result jsonb;
BEGIN
  -- Validation: user must be authenticated
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'unauthenticated');
  END IF;

  -- Validation: referral code must not be empty
  IF p_ref_code IS NULL OR length(trim(p_ref_code)) = 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'empty_code');
  END IF;

  -- Get current user's created_at for validation
  SELECT created_at INTO v_user_created_at
  FROM public.profiles
  WHERE id = v_user_id;

  -- Find referrer by referral code (case-insensitive, trimmed)
  SELECT p.* INTO v_referrer
  FROM public.profiles p
  WHERE LOWER(p.referral_code) = LOWER(trim(p_ref_code))
    AND p.is_active = true
    AND (p.deleted_at IS NULL)
    AND (p.is_archived IS NULL OR p.is_archived = false);

  -- Check if referrer exists
  IF v_referrer.id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'invalid_code');
  END IF;

  -- Prevent self-referral
  IF v_referrer.id = v_user_id THEN
    RETURN jsonb_build_object('success', false, 'error', 'self_referral');
  END IF;

  -- ============================================
  -- NEW PROTECTION 1: User is already a sponsor for others
  -- ============================================
  IF EXISTS (SELECT 1 FROM public.referrals WHERE referrer_id = v_user_id LIMIT 1) THEN
    RETURN jsonb_build_object('success', false, 'error', 'already_sponsor', 
      'message', 'Вы уже являетесь спонсором для других пользователей');
  END IF;

  -- ============================================
  -- NEW PROTECTION 2: Sponsor must be registered BEFORE the user
  -- ============================================
  IF v_referrer.created_at > v_user_created_at THEN
    RETURN jsonb_build_object('success', false, 'error', 'sponsor_registered_later',
      'message', 'Спонсор был зарегистрирован позже вас');
  END IF;

  -- Check if user already has a sponsor
  SELECT sponsor_id INTO v_existing_sponsor
  FROM public.profiles
  WHERE id = v_user_id;

  -- If already has different sponsor, return error
  IF v_existing_sponsor IS NOT NULL AND v_existing_sponsor != v_referrer.id THEN
    RETURN jsonb_build_object('success', false, 'error', 'already_has_sponsor');
  END IF;

  -- If already bound to this sponsor, return success
  IF v_existing_sponsor = v_referrer.id THEN
    RETURN jsonb_build_object('success', true, 'message', 'already_bound', 'sponsor_name', v_referrer.full_name);
  END IF;

  -- Update sponsor_id and referrer snapshot
  UPDATE public.profiles
  SET 
    sponsor_id = v_referrer.id,
    referrer_snapshot = jsonb_build_object(
      'id', v_referrer.id,
      'full_name', v_referrer.full_name,
      'email', v_referrer.email,
      'referral_code', v_referrer.referral_code
    ),
    updated_at = now()
  WHERE id = v_user_id;

  -- Create referral records for BOTH structures (S1 and S2)
  INSERT INTO public.referrals (referrer_id, referred_user_id, structure_type)
  VALUES 
    (v_referrer.id, v_user_id, 1),  -- Structure 1 (subscriptions)
    (v_referrer.id, v_user_id, 2)   -- Structure 2 (orders)
  ON CONFLICT (referred_user_id, structure_type) DO NOTHING;

  -- Log activity
  INSERT INTO public.activity_log (user_id, type, payload)
  VALUES (
    v_user_id,
    'referral_bound',
    jsonb_build_object(
      'sponsor_id', v_referrer.id,
      'sponsor_name', v_referrer.full_name,
      'referral_code', p_ref_code
    )
  );

  RETURN jsonb_build_object('success', true, 'sponsor_name', v_referrer.full_name);
END;
$function$;

-- ============================================
-- 3. Также обновить admin_bind_sponsor с теми же защитами
-- ============================================

CREATE OR REPLACE FUNCTION public.admin_bind_sponsor(p_user_id uuid, p_sponsor_referral_code text, p_admin_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_sponsor_id uuid;
  v_sponsor_name text;
  v_existing_sponsor uuid;
  v_user_created_at timestamptz;
  v_sponsor_created_at timestamptz;
BEGIN
  -- Check admin role
  IF NOT (has_role(p_admin_id, 'admin'::app_role) OR has_role(p_admin_id, 'superadmin'::app_role)) THEN
    RETURN jsonb_build_object('success', false, 'error', 'UNAUTHORIZED');
  END IF;

  -- Get user's creation date
  SELECT created_at INTO v_user_created_at
  FROM public.profiles WHERE id = p_user_id;

  -- Find sponsor by referral code
  SELECT id, full_name, created_at INTO v_sponsor_id, v_sponsor_name, v_sponsor_created_at
  FROM public.profiles
  WHERE LOWER(referral_code) = LOWER(TRIM(p_sponsor_referral_code))
    AND is_active = true
    AND (deleted_at IS NULL)
    AND (is_archived IS NULL OR is_archived = false);

  IF v_sponsor_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'SPONSOR_NOT_FOUND');
  END IF;

  -- Prevent self-referral
  IF v_sponsor_id = p_user_id THEN
    RETURN jsonb_build_object('success', false, 'error', 'SELF_REFERRAL');
  END IF;

  -- Check if user already has a sponsor
  SELECT sponsor_id INTO v_existing_sponsor
  FROM public.profiles WHERE id = p_user_id;

  IF v_existing_sponsor IS NOT NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'ALREADY_HAS_SPONSOR');
  END IF;

  -- NEW PROTECTION: User is already a sponsor for others
  IF EXISTS (SELECT 1 FROM public.referrals WHERE referrer_id = p_user_id LIMIT 1) THEN
    RETURN jsonb_build_object('success', false, 'error', 'USER_IS_SPONSOR',
      'message', 'Пользователь уже является спонсором для других');
  END IF;

  -- NEW PROTECTION: Sponsor must be registered BEFORE the user
  IF v_sponsor_created_at > v_user_created_at THEN
    RETURN jsonb_build_object('success', false, 'error', 'SPONSOR_REGISTERED_LATER',
      'message', 'Спонсор был зарегистрирован позже пользователя');
  END IF;

  -- Update sponsor_id
  UPDATE public.profiles
  SET 
    sponsor_id = v_sponsor_id,
    referrer_snapshot = jsonb_build_object(
      'id', v_sponsor_id,
      'full_name', v_sponsor_name
    ),
    updated_at = NOW()
  WHERE id = p_user_id;

  -- Create referral records
  INSERT INTO public.referrals (referrer_id, referred_user_id, structure_type)
  VALUES 
    (v_sponsor_id, p_user_id, 1),
    (v_sponsor_id, p_user_id, 2)
  ON CONFLICT (referred_user_id, structure_type) DO NOTHING;

  -- Log admin action
  INSERT INTO public.admin_actions (admin_id, action_type, target_type, target_id, metadata)
  VALUES (
    p_admin_id,
    'bind_sponsor',
    'user',
    p_user_id,
    jsonb_build_object('sponsor_id', v_sponsor_id, 'sponsor_name', v_sponsor_name)
  );

  RETURN jsonb_build_object('success', true, 'sponsor_name', v_sponsor_name);
END;
$function$;