-- Create function to validate referral code (accessible without auth)
CREATE OR REPLACE FUNCTION public.validate_referral_code(p_ref_code text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  v_referrer profiles%ROWTYPE;
BEGIN
  -- Validation: referral code must not be empty
  IF p_ref_code IS NULL OR length(trim(p_ref_code)) = 0 THEN
    RETURN jsonb_build_object('valid', false, 'error', 'EMPTY_CODE');
  END IF;

  -- Find referrer by referral code
  SELECT p.* INTO v_referrer
  FROM public.profiles p
  WHERE LOWER(p.referral_code) = LOWER(trim(p_ref_code))
    AND p.is_active = true
    AND (p.deleted_at IS NULL)
    AND (p.is_archived IS NULL OR p.is_archived = false);

  -- Check if referrer exists
  IF v_referrer.id IS NULL THEN
    RETURN jsonb_build_object('valid', false, 'error', 'INVALID_CODE');
  END IF;

  RETURN jsonb_build_object(
    'valid', true, 
    'sponsor_id', v_referrer.id,
    'sponsor_name', v_referrer.full_name
  );
END;
$$;

-- Grant execute to anon users (for pre-registration validation)
GRANT EXECUTE ON FUNCTION public.validate_referral_code(text) TO anon, authenticated;