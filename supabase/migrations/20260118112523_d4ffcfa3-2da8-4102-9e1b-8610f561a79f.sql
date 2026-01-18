-- Create comprehensive backfill function that finds ALL missing L1 commissions
CREATE OR REPLACE FUNCTION backfill_all_missing_l1_commissions(
  p_admin_id uuid,
  p_dry_run boolean DEFAULT true,
  p_target_sponsor_id uuid DEFAULT NULL
)
RETURNS json AS $$
DECLARE
  v_created_count int := 0;
  v_total_amount bigint := 0;
  v_details jsonb := '[]'::jsonb;
  v_record record;
  v_new_tx_id uuid;
  v_freeze_until timestamptz;
  v_commission_amount bigint;
BEGIN
  -- Verify admin
  IF NOT (has_role(p_admin_id, 'admin') OR has_role(p_admin_id, 'superadmin')) THEN
    RETURN json_build_object('success', false, 'error', 'Unauthorized');
  END IF;

  -- Find all active subscriptions where the sponsor should have received L1 commission but didn't
  FOR v_record IN
    SELECT 
      sub_p.id as subscriber_id,
      sub_p.full_name as subscriber_name,
      sub_p.email as subscriber_email,
      sub_p.sponsor_id,
      sponsor_p.full_name as sponsor_name,
      sponsor_p.email as sponsor_email,
      sponsor_p.subscription_status as sponsor_status,
      s.id as subscription_id,
      s.amount_kzt,
      s.paid_at,
      s.is_marketing_free_access
    FROM subscriptions s
    JOIN profiles sub_p ON sub_p.id = s.user_id
    JOIN profiles sponsor_p ON sponsor_p.id = sub_p.sponsor_id
    WHERE s.status = 'active'
      AND s.is_marketing_free_access = false
      AND sponsor_p.subscription_status = 'active'
      AND (p_target_sponsor_id IS NULL OR sub_p.sponsor_id = p_target_sponsor_id)
      -- Exclude if L1 commission already exists for this sponsor
      AND NOT EXISTS (
        SELECT 1 FROM transactions t
        WHERE t.user_id = sub_p.sponsor_id
          AND t.source_id = s.id
          AND t.type = 'commission'
          AND t.level = 1
          AND t.structure_type = 'primary'
      )
      -- Also check source_ref pattern used in backfills
      AND NOT EXISTS (
        SELECT 1 FROM transactions t
        WHERE t.user_id = sub_p.sponsor_id
          AND t.source_ref LIKE '%' || s.id::text || '%'
          AND t.type = 'commission'
          AND t.level = 1
          AND t.structure_type = 'primary'
      )
    ORDER BY s.paid_at
  LOOP
    -- Calculate commission amount (5% of subscription)
    v_commission_amount := (v_record.amount_kzt * 5 / 100)::bigint;
    
    -- Freeze for 14 days from subscription paid_at
    v_freeze_until := v_record.paid_at + interval '14 days';
    
    IF p_dry_run THEN
      v_details := v_details || jsonb_build_object(
        'sponsor_id', v_record.sponsor_id,
        'sponsor_name', v_record.sponsor_name,
        'subscriber_name', v_record.subscriber_name,
        'subscription_id', v_record.subscription_id,
        'subscription_amount', v_record.amount_kzt,
        'level', 1,
        'amount_kzt', v_commission_amount,
        'freeze_until', v_freeze_until,
        'action', 'would_create'
      );
      v_created_count := v_created_count + 1;
      v_total_amount := v_total_amount + v_commission_amount;
    ELSE
      -- Create the commission transaction
      INSERT INTO transactions (
        user_id,
        type,
        amount_cents,
        currency,
        status,
        frozen_until,
        source_id,
        source_ref,
        structure_type,
        level,
        payload
      ) VALUES (
        v_record.sponsor_id,
        'commission',
        v_commission_amount,
        'KZT',
        'frozen',
        v_freeze_until,
        v_record.subscription_id,
        'subscription',
        'primary',
        1,
        jsonb_build_object(
          'backfill', true,
          'backfill_date', now(),
          'backfill_reason', 'Missing L1 commission recovery',
          'subscriber_id', v_record.subscriber_id,
          'subscriber_name', v_record.subscriber_name,
          'subscription_amount', v_record.amount_kzt,
          'percent', 5
        )
      )
      RETURNING id INTO v_new_tx_id;
      
      v_details := v_details || jsonb_build_object(
        'sponsor_id', v_record.sponsor_id,
        'sponsor_name', v_record.sponsor_name,
        'subscriber_name', v_record.subscriber_name,
        'subscription_id', v_record.subscription_id,
        'level', 1,
        'amount_kzt', v_commission_amount,
        'transaction_id', v_new_tx_id,
        'action', 'created'
      );
      v_created_count := v_created_count + 1;
      v_total_amount := v_total_amount + v_commission_amount;
    END IF;
  END LOOP;
  
  -- Log admin action
  IF NOT p_dry_run AND v_created_count > 0 THEN
    INSERT INTO admin_actions (admin_id, action_type, target_type, metadata, comment)
    VALUES (
      p_admin_id,
      'backfill_missing_l1_commissions',
      'transactions',
      jsonb_build_object(
        'created_count', v_created_count,
        'total_amount_kzt', v_total_amount,
        'target_sponsor_id', p_target_sponsor_id
      ),
      'Backfilled missing L1 commissions'
    );
  END IF;
  
  RETURN json_build_object(
    'success', true,
    'dry_run', p_dry_run,
    'created_count', v_created_count,
    'total_amount_kzt', v_total_amount,
    'details', v_details
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;