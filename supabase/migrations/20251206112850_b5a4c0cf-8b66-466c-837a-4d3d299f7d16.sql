-- 1. Migrate existing Structure 1 referrals to Structure 2
INSERT INTO referrals (referrer_id, referred_user_id, structure_type, created_at)
SELECT referrer_id, referred_user_id, 2, created_at
FROM referrals
WHERE structure_type = 1
ON CONFLICT (referred_user_id, structure_type) DO NOTHING;

-- 2. Update bind_referral function to create entries in BOTH structures
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

-- 3. Update admin_bind_sponsor to also create entries in both structures
CREATE OR REPLACE FUNCTION public.admin_bind_sponsor(p_user_id uuid, p_sponsor_referral_code text, p_admin_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_sponsor_id UUID;
  v_existing_sponsor UUID;
  v_sponsor_name TEXT;
BEGIN
  -- Check admin role
  IF NOT (has_role(p_admin_id, 'admin'::app_role) OR has_role(p_admin_id, 'superadmin'::app_role)) THEN
    RETURN jsonb_build_object('success', false, 'error', 'UNAUTHORIZED');
  END IF;

  -- Find sponsor by referral code
  SELECT id, full_name INTO v_sponsor_id, v_sponsor_name
  FROM profiles
  WHERE referral_code = TRIM(p_sponsor_referral_code);

  IF v_sponsor_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'SPONSOR_NOT_FOUND');
  END IF;

  -- Check if user is trying to refer themselves
  IF v_sponsor_id = p_user_id THEN
    RETURN jsonb_build_object('success', false, 'error', 'SELF_REFERRAL');
  END IF;

  -- Check existing sponsor
  SELECT sponsor_id INTO v_existing_sponsor
  FROM profiles
  WHERE id = p_user_id;

  IF v_existing_sponsor IS NOT NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'ALREADY_HAS_SPONSOR');
  END IF;

  -- Update sponsor_id in profiles
  UPDATE profiles
  SET 
    sponsor_id = v_sponsor_id,
    referrer_snapshot = jsonb_build_object(
      'id', v_sponsor_id,
      'full_name', v_sponsor_name
    ),
    updated_at = NOW()
  WHERE id = p_user_id;

  -- Create referral records for BOTH structures (S1 and S2)
  INSERT INTO referrals (referrer_id, referred_user_id, structure_type)
  VALUES 
    (v_sponsor_id, p_user_id, 1),  -- Structure 1 (subscriptions)
    (v_sponsor_id, p_user_id, 2)   -- Structure 2 (orders)
  ON CONFLICT (referred_user_id, structure_type) DO NOTHING;

  -- Log admin action
  INSERT INTO admin_actions (admin_id, action_type, target_type, target_id, metadata)
  VALUES (
    p_admin_id,
    'bind_sponsor',
    'user',
    p_user_id,
    jsonb_build_object(
      'sponsor_id', v_sponsor_id,
      'sponsor_name', v_sponsor_name,
      'referral_code', p_sponsor_referral_code
    )
  );

  RETURN jsonb_build_object(
    'success', true, 
    'sponsor_name', v_sponsor_name,
    'sponsor_id', v_sponsor_id
  );
END;
$function$;

-- 4. Update upsert_referral_on_sponsor_update trigger to create entries in both structures
CREATE OR REPLACE FUNCTION public.upsert_referral_on_sponsor_update()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_sponsor_name text;
  v_sponsor_email text;
BEGIN
  IF NEW.sponsor_id IS NOT NULL AND (OLD.sponsor_id IS NULL OR OLD.sponsor_id <> NEW.sponsor_id) THEN
    -- Ensure referrals rows for BOTH structures exist
    INSERT INTO public.referrals (referrer_id, referred_user_id, structure_type)
    VALUES 
      (NEW.sponsor_id, NEW.id, 1),  -- Structure 1
      (NEW.sponsor_id, NEW.id, 2)   -- Structure 2
    ON CONFLICT (referred_user_id, structure_type) DO NOTHING;

    -- Update snapshot on the profile to lock inviter info
    SELECT p.full_name, p.email
      INTO v_sponsor_name, v_sponsor_email
    FROM public.profiles p
    WHERE p.id = NEW.sponsor_id;

    NEW.referrer_snapshot := jsonb_build_object(
      'id', NEW.sponsor_id,
      'full_name', v_sponsor_name,
      'email', v_sponsor_email
    );

    -- Keep direct_referrals_count in sync (idempotent)
    UPDATE public.profiles sp
    SET direct_referrals_count = (
      SELECT COUNT(*) FROM public.profiles WHERE sponsor_id = NEW.sponsor_id
    ),
    updated_at = NOW()
    WHERE sp.id = NEW.sponsor_id;
  END IF;
  RETURN NEW;
END;
$function$;

-- 5. Update handle_referral_registration trigger to create entries in both structures
CREATE OR REPLACE FUNCTION public.handle_referral_registration()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  -- Get referrer from sponsor_id if set
  IF NEW.sponsor_id IS NOT NULL THEN
    -- Insert referrals for BOTH structures
    INSERT INTO public.referrals (
      referrer_id,
      referred_user_id,
      structure_type
    ) VALUES 
      (NEW.sponsor_id, NEW.id, 1),  -- Structure 1 (subscriptions)
      (NEW.sponsor_id, NEW.id, 2)   -- Structure 2 (orders)
    ON CONFLICT (referred_user_id, structure_type) DO NOTHING;
  END IF;
  
  RETURN NEW;
END;
$function$;

-- 6. Remove the handle_activation_structure function as S2 is now mirrored from S1
DROP FUNCTION IF EXISTS public.handle_activation_structure() CASCADE;

-- 7. Drop trigger if exists
DROP TRIGGER IF EXISTS on_order_check_activation_structure ON public.orders;