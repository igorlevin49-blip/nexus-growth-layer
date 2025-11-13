-- =====================================================
-- FIX: Missing RPC functions for referral system
-- =====================================================

-- Function 1: validate_referral_code
-- Validates a referral code exists and is active
CREATE OR REPLACE FUNCTION public.validate_referral_code(p_ref_code TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sponsor_id UUID;
  v_sponsor_name TEXT;
BEGIN
  -- Trim and validate input
  IF p_ref_code IS NULL OR TRIM(p_ref_code) = '' THEN
    RETURN jsonb_build_object('valid', false, 'error', 'EMPTY_CODE');
  END IF;

  -- Find sponsor by referral code
  SELECT id, full_name INTO v_sponsor_id, v_sponsor_name
  FROM public.profiles
  WHERE referral_code = TRIM(p_ref_code)
    AND is_active = true
    AND (deleted_at IS NULL)
    AND (is_archived IS NULL OR is_archived = false);

  IF v_sponsor_id IS NULL THEN
    RETURN jsonb_build_object('valid', false, 'error', 'INVALID_CODE');
  END IF;

  RETURN jsonb_build_object(
    'valid', true,
    'sponsor_id', v_sponsor_id,
    'sponsor_name', v_sponsor_name
  );
END;
$$;

-- Function 2: admin_backfill_sponsor_from_metadata
-- Restores sponsor relationships from auth.users metadata
CREATE OR REPLACE FUNCTION public.admin_backfill_sponsor_from_metadata()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_updated_count INT := 0;
  v_failed_count INT := 0;
  v_inserted_referrals INT := 0;
  v_user RECORD;
  v_ref_code TEXT;
  v_sponsor_id UUID;
  v_sponsor_name TEXT;
BEGIN
  -- Check admin role
  IF NOT (has_role(auth.uid(), 'admin'::app_role) OR has_role(auth.uid(), 'superadmin'::app_role)) THEN
    RETURN jsonb_build_object('success', false, 'error', 'UNAUTHORIZED');
  END IF;

  -- Loop through users without sponsor_id
  FOR v_user IN
    SELECT p.id, p.email, u.raw_user_meta_data
    FROM public.profiles p
    JOIN auth.users u ON u.id = p.id
    WHERE p.sponsor_id IS NULL
      AND p.is_active = true
      AND (p.deleted_at IS NULL)
      AND (p.is_archived IS NULL OR p.is_archived = false)
      AND u.raw_user_meta_data->>'inviter_ref_code' IS NOT NULL
  LOOP
    BEGIN
      -- Extract ref code from metadata
      v_ref_code := v_user.raw_user_meta_data->>'inviter_ref_code';
      
      IF v_ref_code IS NOT NULL AND TRIM(v_ref_code) != '' THEN
        -- Find sponsor
        SELECT id, full_name INTO v_sponsor_id, v_sponsor_name
        FROM public.profiles
        WHERE referral_code = TRIM(v_ref_code)
          AND is_active = true
          AND (deleted_at IS NULL);

        IF v_sponsor_id IS NOT NULL THEN
          -- Update sponsor_id and snapshot
          UPDATE public.profiles
          SET 
            sponsor_id = v_sponsor_id,
            referrer_snapshot = jsonb_build_object(
              'id', v_sponsor_id,
              'full_name', v_sponsor_name
            ),
            updated_at = NOW()
          WHERE id = v_user.id;

          -- Ensure referrals row exists
          INSERT INTO public.referrals (referrer_id, referred_user_id, structure_type)
          VALUES (v_sponsor_id, v_user.id, 1)
          ON CONFLICT (referred_user_id, structure_type) DO NOTHING;

          v_updated_count := v_updated_count + 1;
          v_inserted_referrals := v_inserted_referrals + 1;
        ELSE
          v_failed_count := v_failed_count + 1;
        END IF;
      END IF;
    EXCEPTION WHEN OTHERS THEN
      v_failed_count := v_failed_count + 1;
    END;
  END LOOP;

  RETURN jsonb_build_object(
    'success', true,
    'updated_count', v_updated_count,
    'inserted_referrals', v_inserted_referrals,
    'failed_count', v_failed_count
  );
END;
$$;