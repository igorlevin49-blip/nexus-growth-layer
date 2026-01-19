-- Drop old function variants and recreate with correct signature
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
  -- Verify admin
  IF NOT EXISTS (
    SELECT 1 FROM user_roles 
    WHERE user_id = p_admin_id AND role IN ('admin', 'super_admin')
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Access denied');
  END IF;

  -- Get correct percent from mlm_commission_rules for S1 L1
  SELECT percent INTO v_percent
  FROM mlm_commission_rules
  WHERE structure_type = 1 AND level = 1 AND is_active = true AND plan_id = 'default'
  ORDER BY effective_from DESC
  LIMIT 1;

  IF v_percent IS NULL THEN
    v_percent := 10; -- fallback default
  END IF;

  -- Find missing L1 commissions
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
        user_id,
        type,
        amount_cents,
        currency,
        status,
        structure_type,
        level,
        source_id,
        source_ref,
        frozen_until,
        payload
      ) VALUES (
        v_record.sponsor_id,
        'commission',
        v_commission_amount,
        'KZT',
        'frozen',
        'primary',
        1,
        v_record.subscription_id,
        'subscription:' || v_record.subscription_id::text || ':L1:' || v_record.sponsor_id::text || ':backfill_' || to_char(now(), 'YYYYMMDDHH24MISS'),
        v_frozen_until,
        jsonb_build_object(
          'structure', 'S1',
          'level', 1,
          'percent', v_percent,
          'subscription_amount_kzt', v_record.amount_kzt,
          'subscriber_id', v_record.subscriber_id,
          'subscriber_name', v_record.subscriber_name,
          'source_user_id', v_record.subscriber_id,
          'source_user_name', v_record.subscriber_name,
          'backfill', true,
          'backfill_at', now()
        )
      );
    END IF;
    
    v_created_count := v_created_count + 1;
    v_total_amount := v_total_amount + v_commission_amount;
  END LOOP;

  -- Sync subscription_active flags
  IF NOT p_dry_run THEN
    WITH synced AS (
      UPDATE profiles p
      SET subscription_active = EXISTS (
        SELECT 1 FROM subscriptions s 
        WHERE s.user_id = p.id 
          AND s.status = 'active' 
          AND (s.expires_at IS NULL OR s.expires_at > now())
      )
      WHERE subscription_active IS DISTINCT FROM EXISTS (
        SELECT 1 FROM subscriptions s 
        WHERE s.user_id = p.id 
          AND s.status = 'active' 
          AND (s.expires_at IS NULL OR s.expires_at > now())
      )
      RETURNING id
    )
    SELECT count(*) INTO v_profiles_synced FROM synced;
  END IF;

  -- Log admin action
  IF NOT p_dry_run AND v_created_count > 0 THEN
    INSERT INTO admin_actions (
      admin_id, action_type, target_type, comment, metadata
    ) VALUES (
      p_admin_id,
      'backfill_l1_commissions',
      'transactions',
      'Created ' || v_created_count || ' missing L1 commissions totaling ' || v_total_amount || ' KZT',
      jsonb_build_object(
        'created_count', v_created_count,
        'total_amount', v_total_amount,
        'percent_used', v_percent,
        'profiles_synced', v_profiles_synced,
        'target_sponsor_id', p_target_sponsor_id
      )
    );
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'dry_run', p_dry_run,
    'created_count', v_created_count,
    'total_amount_kzt', v_total_amount,
    'percent_used', v_percent,
    'profiles_synced', v_profiles_synced,
    'details', v_details
  );
END;
$$;