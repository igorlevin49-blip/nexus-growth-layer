
-- ============================================
-- COMPREHENSIVE FIX: unlock_levels check for S1 commissions
-- ============================================

-- 1. Fix TRIGGER function: award_s1_subscription_commission
-- This is the main trigger that fires on subscription activation
CREATE OR REPLACE FUNCTION public.award_s1_subscription_commission()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_sponsor_id uuid;
  v_current_user_id uuid;
  v_level integer := 0;
  v_max_level integer := 5;
  v_percent numeric;
  v_amount_cents integer;
  v_commission_cents integer;
  v_frozen_until timestamptz;
  v_sponsor_active boolean;
  v_sponsor_activated boolean;
  v_sponsor_direct_count integer;
  v_unlock_levels jsonb;
  v_required_referrals integer;
BEGIN
  -- Only trigger when status changes TO 'active'
  IF NEW.status != 'active' OR (OLD IS NOT NULL AND OLD.status = 'active') THEN
    RETURN NEW;
  END IF;

  -- Skip test subscriptions
  IF NEW.is_test = true THEN
    RETURN NEW;
  END IF;

  -- Skip marketing free access
  IF NEW.is_marketing_free_access = true THEN
    RETURN NEW;
  END IF;

  v_amount_cents := NEW.amount_kzt;
  v_frozen_until := now() + interval '14 days';
  v_current_user_id := NEW.user_id;

  -- Get unlock_levels settings: {"l2": 3, "l3": 5, "l4": 8, "l5": 10}
  SELECT value INTO v_unlock_levels
  FROM mlm_settings
  WHERE key = 'unlock_levels';
  
  IF v_unlock_levels IS NULL THEN
    v_unlock_levels := '{"l2": 3, "l3": 5, "l4": 8, "l5": 10}'::jsonb;
  END IF;

  -- Get sponsor of the subscriber
  SELECT sponsor_id INTO v_sponsor_id
  FROM public.profiles
  WHERE id = v_current_user_id;

  -- Walk up the sponsor chain
  WHILE v_sponsor_id IS NOT NULL AND v_level < v_max_level LOOP
    v_level := v_level + 1;

    -- *** CRITICAL: Check unlock_levels requirement for levels > 1 ***
    IF v_level > 1 THEN
      -- Get required direct referrals for this level
      v_required_referrals := COALESCE((v_unlock_levels->('l' || v_level))::integer, 999);
      
      -- Count sponsor's direct referrals
      SELECT COUNT(*) INTO v_sponsor_direct_count
      FROM referrals
      WHERE referrer_id = v_sponsor_id
        AND structure_type = 1;
      
      -- Skip this level if sponsor doesn't have enough referrals
      IF v_sponsor_direct_count < v_required_referrals THEN
        -- Move to next sponsor
        SELECT sponsor_id INTO v_sponsor_id
        FROM public.profiles
        WHERE id = v_sponsor_id;
        CONTINUE;
      END IF;
    END IF;

    -- Check sponsor's subscription status
    SELECT 
      (subscription_status = 'active'),
      monthly_activation_completed
    INTO v_sponsor_active, v_sponsor_activated
    FROM public.profiles
    WHERE id = v_sponsor_id;

    -- Only award if sponsor is active and has monthly activation
    IF v_sponsor_active AND v_sponsor_activated THEN
      -- Get commission percent for this level (S1 = structure_type 1)
      SELECT percent INTO v_percent
      FROM public.mlm_commission_rules
      WHERE structure_type = 1
        AND level = v_level
        AND is_active = true
      ORDER BY effective_from DESC
      LIMIT 1;

      IF v_percent IS NOT NULL AND v_percent > 0 THEN
        v_commission_cents := ROUND(v_amount_cents * v_percent / 100);

        IF v_commission_cents > 0 THEN
          -- Insert with unique source_ref and ON CONFLICT DO NOTHING
          INSERT INTO public.transactions (
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
            v_sponsor_id,
            'commission'::transaction_type,
            v_commission_cents,
            'KZT',
            'frozen'::transaction_status,
            NEW.id,
            'subscription_' || NEW.id || '_s1_level_' || v_level,
            v_level,
            'primary'::structure_type,
            v_frozen_until,
            jsonb_build_object(
              'source_type', 'subscription',
              'source_user_id', NEW.user_id,
              'percent', v_percent,
              'base_amount', v_amount_cents,
              'sponsor_direct_count', v_sponsor_direct_count
            )
          )
          ON CONFLICT ON CONSTRAINT unique_source_ref DO NOTHING;
        END IF;
      END IF;
    END IF;

    -- Move to next sponsor
    SELECT sponsor_id INTO v_sponsor_id
    FROM public.profiles
    WHERE id = v_sponsor_id;
  END LOOP;

  RETURN NEW;
END;
$function$;


-- 2. Fix backfill_missing_s1_commissions with unlock_levels check
CREATE OR REPLACE FUNCTION public.backfill_missing_s1_commissions(p_admin_id uuid, p_days_back integer DEFAULT 30)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_subscription record;
  v_sponsor_id uuid;
  v_current_user_id uuid;
  v_level integer;
  v_max_level integer := 5;
  v_percent numeric;
  v_amount_cents integer;
  v_commission_cents integer;
  v_frozen_until timestamptz;
  v_sponsor_active boolean;
  v_sponsor_activated boolean;
  v_sponsor_direct_count integer;
  v_unlock_levels jsonb;
  v_required_referrals integer;
  v_total_commissions integer := 0;
  v_processed_subscriptions integer := 0;
  v_skipped_subscriptions integer := 0;
  v_skipped_unlock integer := 0;
  v_source_ref text;
BEGIN
  -- Verify admin
  IF NOT EXISTS (
    SELECT 1 FROM public.user_roles 
    WHERE user_id = p_admin_id AND role IN ('admin', 'superadmin')
  ) THEN
    RETURN json_build_object('success', false, 'error', 'Unauthorized');
  END IF;

  -- Get unlock_levels settings
  SELECT value INTO v_unlock_levels
  FROM mlm_settings
  WHERE key = 'unlock_levels';
  
  IF v_unlock_levels IS NULL THEN
    v_unlock_levels := '{"l2": 3, "l3": 5, "l4": 8, "l5": 10}'::jsonb;
  END IF;

  -- Process active subscriptions from the last N days
  FOR v_subscription IN
    SELECT s.id, s.user_id, s.amount_kzt, s.paid_at
    FROM public.subscriptions s
    WHERE s.status = 'active'
      AND s.paid_at >= (now() - (p_days_back || ' days')::interval)
      AND s.is_test IS NOT TRUE
      AND s.is_marketing_free_access IS NOT TRUE
    ORDER BY s.paid_at ASC
  LOOP
    v_current_user_id := v_subscription.user_id;
    v_amount_cents := v_subscription.amount_kzt;
    v_frozen_until := COALESCE(v_subscription.paid_at, now()) + interval '14 days';
    v_level := 0;

    -- Get sponsor
    SELECT sponsor_id INTO v_sponsor_id
    FROM public.profiles
    WHERE id = v_current_user_id;

    IF v_sponsor_id IS NULL THEN
      v_skipped_subscriptions := v_skipped_subscriptions + 1;
      CONTINUE;
    END IF;

    v_processed_subscriptions := v_processed_subscriptions + 1;

    -- Walk up sponsor chain
    WHILE v_sponsor_id IS NOT NULL AND v_level < v_max_level LOOP
      v_level := v_level + 1;
      v_source_ref := 'subscription_' || v_subscription.id || '_s1_level_' || v_level;

      -- Check if commission already exists
      IF EXISTS (
        SELECT 1 FROM public.transactions 
        WHERE source_ref = v_source_ref
      ) THEN
        -- Move to next sponsor
        SELECT sponsor_id INTO v_sponsor_id
        FROM public.profiles
        WHERE id = v_sponsor_id;
        CONTINUE;
      END IF;

      -- *** CRITICAL: Check unlock_levels requirement for levels > 1 ***
      IF v_level > 1 THEN
        v_required_referrals := COALESCE((v_unlock_levels->('l' || v_level))::integer, 999);
        
        SELECT COUNT(*) INTO v_sponsor_direct_count
        FROM referrals
        WHERE referrer_id = v_sponsor_id
          AND structure_type = 1;
        
        IF v_sponsor_direct_count < v_required_referrals THEN
          v_skipped_unlock := v_skipped_unlock + 1;
          -- Move to next sponsor
          SELECT sponsor_id INTO v_sponsor_id
          FROM public.profiles
          WHERE id = v_sponsor_id;
          CONTINUE;
        END IF;
      END IF;

      -- Check sponsor qualifications
      SELECT 
        (subscription_status = 'active'),
        monthly_activation_completed
      INTO v_sponsor_active, v_sponsor_activated
      FROM public.profiles
      WHERE id = v_sponsor_id;

      IF v_sponsor_active AND v_sponsor_activated THEN
        SELECT percent INTO v_percent
        FROM public.mlm_commission_rules
        WHERE structure_type = 1
          AND level = v_level
          AND is_active = true
        ORDER BY effective_from DESC
        LIMIT 1;

        IF v_percent IS NOT NULL AND v_percent > 0 THEN
          v_commission_cents := ROUND(v_amount_cents * v_percent / 100);

          IF v_commission_cents > 0 THEN
            INSERT INTO public.transactions (
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
              v_sponsor_id,
              'commission'::transaction_type,
              v_commission_cents,
              'KZT',
              'frozen'::transaction_status,
              v_subscription.id,
              v_source_ref,
              v_level,
              'primary'::structure_type,
              v_frozen_until,
              jsonb_build_object(
                'source_type', 'subscription',
                'source_user_id', v_subscription.user_id,
                'percent', v_percent,
                'base_amount', v_amount_cents,
                'backfilled', true,
                'backfilled_at', now()
              )
            )
            ON CONFLICT ON CONSTRAINT unique_source_ref DO NOTHING;

            v_total_commissions := v_total_commissions + 1;
          END IF;
        END IF;
      END IF;

      -- Move to next sponsor
      SELECT sponsor_id INTO v_sponsor_id
      FROM public.profiles
      WHERE id = v_sponsor_id;
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
$function$;


-- 3. Fix recalculate_all_s1_commissions with unlock_levels check
CREATE OR REPLACE FUNCTION public.recalculate_all_s1_commissions(p_admin_id uuid)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
  v_skipped_unlock integer := 0;
  v_source_ref text;
  v_unlock_levels jsonb;
  v_required_referrals integer;
  v_sponsor_direct_count integer;
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

  -- Get unlock_levels settings
  SELECT value INTO v_unlock_levels
  FROM mlm_settings
  WHERE key = 'unlock_levels';
  
  IF v_unlock_levels IS NULL THEN
    v_unlock_levels := '{"l2": 3, "l3": 5, "l4": 8, "l5": 10}'::jsonb;
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
      
      -- *** CRITICAL: Check unlock_levels requirement for levels > 1 ***
      IF v_current_level > 1 THEN
        v_required_referrals := COALESCE((v_unlock_levels->('l' || v_current_level))::integer, 999);
        
        SELECT COUNT(*) INTO v_sponsor_direct_count
        FROM referrals
        WHERE referrer_id = v_sponsor_id
          AND structure_type = 1;
        
        IF v_sponsor_direct_count < v_required_referrals THEN
          v_skipped_unlock := v_skipped_unlock + 1;
          -- Move to next level
          SELECT sponsor_id INTO v_sponsor_id FROM profiles WHERE id = v_sponsor_id;
          v_current_level := v_current_level + 1;
          CONTINUE;
        END IF;
      END IF;
      
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
        AND type = 'commission'::transaction_type
        AND structure_type = 'primary'::structure_type
      LIMIT 1;
      
      IF v_existing_commission IS NULL THEN
        INSERT INTO transactions (
          user_id, type, amount_cents, status, source_id, source_ref,
          level, structure_type, payload, created_at, updated_at
        ) VALUES (
          v_sponsor_id, 
          'commission'::transaction_type, 
          v_commission_amount, 
          'completed'::transaction_status,
          v_subscription.id, v_source_ref, v_current_level, 
          'primary'::structure_type,
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
    'Recalculated S1 commissions with unlock_levels check',
    jsonb_build_object(
      'subscriptions_processed', v_subscriptions_processed,
      'commissions_created', v_commissions_created,
      'commissions_skipped', v_commissions_skipped,
      'skipped_unlock_levels', v_skipped_unlock
    )
  );

  RETURN json_build_object(
    'success', true,
    'subscriptions_processed', v_subscriptions_processed,
    'commissions_created', v_commissions_created,
    'commissions_skipped', v_commissions_skipped,
    'skipped_unlock_levels', v_skipped_unlock
  );
END;
$function$;


-- 4. Create audit function for unlock_levels violations
CREATE OR REPLACE FUNCTION public.audit_unlock_levels_violations()
RETURNS TABLE(
  user_id uuid,
  user_email text,
  user_name text,
  level integer,
  direct_referrals_count integer,
  required_referrals integer,
  violation_count integer,
  total_wrong_amount_cents bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_unlock_levels jsonb;
BEGIN
  -- Get unlock_levels settings
  SELECT value INTO v_unlock_levels
  FROM mlm_settings
  WHERE key = 'unlock_levels';
  
  IF v_unlock_levels IS NULL THEN
    v_unlock_levels := '{"l2": 3, "l3": 5, "l4": 8, "l5": 10}'::jsonb;
  END IF;

  RETURN QUERY
  WITH unlock_reqs AS (
    SELECT 
      2 as lvl, COALESCE((v_unlock_levels->>'l2')::integer, 3) as required
    UNION ALL SELECT 3, COALESCE((v_unlock_levels->>'l3')::integer, 5)
    UNION ALL SELECT 4, COALESCE((v_unlock_levels->>'l4')::integer, 8)
    UNION ALL SELECT 5, COALESCE((v_unlock_levels->>'l5')::integer, 10)
  ),
  user_direct_counts AS (
    SELECT 
      r.referrer_id as uid,
      COUNT(*) as direct_count
    FROM referrals r
    WHERE r.structure_type = 1
    GROUP BY r.referrer_id
  )
  SELECT 
    t.user_id,
    p.email,
    p.full_name,
    t.level,
    COALESCE(udc.direct_count, 0)::integer,
    ur.required::integer,
    COUNT(*)::integer as violation_count,
    SUM(t.amount_cents)::bigint as total_wrong_amount
  FROM transactions t
  JOIN unlock_reqs ur ON t.level = ur.lvl
  LEFT JOIN user_direct_counts udc ON t.user_id = udc.uid
  LEFT JOIN profiles p ON p.id = t.user_id
  WHERE t.type = 'commission'
    AND t.structure_type = 'primary'
    AND t.level > 1
    AND COALESCE(udc.direct_count, 0) < ur.required
  GROUP BY t.user_id, p.email, p.full_name, t.level, udc.direct_count, ur.required
  ORDER BY total_wrong_amount DESC;
END;
$function$;


-- 5. Create function to fix unlock_levels violations (delete wrong commissions)
CREATE OR REPLACE FUNCTION public.fix_unlock_levels_violations(p_admin_id uuid, p_dry_run boolean DEFAULT true)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_unlock_levels jsonb;
  v_deleted_count integer := 0;
  v_deleted_amount bigint := 0;
  v_violations record;
BEGIN
  -- Verify admin permissions
  IF NOT EXISTS (
    SELECT 1 FROM user_roles 
    WHERE user_id = p_admin_id 
    AND role IN ('admin', 'superadmin')
  ) THEN
    RETURN json_build_object('success', false, 'error', 'Unauthorized');
  END IF;

  -- Get unlock_levels settings
  SELECT value INTO v_unlock_levels
  FROM mlm_settings
  WHERE key = 'unlock_levels';
  
  IF v_unlock_levels IS NULL THEN
    v_unlock_levels := '{"l2": 3, "l3": 5, "l4": 8, "l5": 10}'::jsonb;
  END IF;

  -- Count violations first
  WITH unlock_reqs AS (
    SELECT 
      2 as lvl, COALESCE((v_unlock_levels->>'l2')::integer, 3) as required
    UNION ALL SELECT 3, COALESCE((v_unlock_levels->>'l3')::integer, 5)
    UNION ALL SELECT 4, COALESCE((v_unlock_levels->>'l4')::integer, 8)
    UNION ALL SELECT 5, COALESCE((v_unlock_levels->>'l5')::integer, 10)
  ),
  user_direct_counts AS (
    SELECT 
      r.referrer_id as uid,
      COUNT(*) as direct_count
    FROM referrals r
    WHERE r.structure_type = 1
    GROUP BY r.referrer_id
  ),
  violations AS (
    SELECT t.id, t.amount_cents
    FROM transactions t
    JOIN unlock_reqs ur ON t.level = ur.lvl
    LEFT JOIN user_direct_counts udc ON t.user_id = udc.uid
    WHERE t.type = 'commission'
      AND t.structure_type = 'primary'
      AND t.level > 1
      AND COALESCE(udc.direct_count, 0) < ur.required
  )
  SELECT COUNT(*), COALESCE(SUM(amount_cents), 0)
  INTO v_deleted_count, v_deleted_amount
  FROM violations;

  -- If not dry run, delete the violations
  IF NOT p_dry_run THEN
    WITH unlock_reqs AS (
      SELECT 
        2 as lvl, COALESCE((v_unlock_levels->>'l2')::integer, 3) as required
      UNION ALL SELECT 3, COALESCE((v_unlock_levels->>'l3')::integer, 5)
      UNION ALL SELECT 4, COALESCE((v_unlock_levels->>'l4')::integer, 8)
      UNION ALL SELECT 5, COALESCE((v_unlock_levels->>'l5')::integer, 10)
    ),
    user_direct_counts AS (
      SELECT 
        r.referrer_id as uid,
        COUNT(*) as direct_count
      FROM referrals r
      WHERE r.structure_type = 1
      GROUP BY r.referrer_id
    )
    DELETE FROM transactions t
    USING unlock_reqs ur, user_direct_counts udc
    WHERE t.level = ur.lvl
      AND t.user_id = udc.uid
      AND t.type = 'commission'
      AND t.structure_type = 'primary'
      AND t.level > 1
      AND udc.direct_count < ur.required;

    -- Also delete from users with NO direct referrals at all (not in user_direct_counts)
    WITH unlock_reqs AS (
      SELECT 
        2 as lvl, COALESCE((v_unlock_levels->>'l2')::integer, 3) as required
      UNION ALL SELECT 3, COALESCE((v_unlock_levels->>'l3')::integer, 5)
      UNION ALL SELECT 4, COALESCE((v_unlock_levels->>'l4')::integer, 8)
      UNION ALL SELECT 5, COALESCE((v_unlock_levels->>'l5')::integer, 10)
    ),
    users_with_referrals AS (
      SELECT DISTINCT referrer_id FROM referrals WHERE structure_type = 1
    )
    DELETE FROM transactions t
    WHERE t.type = 'commission'
      AND t.structure_type = 'primary'
      AND t.level > 1
      AND NOT EXISTS (
        SELECT 1 FROM users_with_referrals uwr WHERE uwr.referrer_id = t.user_id
      );

    -- Log action
    INSERT INTO admin_actions (admin_id, action_type, target_type, comment, metadata)
    VALUES (p_admin_id, 'fix_unlock_violations', 'transactions', 
      'Deleted commissions for levels 2-5 where user did not have enough direct referrals',
      jsonb_build_object(
        'deleted_count', v_deleted_count,
        'deleted_amount_cents', v_deleted_amount,
        'dry_run', p_dry_run
      )
    );
  END IF;

  RETURN json_build_object(
    'success', true,
    'dry_run', p_dry_run,
    'would_delete_count', v_deleted_count,
    'would_delete_amount_cents', v_deleted_amount
  );
END;
$function$;
