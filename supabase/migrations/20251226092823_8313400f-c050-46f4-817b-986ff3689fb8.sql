-- Fix S1 commissions structure_type bug
-- Problem: award_s1_subscription_commission was incorrectly using 'secondary' instead of 'primary'

-- 1. Fix existing transactions with wrong structure_type
UPDATE public.transactions
SET structure_type = 'primary'
WHERE type = 'commission'
  AND source_ref LIKE '%_s1_level_%'
  AND structure_type = 'secondary';

-- 2. Fix the award_s1_subscription_commission function
CREATE OR REPLACE FUNCTION public.award_s1_subscription_commission(
  p_user_id uuid,
  p_subscription_id uuid,
  p_amount_kzt numeric
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_current_user_id uuid;
  v_level int := 0;
  v_commission_percent numeric;
  v_commission_amount int;
  v_frozen_until timestamptz;
  v_commissions_created int := 0;
  v_details jsonb := '[]'::jsonb;
  v_upline_active boolean;
  v_source_ref text;
BEGIN
  -- Get the sponsor of the user who paid
  SELECT sponsor_id INTO v_current_user_id
  FROM public.profiles
  WHERE id = p_user_id;
  
  -- Walk up the referral chain
  WHILE v_current_user_id IS NOT NULL AND v_level < 10 LOOP
    v_level := v_level + 1;
    
    -- Check if upline is active (has monthly activation)
    SELECT COALESCE(monthly_activation_completed, false) INTO v_upline_active
    FROM public.profiles
    WHERE id = v_current_user_id;
    
    -- Get commission percent for this level from S1 (primary) structure
    SELECT percent INTO v_commission_percent
    FROM public.mlm_commission_rules
    WHERE structure_type = 1  -- S1 = primary structure
      AND level = v_level
      AND is_active = true
    ORDER BY effective_from DESC
    LIMIT 1;
    
    -- If no commission rule for this level, stop
    IF v_commission_percent IS NULL OR v_commission_percent = 0 THEN
      EXIT;
    END IF;
    
    -- Calculate commission (in whole KZT, not cents for this function)
    v_commission_amount := FLOOR(p_amount_kzt * v_commission_percent / 100);
    
    -- Skip if commission is 0
    IF v_commission_amount > 0 THEN
      -- Create unique source_ref
      v_source_ref := p_subscription_id::text || '_s1_level_' || v_level || '_' || v_current_user_id::text;
      
      -- Set frozen period (14 days if upline not active)
      IF v_upline_active THEN
        v_frozen_until := NULL;
      ELSE
        v_frozen_until := now() + interval '14 days';
      END IF;
      
      -- Insert commission transaction (skip if already exists)
      INSERT INTO public.transactions (
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
        v_current_user_id,
        'commission',
        v_commission_amount,
        'KZT',
        CASE WHEN v_upline_active THEN 'completed' ELSE 'frozen' END,
        'primary',  -- FIXED: was incorrectly 'secondary'
        v_level,
        p_user_id,
        v_source_ref,
        v_frozen_until,
        jsonb_build_object(
          'subscription_id', p_subscription_id,
          'source_user_id', p_user_id,
          'level', v_level,
          'percent', v_commission_percent,
          'base_amount_kzt', p_amount_kzt,
          'structure', 'S1',
          'upline_active', v_upline_active
        )
      )
      ON CONFLICT (source_ref) DO NOTHING;
      
      -- Check if insert happened
      IF FOUND THEN
        v_commissions_created := v_commissions_created + 1;
        
        -- Update balance if completed
        IF v_upline_active THEN
          UPDATE public.profiles
          SET balance = COALESCE(balance, 0) + v_commission_amount
          WHERE id = v_current_user_id;
        END IF;
        
        v_details := v_details || jsonb_build_object(
          'user_id', v_current_user_id,
          'level', v_level,
          'percent', v_commission_percent,
          'amount', v_commission_amount,
          'status', CASE WHEN v_upline_active THEN 'completed' ELSE 'frozen' END
        );
      END IF;
    END IF;
    
    -- Move to next upline
    SELECT sponsor_id INTO v_current_user_id
    FROM public.profiles
    WHERE id = v_current_user_id;
  END LOOP;
  
  RETURN json_build_object(
    'success', true,
    'commissions_created', v_commissions_created,
    'details', v_details
  );
END;
$$;

-- 3. Add integrity check function for commission structure_type
CREATE OR REPLACE FUNCTION public.audit_commission_structure_integrity()
RETURNS TABLE (
  transaction_id uuid,
  source_ref text,
  current_structure_type text,
  expected_structure_type text,
  issue text
)
LANGUAGE sql
STABLE
AS $$
  -- Find S1 commissions with wrong structure_type
  SELECT 
    t.id as transaction_id,
    t.source_ref,
    t.structure_type::text as current_structure_type,
    'primary' as expected_structure_type,
    'S1 commission marked as secondary' as issue
  FROM public.transactions t
  WHERE t.type = 'commission'
    AND t.source_ref LIKE '%_s1_level_%'
    AND t.structure_type = 'secondary'
  
  UNION ALL
  
  -- Find S2 commissions with wrong structure_type  
  SELECT 
    t.id as transaction_id,
    t.source_ref,
    t.structure_type::text as current_structure_type,
    'secondary' as expected_structure_type,
    'S2 commission marked as primary' as issue
  FROM public.transactions t
  WHERE t.type = 'commission'
    AND t.source_ref LIKE '%_s2_level_%'
    AND t.structure_type = 'primary';
$$;