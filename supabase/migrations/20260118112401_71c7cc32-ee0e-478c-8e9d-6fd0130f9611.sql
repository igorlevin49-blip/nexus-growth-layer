-- 1. Fix all 111 profiles where subscription_active doesn't match subscription_status
UPDATE profiles
SET subscription_active = true,
    updated_at = now()
WHERE subscription_status = 'active'
  AND (subscription_active = false OR subscription_active IS NULL)
  AND is_active = true
  AND deleted_at IS NULL;

-- 2. Create trigger function to auto-sync subscription_active with subscription_status
CREATE OR REPLACE FUNCTION sync_subscription_active()
RETURNS trigger AS $$
BEGIN
  -- Automatically set subscription_active based on subscription_status
  NEW.subscription_active := (NEW.subscription_status = 'active');
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- 3. Create trigger on profiles to keep subscription_active in sync
DROP TRIGGER IF EXISTS trg_sync_subscription_active ON profiles;
CREATE TRIGGER trg_sync_subscription_active
BEFORE INSERT OR UPDATE OF subscription_status ON profiles
FOR EACH ROW
EXECUTE FUNCTION sync_subscription_active();

-- 4. Create backfill function for missing commissions
CREATE OR REPLACE FUNCTION backfill_skipped_sponsor_inactive_commissions(
  p_admin_id uuid,
  p_dry_run boolean DEFAULT true
)
RETURNS json AS $$
DECLARE
  v_result json;
  v_created_count int := 0;
  v_skipped_count int := 0;
  v_total_amount bigint := 0;
  v_details jsonb := '[]'::jsonb;
  v_record record;
  v_new_tx_id uuid;
  v_freeze_until timestamptz;
  v_commission_amount bigint;
  v_sponsor_id uuid;
  v_level int;
BEGIN
  -- Verify admin
  IF NOT (has_role(p_admin_id, 'admin') OR has_role(p_admin_id, 'superadmin')) THEN
    RETURN json_build_object('success', false, 'error', 'Unauthorized');
  END IF;

  -- Find all skipped commissions where sponsor was actually active
  FOR v_record IN
    SELECT 
      al.id as log_id,
      al.user_id as subscriber_id,
      al.payload->>'sponsor_id' as sponsor_id,
      al.payload->>'subscription_id' as subscription_id,
      al.payload->>'level' as level,
      al.payload->>'reason' as reason,
      al.created_at,
      s.amount_kzt,
      s.paid_at,
      sp.full_name as sponsor_name,
      sp.email as sponsor_email,
      sp.subscription_status as sponsor_status,
      sub_p.full_name as subscriber_name
    FROM activity_log al
    JOIN subscriptions s ON s.id = (al.payload->>'subscription_id')::uuid
    JOIN profiles sp ON sp.id = (al.payload->>'sponsor_id')::uuid
    JOIN profiles sub_p ON sub_p.id = al.user_id
    WHERE al.type = 'commission_skipped'
      AND al.payload->>'reason' = 'sponsor_inactive'
      AND sp.subscription_status = 'active'
      AND s.status = 'active'
      AND s.is_marketing_free_access = false
      -- Exclude if commission already exists
      AND NOT EXISTS (
        SELECT 1 FROM transactions t
        WHERE t.source_id = s.id
          AND t.user_id = sp.id
          AND t.type = 'commission'
          AND t.structure_type = 'primary'
      )
    ORDER BY al.created_at
  LOOP
    v_sponsor_id := v_record.sponsor_id::uuid;
    v_level := COALESCE((v_record.level)::int, 1);
    
    -- Calculate commission amount (5% = 5500 for 110000 subscription)
    v_commission_amount := (v_record.amount_kzt * 5 / 100)::bigint;
    
    -- Freeze for 14 days from subscription paid_at
    v_freeze_until := COALESCE(v_record.paid_at, v_record.created_at) + interval '14 days';
    
    IF p_dry_run THEN
      v_details := v_details || jsonb_build_object(
        'sponsor_id', v_sponsor_id,
        'sponsor_name', v_record.sponsor_name,
        'subscriber_name', v_record.subscriber_name,
        'subscription_id', v_record.subscription_id,
        'level', v_level,
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
        v_sponsor_id,
        'commission',
        v_commission_amount,
        'KZT',
        'frozen',
        v_freeze_until,
        v_record.subscription_id::uuid,
        'subscription',
        'primary',
        v_level,
        jsonb_build_object(
          'backfilled', true,
          'backfill_date', now(),
          'original_skip_reason', 'sponsor_inactive',
          'subscriber_name', v_record.subscriber_name,
          'subscription_amount', v_record.amount_kzt
        )
      )
      RETURNING id INTO v_new_tx_id;
      
      v_details := v_details || jsonb_build_object(
        'sponsor_id', v_sponsor_id,
        'sponsor_name', v_record.sponsor_name,
        'subscriber_name', v_record.subscriber_name,
        'subscription_id', v_record.subscription_id,
        'level', v_level,
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
      'backfill_sponsor_inactive_commissions',
      'transactions',
      jsonb_build_object(
        'created_count', v_created_count,
        'total_amount_kzt', v_total_amount
      ),
      'Backfilled commissions skipped due to sponsor_inactive bug'
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