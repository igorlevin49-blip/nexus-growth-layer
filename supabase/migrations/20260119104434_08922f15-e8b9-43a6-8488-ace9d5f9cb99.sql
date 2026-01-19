-- Fix backfill_all_missing_multilevel_commissions to check ALL source_ref formats
CREATE OR REPLACE FUNCTION public.backfill_all_missing_multilevel_commissions(
  p_admin_id UUID,
  p_dry_run BOOLEAN DEFAULT true,
  p_days_back INTEGER DEFAULT 30
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_is_admin BOOLEAN;
  v_subscriptions RECORD;
  v_current_sponsor_id UUID;
  v_current_level INTEGER;
  v_commission_percent NUMERIC;
  v_commission_amount NUMERIC;
  v_existing_count INTEGER;
  v_source_ref TEXT;
  v_total_created INTEGER := 0;
  v_total_skipped INTEGER := 0;
  v_total_amount NUMERIC := 0;
  v_details JSONB := '[]'::JSONB;
  v_levels_stats JSONB := '{}'::JSONB;
  v_freeze_days INTEGER := 14;
  v_sponsor_subscription_status TEXT;
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
      'error', 'Unauthorized: admin rights required'
    );
  END IF;

  -- Initialize level stats
  v_levels_stats := jsonb_build_object(
    'L1', jsonb_build_object('created', 0, 'skipped', 0, 'amount', 0),
    'L2', jsonb_build_object('created', 0, 'skipped', 0, 'amount', 0),
    'L3', jsonb_build_object('created', 0, 'skipped', 0, 'amount', 0),
    'L4', jsonb_build_object('created', 0, 'skipped', 0, 'amount', 0),
    'L5', jsonb_build_object('created', 0, 'skipped', 0, 'amount', 0)
  );

  -- Find all active (paid) subscriptions in the period
  -- EXCLUDE is_marketing_free_access = true
  FOR v_subscriptions IN 
    SELECT 
      s.id as subscription_id,
      s.user_id as subscriber_id,
      s.amount_kzt,
      s.paid_at,
      p.sponsor_id as direct_sponsor_id,
      p.full_name as subscriber_name
    FROM subscriptions s
    JOIN profiles p ON p.id = s.user_id
    WHERE s.status = 'active'
      AND s.paid_at IS NOT NULL
      AND s.paid_at >= NOW() - (p_days_back || ' days')::INTERVAL
      AND COALESCE(s.is_marketing_free_access, false) = false  -- Exclude free subscriptions!
      AND COALESCE(s.is_test, false) = false
      AND COALESCE(s.is_archived, false) = false
    ORDER BY s.paid_at DESC
  LOOP
    -- Start from direct sponsor
    v_current_sponsor_id := v_subscriptions.direct_sponsor_id;
    v_current_level := 1;
    
    -- Traverse sponsor chain up to L5
    WHILE v_current_level <= 5 AND v_current_sponsor_id IS NOT NULL LOOP
      -- Get commission percent for this level
      SELECT percent INTO v_commission_percent
      FROM mlm_commission_rules
      WHERE structure_type = 1
        AND level = v_current_level
        AND is_active = true
      LIMIT 1;
      
      -- Default percentages if not found
      IF v_commission_percent IS NULL THEN
        v_commission_percent := CASE v_current_level
          WHEN 1 THEN 10
          WHEN 2 THEN 5
          WHEN 3 THEN 5
          WHEN 4 THEN 5
          WHEN 5 THEN 5
          ELSE 0
        END;
      END IF;
      
      -- Calculate commission amount (amount_kzt is already in whole KZT)
      v_commission_amount := ROUND(v_subscriptions.amount_kzt * v_commission_percent / 100);
      
      -- Check if commission already exists - CHECK ALL FORMATS!
      SELECT COUNT(*) INTO v_existing_count
      FROM transactions t
      WHERE t.user_id = v_current_sponsor_id
        AND t.type = 'commission'
        AND t.structure_type = 'primary'
        AND (
          -- Format 1: New standard format
          t.source_ref = 'subscription_' || v_subscriptions.subscription_id || '_s1_level_' || v_current_level
          -- Format 2: Old colon format (for L1 primarily)
          OR (v_current_level = 1 AND t.source_ref LIKE 'subscription:' || v_subscriptions.subscription_id::text || '%')
          -- Format 3: Plain UUID (for L1)
          OR (v_current_level = 1 AND t.source_ref = v_subscriptions.subscription_id::text)
          -- Format 4: Backfill format
          OR t.source_ref = 'backfill_subscription:' || v_subscriptions.subscription_id || ':s1:l' || v_current_level
          -- Format 5: Check by source_id + level combination
          OR (t.source_id = v_subscriptions.subscription_id AND t.level = v_current_level)
        );
      
      IF v_existing_count = 0 THEN
        -- Check sponsor's subscription status
        SELECT subscription_status INTO v_sponsor_subscription_status
        FROM profiles WHERE id = v_current_sponsor_id;
        
        v_source_ref := 'subscription_' || v_subscriptions.subscription_id || '_s1_level_' || v_current_level;
        
        IF NOT p_dry_run THEN
          -- Create the missing commission
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
            v_current_sponsor_id,
            'commission',
            v_commission_amount,  -- Already in whole KZT
            'KZT',
            'frozen',
            v_subscriptions.subscription_id,
            v_source_ref,
            v_current_level,
            'primary',
            NOW() + (v_freeze_days || ' days')::INTERVAL,
            jsonb_build_object(
              'backfill', true,
              'backfill_reason', 'multilevel_backfill_v2',
              'backfill_date', NOW(),
              'source_user_id', v_subscriptions.subscriber_id,
              'source_user_name', v_subscriptions.subscriber_name,
              'original_sponsor_status', v_sponsor_subscription_status,
              'admin_id', p_admin_id
            ),
            v_subscriptions.paid_at  -- Use original paid_at date
          )
          ON CONFLICT ON CONSTRAINT unique_source_ref DO NOTHING;
          
          -- Check if insert happened
          IF FOUND THEN
            v_total_created := v_total_created + 1;
            v_total_amount := v_total_amount + v_commission_amount;
            
            -- Update level stats
            v_levels_stats := jsonb_set(
              v_levels_stats,
              ARRAY['L' || v_current_level, 'created'],
              to_jsonb(COALESCE((v_levels_stats->'L' || v_current_level->>'created')::INTEGER, 0) + 1)
            );
            v_levels_stats := jsonb_set(
              v_levels_stats,
              ARRAY['L' || v_current_level, 'amount'],
              to_jsonb(COALESCE((v_levels_stats->'L' || v_current_level->>'amount')::NUMERIC, 0) + v_commission_amount)
            );
          END IF;
        ELSE
          -- Dry run - just count
          v_total_created := v_total_created + 1;
          v_total_amount := v_total_amount + v_commission_amount;
          
          -- Update level stats for dry run
          v_levels_stats := jsonb_set(
            v_levels_stats,
            ARRAY['L' || v_current_level, 'created'],
            to_jsonb(COALESCE((v_levels_stats->'L' || v_current_level->>'created')::INTEGER, 0) + 1)
          );
          v_levels_stats := jsonb_set(
            v_levels_stats,
            ARRAY['L' || v_current_level, 'amount'],
            to_jsonb(COALESCE((v_levels_stats->'L' || v_current_level->>'amount')::NUMERIC, 0) + v_commission_amount)
          );
          
          -- Add to details (limit to first 100)
          IF jsonb_array_length(v_details) < 100 THEN
            v_details := v_details || jsonb_build_object(
              'subscription_id', v_subscriptions.subscription_id,
              'subscriber_name', v_subscriptions.subscriber_name,
              'sponsor_id', v_current_sponsor_id,
              'level', v_current_level,
              'amount_kzt', v_commission_amount
            );
          END IF;
        END IF;
      ELSE
        v_total_skipped := v_total_skipped + 1;
        
        -- Update skipped stats
        v_levels_stats := jsonb_set(
          v_levels_stats,
          ARRAY['L' || v_current_level, 'skipped'],
          to_jsonb(COALESCE((v_levels_stats->'L' || v_current_level->>'skipped')::INTEGER, 0) + 1)
        );
      END IF;
      
      -- Move to next level sponsor
      SELECT sponsor_id INTO v_current_sponsor_id
      FROM profiles WHERE id = v_current_sponsor_id;
      
      v_current_level := v_current_level + 1;
    END LOOP;
  END LOOP;
  
  -- Log admin action if not dry run
  IF NOT p_dry_run AND v_total_created > 0 THEN
    INSERT INTO admin_actions (
      admin_id,
      action_type,
      target_type,
      metadata,
      comment
    ) VALUES (
      p_admin_id,
      'backfill_multilevel_commissions',
      'transactions',
      jsonb_build_object(
        'commissions_created', v_total_created,
        'total_amount_kzt', v_total_amount,
        'days_back', p_days_back,
        'levels_stats', v_levels_stats
      ),
      'Backfill missing multilevel commissions (L1-L5)'
    );
  END IF;

  RETURN json_build_object(
    'success', true,
    'dry_run', p_dry_run,
    'commissions_created', v_total_created,
    'commissions_skipped', v_total_skipped,
    'total_kzt', v_total_amount,
    'levels_stats', v_levels_stats,
    'details', v_details
  );
END;
$$;