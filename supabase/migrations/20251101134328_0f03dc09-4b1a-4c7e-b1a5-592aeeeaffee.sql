-- 1) Ensure unique constraint on referrals (referred_user_id, structure_type)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'uniq_referrals_referred_structure'
  ) THEN
    ALTER TABLE public.referrals
    ADD CONSTRAINT uniq_referrals_referred_structure UNIQUE (referred_user_id, structure_type);
  END IF;
END $$;

-- 2) Create RPC to bind referral atomically and safely
CREATE OR REPLACE FUNCTION public.bind_referral(p_ref_code text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_sponsor RECORD;
  v_already_set boolean;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHENTICATED');
  END IF;

  -- If user already has a sponsor, do nothing (idempotent)
  SELECT (sponsor_id IS NOT NULL) INTO v_already_set FROM profiles WHERE id = v_user_id;
  IF v_already_set THEN
    RETURN jsonb_build_object('success', true, 'message', 'ALREADY_BOUND');
  END IF;

  -- Find sponsor by referral code
  SELECT id, full_name, email
  INTO v_sponsor
  FROM profiles
  WHERE referral_code = p_ref_code
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_CODE');
  END IF;

  -- Prevent self-referral just in case
  IF v_sponsor.id = v_user_id THEN
    RETURN jsonb_build_object('success', false, 'error', 'SELF_REFERRAL');
  END IF;

  -- Update profile with sponsor and snapshot
  UPDATE profiles
  SET 
    sponsor_id = v_sponsor.id,
    referrer_snapshot = jsonb_build_object('full_name', v_sponsor.full_name, 'email', v_sponsor.email),
    updated_at = now()
  WHERE id = v_user_id AND sponsor_id IS NULL;

  -- Create primary structure referral row (idempotent)
  INSERT INTO referrals (referrer_id, referred_user_id, structure_type)
  VALUES (v_sponsor.id, v_user_id, 1)
  ON CONFLICT (referred_user_id, structure_type) DO NOTHING;

  -- Return sponsor info
  RETURN jsonb_build_object('success', true, 'sponsor_id', v_sponsor.id);
END;
$$;

-- 3) Grant execute to authenticated users (function runs as SECURITY DEFINER)
REVOKE ALL ON FUNCTION public.bind_referral(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.bind_referral(text) TO authenticated;
