-- Drop and recreate create_commission_transactions function with correct conflict handling
DROP FUNCTION IF EXISTS public.create_commission_transactions(numeric, uuid, text, uuid, integer);

CREATE FUNCTION public.create_commission_transactions(
  p_amount_kzt numeric,
  p_source_id uuid,
  p_source_ref text,
  p_source_user_id uuid,
  p_structure_type integer DEFAULT 1
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_sponsor_id uuid;
  v_current_user_id uuid;
  v_level integer := 0;
  v_percent numeric;
  v_commission_amount integer;
  v_created_count integer := 0;
  v_skipped_count integer := 0;
  v_total_commission integer := 0;
  v_freeze_days integer;
  v_frozen_until timestamptz;
  v_direct_referrals integer;
  v_required_referrals integer;
  v_max_level integer;
  v_source_user_name text;
  v_recipient_name text;
  v_is_recipient_active boolean;
  v_recipient_subscription_status text;
  v_source_user_subscription_status text;
  v_source_user_is_marketing_free boolean := false;
  v_details jsonb := '[]'::jsonb;
BEGIN
  -- Get source user info
  SELECT 
    full_name, 
    sponsor_id,
    subscription_status
  INTO v_source_user_name, v_sponsor_id, v_source_user_subscription_status
  FROM profiles 
  WHERE id = p_source_user_id;

  -- Check if source user has marketing free access (no commissions should be paid)
  SELECT EXISTS (
    SELECT 1 FROM subscriptions 
    WHERE user_id = p_source_user_id 
    AND is_marketing_free_access = true 
    AND status = 'active'
  ) INTO v_source_user_is_marketing_free;

  IF v_source_user_is_marketing_free THEN
    RETURN json_build_object(
      'success', true,
      'message', 'Marketing free access - no commissions calculated',
      'created_count', 0,
      'skipped_count', 0,
      'total_commission_cents', 0,
      'details', v_details
    );
  END IF;

  IF v_sponsor_id IS NULL THEN
    RETURN json_build_object(
      'success', true,
      'message', 'No sponsor found for user',
      'created_count', 0,
      'skipped_count', 0,
      'total_commission_cents', 0,
      'details', v_details
    );
  END IF;

  -- Get freeze days from settings
  SELECT COALESCE((value::text)::integer, 14)
  INTO v_freeze_days
  FROM mlm_settings
  WHERE key = 'commission_freeze_days';

  v_frozen_until := now() + (v_freeze_days || ' days')::interval;

  -- Get max level for structure type
  SELECT COALESCE(MAX(level), 10)
  INTO v_max_level
  FROM commission_plan_levels
  WHERE structure_type = CASE WHEN p_structure_type = 1 THEN 'primary'::structure_type ELSE 'secondary'::structure_type END;

  v_current_user_id := v_sponsor_id;

  WHILE v_current_user_id IS NOT NULL AND v_level < v_max_level LOOP
    v_level := v_level + 1;

    -- Get commission percent for this level
    SELECT percent
    INTO v_percent
    FROM commission_plan_levels
    WHERE level = v_level
    AND structure_type = CASE WHEN p_structure_type = 1 THEN 'primary'::structure_type ELSE 'secondary'::structure_type END;

    IF v_percent IS NULL OR v_percent = 0 THEN
      SELECT sponsor_id INTO v_current_user_id FROM profiles WHERE id = v_current_user_id;
      CONTINUE;
    END IF;

    -- Get recipient info
    SELECT 
      full_name, 
      is_active,
      subscription_status,
      direct_referrals_count
    INTO v_recipient_name, v_is_recipient_active, v_recipient_subscription_status, v_direct_referrals
    FROM profiles 
    WHERE id = v_current_user_id;

    v_direct_referrals := COALESCE(v_direct_referrals, 0);

    -- Check unlock requirements for levels 2-10
    IF v_level >= 2 THEN
      v_required_referrals := CASE v_level
        WHEN 2 THEN 2
        WHEN 3 THEN 4
        WHEN 4 THEN 8
        WHEN 5 THEN 10
        WHEN 6 THEN 12
        WHEN 7 THEN 14
        WHEN 8 THEN 16
        WHEN 9 THEN 18
        WHEN 10 THEN 20
        ELSE 0
      END;

      IF v_direct_referrals < v_required_referrals THEN
        v_skipped_count := v_skipped_count + 1;
        v_details := v_details || jsonb_build_object(
          'level', v_level,
          'recipient_id', v_current_user_id,
          'recipient_name', v_recipient_name,
          'status', 'skipped',
          'reason', format('Level %s requires %s referrals, has %s', v_level, v_required_referrals, v_direct_referrals)
        );
        SELECT sponsor_id INTO v_current_user_id FROM profiles WHERE id = v_current_user_id;
        CONTINUE;
      END IF;
    END IF;

    -- Check if recipient is active
    IF NOT COALESCE(v_is_recipient_active, false) OR v_recipient_subscription_status != 'active' THEN
      v_skipped_count := v_skipped_count + 1;
      v_details := v_details || jsonb_build_object(
        'level', v_level,
        'recipient_id', v_current_user_id,
        'recipient_name', v_recipient_name,
        'status', 'skipped',
        'reason', 'Recipient not active or no active subscription'
      );
      SELECT sponsor_id INTO v_current_user_id FROM profiles WHERE id = v_current_user_id;
      CONTINUE;
    END IF;

    -- Calculate commission amount in cents (tenge * 100)
    v_commission_amount := ROUND(p_amount_kzt * (v_percent / 100) * 100);

    IF v_commission_amount > 0 THEN
      -- Insert commission transaction with CORRECT conflict handling (using index, not constraint)
      INSERT INTO transactions (
        user_id,
        type,
        amount_cents,
        currency,
        status,
        source_id,
        source_ref,
        level,
        structure_type,
        frozen_until,
        payload
      ) VALUES (
        v_current_user_id,
        'commission',
        v_commission_amount,
        'KZT',
        'frozen',
        p_source_id,
        p_source_ref,
        v_level,
        CASE WHEN p_structure_type = 1 THEN 'primary'::structure_type ELSE 'secondary'::structure_type END,
        v_frozen_until,
        jsonb_build_object(
          'source_user_id', p_source_user_id,
          'source_user_name', v_source_user_name,
          'percent', v_percent,
          'base_amount_kzt', p_amount_kzt
        )
      )
      ON CONFLICT (user_id, source_ref) WHERE source_ref IS NOT NULL DO NOTHING;

      IF FOUND THEN
        v_created_count := v_created_count + 1;
        v_total_commission := v_total_commission + v_commission_amount;
        v_details := v_details || jsonb_build_object(
          'level', v_level,
          'recipient_id', v_current_user_id,
          'recipient_name', v_recipient_name,
          'status', 'created',
          'amount_cents', v_commission_amount,
          'percent', v_percent,
          'frozen_until', v_frozen_until
        );
      ELSE
        v_skipped_count := v_skipped_count + 1;
        v_details := v_details || jsonb_build_object(
          'level', v_level,
          'recipient_id', v_current_user_id,
          'recipient_name', v_recipient_name,
          'status', 'skipped',
          'reason', 'Duplicate transaction (already exists)'
        );
      END IF;
    END IF;

    SELECT sponsor_id INTO v_current_user_id FROM profiles WHERE id = v_current_user_id;
  END LOOP;

  RETURN json_build_object(
    'success', true,
    'message', format('Created %s commission transactions, skipped %s', v_created_count, v_skipped_count),
    'created_count', v_created_count,
    'skipped_count', v_skipped_count,
    'total_commission_cents', v_total_commission,
    'details', v_details
  );
END;
$function$;