
-- Fix the function to not use non-existent constraint
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
  v_commission_amount INTEGER;
  v_existing_count INTEGER;
  v_source_ref TEXT;
  v_sponsor_subscription_status TEXT;
  v_sponsor_referrals_count INTEGER;
  v_required_referrals INTEGER;
  v_freeze_days INTEGER := 14;
  v_total_created INTEGER := 0;
  v_total_skipped INTEGER := 0;
  v_total_amount INTEGER := 0;
  v_level_stats JSONB := '{}'::jsonb;
  v_details JSONB := '[]'::jsonb;
  v_cutoff_date TIMESTAMP WITH TIME ZONE;
  v_levels_required JSONB := '{"1": 0, "2": 3, "3": 5, "4": 8, "5": 10}'::jsonb;
BEGIN
  -- Check admin rights
  SELECT EXISTS (
    SELECT 1 FROM user_roles 
    WHERE user_id = p_admin_id 
    AND role IN ('admin', 'superadmin')
  ) INTO v_is_admin;
  
  IF NOT v_is_admin THEN
    RETURN json_build_object('success', false, 'error', 'Not authorized');
  END IF;

  v_cutoff_date := NOW() - (p_days_back || ' days')::INTERVAL;

  -- Get freeze period from settings
  SELECT COALESCE((value->>'days')::INTEGER, 14)
  INTO v_freeze_days
  FROM mlm_settings
  WHERE key = 'commission_freeze_period';

  -- Iterate through active subscriptions from last N days
  FOR v_subscriptions IN
    SELECT 
      s.id AS subscription_id,
      s.user_id AS subscriber_id,
      COALESCE(p.full_name, p.email, 'Unknown') AS subscriber_name,
      s.amount_kzt,
      s.paid_at,
      p.sponsor_id AS direct_sponsor_id
    FROM subscriptions s
    JOIN profiles p ON p.id = s.user_id
    WHERE s.status = 'active'
      AND s.paid_at >= v_cutoff_date
      AND s.paid_at IS NOT NULL
      AND COALESCE(s.is_marketing_free_access, false) = false
      AND COALESCE(s.is_test, false) = false
      AND p.sponsor_id IS NOT NULL
    ORDER BY s.paid_at DESC
  LOOP
    -- Traverse sponsor chain up to 5 levels
    v_current_sponsor_id := v_subscriptions.direct_sponsor_id;
    v_current_level := 1;
    
    WHILE v_current_level <= 5 AND v_current_sponsor_id IS NOT NULL LOOP
      -- Get sponsor info
      SELECT 
        subscription_status,
        COALESCE(direct_referrals_count, 0)
      INTO v_sponsor_subscription_status, v_sponsor_referrals_count
      FROM profiles
      WHERE id = v_current_sponsor_id;
      
      -- Get required referrals for this level
      v_required_referrals := (v_levels_required->>v_current_level::text)::INTEGER;
      
      -- Build source_ref for new format
      v_source_ref := 'subscription_' || v_subscriptions.subscription_id || '_s1_level_' || v_current_level;
      
      -- Check if commission already exists (checking ALL formats)
      SELECT COUNT(*) INTO v_existing_count
      FROM transactions
      WHERE user_id = v_current_sponsor_id
        AND type = 'commission'
        AND structure_type = 'primary'
        AND (
          -- New format
          source_ref = v_source_ref
          -- Old format with colon
          OR source_ref LIKE 'subscription:' || v_subscriptions.subscription_id || '%'
          -- Backfill format
          OR source_ref = 'backfill_subscription:' || v_subscriptions.subscription_id || ':s1:l' || v_current_level
          -- Plain UUID for L1
          OR (v_current_level = 1 AND source_ref = v_subscriptions.subscription_id::text)
          -- By source_id + level
          OR (source_id = v_subscriptions.subscription_id AND level = v_current_level)
        );
      
      -- If commission doesn't exist and sponsor is eligible
      IF v_existing_count = 0 
         AND v_sponsor_subscription_status = 'active'
         AND v_sponsor_referrals_count >= v_required_referrals THEN
        
        -- Get commission percent from rules
        SELECT percent INTO v_commission_percent
        FROM mlm_commission_rules
        WHERE structure_type = 1
          AND level = v_current_level
          AND is_active = true
        ORDER BY effective_from DESC
        LIMIT 1;
        
        -- Fallback percentages if rule not found
        IF v_commission_percent IS NULL THEN
          v_commission_percent := CASE v_current_level
            WHEN 1 THEN 10
            WHEN 2 THEN 5
            WHEN 3 THEN 3
            WHEN 4 THEN 2
            WHEN 5 THEN 1
            ELSE 0
          END;
        END IF;
        
        -- Calculate commission in whole KZT
        v_commission_amount := ROUND(v_subscriptions.amount_kzt * v_commission_percent / 100);
        
        IF v_commission_amount > 0 THEN
          IF NOT p_dry_run THEN
            -- Insert commission (without ON CONFLICT constraint)
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
              v_commission_amount,
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
              v_subscriptions.paid_at
            );
          END IF;
          
          v_total_created := v_total_created + 1;
          v_total_amount := v_total_amount + v_commission_amount;
          
          -- Update level stats
          v_level_stats := jsonb_set(
            v_level_stats,
            ARRAY['L' || v_current_level],
            to_jsonb(COALESCE((v_level_stats->>'L' || v_current_level)::INTEGER, 0) + 1)
          );
          
          -- Add to details (limit to first 50)
          IF jsonb_array_length(v_details) < 50 THEN
            v_details := v_details || jsonb_build_object(
              'subscription_id', v_subscriptions.subscription_id,
              'subscriber_name', v_subscriptions.subscriber_name,
              'level', v_current_level,
              'amount_kzt', v_commission_amount,
              'sponsor_id', v_current_sponsor_id
            );
          END IF;
        END IF;
      ELSE
        v_total_skipped := v_total_skipped + 1;
      END IF;
      
      -- Move to next sponsor in chain
      SELECT sponsor_id INTO v_current_sponsor_id
      FROM profiles
      WHERE id = v_current_sponsor_id;
      
      v_current_level := v_current_level + 1;
    END LOOP;
  END LOOP;

  RETURN json_build_object(
    'success', true,
    'dry_run', p_dry_run,
    'commissions_created', v_total_created,
    'commissions_skipped', v_total_skipped,
    'total_kzt', v_total_amount,
    'by_level', v_level_stats,
    'details', v_details,
    'days_back', p_days_back
  );
END;
$$;
