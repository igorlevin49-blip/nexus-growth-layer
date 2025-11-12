
-- Function to manually bind sponsor by admin
CREATE OR REPLACE FUNCTION public.admin_bind_sponsor(
  p_user_id UUID,
  p_sponsor_referral_code TEXT,
  p_admin_id UUID
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
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

  -- Create referral record for structure 1 (primary)
  INSERT INTO referrals (referrer_id, referred_user_id, structure_type)
  VALUES (v_sponsor_id, p_user_id, 1)
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
$$;

COMMENT ON FUNCTION public.admin_bind_sponsor IS 'Allows admin to manually bind a sponsor to a user who registered without referral link';
