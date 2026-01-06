-- =============================================
-- FIX 1: Correct S2 commission calculation in create_commission_transactions
-- The bug: v_amount_kzt * (v_percent / 100) * 100 - extra *100 caused 100x overcalculation
-- =============================================

-- First, let's check if the function exists and fix it
CREATE OR REPLACE FUNCTION public.create_commission_transactions(
  p_source_user_id uuid,
  p_source_ref text,
  p_source_id uuid,
  p_amount_kzt numeric,
  p_structure_type integer DEFAULT 2
)
RETURNS json AS $$
DECLARE
  v_ancestor_id uuid;
  v_current_id uuid;
  v_level integer := 0;
  v_percent numeric;
  v_commission_cents numeric;
  v_direct_count integer;
  v_amount_kzt numeric := p_amount_kzt;
  v_frozen_until timestamptz;
  v_created_count integer := 0;
  v_results jsonb := '[]'::jsonb;
  v_max_levels integer := 10;
  v_skip_reason text;
BEGIN
  -- Start with the source user's sponsor
  SELECT sponsor_id INTO v_current_id FROM profiles WHERE id = p_source_user_id;
  
  IF v_current_id IS NULL THEN
    RETURN json_build_object('success', true, 'message', 'No sponsor found', 'created', 0);
  END IF;

  -- Walk up the sponsor chain
  WHILE v_current_id IS NOT NULL AND v_level < v_max_levels LOOP
    v_level := v_level + 1;
    v_skip_reason := NULL;
    
    -- Get commission percent for this level
    SELECT percent INTO v_percent 
    FROM mlm_commission_rules 
    WHERE structure_type = p_structure_type 
      AND level = v_level 
      AND is_active = true
    LIMIT 1;
    
    IF v_percent IS NULL THEN
      -- No more commission rules, exit loop
      EXIT;
    END IF;
    
    -- Count active direct referrals for unlock check
    SELECT COUNT(*) INTO v_direct_count
    FROM referrals r
    JOIN profiles p ON p.id = r.referred_user_id
    WHERE r.referrer_id = v_current_id
      AND r.structure_type = p_structure_type
      AND p.subscription_status = 'active';
    
    -- Check if level is unlocked (need >= level active referrals for levels 2+)
    IF v_level >= 2 AND v_direct_count < v_level THEN
      v_skip_reason := 'level_' || v_level || '_locked';
    END IF;
    
    -- Check if user is active
    IF v_skip_reason IS NULL THEN
      DECLARE
        v_is_active boolean;
        v_subscription_status text;
      BEGIN
        SELECT is_active, subscription_status 
        INTO v_is_active, v_subscription_status
        FROM profiles WHERE id = v_current_id;
        
        IF NOT COALESCE(v_is_active, false) THEN
          v_skip_reason := 'sponsor_inactive';
        ELSIF v_subscription_status != 'active' THEN
          v_skip_reason := 'no_active_subscription';
        END IF;
      END;
    END IF;
    
    IF v_skip_reason IS NULL THEN
      -- Calculate commission - FIX: removed extra *100
      v_commission_cents := ROUND(v_amount_kzt * (v_percent / 100));
      
      -- Set freeze period for S2 (30 days)
      IF p_structure_type = 2 THEN
        v_frozen_until := now() + interval '30 days';
      ELSE
        v_frozen_until := NULL;
      END IF;
      
      -- Create transaction
      INSERT INTO transactions (
        user_id, type, amount_cents, currency, status, 
        structure_type, level, source_id, source_ref, frozen_until,
        payload
      ) VALUES (
        v_current_id, 'commission', v_commission_cents, 'KZT',
        CASE WHEN v_frozen_until IS NOT NULL THEN 'frozen' ELSE 'completed' END,
        CASE WHEN p_structure_type = 1 THEN 'primary'::structure_type ELSE 'secondary'::structure_type END,
        v_level, p_source_id, p_source_ref, v_frozen_until,
        jsonb_build_object(
          'source_user_id', p_source_user_id,
          'order_amount_kzt', p_amount_kzt,
          'percent', v_percent
        )
      );
      
      v_created_count := v_created_count + 1;
      
      -- Update balance for non-frozen transactions
      IF v_frozen_until IS NULL THEN
        UPDATE profiles 
        SET balance = COALESCE(balance, 0) + v_commission_cents
        WHERE id = v_current_id;
      END IF;
      
      v_results := v_results || jsonb_build_object(
        'user_id', v_current_id,
        'level', v_level,
        'percent', v_percent,
        'amount_cents', v_commission_cents,
        'frozen', v_frozen_until IS NOT NULL
      );
    ELSE
      v_results := v_results || jsonb_build_object(
        'user_id', v_current_id,
        'level', v_level,
        'skipped', true,
        'reason', v_skip_reason
      );
    END IF;
    
    -- Move to next ancestor
    SELECT sponsor_id INTO v_current_id FROM profiles WHERE id = v_current_id;
  END LOOP;

  RETURN json_build_object(
    'success', true,
    'created', v_created_count,
    'details', v_results
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =============================================
-- FIX 2: Correct existing incorrect S2 transactions (divided by 100)
-- =============================================

UPDATE transactions
SET 
  amount_cents = ROUND(amount_cents / 100),
  payload = COALESCE(payload, '{}'::jsonb) || jsonb_build_object(
    'fix_applied', 'divided_by_100_s2_bug',
    'fix_date', now()::text,
    'original_amount_cents', amount_cents
  ),
  updated_at = now()
WHERE type = 'commission'
  AND structure_type = 'secondary'
  AND amount_cents > 10000
  AND payload IS NOT NULL
  AND (payload->>'order_amount_kzt')::numeric IS NOT NULL
  AND amount_cents > (payload->>'order_amount_kzt')::numeric;

-- =============================================
-- FIX 3: Create proper release function that changes status
-- =============================================

CREATE OR REPLACE FUNCTION public.release_expired_frozen_transactions()
RETURNS json AS $$
DECLARE
  v_count integer;
  v_total_amount numeric := 0;
  v_user_updates jsonb := '[]'::jsonb;
BEGIN
  -- Update transactions and sum amounts per user
  WITH released AS (
    UPDATE transactions
    SET 
      status = 'completed',
      frozen_until = null,
      updated_at = now()
    WHERE status = 'frozen'
      AND frozen_until IS NOT NULL
      AND frozen_until <= now()
    RETURNING user_id, amount_cents
  ),
  user_totals AS (
    SELECT user_id, SUM(amount_cents) as total_released
    FROM released
    GROUP BY user_id
  )
  UPDATE profiles p
  SET balance = COALESCE(p.balance, 0) + ut.total_released
  FROM user_totals ut
  WHERE p.id = ut.user_id;

  -- Get count of released transactions
  SELECT COUNT(*) INTO v_count
  FROM transactions
  WHERE updated_at >= now() - interval '1 second'
    AND status = 'completed'
    AND payload->>'fix_applied' IS NULL;

  RETURN json_build_object(
    'success', true,
    'released_count', v_count,
    'message', 'Released frozen transactions and updated balances'
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =============================================
-- FIX 4: Immediately release all expired frozen transactions
-- =============================================

-- First update statuses
UPDATE transactions
SET 
  status = 'completed',
  frozen_until = null,
  updated_at = now()
WHERE status = 'frozen'
  AND frozen_until IS NOT NULL
  AND frozen_until <= now();

-- Then update balances
WITH frozen_to_release AS (
  SELECT user_id, SUM(amount_cents) as total
  FROM transactions
  WHERE status = 'completed'
    AND updated_at >= now() - interval '5 seconds'
    AND structure_type = 'secondary'
  GROUP BY user_id
)
UPDATE profiles p
SET balance = COALESCE(p.balance, 0) + f.total
FROM frozen_to_release f
WHERE p.id = f.user_id;