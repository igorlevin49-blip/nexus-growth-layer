
-- Function to reverse incorrect unlock level commissions
CREATE OR REPLACE FUNCTION public.reverse_unlock_level_violations(
  p_admin_id uuid,
  p_dry_run boolean DEFAULT true
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_violation RECORD;
  v_reversed_count int := 0;
  v_total_reversed_cents bigint := 0;
  v_violations jsonb := '[]'::jsonb;
  v_new_transaction_id uuid;
BEGIN
  -- Check admin rights
  IF NOT public.has_role(p_admin_id, 'superadmin') THEN
    RETURN jsonb_build_object('success', false, 'error', 'Only superadmin can reverse commissions');
  END IF;

  -- Find all violations using the audit function
  FOR v_violation IN 
    SELECT * FROM public.audit_unlock_level_violations_detailed()
  LOOP
    v_violations := v_violations || jsonb_build_object(
      'transaction_id', v_violation.transaction_id,
      'user_id', v_violation.user_id,
      'user_name', v_violation.user_name,
      'user_email', v_violation.user_email,
      'level', v_violation.level,
      'amount_cents', v_violation.amount_cents,
      'required_referrals', v_violation.required_referrals,
      'actual_referrals', v_violation.actual_referrals_at_time,
      'created_at', v_violation.created_at
    );

    IF NOT p_dry_run THEN
      -- Create reversal transaction (negative adjustment)
      INSERT INTO transactions (
        user_id,
        type,
        amount_cents,
        currency,
        status,
        structure_type,
        level,
        source_ref,
        payload
      ) VALUES (
        v_violation.user_id,
        'adjustment',
        -v_violation.amount_cents,
        'KZT',
        'completed',
        'primary',
        v_violation.level,
        'unlock_violation_reversal:' || v_violation.transaction_id,
        jsonb_build_object(
          'reason', 'Отмена комиссии: уровень ' || v_violation.level || ' не был разблокирован',
          'original_transaction_id', v_violation.transaction_id,
          'required_referrals', v_violation.required_referrals,
          'actual_referrals', v_violation.actual_referrals_at_time,
          'reversed_by', p_admin_id
        )
      )
      RETURNING id INTO v_new_transaction_id;

      -- Update user balance
      UPDATE profiles
      SET balance = COALESCE(balance, 0) - v_violation.amount_cents
      WHERE id = v_violation.user_id;

      -- Log admin action
      INSERT INTO admin_audit (admin_id, target_type, target_id, action_type, metadata, comment)
      VALUES (
        p_admin_id,
        'transaction',
        v_new_transaction_id::text,
        'commission_reversal',
        jsonb_build_object(
          'original_transaction_id', v_violation.transaction_id,
          'amount_cents', v_violation.amount_cents,
          'level', v_violation.level,
          'reason', 'unlock_level_violation'
        ),
        'Автоматическая отмена комиссии за нарушение правил разблокировки уровня'
      );
    END IF;

    v_reversed_count := v_reversed_count + 1;
    v_total_reversed_cents := v_total_reversed_cents + v_violation.amount_cents;
  END LOOP;

  RETURN jsonb_build_object(
    'success', true,
    'dry_run', p_dry_run,
    'reversed_count', v_reversed_count,
    'total_reversed_cents', v_total_reversed_cents,
    'total_reversed_kzt', v_total_reversed_cents,
    'violations', v_violations
  );
END;
$$;
