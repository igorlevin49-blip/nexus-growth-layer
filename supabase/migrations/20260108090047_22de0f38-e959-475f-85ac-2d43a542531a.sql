
-- Fix backfill_missing_s1_commissions function to work without auth context
-- and fix the admin_audit_user_commissions level ambiguity

-- Drop existing function first
DROP FUNCTION IF EXISTS backfill_missing_s1_commissions(uuid, integer);

-- Recreate with fixed logic
CREATE OR REPLACE FUNCTION public.backfill_missing_s1_commissions(
  p_admin_id uuid,
  p_days_back integer DEFAULT 30
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_result json;
  v_subscriptions_processed integer := 0;
  v_commissions_created integer := 0;
  v_commissions_skipped integer := 0;
  v_sub record;
  v_ancestor record;
  v_level_counter integer;
  v_commission_amount numeric;
  v_commission_percent numeric;
  v_freeze_days integer;
  v_existing_count integer;
BEGIN
  -- Check admin role
  IF NOT (has_role(p_admin_id, 'admin') OR has_role(p_admin_id, 'superadmin')) THEN
    RAISE EXCEPTION 'Access denied: admin role required';
  END IF;

  -- Get freeze period
  SELECT COALESCE((value->>'days')::integer, 14) INTO v_freeze_days
  FROM mlm_settings WHERE key = 'commission_freeze_period';
  
  IF v_freeze_days IS NULL THEN
    v_freeze_days := 14;
  END IF;

  -- Process all active subscriptions from last N days that may be missing commissions
  FOR v_sub IN
    SELECT s.id as subscription_id, 
           s.user_id as subscriber_id, 
           s.amount_kzt,
           s.paid_at,
           s.is_marketing_free_access,
           p.sponsor_id,
           p.full_name as subscriber_name
    FROM subscriptions s
    JOIN profiles p ON p.id = s.user_id
    WHERE s.status = 'active'
      AND s.paid_at > NOW() - (p_days_back || ' days')::interval
      AND s.is_marketing_free_access = false
      AND p.deleted_at IS NULL
    ORDER BY s.paid_at ASC
  LOOP
    v_subscriptions_processed := v_subscriptions_processed + 1;
    
    -- Walk up the sponsor chain for up to 5 levels
    v_level_counter := 0;
    
    -- Start from subscriber's sponsor
    FOR v_ancestor IN
      WITH RECURSIVE sponsor_chain AS (
        SELECT id, sponsor_id, is_active, subscription_status, full_name, 1 as chain_level
        FROM profiles
        WHERE id = v_sub.sponsor_id AND deleted_at IS NULL
        
        UNION ALL
        
        SELECT p.id, p.sponsor_id, p.is_active, p.subscription_status, p.full_name, sc.chain_level + 1
        FROM profiles p
        JOIN sponsor_chain sc ON p.id = sc.sponsor_id
        WHERE sc.chain_level < 5 AND p.deleted_at IS NULL
      )
      SELECT * FROM sponsor_chain ORDER BY chain_level
    LOOP
      v_level_counter := v_ancestor.chain_level;
      
      -- Skip if ancestor not active
      IF NOT v_ancestor.is_active OR v_ancestor.subscription_status != 'active' THEN
        v_commissions_skipped := v_commissions_skipped + 1;
        CONTINUE;
      END IF;
      
      -- Get commission percent for this level
      SELECT percent INTO v_commission_percent
      FROM mlm_commission_rules
      WHERE structure_type = 1 
        AND level = v_level_counter 
        AND is_active = true
      LIMIT 1;
      
      IF v_commission_percent IS NULL OR v_commission_percent <= 0 THEN
        CONTINUE;
      END IF;
      
      -- Check if commission already exists
      SELECT COUNT(*) INTO v_existing_count
      FROM transactions
      WHERE source_id = v_sub.subscription_id
        AND user_id = v_ancestor.id
        AND type = 'commission'
        AND structure_type = 'primary';
      
      IF v_existing_count > 0 THEN
        v_commissions_skipped := v_commissions_skipped + 1;
        CONTINUE;
      END IF;
      
      -- Calculate commission (amount is already in KZT)
      v_commission_amount := ROUND(v_sub.amount_kzt * v_commission_percent / 100);
      
      IF v_commission_amount <= 0 THEN
        CONTINUE;
      END IF;
      
      -- Insert the commission transaction
      INSERT INTO transactions (
        user_id,
        type,
        amount_cents,
        currency,
        status,
        level,
        structure_type,
        source_id,
        source_ref,
        frozen_until,
        payload
      ) VALUES (
        v_ancestor.id,
        'commission',
        v_commission_amount,  -- Now in KZT
        'KZT',
        'frozen',
        v_level_counter,
        'primary',
        v_sub.subscription_id,
        'subscription:' || v_sub.subscription_id,
        v_sub.paid_at + (v_freeze_days || ' days')::interval,
        jsonb_build_object(
          'base_amount', v_sub.amount_kzt,
          'percent', v_commission_percent,
          'from_user_id', v_sub.subscriber_id,
          'partner_name', v_sub.subscriber_name,
          'backfill', true
        )
      );
      
      v_commissions_created := v_commissions_created + 1;
    END LOOP;
  END LOOP;

  -- Log the action
  INSERT INTO admin_actions (admin_id, action_type, target_type, metadata)
  VALUES (p_admin_id, 'backfill_s1_commissions', 'system', jsonb_build_object(
    'subscriptions_processed', v_subscriptions_processed,
    'commissions_created', v_commissions_created,
    'commissions_skipped', v_commissions_skipped,
    'days_back', p_days_back
  ));

  RETURN json_build_object(
    'success', true,
    'subscriptions_processed', v_subscriptions_processed,
    'commissions_created', v_commissions_created,
    'commissions_skipped', v_commissions_skipped
  );
END;
$function$;

-- Also fix admin_audit_user_commissions to resolve level ambiguity
DROP FUNCTION IF EXISTS admin_audit_user_commissions(uuid, uuid);

CREATE OR REPLACE FUNCTION public.admin_audit_user_commissions(
  p_admin_id uuid,
  p_user_id uuid
)
RETURNS TABLE (
  partner_id uuid,
  partner_name text,
  partner_email text,
  level integer,
  subscription_id uuid,
  subscription_amount_kzt numeric,
  commission_received boolean,
  commission_amount_cents bigint,
  expected_percent numeric,
  expected_commission_cents bigint,
  actual_vs_expected text,
  no_commission_reason text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
BEGIN
  -- Check admin access
  IF NOT (has_role(p_admin_id, 'admin') OR has_role(p_admin_id, 'superadmin')) THEN
    RAISE EXCEPTION 'Access denied';
  END IF;

  RETURN QUERY
  WITH RECURSIVE network AS (
    -- Direct referrals
    SELECT 
      p.id as user_id,
      1 as lvl
    FROM profiles p
    WHERE p.sponsor_id = p_user_id
      AND p.deleted_at IS NULL
    
    UNION ALL
    
    -- Deeper levels (max 5 for S1)
    SELECT 
      p.id as user_id,
      n.lvl + 1 as lvl
    FROM profiles p
    INNER JOIN network n ON p.sponsor_id = n.user_id
    WHERE n.lvl < 5
      AND p.deleted_at IS NULL
  ),
  -- Get S1 commission percentages
  commission_rates AS (
    SELECT mcr.level as cr_level, mcr.percent as cr_percent
    FROM mlm_commission_rules mcr
    WHERE mcr.structure_type = 1 AND mcr.is_active = true
  ),
  -- Partner subscriptions with commission info
  partner_subs AS (
    SELECT 
      n.user_id as ps_partner_id,
      p.full_name as ps_full_name,
      p.email as ps_email,
      n.lvl as ps_level,
      s.id as ps_subscription_id,
      s.amount_kzt as ps_amount_kzt,
      cr.cr_percent as ps_rate_percent,
      -- Check if commission exists for this subscription
      (
        SELECT t.id 
        FROM transactions t 
        WHERE t.source_id = s.id 
          AND t.user_id = p_user_id 
          AND t.type = 'commission'
          AND t.structure_type = 'primary'
        LIMIT 1
      ) as commission_tx_id,
      (
        SELECT t.amount_cents 
        FROM transactions t 
        WHERE t.source_id = s.id 
          AND t.user_id = p_user_id 
          AND t.type = 'commission'
          AND t.structure_type = 'primary'
        LIMIT 1
      ) as actual_commission,
      -- Expected commission
      ROUND(s.amount_kzt * COALESCE(cr.cr_percent, 0) / 100) as expected_commission,
      -- Reason if no commission
      CASE
        WHEN s.status != 'active' THEN 'subscription_not_active'
        WHEN s.is_marketing_free_access THEN 'marketing_free_access'
        WHEN n.lvl > 5 THEN 'too_deep'
        ELSE 'unknown'
      END as reason
    FROM network n
    JOIN profiles p ON p.id = n.user_id
    LEFT JOIN subscriptions s ON s.user_id = n.user_id AND s.status = 'active'
    LEFT JOIN commission_rates cr ON cr.cr_level = n.lvl
    WHERE s.id IS NOT NULL
  )
  SELECT 
    ps.ps_partner_id,
    ps.ps_full_name,
    ps.ps_email,
    ps.ps_level,
    ps.ps_subscription_id,
    ps.ps_amount_kzt,
    (ps.commission_tx_id IS NOT NULL),
    ps.actual_commission::bigint,
    ps.ps_rate_percent,
    ps.expected_commission::bigint,
    CASE
      WHEN ps.commission_tx_id IS NULL THEN 'MISSING'
      WHEN ps.actual_commission = ps.expected_commission THEN 'OK'
      WHEN ps.actual_commission < ps.expected_commission THEN 'UNDERPAID'
      ELSE 'OVERPAID'
    END,
    CASE
      WHEN ps.commission_tx_id IS NOT NULL THEN NULL
      ELSE ps.reason
    END
  FROM partner_subs ps
  ORDER BY ps.ps_level, ps.ps_full_name;
END;
$function$;
