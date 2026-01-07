-- Fix the create_commission_transactions function to remove the extra * 100 multiplication
-- The bug was on line 78: v_commission_cents := ROUND(v_amount_kzt * (v_percent / 100) * 100);
-- Should be: v_commission_cents := ROUND(v_amount_kzt * v_percent / 100);

CREATE OR REPLACE FUNCTION public.create_commission_transactions(
  p_source_user_id UUID,
  p_source_id UUID,
  p_source_ref TEXT,
  p_amount_kzt NUMERIC,
  p_structure_type INTEGER DEFAULT 2
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_current_user_id UUID;
  v_level INTEGER := 1;
  v_max_level INTEGER;
  v_percent NUMERIC;
  v_commission_cents INTEGER;
  v_created_count INTEGER := 0;
  v_sponsor_id UUID;
  v_freeze_days INTEGER;
  v_frozen_until TIMESTAMPTZ;
  v_result JSON;
  v_direct_referrals INTEGER;
  v_required_referrals INTEGER;
  v_is_active BOOLEAN;
  v_monthly_activation_completed BOOLEAN;
  v_subscription_status TEXT;
  v_skip_reason TEXT;
BEGIN
  -- Get max level for this structure type
  SELECT COALESCE(MAX(level), 10) INTO v_max_level
  FROM mlm_commission_rules
  WHERE structure_type = p_structure_type AND is_active = true;

  -- Get freeze days from settings
  SELECT COALESCE((value::text)::integer, 14) INTO v_freeze_days
  FROM mlm_settings
  WHERE key = 'commission_freeze_days';

  -- Start with source user's sponsor
  SELECT sponsor_id INTO v_current_user_id
  FROM profiles
  WHERE id = p_source_user_id;

  -- Walk up the sponsor chain
  WHILE v_current_user_id IS NOT NULL AND v_level <= v_max_level LOOP
    -- Get user's status
    SELECT 
      is_active,
      monthly_activation_completed,
      subscription_status,
      direct_referrals_count,
      sponsor_id
    INTO 
      v_is_active,
      v_monthly_activation_completed,
      v_subscription_status,
      v_direct_referrals,
      v_sponsor_id
    FROM profiles
    WHERE id = v_current_user_id;

    -- Get commission percent for this level
    SELECT percent INTO v_percent
    FROM mlm_commission_rules
    WHERE structure_type = p_structure_type
      AND level = v_level
      AND is_active = true
    ORDER BY effective_from DESC
    LIMIT 1;

    -- Check if level is unlocked (required referrals)
    SELECT COALESCE((value->>v_level::text)::integer, 0) INTO v_required_referrals
    FROM mlm_settings
    WHERE key = 'unlock_levels';

    v_skip_reason := NULL;

    -- Check conditions
    IF v_percent IS NULL OR v_percent = 0 THEN
      v_skip_reason := 'no_percent_for_level';
    ELSIF v_subscription_status != 'active' THEN
      v_skip_reason := 'subscription_not_active';
    ELSIF NOT COALESCE(v_monthly_activation_completed, false) THEN
      v_skip_reason := 'monthly_activation_not_completed';
    ELSIF COALESCE(v_direct_referrals, 0) < v_required_referrals THEN
      v_skip_reason := 'level_not_unlocked';
    END IF;

    IF v_skip_reason IS NULL THEN
      -- Calculate commission - FIXED: removed extra * 100
      v_commission_cents := ROUND(p_amount_kzt * v_percent / 100);

      IF v_commission_cents > 0 THEN
        -- Calculate frozen_until
        v_frozen_until := NOW() + (v_freeze_days || ' days')::INTERVAL;

        -- Create commission transaction
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
          v_commission_cents,
          'KZT',
          'frozen',
          p_source_id,
          p_source_ref,
          v_level,
          CASE WHEN p_structure_type = 1 THEN 'primary'::structure_type ELSE 'secondary'::structure_type END,
          v_frozen_until,
          jsonb_build_object(
            'source_user_id', p_source_user_id,
            'percent', v_percent,
            'base_amount_kzt', p_amount_kzt,
            'structure_type', p_structure_type
          )
        );

        v_created_count := v_created_count + 1;

        -- Log activity
        INSERT INTO activity_log (user_id, type, payload)
        VALUES (
          v_current_user_id,
          'commission_created',
          jsonb_build_object(
            'amount_cents', v_commission_cents,
            'level', v_level,
            'source_user_id', p_source_user_id,
            'source_ref', p_source_ref,
            'structure_type', p_structure_type
          )
        );
      END IF;
    ELSE
      -- Log skipped commission
      INSERT INTO activity_log (user_id, type, payload)
      VALUES (
        v_current_user_id,
        'commission_skipped',
        jsonb_build_object(
          'level', v_level,
          'reason', v_skip_reason,
          'source_user_id', p_source_user_id,
          'source_ref', p_source_ref,
          'structure_type', p_structure_type,
          'would_be_amount_kzt', ROUND(p_amount_kzt * COALESCE(v_percent, 0) / 100)
        )
      );
    END IF;

    -- Move to next level
    v_level := v_level + 1;
    v_current_user_id := v_sponsor_id;
  END LOOP;

  v_result := jsonb_build_object(
    'success', true,
    'commissions_created', v_created_count,
    'structure_type', p_structure_type,
    'source_amount_kzt', p_amount_kzt
  );

  RETURN v_result;
END;
$$;

-- Fix existing overcalculated S2 commissions from 2026-01-07
-- These were multiplied by 100 incorrectly
UPDATE transactions
SET 
  amount_cents = ROUND(amount_cents / 100),
  payload = COALESCE(payload, '{}'::jsonb) || jsonb_build_object(
    'fix_applied', 'divided_by_100_s2_bug_fix',
    'original_amount_cents', amount_cents,
    'fix_date', NOW()
  )
WHERE type = 'commission'
  AND structure_type = 'secondary'
  AND created_at >= '2026-01-07'
  AND (payload->>'fix_applied' IS NULL)
  AND amount_cents >= 10000;