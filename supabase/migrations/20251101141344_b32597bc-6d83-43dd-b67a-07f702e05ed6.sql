-- Ensure unique relation per referred user per structure
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'uniq_referrals_referred_per_structure'
  ) THEN
    ALTER TABLE public.referrals
      ADD CONSTRAINT uniq_referrals_referred_per_structure UNIQUE (referred_user_id, structure_type);
  END IF;
END $$;

-- Create or replace the referral binding function
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
  WHERE p.referral_code = trim(p_ref_code)
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'invalid_code');
  END IF;

  -- Prevent self-referral
  IF v_referrer.id = v_user_id THEN
    RETURN jsonb_build_object('success', false, 'error', 'self_referral');
  END IF;

  -- Check if already bound
  SELECT sponsor_id INTO v_existing_sponsor
  FROM public.profiles
  WHERE id = v_user_id;

  IF v_existing_sponsor IS NOT NULL THEN
    IF v_existing_sponsor = v_referrer.id THEN
      RETURN jsonb_build_object('success', true, 'message', 'already_bound');
    ELSE
      RETURN jsonb_build_object('success', false, 'error', 'already_has_sponsor');
    END IF;
  END IF;

  -- Perform binding atomically
  PERFORM 1;  -- no-op to keep structure clear
  BEGIN
    -- Update user's profile with sponsor and snapshot
    UPDATE public.profiles
    SET sponsor_id = v_referrer.id,
        referrer_snapshot = jsonb_build_object(
          'id', v_referrer.id,
          'full_name', v_referrer.full_name,
          'email', v_referrer.email,
          'referral_code', v_referrer.referral_code
        ),
        updated_at = now()
    WHERE id = v_user_id
      AND sponsor_id IS NULL;

    -- Insert into referrals table (idempotent)
    INSERT INTO public.referrals (referrer_id, referred_user_id, structure_type)
    VALUES (v_referrer.id, v_user_id, 1)
    ON CONFLICT (referred_user_id, structure_type) DO NOTHING;
  EXCEPTION WHEN others THEN
    RETURN jsonb_build_object('success', false, 'error', SQLERRM);
  END;

  RETURN jsonb_build_object('success', true);
END;
$$;

-- Grant execute to authenticated users
REVOKE ALL ON FUNCTION public.bind_referral(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.bind_referral(text) TO anon, authenticated, service_role;
