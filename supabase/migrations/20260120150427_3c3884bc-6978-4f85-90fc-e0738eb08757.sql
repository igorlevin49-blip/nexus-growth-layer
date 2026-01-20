
-- ============================================================
-- FIX: Archive free subscription commissions and update balance functions
-- ============================================================

-- 1. Archive all commissions from free subscriptions
UPDATE transactions t
SET 
  is_archived = true,
  archived_at = NOW()
FROM subscriptions s
WHERE t.source_id = s.id
  AND s.is_marketing_free_access = true
  AND t.type = 'commission'
  AND t.structure_type = 'primary'
  AND COALESCE(t.is_archived, false) = false;

-- 2. Drop existing functions first
DROP FUNCTION IF EXISTS public.get_user_balance(uuid);
DROP FUNCTION IF EXISTS public.get_all_user_balances();

-- 3. Recreate get_user_balance with protection against free subscriptions
CREATE FUNCTION public.get_user_balance(p_user_id uuid)
RETURNS TABLE(
  available_kzt bigint,
  frozen_kzt bigint,
  pending_kzt bigint,
  withdrawn_kzt bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  WITH commission_transactions AS (
    SELECT 
      t.amount_cents,
      t.status,
      t.frozen_until,
      t.type
    FROM transactions t
    LEFT JOIN subscriptions s ON t.source_id = s.id 
      AND t.type = 'commission' 
      AND t.structure_type = 'primary'
    WHERE t.user_id = p_user_id
      AND t.currency = 'KZT'
      AND COALESCE(t.is_archived, false) = false
      AND COALESCE(t.is_test, false) = false
      -- Exclude commissions from free subscriptions
      AND NOT (t.type = 'commission' AND t.structure_type = 'primary' AND COALESCE(s.is_marketing_free_access, false) = true)
  )
  SELECT
    COALESCE(SUM(
      CASE 
        WHEN type IN ('commission', 'bonus', 'adjustment') 
          AND status = 'completed'
          AND (frozen_until IS NULL OR frozen_until <= NOW())
        THEN amount_cents
        WHEN type = 'withdrawal' AND status = 'completed'
        THEN -amount_cents
        ELSE 0
      END
    ), 0)::bigint AS available_kzt,
    
    COALESCE(SUM(
      CASE 
        WHEN type IN ('commission', 'bonus') 
          AND (status = 'frozen' OR (status = 'completed' AND frozen_until > NOW()))
        THEN amount_cents
        ELSE 0
      END
    ), 0)::bigint AS frozen_kzt,
    
    COALESCE(SUM(
      CASE 
        WHEN type = 'withdrawal' AND status = 'pending'
        THEN amount_cents
        ELSE 0
      END
    ), 0)::bigint AS pending_kzt,
    
    COALESCE(SUM(
      CASE 
        WHEN type = 'withdrawal' AND status = 'completed'
        THEN amount_cents
        ELSE 0
      END
    ), 0)::bigint AS withdrawn_kzt
  FROM commission_transactions;
END;
$$;

-- 4. Recreate get_all_user_balances
CREATE FUNCTION public.get_all_user_balances()
RETURNS TABLE(
  user_id uuid,
  available_kzt bigint,
  frozen_kzt bigint,
  pending_kzt bigint,
  withdrawn_kzt bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  WITH commission_transactions AS (
    SELECT 
      t.user_id as uid,
      t.amount_cents,
      t.status,
      t.frozen_until,
      t.type
    FROM transactions t
    LEFT JOIN subscriptions s ON t.source_id = s.id 
      AND t.type = 'commission' 
      AND t.structure_type = 'primary'
    WHERE t.currency = 'KZT'
      AND COALESCE(t.is_archived, false) = false
      AND COALESCE(t.is_test, false) = false
      -- Exclude commissions from free subscriptions
      AND NOT (t.type = 'commission' AND t.structure_type = 'primary' AND COALESCE(s.is_marketing_free_access, false) = true)
  )
  SELECT
    ct.uid,
    COALESCE(SUM(
      CASE 
        WHEN ct.type IN ('commission', 'bonus', 'adjustment') 
          AND ct.status = 'completed'
          AND (ct.frozen_until IS NULL OR ct.frozen_until <= NOW())
        THEN ct.amount_cents
        WHEN ct.type = 'withdrawal' AND ct.status = 'completed'
        THEN -ct.amount_cents
        ELSE 0
      END
    ), 0)::bigint AS available_kzt,
    
    COALESCE(SUM(
      CASE 
        WHEN ct.type IN ('commission', 'bonus') 
          AND (ct.status = 'frozen' OR (ct.status = 'completed' AND ct.frozen_until > NOW()))
        THEN ct.amount_cents
        ELSE 0
      END
    ), 0)::bigint AS frozen_kzt,
    
    COALESCE(SUM(
      CASE 
        WHEN ct.type = 'withdrawal' AND ct.status = 'pending'
        THEN ct.amount_cents
        ELSE 0
      END
    ), 0)::bigint AS pending_kzt,
    
    COALESCE(SUM(
      CASE 
        WHEN ct.type = 'withdrawal' AND ct.status = 'completed'
        THEN ct.amount_cents
        ELSE 0
      END
    ), 0)::bigint AS withdrawn_kzt
  FROM commission_transactions ct
  GROUP BY ct.uid;
END;
$$;

-- 5. Update backfill functions to skip free subscriptions
DROP FUNCTION IF EXISTS public.backfill_all_missing_multilevel_commissions(uuid, integer, boolean);

CREATE FUNCTION public.backfill_all_missing_multilevel_commissions(
  p_admin_id uuid,
  p_days_back integer DEFAULT 365,
  p_dry_run boolean DEFAULT true
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_subscription RECORD;
  v_sponsor RECORD;
  v_level INTEGER;
  v_percent NUMERIC;
  v_commission_amount INTEGER;
  v_existing_count INTEGER;
  v_created_count INTEGER := 0;
  v_skipped_count INTEGER := 0;
  v_total_amount INTEGER := 0;
  v_freeze_days INTEGER := 14;
  v_unlock_requirements INTEGER[] := ARRAY[0, 3, 5, 8, 10];
  v_source_ref TEXT;
  v_current_sponsor_id UUID;
  v_active_l1_count INTEGER;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM user_roles 
    WHERE user_id = p_admin_id 
    AND role IN ('admin', 'superadmin')
  ) THEN
    RETURN json_build_object('success', false, 'error', 'Unauthorized');
  END IF;

  CREATE TEMP TABLE IF NOT EXISTS temp_commission_levels AS
  SELECT level, percent 
  FROM commission_plan_levels 
  WHERE structure_type = 'primary'
  ORDER BY level;

  FOR v_subscription IN
    SELECT 
      s.id as subscription_id,
      s.user_id as subscriber_id,
      s.amount_kzt,
      s.paid_at,
      p.sponsor_id,
      p.full_name as subscriber_name
    FROM subscriptions s
    JOIN profiles p ON s.user_id = p.id
    WHERE s.status = 'active'
      AND s.paid_at IS NOT NULL
      AND s.paid_at >= NOW() - (p_days_back || ' days')::interval
      AND COALESCE(s.is_archived, false) = false
      AND COALESCE(s.is_test, false) = false
      AND COALESCE(s.is_marketing_free_access, false) = false
      AND p.sponsor_id IS NOT NULL
    ORDER BY s.paid_at
  LOOP
    v_current_sponsor_id := v_subscription.sponsor_id;
    
    FOR v_level IN 1..5 LOOP
      EXIT WHEN v_current_sponsor_id IS NULL;
      
      SELECT id, sponsor_id, full_name, email
      INTO v_sponsor
      FROM profiles
      WHERE id = v_current_sponsor_id;
      
      EXIT WHEN v_sponsor IS NULL;
      
      SELECT COUNT(*) INTO v_active_l1_count
      FROM referrals r
      JOIN profiles p ON r.referred_user_id = p.id
      WHERE r.referrer_id = v_sponsor.id
        AND r.structure_type = 1
        AND p.subscription_status = 'active';
      
      IF v_active_l1_count < v_unlock_requirements[v_level] THEN
        v_skipped_count := v_skipped_count + 1;
        v_current_sponsor_id := v_sponsor.sponsor_id;
        CONTINUE;
      END IF;
      
      SELECT percent INTO v_percent
      FROM temp_commission_levels
      WHERE level = v_level;
      
      IF v_percent IS NULL OR v_percent = 0 THEN
        v_current_sponsor_id := v_sponsor.sponsor_id;
        CONTINUE;
      END IF;
      
      v_commission_amount := ROUND(v_subscription.amount_kzt * v_percent / 100);
      
      IF v_commission_amount <= 0 THEN
        v_current_sponsor_id := v_sponsor.sponsor_id;
        CONTINUE;
      END IF;
      
      v_source_ref := 'subscription_' || v_subscription.subscription_id || '_s1_level_' || v_level;
      
      SELECT COUNT(*) INTO v_existing_count
      FROM transactions
      WHERE user_id = v_sponsor.id
        AND type = 'commission'
        AND structure_type = 'primary'
        AND COALESCE(is_archived, false) = false
        AND (
          source_ref = v_source_ref
          OR source_ref LIKE 'subscription:' || v_subscription.subscription_id || '%'
          OR source_ref LIKE 'backfill_subscription:' || v_subscription.subscription_id || ':s1:l' || v_level || '%'
          OR (source_id = v_subscription.subscription_id AND level = v_level)
        );
      
      IF v_existing_count > 0 THEN
        v_skipped_count := v_skipped_count + 1;
        v_current_sponsor_id := v_sponsor.sponsor_id;
        CONTINUE;
      END IF;
      
      IF NOT p_dry_run THEN
        INSERT INTO transactions (
          user_id, type, amount_cents, currency, status,
          source_id, source_ref, structure_type, level, frozen_until, payload
        ) VALUES (
          v_sponsor.id, 'commission', v_commission_amount, 'KZT', 'completed',
          v_subscription.subscription_id, v_source_ref, 'primary', v_level,
          NOW() + (v_freeze_days || ' days')::interval,
          jsonb_build_object(
            'backfill_reason', 'L' || v_level || ' commission backfill',
            'subscriber_id', v_subscription.subscriber_id,
            'subscriber_name', v_subscription.subscriber_name,
            'subscription_amount', v_subscription.amount_kzt,
            'percent', v_percent,
            'backfilled_at', NOW()
          )
        );
      END IF;
      
      v_created_count := v_created_count + 1;
      v_total_amount := v_total_amount + v_commission_amount;
      v_current_sponsor_id := v_sponsor.sponsor_id;
    END LOOP;
  END LOOP;
  
  DROP TABLE IF EXISTS temp_commission_levels;
  
  IF NOT p_dry_run THEN
    INSERT INTO admin_actions (admin_id, action_type, target_type, comment, metadata)
    VALUES (p_admin_id, 'backfill_multilevel_commissions', 'transactions',
      'Backfilled ' || v_created_count || ' multilevel commissions',
      jsonb_build_object('created_count', v_created_count, 'skipped_count', v_skipped_count, 'total_amount', v_total_amount, 'dry_run', p_dry_run));
  END IF;
  
  RETURN json_build_object(
    'success', true, 'dry_run', p_dry_run, 'created_count', v_created_count,
    'skipped_count', v_skipped_count, 'total_amount', v_total_amount,
    'message', CASE WHEN p_dry_run 
      THEN 'Dry run: would create ' || v_created_count || ' commissions totaling ' || v_total_amount || ' KZT'
      ELSE 'Created ' || v_created_count || ' commissions totaling ' || v_total_amount || ' KZT' END
  );
END;
$$;

-- 6. Update backfill_missing_s1_commissions
DROP FUNCTION IF EXISTS public.backfill_missing_s1_commissions(uuid, boolean, uuid);

CREATE FUNCTION public.backfill_missing_s1_commissions(
  p_admin_id uuid,
  p_dry_run boolean DEFAULT true,
  p_sponsor_id uuid DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_subscription RECORD;
  v_sponsor RECORD;
  v_percent NUMERIC;
  v_commission_amount INTEGER;
  v_existing_count INTEGER;
  v_created_count INTEGER := 0;
  v_skipped_count INTEGER := 0;
  v_total_amount INTEGER := 0;
  v_freeze_days INTEGER := 14;
  v_source_ref TEXT;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM user_roles 
    WHERE user_id = p_admin_id 
    AND role IN ('admin', 'superadmin')
  ) THEN
    RETURN json_build_object('success', false, 'error', 'Unauthorized');
  END IF;

  SELECT percent INTO v_percent
  FROM commission_plan_levels 
  WHERE structure_type = 'primary' AND level = 1;

  IF v_percent IS NULL THEN v_percent := 10; END IF;

  FOR v_subscription IN
    SELECT 
      s.id as subscription_id, s.user_id as subscriber_id,
      s.amount_kzt, s.paid_at, p.sponsor_id, p.full_name as subscriber_name
    FROM subscriptions s
    JOIN profiles p ON s.user_id = p.id
    WHERE s.status = 'active' AND s.paid_at IS NOT NULL
      AND COALESCE(s.is_archived, false) = false
      AND COALESCE(s.is_test, false) = false
      AND COALESCE(s.is_marketing_free_access, false) = false
      AND p.sponsor_id IS NOT NULL
      AND (p_sponsor_id IS NULL OR p.sponsor_id = p_sponsor_id)
    ORDER BY s.paid_at
  LOOP
    SELECT id, full_name, email, subscription_status
    INTO v_sponsor FROM profiles WHERE id = v_subscription.sponsor_id;
    
    IF v_sponsor IS NULL THEN v_skipped_count := v_skipped_count + 1; CONTINUE; END IF;
    
    v_commission_amount := ROUND(v_subscription.amount_kzt * v_percent / 100);
    IF v_commission_amount <= 0 THEN v_skipped_count := v_skipped_count + 1; CONTINUE; END IF;
    
    v_source_ref := 'subscription_' || v_subscription.subscription_id || '_s1_level_1';
    
    SELECT COUNT(*) INTO v_existing_count
    FROM transactions
    WHERE user_id = v_sponsor.id AND type = 'commission' AND structure_type = 'primary' AND level = 1
      AND COALESCE(is_archived, false) = false
      AND (source_ref = v_source_ref OR source_id = v_subscription.subscription_id OR source_ref LIKE '%' || v_subscription.subscription_id || '%');
    
    IF v_existing_count > 0 THEN v_skipped_count := v_skipped_count + 1; CONTINUE; END IF;
    
    IF NOT p_dry_run THEN
      INSERT INTO transactions (user_id, type, amount_cents, currency, status, source_id, source_ref, structure_type, level, frozen_until, payload)
      VALUES (v_sponsor.id, 'commission', v_commission_amount, 'KZT', 'completed', v_subscription.subscription_id, v_source_ref, 'primary', 1,
        NOW() + (v_freeze_days || ' days')::interval,
        jsonb_build_object('backfill_reason', 'L1 S1 commission backfill', 'subscriber_id', v_subscription.subscriber_id,
          'subscriber_name', v_subscription.subscriber_name, 'subscription_amount', v_subscription.amount_kzt, 'percent', v_percent, 'backfilled_at', NOW()));
    END IF;
    
    v_created_count := v_created_count + 1;
    v_total_amount := v_total_amount + v_commission_amount;
  END LOOP;
  
  IF NOT p_dry_run THEN
    INSERT INTO admin_actions (admin_id, action_type, target_type, comment, metadata)
    VALUES (p_admin_id, 'backfill_s1_commissions', 'transactions', 'Backfilled ' || v_created_count || ' S1 L1 commissions',
      jsonb_build_object('created_count', v_created_count, 'skipped_count', v_skipped_count, 'total_amount', v_total_amount, 'dry_run', p_dry_run, 'sponsor_id', p_sponsor_id));
  END IF;
  
  RETURN json_build_object('success', true, 'dry_run', p_dry_run, 'created_count', v_created_count, 'skipped_count', v_skipped_count, 'total_amount', v_total_amount,
    'message', CASE WHEN p_dry_run THEN 'Dry run: would create ' || v_created_count || ' commissions totaling ' || v_total_amount || ' KZT'
      ELSE 'Created ' || v_created_count || ' commissions totaling ' || v_total_amount || ' KZT' END);
END;
$$;
