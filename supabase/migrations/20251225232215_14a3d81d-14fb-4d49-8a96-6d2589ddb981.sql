-- Drop and recreate bind_referral with JSON return type
DROP FUNCTION IF EXISTS bind_referral(text);

-- Recreate bind_referral to check for blocked sponsors
CREATE OR REPLACE FUNCTION bind_referral(p_ref_code TEXT)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_referrer_id UUID;
  v_referrer RECORD;
  v_existing_sponsor UUID;
  v_user_created_at TIMESTAMPTZ;
BEGIN
  -- Get current user
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'not_authenticated');
  END IF;
  
  -- Check if user already has a sponsor
  SELECT sponsor_id, created_at INTO v_existing_sponsor, v_user_created_at 
  FROM profiles WHERE id = v_user_id;
  
  IF v_existing_sponsor IS NOT NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'already_has_sponsor');
  END IF;
  
  -- Find referrer by code
  SELECT id, full_name, referral_code, subscription_status, activation_due_from, monthly_activation_completed, created_at
  INTO v_referrer
  FROM profiles
  WHERE LOWER(referral_code) = LOWER(TRIM(p_ref_code));
  
  IF v_referrer IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'invalid_code');
  END IF;
  
  -- Prevent self-referral
  IF v_referrer.id = v_user_id THEN
    RETURN jsonb_build_object('success', false, 'error', 'self_referral');
  END IF;
  
  -- Check if user is already a sponsor of the referrer (circular reference)
  IF EXISTS (
    SELECT 1 FROM profiles 
    WHERE id = v_referrer.id AND sponsor_id = v_user_id
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'already_sponsor');
  END IF;
  
  -- Check if referrer registered after current user
  IF v_referrer.created_at > v_user_created_at THEN
    RETURN jsonb_build_object('success', false, 'error', 'sponsor_registered_later');
  END IF;
  
  -- Check if sponsor's referral link is blocked (subscription inactive)
  IF v_referrer.subscription_status != 'active' THEN
    RETURN jsonb_build_object('success', false, 'error', 'sponsor_not_active');
  END IF;
  
  -- Check if sponsor's referral link is blocked (activation overdue)
  IF v_referrer.activation_due_from IS NOT NULL 
     AND v_referrer.activation_due_from < NOW() 
     AND v_referrer.monthly_activation_completed = false THEN
    RETURN jsonb_build_object('success', false, 'error', 'sponsor_activation_blocked');
  END IF;
  
  -- Update user's sponsor
  UPDATE profiles
  SET 
    sponsor_id = v_referrer.id,
    referrer_snapshot = jsonb_build_object(
      'id', v_referrer.id,
      'full_name', v_referrer.full_name,
      'referral_code', v_referrer.referral_code,
      'bound_at', NOW()
    )
  WHERE id = v_user_id;
  
  -- Create referral record (S1 structure)
  INSERT INTO referrals (referrer_id, referred_user_id, structure_type)
  VALUES (v_referrer.id, v_user_id, 1)
  ON CONFLICT DO NOTHING;
  
  -- Create referral record (S2 structure)  
  INSERT INTO referrals (referrer_id, referred_user_id, structure_type)
  VALUES (v_referrer.id, v_user_id, 2)
  ON CONFLICT DO NOTHING;
  
  -- Update referrer's direct referrals count
  UPDATE profiles
  SET direct_referrals_count = COALESCE(direct_referrals_count, 0) + 1
  WHERE id = v_referrer.id;
  
  RETURN jsonb_build_object(
    'success', true, 
    'sponsor_id', v_referrer.id,
    'sponsor_name', v_referrer.full_name
  );
END;
$$;