
-- Обновить функцию admin_fix_early_unlock_commissions с логированием в activity_log
CREATE OR REPLACE FUNCTION admin_fix_early_unlock_commissions(
  p_admin_id uuid,
  p_dry_run boolean DEFAULT true,
  p_days_back integer DEFAULT 90
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_result json;
  v_violations_found integer := 0;
  v_violations_fixed integer := 0;
  v_total_amount_fixed integer := 0;
  v_rec record;
BEGIN
  -- Check admin role
  IF NOT (has_role(p_admin_id, 'admin') OR has_role(p_admin_id, 'superadmin')) THEN
    RAISE EXCEPTION 'Access denied: admin role required';
  END IF;

  -- Найти все нарушения
  FOR v_rec IN 
    SELECT * FROM admin_find_early_unlock_commissions(p_admin_id, p_days_back)
  LOOP
    v_violations_found := v_violations_found + 1;
    v_total_amount_fixed := v_total_amount_fixed + v_rec.amount_cents;
    
    IF NOT p_dry_run THEN
      -- Для frozen комиссий - просто помечаем как failed
      IF v_rec.status = 'frozen' THEN
        UPDATE transactions 
        SET status = 'failed',
            payload = COALESCE(payload, '{}'::jsonb) || jsonb_build_object(
              'early_unlock_fix', true,
              'fixed_at', now(),
              'fixed_by', p_admin_id,
              'reason', 'Level ' || v_rec.level || ' was not unlocked at subscription time. Had ' || 
                        v_rec.actual_referrals_at_time || ' referrals, needed ' || v_rec.required_referrals
            )
        WHERE id = v_rec.transaction_id;
        
        -- Логируем в activity_log
        INSERT INTO activity_log (user_id, type, payload)
        VALUES (
          v_rec.user_id,
          'early_commission_fix',
          jsonb_build_object(
            'transaction_id', v_rec.transaction_id,
            'amount_cents', v_rec.amount_cents,
            'level', v_rec.level,
            'structure_type', v_rec.structure_type,
            'subscriber_name', v_rec.subscriber_name,
            'subscription_paid_at', v_rec.subscription_paid_at,
            'actual_referrals', v_rec.actual_referrals_at_time,
            'required_referrals', v_rec.required_referrals,
            'previous_status', 'frozen',
            'fixed_by', p_admin_id
          )
        );
        
        v_violations_fixed := v_violations_fixed + 1;
        
      -- Для completed комиссий - нужно откатить баланс
      ELSIF v_rec.status = 'completed' THEN
        -- Уменьшить баланс пользователя
        UPDATE profiles 
        SET balance = GREATEST(0, COALESCE(balance, 0) - v_rec.amount_cents)
        WHERE id = v_rec.user_id;
        
        -- Пометить транзакцию как failed
        UPDATE transactions 
        SET status = 'failed',
            payload = COALESCE(payload, '{}'::jsonb) || jsonb_build_object(
              'early_unlock_fix', true,
              'fixed_at', now(),
              'fixed_by', p_admin_id,
              'balance_reversed', true,
              'reason', 'Level ' || v_rec.level || ' was not unlocked at subscription time. Had ' || 
                        v_rec.actual_referrals_at_time || ' referrals, needed ' || v_rec.required_referrals
            )
        WHERE id = v_rec.transaction_id;
        
        -- Логируем в activity_log
        INSERT INTO activity_log (user_id, type, payload)
        VALUES (
          v_rec.user_id,
          'early_commission_fix',
          jsonb_build_object(
            'transaction_id', v_rec.transaction_id,
            'amount_cents', v_rec.amount_cents,
            'level', v_rec.level,
            'structure_type', v_rec.structure_type,
            'subscriber_name', v_rec.subscriber_name,
            'subscription_paid_at', v_rec.subscription_paid_at,
            'actual_referrals', v_rec.actual_referrals_at_time,
            'required_referrals', v_rec.required_referrals,
            'previous_status', 'completed',
            'balance_reversed', true,
            'fixed_by', p_admin_id
          )
        );
        
        v_violations_fixed := v_violations_fixed + 1;
      END IF;
    END IF;
  END LOOP;

  -- Логируем итоговый результат операции (если не dry run и были исправления)
  IF NOT p_dry_run AND v_violations_fixed > 0 THEN
    INSERT INTO activity_log (user_id, type, payload)
    VALUES (
      p_admin_id,
      'early_commission_fix_batch',
      jsonb_build_object(
        'violations_found', v_violations_found,
        'violations_fixed', v_violations_fixed,
        'total_amount_cents', v_total_amount_fixed,
        'days_back', p_days_back
      )
    );
  END IF;

  v_result := json_build_object(
    'success', true,
    'dry_run', p_dry_run,
    'violations_found', v_violations_found,
    'violations_fixed', v_violations_fixed,
    'total_amount_cents', v_total_amount_fixed
  );

  RETURN v_result;
END;
$$;
