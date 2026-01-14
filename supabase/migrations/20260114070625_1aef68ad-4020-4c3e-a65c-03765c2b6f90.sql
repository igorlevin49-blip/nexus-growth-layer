-- Fix backfill_missing_multilevel_commissions: replace invalid 'S1' with correct 'primary' enum value
CREATE OR REPLACE FUNCTION public.backfill_missing_multilevel_commissions(
  p_admin_id uuid,
  p_dry_run boolean DEFAULT true
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_result jsonb;
  v_processed integer := 0;
  v_created integer := 0;
  v_skipped integer := 0;
  v_total_amount numeric := 0;
  v_details jsonb := '[]'::jsonb;
  v_subscription record;
  v_sponsor record;
  v_level integer;
  v_commission_rate numeric;
  v_commission_amount integer;
  v_existing_count integer;
  v_is_admin boolean;
BEGIN
  -- Check admin access
  SELECT EXISTS(
    SELECT 1 FROM user_roles 
    WHERE user_id = p_admin_id 
    AND role IN ('admin', 'superadmin')
  ) INTO v_is_admin;
  
  IF NOT v_is_admin THEN
    RAISE EXCEPTION 'Access denied: admin role required';
  END IF;

  -- Loop through all active subscriptions with sponsors
  FOR v_subscription IN
    SELECT 
      s.id as subscription_id,
      s.user_id as subscriber_id,
      p.full_name as subscriber_name,
      p.sponsor_id,
      s.amount_cents,
      s.created_at
    FROM subscriptions s
    JOIN profiles p ON p.id = s.user_id
    WHERE s.status = 'active'
      AND p.sponsor_id IS NOT NULL
      AND s.amount_cents > 0
    ORDER BY s.created_at
  LOOP
    v_processed := v_processed + 1;
    
    -- Walk up the sponsor chain (up to 10 levels for P1-P10)
    v_level := 1;
    v_sponsor := NULL;
    
    -- Get first sponsor
    SELECT id, sponsor_id, full_name 
    INTO v_sponsor
    FROM profiles 
    WHERE id = v_subscription.sponsor_id;
    
    WHILE v_sponsor.id IS NOT NULL AND v_level <= 10 LOOP
      -- Get commission rate for this level
      SELECT commission_percent INTO v_commission_rate
      FROM mlm_commission_rules
      WHERE level_number = v_level
        AND structure_type = 'primary'
        AND is_active = true;
      
      IF v_commission_rate IS NOT NULL AND v_commission_rate > 0 THEN
        -- Check if commission already exists for this sponsor/subscription/level
        SELECT COUNT(*) INTO v_existing_count
        FROM transactions t
        WHERE t.user_id = v_sponsor.id
          AND t.type = 'commission'
          AND t.structure_type = 'primary'
          AND t.payload->>'subscription_id' = v_subscription.subscription_id::text
          AND (t.payload->>'level')::integer = v_level;
        
        IF v_existing_count = 0 THEN
          -- Calculate commission
          v_commission_amount := ROUND(v_subscription.amount_cents * v_commission_rate);
          
          IF NOT p_dry_run THEN
            -- Create commission transaction
            INSERT INTO transactions (
              user_id,
              type,
              amount_cents,
              status,
              structure_type,
              payload,
              created_at
            ) VALUES (
              v_sponsor.id,
              'commission',
              v_commission_amount,
              'completed',
              'primary',
              jsonb_build_object(
                'subscription_id', v_subscription.subscription_id,
                'subscriber_id', v_subscription.subscriber_id,
                'subscriber_name', v_subscription.subscriber_name,
                'level', v_level,
                'rate', v_commission_rate,
                'backfill', true,
                'backfilled_at', NOW()
              ),
              v_subscription.created_at
            );
          END IF;
          
          v_created := v_created + 1;
          v_total_amount := v_total_amount + v_commission_amount;
          
          -- Add to details
          v_details := v_details || jsonb_build_object(
            'sponsor_id', v_sponsor.id,
            'sponsor_name', v_sponsor.full_name,
            'subscriber_name', v_subscription.subscriber_name,
            'level', v_level,
            'rate', v_commission_rate,
            'amount_cents', v_commission_amount
          );
        ELSE
          v_skipped := v_skipped + 1;
        END IF;
      END IF;
      
      -- Move to next level sponsor
      v_level := v_level + 1;
      
      IF v_sponsor.sponsor_id IS NOT NULL THEN
        SELECT id, sponsor_id, full_name 
        INTO v_sponsor
        FROM profiles 
        WHERE id = v_sponsor.sponsor_id;
      ELSE
        EXIT;
      END IF;
    END LOOP;
  END LOOP;

  -- Build result
  v_result := jsonb_build_object(
    'success', true,
    'dry_run', p_dry_run,
    'subscriptions_processed', v_processed,
    'commissions_created', v_created,
    'commissions_skipped', v_skipped,
    'total_cents', v_total_amount,
    'total_kzt', ROUND(v_total_amount / 100),
    'details', v_details
  );

  RETURN v_result;
END;
$$;