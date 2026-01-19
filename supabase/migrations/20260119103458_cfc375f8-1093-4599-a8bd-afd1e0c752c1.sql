
-- Function to backfill ALL missing multilevel commissions (L1-L5) for Structure 1
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
  v_sub RECORD;
  v_sponsor_id UUID;
  v_current_level INTEGER;
  v_percent NUMERIC;
  v_commission_amount INTEGER;
  v_source_ref TEXT;
  v_existing_count INTEGER;
  v_sponsor_name TEXT;
  v_created_count INTEGER := 0;
  v_skipped_count INTEGER := 0;
  v_total_amount INTEGER := 0;
  v_details JSONB := '[]'::JSONB;
  v_level_stats JSONB := '{}'::JSONB;
BEGIN
  -- Check admin permissions
  SELECT EXISTS (
    SELECT 1 FROM user_roles 
    WHERE user_id = p_admin_id AND role IN ('admin', 'superadmin')
  ) INTO v_is_admin;
  
  IF NOT v_is_admin THEN
    RETURN json_build_object('success', false, 'error', 'Not authorized');
  END IF;

  -- Loop through all active subscriptions from last N days
  FOR v_sub IN 
    SELECT 
      s.id as subscription_id,
      s.user_id as subscriber_id,
      s.amount_kzt,
      s.paid_at,
      p.full_name as subscriber_name,
      p.sponsor_id as direct_sponsor_id
    FROM subscriptions s
    JOIN profiles p ON p.id = s.user_id
    WHERE s.status = 'active'
      AND s.paid_at IS NOT NULL
      AND s.paid_at > NOW() - (p_days_back || ' days')::INTERVAL
      AND s.is_marketing_free_access IS NOT TRUE
      AND s.is_test IS NOT TRUE
      AND p.sponsor_id IS NOT NULL
    ORDER BY s.paid_at
  LOOP
    -- Traverse sponsor chain up to L5
    v_sponsor_id := v_sub.direct_sponsor_id;
    v_current_level := 1;
    
    WHILE v_sponsor_id IS NOT NULL AND v_current_level <= 5 LOOP
      -- Get commission percent for this level from mlm_commission_rules
      SELECT percent INTO v_percent
      FROM mlm_commission_rules
      WHERE structure_type = 1 
        AND level = v_current_level 
        AND is_active = true
      ORDER BY effective_from DESC
      LIMIT 1;
      
      IF v_percent IS NULL THEN
        v_percent := CASE v_current_level
          WHEN 1 THEN 10
          WHEN 2 THEN 10
          WHEN 3 THEN 10
          WHEN 4 THEN 5
          WHEN 5 THEN 5
          ELSE 0
        END;
      END IF;
      
      -- Calculate commission amount
      v_commission_amount := floor(v_sub.amount_kzt * v_percent / 100);
      
      -- Build source_ref
      v_source_ref := 'subscription_' || v_sub.subscription_id || '_s1_level_' || v_current_level;
      
      -- Check if commission already exists
      SELECT COUNT(*) INTO v_existing_count
      FROM transactions
      WHERE source_ref = v_source_ref
        AND user_id = v_sponsor_id
        AND type = 'commission';
      
      IF v_existing_count = 0 AND v_commission_amount > 0 THEN
        -- Get sponsor name
        SELECT full_name INTO v_sponsor_name
        FROM profiles WHERE id = v_sponsor_id;
        
        IF NOT p_dry_run THEN
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
            NOW() + INTERVAL '14 days',
            v_sub.subscription_id,
            v_source_ref,
            'primary',
            v_current_level,
            jsonb_build_object(
              'subscription_amount_kzt', v_sub.amount_kzt,
              'structure', 'S1',
              'level', v_current_level,
              'percent', v_percent,
              'subscriber_id', v_sub.subscriber_id,
              'subscriber_name', v_sub.subscriber_name,
              'backfill', true,
              'backfill_reason', 'multilevel_backfill',
              'backfill_date', NOW()
            )
          );
        END IF;
        
        v_created_count := v_created_count + 1;
        v_total_amount := v_total_amount + v_commission_amount;
        
        -- Update level stats
        v_level_stats := jsonb_set(
          v_level_stats,
          ARRAY['L' || v_current_level],
          to_jsonb(COALESCE((v_level_stats->('L' || v_current_level))::INTEGER, 0) + 1)
        );
        
        -- Add to details (first 50 only to avoid huge response)
        IF jsonb_array_length(v_details) < 50 THEN
          v_details := v_details || jsonb_build_object(
            'subscription_id', v_sub.subscription_id,
            'subscriber_name', v_sub.subscriber_name,
            'recipient_id', v_sponsor_id,
            'recipient_name', v_sponsor_name,
            'level', v_current_level,
            'amount_kzt', v_commission_amount,
            'percent', v_percent
          );
        END IF;
      ELSE
        v_skipped_count := v_skipped_count + 1;
      END IF;
      
      -- Move to next sponsor in chain
      SELECT sponsor_id INTO v_sponsor_id
      FROM profiles WHERE id = v_sponsor_id;
      
      v_current_level := v_current_level + 1;
    END LOOP;
  END LOOP;

  RETURN json_build_object(
    'success', true,
    'dry_run', p_dry_run,
    'commissions_created', v_created_count,
    'commissions_skipped', v_skipped_count,
    'total_kzt', v_total_amount,
    'level_stats', v_level_stats,
    'details', v_details
  );
END;
$$;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION public.backfill_all_missing_multilevel_commissions(UUID, BOOLEAN, INTEGER) TO authenticated;
