
-- Fix backfill_missing_s1_commissions - add proper type casting
CREATE OR REPLACE FUNCTION public.backfill_missing_s1_commissions(
  p_admin_id uuid,
  p_days_back integer DEFAULT 30
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_subscription RECORD;
  v_recipient RECORD;
  v_commission_percent numeric;
  v_commission_amount integer;
  v_level integer;
  v_frozen_until timestamp with time zone;
  v_processed_subscriptions integer := 0;
  v_skipped_subscriptions integer := 0;
  v_skipped_unlock integer := 0;
  v_total_commissions integer := 0;
  v_max_level integer := 5;
  v_direct_count integer;
  v_required_referrals integer;
  v_existing_count integer;
  v_status transaction_status;
BEGIN
  -- Check admin permissions
  IF NOT (has_role(p_admin_id, 'admin') OR has_role(p_admin_id, 'superadmin')) THEN
    RETURN json_build_object('success', false, 'error', 'Unauthorized');
  END IF;

  -- Loop through active subscriptions from the last N days
  FOR v_subscription IN
    SELECT 
      s.id,
      s.user_id,
      s.amount_kzt,
      s.started_at,
      p.sponsor_id
    FROM subscriptions s
    JOIN profiles p ON p.id = s.user_id
    WHERE s.status = 'active'
      AND s.started_at >= NOW() - (p_days_back || ' days')::interval
      AND p.sponsor_id IS NOT NULL
    ORDER BY s.started_at
  LOOP
    v_processed_subscriptions := v_processed_subscriptions + 1;
    
    -- For each level 1-5, find the recipient and create commission if missing
    FOR v_level IN 1..v_max_level LOOP
      -- Find recipient at this level (traverse up the sponsor chain)
      WITH RECURSIVE sponsor_chain AS (
        SELECT 
          p.id,
          p.sponsor_id,
          p.direct_referrals_count,
          1 as chain_level
        FROM profiles p
        WHERE p.id = v_subscription.sponsor_id
        
        UNION ALL
        
        SELECT 
          p.id,
          p.sponsor_id,
          p.direct_referrals_count,
          sc.chain_level + 1
        FROM profiles p
        JOIN sponsor_chain sc ON p.id = sc.sponsor_id
        WHERE sc.chain_level < v_level
      )
      SELECT id, direct_referrals_count INTO v_recipient
      FROM sponsor_chain
      WHERE chain_level = v_level
      LIMIT 1;
      
      -- Skip if no recipient at this level
      IF v_recipient.id IS NULL THEN
        CONTINUE;
      END IF;
      
      -- Check unlock level requirements
      SELECT COALESCE((value->>'referrals')::integer, v_level)
      INTO v_required_referrals
      FROM mlm_settings
      WHERE key = 'unlock_level_' || v_level;
      
      v_required_referrals := COALESCE(v_required_referrals, v_level);
      
      -- Get actual direct referrals count
      SELECT COUNT(*) INTO v_direct_count
      FROM referrals r
      WHERE r.referrer_id = v_recipient.id AND r.structure_type = 1;
      
      IF v_direct_count < v_required_referrals THEN
        v_skipped_unlock := v_skipped_unlock + 1;
        CONTINUE;
      END IF;
      
      -- Check if commission already exists for this subscription+level
      SELECT COUNT(*) INTO v_existing_count
      FROM transactions t
      WHERE t.source_ref = 'subscription_' || v_subscription.id::text || '_s1_level_' || v_level
        AND t.user_id = v_recipient.id
        AND t.type = 'commission';
      
      IF v_existing_count > 0 THEN
        CONTINUE;
      END IF;
      
      -- Get commission percent for this level
      SELECT percent INTO v_commission_percent
      FROM mlm_commission_rules
      WHERE structure_type = 1 AND level = v_level AND is_active = true
      LIMIT 1;
      
      IF v_commission_percent IS NULL THEN
        CONTINUE;
      END IF;
      
      -- Calculate commission amount (amount_kzt * percent / 100)
      v_commission_amount := ROUND(v_subscription.amount_kzt * v_commission_percent / 100)::integer;
      
      IF v_commission_amount <= 0 THEN
        CONTINUE;
      END IF;
      
      -- Set frozen period (14 days from subscription start)
      v_frozen_until := v_subscription.started_at + INTERVAL '14 days';
      
      -- Determine status
      IF v_frozen_until > NOW() THEN
        v_status := 'frozen'::transaction_status;
      ELSE
        v_status := 'completed'::transaction_status;
      END IF;
      
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
        payload,
        created_at
      ) VALUES (
        v_recipient.id,
        'commission'::transaction_type,
        v_commission_amount,
        'KZT',
        v_status,
        v_subscription.user_id,
        'subscription_' || v_subscription.id::text || '_s1_level_' || v_level,
        v_level,
        'primary'::structure_type,
        v_frozen_until,
        jsonb_build_object(
          'subscription_id', v_subscription.id,
          'subscriber_name', (SELECT full_name FROM profiles WHERE id = v_subscription.user_id),
          'backfilled', true,
          'backfill_date', NOW()
        ),
        v_subscription.started_at
      );
      
      v_total_commissions := v_total_commissions + 1;
    END LOOP;
  END LOOP;

  -- Log admin action
  INSERT INTO public.admin_actions (
    admin_id,
    action_type,
    target_type,
    metadata
  ) VALUES (
    p_admin_id,
    'backfill_s1_commissions',
    'system',
    jsonb_build_object(
      'days_back', p_days_back,
      'processed_subscriptions', v_processed_subscriptions,
      'skipped_subscriptions', v_skipped_subscriptions,
      'skipped_unlock_levels', v_skipped_unlock,
      'total_commissions_created', v_total_commissions
    )
  );

  RETURN json_build_object(
    'success', true,
    'processed_subscriptions', v_processed_subscriptions,
    'skipped_subscriptions', v_skipped_subscriptions,
    'skipped_unlock_levels', v_skipped_unlock,
    'total_commissions_created', v_total_commissions
  );
END;
$$;
