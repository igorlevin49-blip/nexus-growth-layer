-- =====================================================
-- FIX: Remove direct referrals check for S2 (Product Structure)
-- S2 only requires: active S1 subscription + monthly activation
-- S1 keeps: unlock requirements from mlm_settings.unlock_levels
-- =====================================================

CREATE OR REPLACE FUNCTION public.create_commission_transactions(
  p_amount_kzt numeric,
  p_source_id uuid,
  p_source_ref text,
  p_source_user_id uuid,
  p_structure_type integer DEFAULT 2
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_current_user_id uuid := p_source_user_id;
  v_sponsor_id uuid;
  v_level integer := 0;
  v_percent numeric;
  v_commission_kzt numeric;
  v_created_count integer := 0;
  v_skipped_count integer := 0;
  v_total_commission_kzt numeric := 0;
  v_freeze_days integer := 14;
  v_frozen_until timestamptz;
  v_sponsor_profile record;
  v_direct_referrals_count integer;
  v_required_referrals integer;
  v_max_level integer;
  v_skip_reason text;
  v_details jsonb := '[]'::jsonb;
  v_existing_count integer;
  v_unlock_levels jsonb;
  v_level_key text;
BEGIN
  -- Check for existing commissions to prevent duplicates
  SELECT COUNT(*) INTO v_existing_count
  FROM transactions
  WHERE source_id = p_source_id
    AND source_ref = p_source_ref
    AND type = 'commission'
    AND structure_type = CASE WHEN p_structure_type = 1 THEN 'primary'::structure_type ELSE 'secondary'::structure_type END;
  
  IF v_existing_count > 0 THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Commissions already exist for this source',
      'existing_count', v_existing_count
    );
  END IF;

  -- Get max level for this structure
  SELECT COALESCE(MAX(level), 10) INTO v_max_level
  FROM mlm_commission_rules
  WHERE structure_type = p_structure_type AND is_active = true;

  -- Get unlock levels settings (only used for S1)
  IF p_structure_type = 1 THEN
    SELECT value INTO v_unlock_levels
    FROM mlm_settings
    WHERE key = 'unlock_levels';
    
    IF v_unlock_levels IS NULL THEN
      v_unlock_levels := '{"l2": 3, "l3": 5, "l4": 8, "l5": 10}'::jsonb;
    END IF;
  END IF;

  -- Calculate freeze date
  v_frozen_until := now() + (v_freeze_days || ' days')::interval;

  -- Walk up the referral chain
  LOOP
    -- Get sponsor from profiles
    SELECT sponsor_id INTO v_sponsor_id
    FROM profiles
    WHERE id = v_current_user_id;
    
    EXIT WHEN v_sponsor_id IS NULL;
    
    v_level := v_level + 1;
    EXIT WHEN v_level > v_max_level;
    
    -- Get commission percent for this level and structure
    SELECT percent INTO v_percent
    FROM mlm_commission_rules
    WHERE structure_type = p_structure_type
      AND level = v_level
      AND is_active = true
    LIMIT 1;
    
    -- Skip if no commission rule
    IF v_percent IS NULL OR v_percent <= 0 THEN
      v_current_user_id := v_sponsor_id;
      CONTINUE;
    END IF;
    
    -- Get sponsor profile for validation
    SELECT * INTO v_sponsor_profile
    FROM profiles
    WHERE id = v_sponsor_id;
    
    v_skip_reason := NULL;
    
    -- Check sponsor has active subscription (required for both S1 and S2)
    IF v_sponsor_profile.subscription_status NOT IN ('active', 'paid') THEN
      v_skip_reason := 'sponsor_inactive';
    END IF;
    
    -- For S2, check monthly activation (this is the ONLY additional requirement for S2)
    IF p_structure_type = 2 AND v_skip_reason IS NULL THEN
      IF NOT COALESCE(v_sponsor_profile.monthly_activation_completed, false) THEN
        v_skip_reason := 'sponsor_no_activation';
      END IF;
    END IF;
    
    -- Check unlock requirements ONLY FOR S1 (subscription structure)
    -- S2 (product structure) does NOT require direct referrals
    IF v_skip_reason IS NULL AND v_level >= 2 AND p_structure_type = 1 THEN
      -- Count direct referrals for S1 only
      SELECT COUNT(*) INTO v_direct_referrals_count
      FROM referrals
      WHERE referrer_id = v_sponsor_id
        AND structure_type = 1;
      
      -- Get requirement for this level from settings
      v_level_key := 'l' || v_level::text;
      v_required_referrals := COALESCE((v_unlock_levels->>v_level_key)::int, 0);
      
      IF v_required_referrals > 0 AND v_direct_referrals_count < v_required_referrals THEN
        v_skip_reason := 'level_locked';
      END IF;
    END IF;
    
    -- Calculate commission amount (whole KZT)
    v_commission_kzt := ROUND(p_amount_kzt * (v_percent / 100.0));
    
    IF v_skip_reason IS NULL AND v_commission_kzt > 0 THEN
      -- Create commission transaction
      INSERT INTO transactions (
        user_id,
        type,
        amount_cents,
        currency,
        status,
        frozen_until,
        source_id,
        source_ref,
        level,
        structure_type,
        payload
      ) VALUES (
        v_sponsor_id,
        'commission',
        v_commission_kzt,
        'KZT',
        'frozen',
        v_frozen_until,
        p_source_id,
        p_source_ref,
        v_level,
        CASE WHEN p_structure_type = 1 THEN 'primary'::structure_type ELSE 'secondary'::structure_type END,
        jsonb_build_object(
          'source_user_id', p_source_user_id,
          'order_amount_kzt', p_amount_kzt,
          'percent', v_percent,
          'created_at', now(),
          'unit', 'KZT'
        )
      );
      
      v_created_count := v_created_count + 1;
      v_total_commission_kzt := v_total_commission_kzt + v_commission_kzt;
      
      v_details := v_details || jsonb_build_object(
        'user_id', v_sponsor_id,
        'level', v_level,
        'percent', v_percent,
        'amount_kzt', v_commission_kzt,
        'status', 'created'
      );
    ELSE
      v_skipped_count := v_skipped_count + 1;
      v_details := v_details || jsonb_build_object(
        'user_id', v_sponsor_id,
        'level', v_level,
        'percent', v_percent,
        'amount_kzt', v_commission_kzt,
        'status', 'skipped',
        'reason', COALESCE(v_skip_reason, 'zero_amount')
      );
    END IF;
    
    v_current_user_id := v_sponsor_id;
  END LOOP;
  
  RETURN jsonb_build_object(
    'success', true,
    'created_count', v_created_count,
    'skipped_count', v_skipped_count,
    'total_commission_kzt', v_total_commission_kzt,
    'frozen_until', v_frozen_until,
    'details', v_details
  );
END;
$$;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION public.create_commission_transactions(numeric, uuid, text, uuid, integer) TO authenticated;