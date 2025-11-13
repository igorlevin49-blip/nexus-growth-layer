-- Fix: Move activity_log writes from BEFORE to AFTER INSERT trigger
-- This resolves foreign key constraint violation during registration

-- Step 1: Rewrite auto_bind_sponsor_from_metadata to ONLY set sponsor_id
-- Remove all activity_log inserts from BEFORE trigger
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
BEGIN
  -- Only process if sponsor_id not already set
  IF NEW.sponsor_id IS NULL THEN
    -- Try to get inviter code from metadata
    SELECT 
      COALESCE(
        u.raw_user_meta_data->>'inviter_ref_code',
        u.raw_app_meta_data->>'inviter_ref_code'
      )
    INTO v_inviter_code
    FROM auth.users u
    WHERE u.id = NEW.id;

    -- If we have an inviter code, try to bind sponsor
    IF v_inviter_code IS NOT NULL AND TRIM(v_inviter_code) != '' THEN
      -- Find sponsor by referral code
      SELECT id, full_name, email
      INTO v_sponsor_id, v_sponsor_name, v_sponsor_email
      FROM public.profiles
      WHERE referral_code = TRIM(v_inviter_code)
        AND is_active = true
        AND (deleted_at IS NULL)
        AND (is_archived IS NULL OR is_archived = false);

      -- Set sponsor if found and not self-referral
      IF v_sponsor_id IS NOT NULL AND v_sponsor_id != NEW.id THEN
        NEW.sponsor_id := v_sponsor_id;
        NEW.referrer_snapshot := jsonb_build_object(
          'id', v_sponsor_id,
          'full_name', v_sponsor_name,
          'email', v_sponsor_email
        );
      END IF;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

-- Step 2: Create AFTER INSERT trigger function for logging
CREATE OR REPLACE FUNCTION public.log_referral_bind_after_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_inviter_code TEXT;
BEGIN
  -- Get inviter code from auth metadata
  SELECT 
    COALESCE(
      u.raw_user_meta_data->>'inviter_ref_code',
      u.raw_app_meta_data->>'inviter_ref_code'
    )
  INTO v_inviter_code
  FROM auth.users u
  WHERE u.id = NEW.id;

  -- Log referral binding result if inviter code was present
  IF v_inviter_code IS NOT NULL AND TRIM(v_inviter_code) != '' THEN
    IF NEW.sponsor_id IS NOT NULL THEN
      -- Success: sponsor was bound
      INSERT INTO public.activity_log (user_id, type, payload)
      VALUES (
        NEW.id,
        'referral_auto_bound',
        jsonb_build_object(
          'sponsor_id', NEW.sponsor_id,
          'inviter_code', TRIM(v_inviter_code),
          'timestamp', NOW()
        )
      );
    ELSE
      -- Failed: inviter code present but sponsor not set
      INSERT INTO public.activity_log (user_id, type, payload)
      VALUES (
        NEW.id,
        'referral_bind_failed',
        jsonb_build_object(
          'reason', 'sponsor_not_set',
          'inviter_code', TRIM(v_inviter_code),
          'timestamp', NOW()
        )
      );
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

-- Step 3: Create AFTER INSERT trigger
DROP TRIGGER IF EXISTS trigger_log_referral_after_insert ON public.profiles;

CREATE TRIGGER trigger_log_referral_after_insert
  AFTER INSERT ON public.profiles
  FOR EACH ROW
  EXECUTE FUNCTION public.log_referral_bind_after_insert();