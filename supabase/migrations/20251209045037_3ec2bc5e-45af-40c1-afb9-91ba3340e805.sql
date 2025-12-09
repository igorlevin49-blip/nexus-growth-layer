
-- Update bind_referral function to log all attempts (successful and failed)
CREATE OR REPLACE FUNCTION public.bind_referral(p_ref_code text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID;
  v_referrer RECORD;
  v_user_created_at TIMESTAMPTZ;
  v_existing_sponsor_id UUID;
  v_log_payload JSONB;
BEGIN
  v_user_id := auth.uid();
  
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'not_authenticated');
  END IF;

  -- Get user info
  SELECT sponsor_id, created_at INTO v_existing_sponsor_id, v_user_created_at
  FROM public.profiles WHERE id = v_user_id;

  -- Check if already has sponsor
  IF v_existing_sponsor_id IS NOT NULL THEN
    -- Log failed attempt
    INSERT INTO public.activity_log (user_id, type, payload)
    VALUES (v_user_id, 'referral_bind_failed', jsonb_build_object(
      'reason', 'already_bound',
      'attempted_code', p_ref_code,
      'existing_sponsor_id', v_existing_sponsor_id
    ));
    
    RETURN jsonb_build_object('success', false, 'error', 'already_bound');
  END IF;

  -- NEW CHECK: User is already a sponsor for others
  IF EXISTS (SELECT 1 FROM public.referrals WHERE referrer_id = v_user_id LIMIT 1) THEN
    -- Log failed attempt
    INSERT INTO public.activity_log (user_id, type, payload)
    VALUES (v_user_id, 'referral_bind_failed', jsonb_build_object(
      'reason', 'already_sponsor',
      'attempted_code', p_ref_code,
      'message', 'User already has referrals and cannot be bound to a sponsor'
    ));
    
    RETURN jsonb_build_object('success', false, 'error', 'already_sponsor');
  END IF;

  -- Find referrer
  SELECT id, full_name, email, created_at INTO v_referrer
  FROM public.profiles
  WHERE referral_code = TRIM(p_ref_code)
    AND is_active = true
    AND (deleted_at IS NULL)
    AND (is_archived IS NULL OR is_archived = false);

  IF v_referrer.id IS NULL THEN
    -- Log failed attempt
    INSERT INTO public.activity_log (user_id, type, payload)
    VALUES (v_user_id, 'referral_bind_failed', jsonb_build_object(
      'reason', 'invalid_code',
      'attempted_code', p_ref_code
    ));
    
    RETURN jsonb_build_object('success', false, 'error', 'invalid_code');
  END IF;

  -- Self-referral check
  IF v_referrer.id = v_user_id THEN
    -- Log failed attempt
    INSERT INTO public.activity_log (user_id, type, payload)
    VALUES (v_user_id, 'referral_bind_failed', jsonb_build_object(
      'reason', 'self_referral',
      'attempted_code', p_ref_code
    ));
    
    RETURN jsonb_build_object('success', false, 'error', 'self_referral');
  END IF;

  -- NEW CHECK: Sponsor must be registered BEFORE the user
  IF v_referrer.created_at > v_user_created_at THEN
    -- Log failed attempt with details
    INSERT INTO public.activity_log (user_id, type, payload)
    VALUES (v_user_id, 'referral_bind_failed', jsonb_build_object(
      'reason', 'sponsor_registered_later',
      'attempted_code', p_ref_code,
      'attempted_sponsor_id', v_referrer.id,
      'attempted_sponsor_name', v_referrer.full_name,
      'user_created_at', v_user_created_at,
      'sponsor_created_at', v_referrer.created_at,
      'message', 'Attempted to bind to a sponsor registered after the user - possible fraud'
    ));
    
    RETURN jsonb_build_object('success', false, 'error', 'sponsor_registered_later');
  END IF;

  -- Update profile
  UPDATE public.profiles
  SET 
    sponsor_id = v_referrer.id,
    referrer_snapshot = jsonb_build_object(
      'id', v_referrer.id,
      'full_name', v_referrer.full_name,
      'email', v_referrer.email
    ),
    updated_at = NOW()
  WHERE id = v_user_id;

  -- Create referral record
  INSERT INTO public.referrals (referrer_id, referred_user_id, structure_type)
  VALUES (v_referrer.id, v_user_id, 1)
  ON CONFLICT (referred_user_id, structure_type) DO NOTHING;

  -- Update sponsor's direct referrals count
  UPDATE public.profiles
  SET direct_referrals_count = (
    SELECT COUNT(*) FROM public.profiles WHERE sponsor_id = v_referrer.id
  )
  WHERE id = v_referrer.id;

  -- Log SUCCESSFUL binding
  INSERT INTO public.activity_log (user_id, type, payload)
  VALUES (v_user_id, 'referral_bound', jsonb_build_object(
    'success', true,
    'sponsor_id', v_referrer.id,
    'sponsor_name', v_referrer.full_name,
    'referral_code', p_ref_code
  ));

  RETURN jsonb_build_object(
    'success', true,
    'sponsor_id', v_referrer.id,
    'sponsor_name', v_referrer.full_name
  );
END;
$function$;

-- Also update admin_bind_sponsor to log all attempts
CREATE OR REPLACE FUNCTION public.admin_bind_sponsor(
  p_user_id UUID,
  p_sponsor_referral_code TEXT,
  p_admin_id UUID
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_sponsor RECORD;
  v_user RECORD;
  v_log_payload JSONB;
BEGIN
  -- Check admin role
  IF NOT (has_role(p_admin_id, 'admin'::app_role) OR has_role(p_admin_id, 'superadmin'::app_role)) THEN
    RETURN jsonb_build_object('success', false, 'error', 'UNAUTHORIZED');
  END IF;

  -- Get user info
  SELECT id, full_name, sponsor_id, created_at INTO v_user
  FROM public.profiles WHERE id = p_user_id;

  IF v_user.id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'USER_NOT_FOUND');
  END IF;

  -- Find sponsor by referral code
  SELECT id, full_name, email, created_at INTO v_sponsor
  FROM public.profiles
  WHERE referral_code = TRIM(p_sponsor_referral_code)
    AND is_active = true
    AND (deleted_at IS NULL);

  IF v_sponsor.id IS NULL THEN
    -- Log failed attempt
    INSERT INTO public.activity_log (user_id, type, payload)
    VALUES (p_user_id, 'admin_bind_sponsor_failed', jsonb_build_object(
      'reason', 'SPONSOR_NOT_FOUND',
      'attempted_code', p_sponsor_referral_code,
      'admin_id', p_admin_id
    ));
    
    RETURN jsonb_build_object('success', false, 'error', 'SPONSOR_NOT_FOUND');
  END IF;

  -- Self-referral check
  IF v_sponsor.id = p_user_id THEN
    INSERT INTO public.activity_log (user_id, type, payload)
    VALUES (p_user_id, 'admin_bind_sponsor_failed', jsonb_build_object(
      'reason', 'SELF_REFERRAL',
      'attempted_code', p_sponsor_referral_code,
      'admin_id', p_admin_id
    ));
    
    RETURN jsonb_build_object('success', false, 'error', 'SELF_REFERRAL');
  END IF;

  -- Check if already has sponsor
  IF v_user.sponsor_id IS NOT NULL THEN
    INSERT INTO public.activity_log (user_id, type, payload)
    VALUES (p_user_id, 'admin_bind_sponsor_failed', jsonb_build_object(
      'reason', 'ALREADY_HAS_SPONSOR',
      'attempted_code', p_sponsor_referral_code,
      'existing_sponsor_id', v_user.sponsor_id,
      'admin_id', p_admin_id
    ));
    
    RETURN jsonb_build_object('success', false, 'error', 'ALREADY_HAS_SPONSOR');
  END IF;

  -- NEW CHECK: User is already a sponsor for others
  IF EXISTS (SELECT 1 FROM public.referrals WHERE referrer_id = p_user_id LIMIT 1) THEN
    INSERT INTO public.activity_log (user_id, type, payload)
    VALUES (p_user_id, 'admin_bind_sponsor_failed', jsonb_build_object(
      'reason', 'USER_IS_SPONSOR',
      'attempted_code', p_sponsor_referral_code,
      'admin_id', p_admin_id,
      'message', 'User already has referrals and cannot be bound to a sponsor'
    ));
    
    RETURN jsonb_build_object('success', false, 'error', 'USER_IS_SPONSOR');
  END IF;

  -- NEW CHECK: Sponsor must be registered BEFORE the user
  IF v_sponsor.created_at > v_user.created_at THEN
    INSERT INTO public.activity_log (user_id, type, payload)
    VALUES (p_user_id, 'admin_bind_sponsor_failed', jsonb_build_object(
      'reason', 'SPONSOR_REGISTERED_LATER',
      'attempted_code', p_sponsor_referral_code,
      'attempted_sponsor_id', v_sponsor.id,
      'attempted_sponsor_name', v_sponsor.full_name,
      'user_created_at', v_user.created_at,
      'sponsor_created_at', v_sponsor.created_at,
      'admin_id', p_admin_id,
      'message', 'Admin attempted to bind user to a sponsor registered after the user'
    ));
    
    RETURN jsonb_build_object('success', false, 'error', 'SPONSOR_REGISTERED_LATER');
  END IF;

  -- Update profile
  UPDATE public.profiles
  SET 
    sponsor_id = v_sponsor.id,
    referrer_snapshot = jsonb_build_object(
      'id', v_sponsor.id,
      'full_name', v_sponsor.full_name,
      'email', v_sponsor.email
    ),
    updated_at = NOW()
  WHERE id = p_user_id;

  -- Create referral record
  INSERT INTO public.referrals (referrer_id, referred_user_id, structure_type)
  VALUES (v_sponsor.id, p_user_id, 1)
  ON CONFLICT (referred_user_id, structure_type) DO NOTHING;

  -- Update sponsor's direct referrals count
  UPDATE public.profiles
  SET direct_referrals_count = (
    SELECT COUNT(*) FROM public.profiles WHERE sponsor_id = v_sponsor.id
  )
  WHERE id = v_sponsor.id;

  -- Log admin action
  INSERT INTO public.admin_actions (admin_id, action_type, target_type, target_id, metadata)
  VALUES (p_admin_id, 'bind_sponsor', 'user', p_user_id, jsonb_build_object(
    'sponsor_id', v_sponsor.id,
    'sponsor_name', v_sponsor.full_name,
    'referral_code', p_sponsor_referral_code
  ));

  -- Log SUCCESSFUL binding in activity_log
  INSERT INTO public.activity_log (user_id, type, payload)
  VALUES (p_user_id, 'admin_bind_sponsor_success', jsonb_build_object(
    'success', true,
    'sponsor_id', v_sponsor.id,
    'sponsor_name', v_sponsor.full_name,
    'referral_code', p_sponsor_referral_code,
    'admin_id', p_admin_id
  ));

  RETURN jsonb_build_object(
    'success', true,
    'sponsor_id', v_sponsor.id,
    'sponsor_name', v_sponsor.full_name
  );
END;
$function$;
