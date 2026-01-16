-- =============================================================================
-- Backfill Missing L3/L4/L5 Commissions for S1 Structure
-- =============================================================================
-- This migration creates a function to backfill missing commissions for levels 3-5
-- where the sponsor has enough direct referrals to unlock those levels.
-- 
-- Unlock requirements for S1:
-- L1: 0 referrals (always unlocked)
-- L2: 1 referral
-- L3: 3 referrals  
-- L4: 5 referrals
-- L5: 10 referrals
-- =============================================================================

CREATE OR REPLACE FUNCTION backfill_missing_multilevel_commissions(
  p_admin_id UUID,
  p_dry_run BOOLEAN DEFAULT true,
  p_target_user_id UUID DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_is_admin BOOLEAN;
  v_result JSON;
  v_subscriptions_processed INT := 0;
  v_commissions_created INT := 0;
  v_commissions_skipped INT := 0;
  v_total_kzt NUMERIC := 0;
  v_details JSON[] := ARRAY[]::JSON[];
  v_commission_percent NUMERIC := 5.0;
  v_freeze_days INT := 14;
  v_unlock_requirements INT[] := ARRAY[0, 1, 3, 5, 10]; -- L1-L5 unlock requirements
  rec RECORD;
BEGIN
  -- Check admin rights
  SELECT EXISTS(
    SELECT 1 FROM user_roles 
    WHERE user_id = p_admin_id 
    AND role IN ('admin', 'superadmin')
  ) INTO v_is_admin;
  
  IF NOT v_is_admin THEN
    RETURN json_build_object(
      'success', false,
      'error', 'Access denied: admin rights required'
    );
  END IF;

  -- Find all missing commissions for L1-L5
  FOR rec IN
    WITH network_hierarchy AS (
      -- Build network hierarchy recursively
      SELECT 
        r.referrer_id,
        r.referred_user_id,
        1 as level
      FROM referrals r
      WHERE r.structure_type = 1
      
      UNION ALL
      
      SELECT 
        nh.referrer_id,
        r.referred_user_id,
        nh.level + 1
      FROM network_hierarchy nh
      JOIN referrals r ON r.referrer_id = nh.referred_user_id AND r.structure_type = 1
      WHERE nh.level < 5
    ),
    sponsor_referral_counts AS (
      -- Count active L1 referrals for each potential sponsor
      SELECT 
        r.referrer_id,
        COUNT(*) FILTER (WHERE p.is_active = true AND p.subscription_status = 'active') as active_l1_count
      FROM referrals r
      JOIN profiles p ON p.id = r.referred_user_id
      WHERE r.structure_type = 1
      GROUP BY r.referrer_id
    ),
    missing_commissions AS (
      SELECT 
        nh.referrer_id as sponsor_id,
        nh.referred_user_id as subscriber_id,
        nh.level,
        s.id as subscription_id,
        s.amount_kzt,
        s.paid_at,
        sp.full_name as sponsor_name,
        sub_p.full_name as subscriber_name,
        src.active_l1_count,
        -- Calculate commission amount (5% of subscription)
        ROUND(s.amount_kzt * 0.05) as commission_kzt,
        -- Calculate freeze until date (14 days from paid_at)
        s.paid_at + INTERVAL '14 days' as freeze_until
      FROM network_hierarchy nh
      JOIN subscriptions s ON s.user_id = nh.referred_user_id
      JOIN profiles sp ON sp.id = nh.referrer_id
      JOIN profiles sub_p ON sub_p.id = nh.referred_user_id
      LEFT JOIN sponsor_referral_counts src ON src.referrer_id = nh.referrer_id
      WHERE s.status = 'active'
        AND s.paid_at IS NOT NULL
        AND s.is_marketing_free_access IS NOT TRUE
        AND s.is_test IS NOT TRUE
        AND sp.is_active = true
        AND sp.subscription_status = 'active'
        -- Filter by target user if specified
        AND (p_target_user_id IS NULL OR nh.referrer_id = p_target_user_id)
        -- Check if level is unlocked based on active L1 count
        AND COALESCE(src.active_l1_count, 0) >= (
          CASE nh.level 
            WHEN 1 THEN 0
            WHEN 2 THEN 1
            WHEN 3 THEN 3
            WHEN 4 THEN 5
            WHEN 5 THEN 10
          END
        )
        -- Check commission doesn't already exist
        AND NOT EXISTS (
          SELECT 1 FROM transactions t
          WHERE t.source_id = s.id
            AND t.user_id = nh.referrer_id
            AND t.type = 'commission'
            AND t.structure_type = 'S1'
            AND t.level = nh.level
        )
    )
    SELECT * FROM missing_commissions
    ORDER BY sponsor_id, level, subscription_id
  LOOP
    v_subscriptions_processed := v_subscriptions_processed + 1;
    
    IF NOT p_dry_run THEN
      -- Create the commission transaction
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
        rec.sponsor_id,
        'commission',
        rec.commission_kzt * 100, -- Convert to cents
        'KZT',
        CASE 
          WHEN rec.freeze_until > NOW() THEN 'frozen'
          ELSE 'available'
        END,
        rec.subscription_id,
        'subscription',
        rec.level,
        'S1',
        CASE 
          WHEN rec.freeze_until > NOW() THEN rec.freeze_until
          ELSE NULL
        END,
        jsonb_build_object(
          'backfill', true,
          'backfill_date', NOW(),
          'admin_id', p_admin_id,
          'subscriber_name', rec.subscriber_name,
          'subscription_amount_kzt', rec.amount_kzt
        )
      );
      
      v_commissions_created := v_commissions_created + 1;
      
      -- Update balance if commission is available (not frozen)
      IF rec.freeze_until <= NOW() THEN
        UPDATE profiles 
        SET balance = COALESCE(balance, 0) + (rec.commission_kzt * 100)
        WHERE id = rec.sponsor_id;
      END IF;
    ELSE
      v_commissions_created := v_commissions_created + 1;
    END IF;
    
    v_total_kzt := v_total_kzt + rec.commission_kzt;
    
    -- Add to details
    v_details := array_append(v_details, json_build_object(
      'sponsor_id', rec.sponsor_id,
      'sponsor_name', rec.sponsor_name,
      'subscriber_id', rec.subscriber_id,
      'subscriber_name', rec.subscriber_name,
      'subscription_id', rec.subscription_id,
      'level', rec.level,
      'amount_kzt', rec.amount_kzt,
      'commission_kzt', rec.commission_kzt,
      'freeze_until', rec.freeze_until,
      'active_l1_count', rec.active_l1_count
    ));
  END LOOP;

  -- Log admin action if not dry run
  IF NOT p_dry_run AND v_commissions_created > 0 THEN
    INSERT INTO admin_audit (
      admin_id,
      action_type,
      target_type,
      target_id,
      metadata
    ) VALUES (
      p_admin_id,
      'backfill_multilevel_commissions',
      'system',
      COALESCE(p_target_user_id::TEXT, 'all'),
      jsonb_build_object(
        'subscriptions_processed', v_subscriptions_processed,
        'commissions_created', v_commissions_created,
        'total_kzt', v_total_kzt,
        'dry_run', p_dry_run
      )
    );
  END IF;

  RETURN json_build_object(
    'success', true,
    'dry_run', p_dry_run,
    'subscriptions_processed', v_subscriptions_processed,
    'commissions_created', v_commissions_created,
    'commissions_skipped', v_commissions_skipped,
    'total_kzt', v_total_kzt,
    'details', CASE WHEN array_length(v_details, 1) <= 100 THEN to_json(v_details) ELSE json_build_object('count', array_length(v_details, 1), 'truncated', true) END
  );
END;
$$;