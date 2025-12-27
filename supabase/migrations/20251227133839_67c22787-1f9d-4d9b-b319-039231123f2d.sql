-- Fix historical level unlock violations for S1 commissions
-- These are commissions that were incorrectly awarded before unlock checks were added

-- Create a function to fix these violations (mark as failed/refunded)
CREATE OR REPLACE FUNCTION fix_unlock_level_violations()
RETURNS TABLE(
  fixed_count integer,
  total_amount_cents bigint,
  details jsonb
) 
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_fixed_count integer := 0;
  v_total_amount bigint := 0;
  v_details jsonb := '[]'::jsonb;
  v_unlock_levels jsonb;
  v_record record;
BEGIN
  -- Get unlock_levels settings
  SELECT value INTO v_unlock_levels
  FROM mlm_settings
  WHERE key = 'unlock_levels';
  
  IF v_unlock_levels IS NULL THEN
    v_unlock_levels := '{"l2": 3, "l3": 5, "l4": 8, "l5": 10}'::jsonb;
  END IF;

  -- Find all violations and mark them as failed
  FOR v_record IN
    SELECT 
      t.id,
      t.user_id,
      t.level,
      t.amount_cents,
      t.status,
      p.direct_referrals_count,
      (v_unlock_levels->('l' || t.level))::integer as required_referrals
    FROM transactions t
    JOIN profiles p ON t.user_id = p.id
    WHERE t.type = 'commission'
    AND t.level >= 2
    AND t.structure_type = 'primary'
    AND t.status IN ('frozen', 'completed')
    AND p.direct_referrals_count < (v_unlock_levels->('l' || t.level))::integer
  LOOP
    -- Update transaction to failed status
    UPDATE transactions
    SET 
      status = 'failed',
      payload = COALESCE(payload, '{}'::jsonb) || jsonb_build_object(
        'fixed_at', now(),
        'fix_reason', 'unlock_level_violation',
        'had_referrals', v_record.direct_referrals_count,
        'required_referrals', v_record.required_referrals,
        'original_status', v_record.status
      )
    WHERE id = v_record.id;

    -- If was completed, deduct from balance
    IF v_record.status = 'completed' THEN
      UPDATE profiles
      SET balance = GREATEST(0, COALESCE(balance, 0) - v_record.amount_cents)
      WHERE id = v_record.user_id;
    END IF;

    v_fixed_count := v_fixed_count + 1;
    v_total_amount := v_total_amount + v_record.amount_cents;
    
    v_details := v_details || jsonb_build_object(
      'transaction_id', v_record.id,
      'user_id', v_record.user_id,
      'level', v_record.level,
      'amount', v_record.amount_cents,
      'had_referrals', v_record.direct_referrals_count,
      'required', v_record.required_referrals
    );
  END LOOP;

  RETURN QUERY SELECT v_fixed_count, v_total_amount, v_details;
END;
$$;

-- Create admin-only RPC wrapper
CREATE OR REPLACE FUNCTION admin_fix_unlock_violations(p_admin_id uuid, p_dry_run boolean DEFAULT true)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_result record;
  v_violations jsonb;
BEGIN
  -- Check admin role
  IF NOT (has_role(p_admin_id, 'admin') OR has_role(p_admin_id, 'superadmin')) THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  IF p_dry_run THEN
    -- Just return what would be fixed
    SELECT jsonb_agg(row_to_json(v))
    INTO v_violations
    FROM (
      SELECT 
        t.id as transaction_id,
        t.user_id,
        p.full_name,
        t.level,
        t.amount_cents,
        t.status,
        p.direct_referrals_count,
        CASE 
          WHEN t.level = 2 THEN 3
          WHEN t.level = 3 THEN 5
          WHEN t.level = 4 THEN 8
          WHEN t.level = 5 THEN 10
          ELSE 0
        END as required_referrals
      FROM transactions t
      JOIN profiles p ON t.user_id = p.id
      WHERE t.type = 'commission'
      AND t.level >= 2
      AND t.structure_type = 'primary'
      AND t.status IN ('frozen', 'completed')
      AND p.direct_referrals_count < CASE 
          WHEN t.level = 2 THEN 3
          WHEN t.level = 3 THEN 5
          WHEN t.level = 4 THEN 8
          WHEN t.level = 5 THEN 10
          ELSE 0
        END
    ) v;
    
    RETURN jsonb_build_object(
      'dry_run', true,
      'violations_count', COALESCE(jsonb_array_length(v_violations), 0),
      'violations', COALESCE(v_violations, '[]'::jsonb)
    );
  ELSE
    -- Actually fix
    SELECT * INTO v_result FROM fix_unlock_level_violations();
    
    -- Log admin action
    INSERT INTO admin_audit (admin_id, action_type, target_type, target_id, metadata)
    VALUES (p_admin_id, 'fix_unlock_violations', 'transactions', gen_random_uuid(), 
      jsonb_build_object('fixed_count', v_result.fixed_count, 'total_amount', v_result.total_amount_cents));
    
    RETURN jsonb_build_object(
      'success', true,
      'fixed_count', v_result.fixed_count,
      'total_amount_cents', v_result.total_amount_cents,
      'details', v_result.details
    );
  END IF;
END;
$$;

-- Create comprehensive audit summary function
CREATE OR REPLACE FUNCTION admin_commission_audit_summary(p_admin_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_unlock_violations jsonb;
  v_balance_issues jsonb;
  v_marketing_free_issues jsonb;
  v_commission_stats jsonb;
BEGIN
  -- Check admin role
  IF NOT (has_role(p_admin_id, 'admin') OR has_role(p_admin_id, 'superadmin')) THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  -- 1. Unlock level violations
  SELECT jsonb_build_object(
    'count', COUNT(*),
    'total_amount_cents', COALESCE(SUM(t.amount_cents), 0),
    'by_level', jsonb_object_agg(
      'L' || t.level, 
      jsonb_build_object('count', COUNT(*), 'amount', SUM(t.amount_cents))
    )
  )
  INTO v_unlock_violations
  FROM transactions t
  JOIN profiles p ON t.user_id = p.id
  WHERE t.type = 'commission'
  AND t.level >= 2
  AND t.structure_type = 'primary'
  AND t.status IN ('frozen', 'completed')
  AND p.direct_referrals_count < CASE 
      WHEN t.level = 2 THEN 3
      WHEN t.level = 3 THEN 5
      WHEN t.level = 4 THEN 8
      WHEN t.level = 5 THEN 10
      ELSE 0
    END;

  -- 2. Balance integrity issues
  SELECT jsonb_build_object(
    'count', COUNT(*),
    'issues', jsonb_agg(jsonb_build_object(
      'user_id', sub.user_id,
      'profile_balance', sub.profile_balance,
      'calculated_balance', sub.calculated_balance,
      'difference', sub.difference
    ))
  )
  INTO v_balance_issues
  FROM (
    SELECT 
      p.id as user_id,
      COALESCE(p.balance, 0) as profile_balance,
      COALESCE(SUM(CASE 
        WHEN t.type = 'commission' AND t.status = 'completed' THEN t.amount_cents
        WHEN t.type = 'withdrawal' AND t.status = 'completed' THEN -t.amount_cents
        ELSE 0
      END), 0) as calculated_balance,
      COALESCE(p.balance, 0) - COALESCE(SUM(CASE 
        WHEN t.type = 'commission' AND t.status = 'completed' THEN t.amount_cents
        WHEN t.type = 'withdrawal' AND t.status = 'completed' THEN -t.amount_cents
        ELSE 0
      END), 0) as difference
    FROM profiles p
    LEFT JOIN transactions t ON t.user_id = p.id
    WHERE p.is_active = true
    GROUP BY p.id, p.balance
    HAVING ABS(COALESCE(p.balance, 0) - COALESCE(SUM(CASE 
        WHEN t.type = 'commission' AND t.status = 'completed' THEN t.amount_cents
        WHEN t.type = 'withdrawal' AND t.status = 'completed' THEN -t.amount_cents
        ELSE 0
      END), 0)) > 1
  ) sub;

  -- 3. Marketing free commissions
  SELECT jsonb_build_object(
    'count', COUNT(*),
    'total_amount_cents', COALESCE(SUM(t.amount_cents), 0)
  )
  INTO v_marketing_free_issues
  FROM transactions t
  JOIN subscriptions s ON t.source_id = s.id
  WHERE t.type = 'commission'
  AND t.structure_type = 'primary'
  AND s.is_marketing_free_access = true;

  -- 4. Commission stats
  SELECT jsonb_build_object(
    's1_total', (SELECT COALESCE(SUM(amount_cents), 0) FROM transactions WHERE type = 'commission' AND structure_type = 'primary'),
    's1_frozen', (SELECT COALESCE(SUM(amount_cents), 0) FROM transactions WHERE type = 'commission' AND structure_type = 'primary' AND status = 'frozen'),
    's1_completed', (SELECT COALESCE(SUM(amount_cents), 0) FROM transactions WHERE type = 'commission' AND structure_type = 'primary' AND status = 'completed'),
    's2_total', (SELECT COALESCE(SUM(amount_cents), 0) FROM transactions WHERE type = 'commission' AND structure_type = 'secondary'),
    's2_frozen', (SELECT COALESCE(SUM(amount_cents), 0) FROM transactions WHERE type = 'commission' AND structure_type = 'secondary' AND status = 'frozen'),
    's2_completed', (SELECT COALESCE(SUM(amount_cents), 0) FROM transactions WHERE type = 'commission' AND structure_type = 'secondary' AND status = 'completed')
  )
  INTO v_commission_stats;

  RETURN jsonb_build_object(
    'timestamp', now(),
    'unlock_violations', v_unlock_violations,
    'balance_issues', v_balance_issues,
    'marketing_free_issues', v_marketing_free_issues,
    'commission_stats', v_commission_stats
  );
END;
$$;