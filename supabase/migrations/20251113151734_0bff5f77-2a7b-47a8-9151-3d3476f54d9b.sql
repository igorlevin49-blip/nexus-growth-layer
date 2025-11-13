-- =====================================================
-- AUTO-BIND SPONSOR FROM USER_METADATA ON PROFILE INSERT
-- =====================================================

-- Function to automatically set sponsor_id from user_metadata during profile creation
CREATE OR REPLACE FUNCTION public.auto_bind_sponsor_from_metadata()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_inviter_code TEXT;
  v_sponsor_id UUID;
  v_sponsor_name TEXT;
  v_sponsor_email TEXT;
  v_sponsor_ref_code TEXT;
BEGIN
  -- Only process if sponsor_id is not already set
  IF NEW.sponsor_id IS NULL THEN
    -- Try to get inviter code from user_metadata (multiple fallback locations)
    SELECT COALESCE(
      u.raw_user_meta_data->>'inviter_ref_code',
      u.raw_app_meta_data->>'inviter_ref_code',
      u.user_metadata->>'inviter_ref_code'
    )
    INTO v_inviter_code
    FROM auth.users u
    WHERE u.id = NEW.id;
    
    -- If inviter code exists, try to find and bind sponsor
    IF v_inviter_code IS NOT NULL AND TRIM(v_inviter_code) != '' THEN
      v_inviter_code := TRIM(v_inviter_code);
      
      -- Find sponsor by referral code
      SELECT id, full_name, email, referral_code
      INTO v_sponsor_id, v_sponsor_name, v_sponsor_email, v_sponsor_ref_code
      FROM public.profiles
      WHERE referral_code = v_inviter_code
        AND is_active = true
        AND deleted_at IS NULL
        AND (is_archived IS NULL OR is_archived = false);
      
      -- Validate and set sponsor
      IF v_sponsor_id IS NOT NULL THEN
        -- Prevent self-referral
        IF v_sponsor_id = NEW.id THEN
          -- Log failed attempt
          INSERT INTO public.activity_log (user_id, type, payload)
          VALUES (
            NEW.id,
            'referral_bind_failed',
            jsonb_build_object(
              'reason', 'self_referral',
              'inviter_code', v_inviter_code,
              'timestamp', NOW()
            )
          );
        ELSE
          -- Set sponsor_id and snapshot
          NEW.sponsor_id := v_sponsor_id;
          NEW.referrer_snapshot := jsonb_build_object(
            'id', v_sponsor_id,
            'full_name', v_sponsor_name,
            'email', v_sponsor_email,
            'referral_code', v_sponsor_ref_code
          );
          
          -- Log successful auto-bind
          INSERT INTO public.activity_log (user_id, type, payload)
          VALUES (
            NEW.id,
            'referral_auto_bound',
            jsonb_build_object(
              'sponsor_id', v_sponsor_id,
              'sponsor_name', v_sponsor_name,
              'inviter_code', v_inviter_code,
              'timestamp', NOW()
            )
          );
        END IF;
      ELSE
        -- Sponsor not found - log it
        INSERT INTO public.activity_log (user_id, type, payload)
        VALUES (
          NEW.id,
          'referral_bind_failed',
          jsonb_build_object(
            'reason', 'sponsor_not_found',
            'inviter_code', v_inviter_code,
            'timestamp', NOW()
          )
        );
      END IF;
    END IF;
  END IF;
  
  RETURN NEW;
END;
$$;

-- Create trigger to auto-bind sponsor on profile insert
DROP TRIGGER IF EXISTS trigger_auto_bind_sponsor_from_metadata ON public.profiles;
CREATE TRIGGER trigger_auto_bind_sponsor_from_metadata
  BEFORE INSERT ON public.profiles
  FOR EACH ROW
  EXECUTE FUNCTION public.auto_bind_sponsor_from_metadata();

-- =====================================================
-- ENSURE REFERRALS ENTRY ON PROFILE INSERT (if sponsor_id set)
-- =====================================================

CREATE OR REPLACE FUNCTION public.ensure_referral_on_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- If sponsor_id is set, ensure referrals entry exists
  IF NEW.sponsor_id IS NOT NULL THEN
    INSERT INTO public.referrals (referrer_id, referred_user_id, structure_type)
    VALUES (NEW.sponsor_id, NEW.id, 1)
    ON CONFLICT (referred_user_id, structure_type) DO NOTHING;
    
    -- Update sponsor's direct referrals count
    UPDATE public.profiles
    SET direct_referrals_count = (
      SELECT COUNT(*) FROM public.profiles WHERE sponsor_id = NEW.sponsor_id
    ),
    updated_at = NOW()
    WHERE id = NEW.sponsor_id;
  END IF;
  
  RETURN NEW;
END;
$$;

-- Create trigger to ensure referrals entry after insert
DROP TRIGGER IF EXISTS trigger_ensure_referral_on_insert ON public.profiles;
CREATE TRIGGER trigger_ensure_referral_on_insert
  AFTER INSERT ON public.profiles
  FOR EACH ROW
  EXECUTE FUNCTION public.ensure_referral_on_insert();

-- =====================================================
-- ADMIN BACKFILL FUNCTION
-- =====================================================

CREATE OR REPLACE FUNCTION public.admin_backfill_sponsor_from_metadata()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_profile RECORD;
  v_inviter_code TEXT;
  v_sponsor_id UUID;
  v_sponsor_name TEXT;
  v_sponsor_email TEXT;
  v_sponsor_ref_code TEXT;
  v_updated_count INTEGER := 0;
  v_inserted_referrals INTEGER := 0;
  v_failed_count INTEGER := 0;
  v_details JSONB := '[]'::JSONB;
BEGIN
  -- Check if user is admin or superadmin
  IF NOT (has_role(auth.uid(), 'admin'::app_role) OR has_role(auth.uid(), 'superadmin'::app_role)) THEN
    RAISE EXCEPTION 'UNAUTHORIZED';
  END IF;
  
  -- Process all profiles with NULL sponsor_id
  FOR v_profile IN
    SELECT p.id, p.email, p.full_name
    FROM public.profiles p
    WHERE p.sponsor_id IS NULL
      AND p.is_active = true
      AND p.deleted_at IS NULL
      AND (p.is_archived IS NULL OR p.is_archived = false)
  LOOP
    -- Try to get inviter code from user_metadata
    SELECT COALESCE(
      u.raw_user_meta_data->>'inviter_ref_code',
      u.raw_app_meta_data->>'inviter_ref_code',
      u.user_metadata->>'inviter_ref_code'
    )
    INTO v_inviter_code
    FROM auth.users u
    WHERE u.id = v_profile.id;
    
    IF v_inviter_code IS NOT NULL AND TRIM(v_inviter_code) != '' THEN
      v_inviter_code := TRIM(v_inviter_code);
      
      -- Find sponsor
      SELECT id, full_name, email, referral_code
      INTO v_sponsor_id, v_sponsor_name, v_sponsor_email, v_sponsor_ref_code
      FROM public.profiles
      WHERE referral_code = v_inviter_code
        AND is_active = true
        AND deleted_at IS NULL
        AND (is_archived IS NULL OR is_archived = false);
      
      IF v_sponsor_id IS NOT NULL AND v_sponsor_id != v_profile.id THEN
        -- Update profile
        UPDATE public.profiles
        SET 
          sponsor_id = v_sponsor_id,
          referrer_snapshot = jsonb_build_object(
            'id', v_sponsor_id,
            'full_name', v_sponsor_name,
            'email', v_sponsor_email,
            'referral_code', v_sponsor_ref_code
          ),
          updated_at = NOW()
        WHERE id = v_profile.id;
        
        -- Insert referrals entry
        INSERT INTO public.referrals (referrer_id, referred_user_id, structure_type)
        VALUES (v_sponsor_id, v_profile.id, 1)
        ON CONFLICT (referred_user_id, structure_type) DO NOTHING;
        
        -- Update sponsor's direct referrals count
        UPDATE public.profiles
        SET direct_referrals_count = (
          SELECT COUNT(*) FROM public.profiles WHERE sponsor_id = v_sponsor_id
        ),
        updated_at = NOW()
        WHERE id = v_sponsor_id;
        
        v_updated_count := v_updated_count + 1;
        v_inserted_referrals := v_inserted_referrals + 1;
        
        v_details := v_details || jsonb_build_object(
          'user_email', v_profile.email,
          'sponsor_name', v_sponsor_name,
          'status', 'updated'
        );
      ELSE
        v_failed_count := v_failed_count + 1;
        v_details := v_details || jsonb_build_object(
          'user_email', v_profile.email,
          'inviter_code', v_inviter_code,
          'status', 'sponsor_not_found'
        );
      END IF;
    ELSE
      v_failed_count := v_failed_count + 1;
      v_details := v_details || jsonb_build_object(
        'user_email', v_profile.email,
        'status', 'no_inviter_code'
      );
    END IF;
  END LOOP;
  
  -- Log admin action
  INSERT INTO public.admin_actions (admin_id, action_type, target_type, metadata)
  VALUES (
    auth.uid(),
    'backfill_sponsor_from_metadata',
    'profiles',
    jsonb_build_object(
      'updated_count', v_updated_count,
      'inserted_referrals', v_inserted_referrals,
      'failed_count', v_failed_count
    )
  );
  
  RETURN jsonb_build_object(
    'success', true,
    'updated_count', v_updated_count,
    'inserted_referrals', v_inserted_referrals,
    'failed_count', v_failed_count,
    'details', v_details
  );
END;
$$;