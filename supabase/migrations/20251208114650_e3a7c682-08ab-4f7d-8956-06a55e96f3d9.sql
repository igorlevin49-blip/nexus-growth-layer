
-- =====================================================
-- FIX: Remove commissions from marketing (free) subscriptions
-- and update recalculate function to exclude them
-- =====================================================

-- Step 1: Delete all commissions from marketing (free access) subscriptions
DELETE FROM transactions
WHERE type = 'commission'
AND source_id IN (
  SELECT id FROM subscriptions WHERE is_marketing_free_access = true
);

-- Step 2: Drop and recreate the function
DROP FUNCTION IF EXISTS recalculate_all_s1_commissions(uuid);

-- Step 3: Create updated function that excludes marketing subscriptions
CREATE OR REPLACE FUNCTION recalculate_all_s1_commissions(p_admin_id uuid)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_is_admin boolean;
  v_subscription record;
  v_sponsor_id uuid;
  v_current_level integer;
  v_commission_percent numeric;
  v_commission_amount integer;
  v_existing_commission uuid;
  v_subscriptions_processed integer := 0;
  v_commissions_created integer := 0;
  v_commissions_skipped integer := 0;
  v_source_ref text;
BEGIN
  -- Verify admin permissions
  SELECT EXISTS(
    SELECT 1 FROM user_roles 
    WHERE user_id = p_admin_id 
    AND role IN ('admin', 'superadmin')
  ) INTO v_is_admin;
  
  IF NOT v_is_admin THEN
    RETURN json_build_object(
      'success', false,
      'error', 'Unauthorized: Admin access required'
    );
  END IF;

  -- Process each PAID (not marketing free) active subscription
  FOR v_subscription IN
    SELECT s.id, s.user_id, s.amount_usd, p.full_name, p.sponsor_id as first_sponsor
    FROM subscriptions s
    JOIN profiles p ON p.id = s.user_id
    WHERE s.status = 'active'
      AND s.paid_at IS NOT NULL
      AND (s.is_marketing_free_access = false OR s.is_marketing_free_access IS NULL)
  LOOP
    v_subscriptions_processed := v_subscriptions_processed + 1;
    
    -- Start from the subscriber's direct sponsor
    v_sponsor_id := v_subscription.first_sponsor;
    v_current_level := 1;
    
    -- Process up to 5 levels
    WHILE v_current_level <= 5 AND v_sponsor_id IS NOT NULL LOOP
      -- Get commission percent for this level
      SELECT percent INTO v_commission_percent
      FROM mlm_commission_rules
      WHERE structure_type = 1
        AND level = v_current_level
        AND is_active = true
      ORDER BY effective_from DESC
      LIMIT 1;
      
      IF v_commission_percent IS NULL THEN
        v_commission_percent := 10;
      END IF;
      
      -- Calculate commission in cents
      v_commission_amount := ROUND(v_subscription.amount_usd * v_commission_percent)::integer;
      
      -- Build source_ref
      v_source_ref := v_subscription.id::text || '_s1_level_' || v_current_level::text;
      
      -- Check if commission already exists
      SELECT id INTO v_existing_commission
      FROM transactions
      WHERE source_id = v_subscription.id
        AND user_id = v_sponsor_id
        AND level = v_current_level
        AND type = 'commission'
        AND structure_type = 'primary'
      LIMIT 1;
      
      IF v_existing_commission IS NULL THEN
        INSERT INTO transactions (
          user_id, type, amount_cents, status, source_id, source_ref,
          level, structure_type, payload, created_at, updated_at
        ) VALUES (
          v_sponsor_id, 'commission', v_commission_amount, 'completed',
          v_subscription.id, v_source_ref, v_current_level, 'primary',
          jsonb_build_object(
            'from_user', v_subscription.full_name,
            'subscription_amount', v_subscription.amount_usd,
            'percent', v_commission_percent,
            'recalculated', true,
            'recalculated_at', now()
          ),
          now(), now()
        );
        v_commissions_created := v_commissions_created + 1;
      ELSE
        v_commissions_skipped := v_commissions_skipped + 1;
      END IF;
      
      -- Move to next level
      SELECT sponsor_id INTO v_sponsor_id FROM profiles WHERE id = v_sponsor_id;
      v_current_level := v_current_level + 1;
    END LOOP;
  END LOOP;

  -- Log action
  INSERT INTO admin_actions (admin_id, action_type, target_type, comment, metadata)
  VALUES (p_admin_id, 'recalculate_commissions', 'system', 
    'Recalculated S1 commissions for paid subscriptions only',
    jsonb_build_object(
      'subscriptions_processed', v_subscriptions_processed,
      'commissions_created', v_commissions_created,
      'commissions_skipped', v_commissions_skipped
    )
  );

  RETURN json_build_object(
    'success', true,
    'subscriptions_processed', v_subscriptions_processed,
    'commissions_created', v_commissions_created,
    'commissions_skipped', v_commissions_skipped
  );
END;
$$;

GRANT EXECUTE ON FUNCTION recalculate_all_s1_commissions(uuid) TO authenticated;
