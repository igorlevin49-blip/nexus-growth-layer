-- Ensure referrals row and snapshot created whenever sponsor_id is set
-- 1) Trigger function
CREATE OR REPLACE FUNCTION public.upsert_referral_on_sponsor_update()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  v_sponsor_name text;
  v_sponsor_email text;
BEGIN
  IF NEW.sponsor_id IS NOT NULL AND (OLD.sponsor_id IS NULL OR OLD.sponsor_id <> NEW.sponsor_id) THEN
    -- Ensure referrals row for primary structure exists
    INSERT INTO public.referrals (referrer_id, referred_user_id, structure_type)
    VALUES (NEW.sponsor_id, NEW.id, 1)
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
$$;

-- 2) Trigger: run before updating sponsor_id to write snapshot
DROP TRIGGER IF EXISTS trg_profiles_sponsor_update_referral ON public.profiles;
CREATE TRIGGER trg_profiles_sponsor_update_referral
BEFORE UPDATE OF sponsor_id ON public.profiles
FOR EACH ROW
EXECUTE FUNCTION public.upsert_referral_on_sponsor_update();

-- 3) Admin helper to fix historical gaps in referrals for users that already have sponsor_id
CREATE OR REPLACE FUNCTION public.admin_fix_missing_referrals()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  v_inserted int := 0;
  v_snapshots int := 0;
BEGIN
  IF NOT (has_role(auth.uid(), 'admin'::app_role) OR has_role(auth.uid(), 'superadmin'::app_role)) THEN
    RAISE EXCEPTION 'UNAUTHORIZED';
  END IF;

  -- Insert missing referrals rows for structure_type = 1
  WITH ins AS (
    INSERT INTO public.referrals (referrer_id, referred_user_id, structure_type)
    SELECT p.sponsor_id, p.id, 1
    FROM public.profiles p
    LEFT JOIN public.referrals r
      ON r.referred_user_id = p.id AND r.structure_type = 1
    WHERE p.sponsor_id IS NOT NULL AND r.id IS NULL
    RETURNING 1
  )
  SELECT COUNT(*) INTO v_inserted FROM ins;

  -- Backfill snapshots where missing
  WITH upd AS (
    UPDATE public.profiles p
    SET referrer_snapshot = jsonb_build_object(
      'id', p.sponsor_id,
      'full_name', sp.full_name,
      'email', sp.email
    ), updated_at = NOW()
    FROM public.profiles sp
    WHERE p.sponsor_id = sp.id
      AND (p.referrer_snapshot IS NULL OR p.referrer_snapshot = '{}'::jsonb)
    RETURNING 1
  )
  SELECT COUNT(*) INTO v_snapshots FROM upd;

  RETURN jsonb_build_object('inserted_referrals', v_inserted, 'updated_snapshots', v_snapshots);
END;
$$;