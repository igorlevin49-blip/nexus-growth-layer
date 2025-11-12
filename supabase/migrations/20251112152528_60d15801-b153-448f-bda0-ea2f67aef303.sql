
-- Улучшенная функция bind_referral с проверкой URL параметров и лучшей обработкой ошибок
CREATE OR REPLACE FUNCTION public.bind_referral(p_ref_code text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_referrer profiles%ROWTYPE;
  v_existing_sponsor uuid;
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

  -- Create referral record for structure 1 (primary)
  INSERT INTO public.referrals (referrer_id, referred_user_id, structure_type)
  VALUES (v_referrer.id, v_user_id, 1)
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
$$;

COMMENT ON FUNCTION public.bind_referral IS 'Binds a referral sponsor to the current authenticated user with improved validation';
