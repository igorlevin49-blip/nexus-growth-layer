-- Function to reassign referrals to upper sponsor before user deletion
CREATE OR REPLACE FUNCTION public.reassign_referrals_to_upper_sponsor(
  p_user_id UUID,
  p_admin_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_upper_sponsor_id UUID;
  v_reassigned_profiles INT := 0;
  v_reassigned_referrals INT := 0;
BEGIN
  -- Check admin permissions
  IF NOT has_role(p_admin_id, 'superadmin'::app_role) AND NOT has_role(p_admin_id, 'admin'::app_role) THEN
    RAISE EXCEPTION 'Access denied: admin role required';
  END IF;

  -- Find upper sponsor
  SELECT sponsor_id INTO v_upper_sponsor_id
  FROM profiles WHERE id = p_user_id;

  -- Reassign profiles
  UPDATE profiles
  SET sponsor_id = v_upper_sponsor_id,
      updated_at = NOW()
  WHERE sponsor_id = p_user_id;

  GET DIAGNOSTICS v_reassigned_profiles = ROW_COUNT;

  -- Reassign referrals table records
  UPDATE referrals
  SET referrer_id = v_upper_sponsor_id
  WHERE referrer_id = p_user_id;

  GET DIAGNOSTICS v_reassigned_referrals = ROW_COUNT;

  -- Audit log
  INSERT INTO admin_audit (admin_id, action_type, target_type, target_id, metadata)
  VALUES (p_admin_id, 'reassign_referrals', 'user', p_user_id, jsonb_build_object(
    'reassigned_to', v_upper_sponsor_id,
    'reassigned_profiles', v_reassigned_profiles,
    'reassigned_referrals', v_reassigned_referrals
  ));

  RETURN jsonb_build_object(
    'success', true,
    'reassigned_count', v_reassigned_profiles,
    'new_sponsor_id', v_upper_sponsor_id
  );
END;
$$;

-- Function to count user's direct referrals
CREATE OR REPLACE FUNCTION public.count_user_referrals(p_user_id UUID)
RETURNS INT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COUNT(*)::INT FROM profiles WHERE sponsor_id = p_user_id;
$$;