-- Fix the role enum value in functions
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
  -- Verify admin (superadmin without underscore)
  IF NOT EXISTS (
    SELECT 1 FROM user_roles 
    WHERE user_id = p_admin_id AND role IN ('admin', 'superadmin')
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

-- Also fix the backfill function
DROP FUNCTION IF EXISTS backfill_all_missing_l1_commissions(uuid, boolean, uuid);

CREATE OR REPLACE FUNCTION backfill_all_missing_l1_commissions(
  p_admin_id uuid,
  p_dry_run boolean DEFAULT true,
  p_target_sponsor_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_record record;
  v_commission_amount int;
  v_frozen_until timestamptz;
  v_created_count int := 0;
  v_total_amount int := 0;
  v_details jsonb := '[]'::jsonb;
  v_percent numeric;
  v_freeze_days int := 7;
  v_profiles_synced int := 0;
BEGIN
  -- Verify admin (superadmin without underscore)
  IF NOT EXISTS (
    SELECT 1 FROM user_roles 
    WHERE user_id = p_admin_id AND role IN ('admin', 'superadmin')
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Access denied');
  END IF;

  SELECT percent INTO v_percent
  FROM mlm_commission_rules
  WHERE structure_type = 1 AND level = 1 AND is_active = true AND plan_id = 'default'
  ORDER BY effective_from DESC
  LIMIT 1;

  IF v_percent IS NULL THEN
    v_percent := 10;
  END IF;

  FOR v_record IN
    SELECT 
      s.id as subscription_id,
      s.user_id as subscriber_id,
      s.amount_kzt,
      s.paid_at,
      p.sponsor_id,
      p.full_name as subscriber_name,
      sp.full_name as sponsor_name
    FROM subscriptions s
    JOIN profiles p ON p.id = s.user_id
    LEFT JOIN profiles sp ON sp.id = p.sponsor_id
    WHERE s.status = 'active'
      AND s.paid_at IS NOT NULL
      AND s.is_marketing_free_access IS NOT TRUE
      AND p.sponsor_id IS NOT NULL
      AND (p_target_sponsor_id IS NULL OR p.sponsor_id = p_target_sponsor_id)
      AND NOT EXISTS (
        SELECT 1 FROM transactions t
        WHERE t.source_id = s.id
          AND t.user_id = p.sponsor_id
          AND t.type = 'commission'
          AND t.structure_type = 'primary'
          AND t.level = 1
      )
    ORDER BY s.paid_at
  LOOP
    v_commission_amount := floor(v_record.amount_kzt * v_percent / 100);
    v_frozen_until := COALESCE(v_record.paid_at, now()) + (v_freeze_days || ' days')::interval;
    
    v_details := v_details || jsonb_build_array(jsonb_build_object(
      'subscription_id', v_record.subscription_id,
      'sponsor_id', v_record.sponsor_id,
      'sponsor_name', v_record.sponsor_name,
      'subscriber_id', v_record.subscriber_id,
      'subscriber_name', v_record.subscriber_name,
      'subscription_amount_kzt', v_record.amount_kzt,
      'commission_amount', v_commission_amount,
      'percent', v_percent
    ));
    
    IF NOT p_dry_run THEN
      INSERT INTO transactions (
        user_id, type, amount_cents, currency, status, structure_type, level,
        source_id, source_ref, frozen_until, payload
      ) VALUES (
        v_record.sponsor_id, 'commission', v_commission_amount, 'KZT', 'frozen', 'primary', 1,
        v_record.subscription_id,
        'subscription:' || v_record.subscription_id::text || ':L1:' || v_record.sponsor_id::text || ':backfill_' || to_char(now(), 'YYYYMMDDHH24MISS'),
        v_frozen_until,
        jsonb_build_object(
          'structure', 'S1', 'level', 1, 'percent', v_percent,
          'subscription_amount_kzt', v_record.amount_kzt,
          'subscriber_id', v_record.subscriber_id,
          'subscriber_name', v_record.subscriber_name,
          'source_user_id', v_record.subscriber_id,
          'source_user_name', v_record.subscriber_name,
          'backfill', true, 'backfill_at', now()
        )
      );
    END IF;
    
    v_created_count := v_created_count + 1;
    v_total_amount := v_total_amount + v_commission_amount;
  END LOOP;

  IF NOT p_dry_run THEN
    WITH synced AS (
      UPDATE profiles p
      SET subscription_active = EXISTS (
        SELECT 1 FROM subscriptions s 
        WHERE s.user_id = p.id AND s.status = 'active' 
          AND (s.expires_at IS NULL OR s.expires_at > now())
      )
      WHERE subscription_active IS DISTINCT FROM EXISTS (
        SELECT 1 FROM subscriptions s 
        WHERE s.user_id = p.id AND s.status = 'active' 
          AND (s.expires_at IS NULL OR s.expires_at > now())
      )
      RETURNING id
    )
    SELECT count(*) INTO v_profiles_synced FROM synced;
  END IF;

  IF NOT p_dry_run AND v_created_count > 0 THEN
    INSERT INTO admin_actions (admin_id, action_type, target_type, comment, metadata)
    VALUES (p_admin_id, 'backfill_l1_commissions', 'transactions',
      'Created ' || v_created_count || ' missing L1 commissions totaling ' || v_total_amount || ' KZT',
      jsonb_build_object('created_count', v_created_count, 'total_amount', v_total_amount,
        'percent_used', v_percent, 'profiles_synced', v_profiles_synced, 'target_sponsor_id', p_target_sponsor_id)
    );
  END IF;

  RETURN jsonb_build_object(
    'success', true, 'dry_run', p_dry_run, 'created_count', v_created_count,
    'total_amount_kzt', v_total_amount, 'percent_used', v_percent,
    'profiles_synced', v_profiles_synced, 'details', v_details
  );
END;
$$;