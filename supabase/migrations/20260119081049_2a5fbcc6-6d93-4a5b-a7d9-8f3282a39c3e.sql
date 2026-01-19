-- Function to fix wrong backfilled L1 commissions (5% -> 10%)
CREATE OR REPLACE FUNCTION fix_wrong_backfilled_l1_commissions(
  p_admin_id uuid,
  p_dry_run boolean DEFAULT true
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_correct_percent numeric;
  v_record record;
  v_fixed_count int := 0;
  v_total_delta_cents int := 0;
  v_details jsonb := '[]'::jsonb;
  v_old_amount int;
  v_new_amount int;
BEGIN
  -- Verify admin
  IF NOT EXISTS (
    SELECT 1 FROM user_roles 
    WHERE user_id = p_admin_id AND role IN ('admin', 'super_admin')
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Access denied');
  END IF;

  -- Get correct percent from mlm_commission_rules for S1 L1
  SELECT percent INTO v_correct_percent
  FROM mlm_commission_rules
  WHERE structure_type = 1 AND level = 1 AND is_active = true AND plan_id = 'default'
  ORDER BY effective_from DESC
  LIMIT 1;

  IF v_correct_percent IS NULL THEN
    v_correct_percent := 10; -- fallback
  END IF;

  -- Find all wrong backfilled transactions
  FOR v_record IN
    SELECT 
      t.id as transaction_id,
      t.user_id,
      t.amount_cents as old_amount,
      t.source_id,
      t.payload,
      s.amount_kzt as subscription_amount_kzt,
      p.full_name as user_name,
      sp.full_name as subscriber_name
    FROM transactions t
    JOIN subscriptions s ON s.id = t.source_id
    JOIN profiles p ON p.id = t.user_id
    LEFT JOIN profiles sp ON sp.id = s.user_id
    WHERE t.type = 'commission'
      AND t.structure_type = 'primary'
      AND t.level = 1
      AND t.payload->>'backfill' = 'true'
      AND (t.payload->>'percent' = '5' OR t.payload->>'percent' = '5.0')
  LOOP
    v_old_amount := v_record.old_amount;
    v_new_amount := floor(v_record.subscription_amount_kzt * v_correct_percent / 100);
    
    v_details := v_details || jsonb_build_array(jsonb_build_object(
      'transaction_id', v_record.transaction_id,
      'user_id', v_record.user_id,
      'user_name', v_record.user_name,
      'subscriber_name', v_record.subscriber_name,
      'old_amount', v_old_amount,
      'new_amount', v_new_amount,
      'delta', v_new_amount - v_old_amount,
      'subscription_amount_kzt', v_record.subscription_amount_kzt
    ));
    
    IF NOT p_dry_run THEN
      -- Update the transaction
      UPDATE transactions
      SET 
        amount_cents = v_new_amount,
        payload = payload || jsonb_build_object(
          'percent', v_correct_percent,
          'subscription_amount_kzt', v_record.subscription_amount_kzt,
          'fix_applied', true,
          'fix_applied_at', now()::text,
          'old_amount_cents', v_old_amount,
          'old_percent', 5
        ),
        updated_at = now()
      WHERE id = v_record.transaction_id;
    END IF;
    
    v_fixed_count := v_fixed_count + 1;
    v_total_delta_cents := v_total_delta_cents + (v_new_amount - v_old_amount);
  END LOOP;

  -- Log admin action
  IF NOT p_dry_run AND v_fixed_count > 0 THEN
    INSERT INTO admin_actions (
      admin_id, action_type, target_type, target_id, comment, metadata
    ) VALUES (
      p_admin_id,
      'fix_wrong_backfilled_commissions',
      'transactions',
      NULL,
      'Fixed ' || v_fixed_count || ' L1 backfill transactions from 5% to ' || v_correct_percent || '%',
      jsonb_build_object(
        'fixed_count', v_fixed_count,
        'total_delta_cents', v_total_delta_cents,
        'correct_percent', v_correct_percent
      )
    );
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'dry_run', p_dry_run,
    'fixed_count', v_fixed_count,
    'total_delta_cents', v_total_delta_cents,
    'correct_percent', v_correct_percent,
    'details', v_details
  );
END;
$$;