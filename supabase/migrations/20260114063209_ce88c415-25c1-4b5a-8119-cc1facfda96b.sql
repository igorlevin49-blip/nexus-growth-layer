
-- ============================================================
-- DROP existing functions first (signature changed)
-- ============================================================
DROP FUNCTION IF EXISTS public.admin_audit_user_commissions(uuid, uuid);
DROP FUNCTION IF EXISTS public.backfill_missing_multilevel_commissions(uuid, boolean, uuid);
DROP FUNCTION IF EXISTS public.get_referral_network_from_table(uuid, integer, integer);

-- ============================================================
-- FIX 1: admin_audit_user_commissions
-- Remove /100 division, read percentages from mlm_commission_rules
-- ============================================================

CREATE OR REPLACE FUNCTION public.admin_audit_user_commissions(p_admin_id uuid, p_user_id uuid)
RETURNS TABLE(
  subscription_id uuid,
  partner_id uuid,
  partner_name text,
  partner_email text,
  level integer,
  subscription_amount_kzt numeric,
  expected_percent numeric,
  expected_commission_kzt numeric,
  commission_received boolean,
  commission_amount_kzt numeric,
  no_commission_reason text,
  actual_vs_expected text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Check admin access
  IF NOT EXISTS (
    SELECT 1 FROM user_roles 
    WHERE user_id = p_admin_id AND role IN ('admin', 'superadmin')
  ) THEN
    RAISE EXCEPTION 'Unauthorized: admin access required';
  END IF;

  RETURN QUERY
  WITH RECURSIVE
  -- Get commission percentages from mlm_commission_rules (NOT hardcoded!)
  commission_percents AS (
    SELECT level AS lvl, percent AS pct
    FROM mlm_commission_rules
    WHERE structure_type = 1 
      AND plan_id = 'default' 
      AND is_active = true
  ),
  -- Build referral tree downwards from target user
  referral_tree AS (
    -- Direct referrals (level 1)
    SELECT 
      r.referred_user_id,
      r.referrer_id,
      1 AS level
    FROM referrals r
    WHERE r.referrer_id = p_user_id
      AND r.structure_type = 1
    
    UNION ALL
    
    -- Deeper levels
    SELECT 
      r.referred_user_id,
      r.referrer_id,
      rt.level + 1
    FROM referrals r
    INNER JOIN referral_tree rt ON r.referrer_id = rt.referred_user_id
    WHERE r.structure_type = 1
      AND rt.level < 5
  ),
  -- Get subscriptions from network members
  network_subscriptions AS (
    SELECT 
      s.id AS subscription_id,
      s.user_id AS partner_id,
      p.full_name AS partner_name,
      p.email AS partner_email,
      rt.level,
      s.amount_kzt,
      s.is_marketing_free_access,
      s.status,
      s.paid_at
    FROM referral_tree rt
    INNER JOIN profiles p ON p.id = rt.referred_user_id
    INNER JOIN subscriptions s ON s.user_id = rt.referred_user_id
    WHERE s.status = 'active'
      AND s.paid_at IS NOT NULL
  ),
  -- Calculate expected commissions
  expected_commissions AS (
    SELECT 
      ns.subscription_id,
      ns.partner_id,
      ns.partner_name,
      ns.partner_email,
      ns.level,
      ns.amount_kzt,
      ns.is_marketing_free_access,
      COALESCE(cp.pct, 0) AS expected_pct,
      CASE 
        WHEN ns.is_marketing_free_access = true THEN 0
        ELSE ROUND(ns.amount_kzt * COALESCE(cp.pct, 0) / 100)
      END AS expected_comm
    FROM network_subscriptions ns
    LEFT JOIN commission_percents cp ON cp.lvl = ns.level
  ),
  -- Get actual commissions received (amount_cents stores KZT, NOT cents!)
  actual_commissions AS (
    SELECT 
      t.source_id,
      t.level,
      SUM(t.amount_cents) AS actual_commission_kzt  -- NO division by 100!
    FROM transactions t
    WHERE t.user_id = p_user_id
      AND t.type = 'commission'
      AND t.structure_type = 'S1'
      AND t.status IN ('available', 'frozen')
    GROUP BY t.source_id, t.level
  ),
  -- Combine expected and actual
  audit_results AS (
    SELECT 
      ec.subscription_id,
      ec.partner_id,
      ec.partner_name,
      ec.partner_email,
      ec.level,
      ec.amount_kzt AS subscription_amount_kzt,
      ec.expected_pct,
      ec.expected_comm,
      ec.is_marketing_free_access,
      COALESCE(ac.actual_commission_kzt, 0) AS actual_commission_kzt
    FROM expected_commissions ec
    LEFT JOIN actual_commissions ac 
      ON ac.source_id = ec.subscription_id 
      AND ac.level = ec.level
  )
  SELECT 
    ar.subscription_id,
    ar.partner_id,
    ar.partner_name,
    ar.partner_email,
    ar.level,
    ar.subscription_amount_kzt,
    ar.expected_pct AS expected_percent,
    ar.expected_comm AS expected_commission_kzt,
    (ar.actual_commission_kzt > 0) AS commission_received,
    ar.actual_commission_kzt AS commission_amount_kzt,
    CASE 
      WHEN ar.is_marketing_free_access = true THEN 'marketing_free_access'
      WHEN ar.actual_commission_kzt = 0 AND ar.expected_comm > 0 THEN 'no_commission'
      ELSE NULL
    END AS no_commission_reason,
    CASE 
      WHEN ar.is_marketing_free_access = true THEN 'SKIPPED (free access)'
      WHEN ar.expected_comm = 0 THEN 'N/A'
      WHEN ABS(ar.actual_commission_kzt - ar.expected_comm) < 100 THEN 'OK'
      WHEN ar.actual_commission_kzt > ar.expected_comm THEN 'OVERPAID'
      WHEN ar.actual_commission_kzt < ar.expected_comm THEN 'UNDERPAID'
      ELSE 'UNKNOWN'
    END AS actual_vs_expected
  FROM audit_results ar
  ORDER BY ar.level, ar.partner_name;
END;
$$;

-- ============================================================
-- FIX 2: backfill_missing_multilevel_commissions
-- Read percentages from mlm_commission_rules, fix calculation
-- ============================================================

CREATE OR REPLACE FUNCTION public.backfill_missing_multilevel_commissions(
  p_admin_id uuid,
  p_dry_run boolean DEFAULT true,
  p_target_user_id uuid DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_result json;
  v_created_count integer := 0;
  v_skipped_count integer := 0;
  v_error_count integer := 0;
  v_total_amount_kzt numeric := 0;
  v_details jsonb := '[]'::jsonb;
  v_commission_record record;
  v_recipient record;
  v_percent numeric;
  v_commission_amount_kzt numeric;
  v_freeze_days integer := 30;
  v_new_tx_id uuid;
BEGIN
  -- Check admin access
  IF NOT EXISTS (
    SELECT 1 FROM user_roles 
    WHERE user_id = p_admin_id AND role IN ('admin', 'superadmin')
  ) THEN
    RETURN json_build_object('success', false, 'error', 'Unauthorized');
  END IF;

  -- Create temp table for level percentages from mlm_commission_rules
  CREATE TEMP TABLE IF NOT EXISTS level_percents (lvl integer, pct numeric) ON COMMIT DROP;
  TRUNCATE level_percents;
  
  -- Read percentages from database (NOT hardcoded!)
  INSERT INTO level_percents (lvl, pct)
  SELECT level, percent
  FROM mlm_commission_rules
  WHERE structure_type = 1 
    AND plan_id = 'default' 
    AND is_active = true;

  -- Find subscriptions that need multilevel commissions
  FOR v_commission_record IN
    SELECT 
      s.id AS subscription_id,
      s.user_id AS subscriber_id,
      s.amount_kzt,
      s.paid_at,
      p.sponsor_id,
      p.full_name AS subscriber_name
    FROM subscriptions s
    INNER JOIN profiles p ON p.id = s.user_id
    WHERE s.status = 'active'
      AND s.paid_at IS NOT NULL
      AND s.is_marketing_free_access IS NOT TRUE
      AND (p_target_user_id IS NULL OR p.sponsor_id = p_target_user_id)
    ORDER BY s.paid_at
  LOOP
    -- Traverse upline for levels 1-5
    FOR v_recipient IN
      WITH RECURSIVE upline AS (
        SELECT 
          p.id AS user_id,
          p.sponsor_id,
          p.full_name,
          p.email,
          1 AS level
        FROM profiles p
        WHERE p.id = v_commission_record.sponsor_id
        
        UNION ALL
        
        SELECT 
          p.id,
          p.sponsor_id,
          p.full_name,
          p.email,
          u.level + 1
        FROM profiles p
        INNER JOIN upline u ON p.id = u.sponsor_id
        WHERE u.level < 5
      )
      SELECT * FROM upline
    LOOP
      -- Get percentage for this level
      SELECT pct INTO v_percent FROM level_percents WHERE lvl = v_recipient.level;
      
      IF v_percent IS NULL OR v_percent = 0 THEN
        CONTINUE;
      END IF;
      
      -- Calculate commission: amount_kzt * percent / 100
      -- e.g., 55000 * 10 / 100 = 5500 KZT
      v_commission_amount_kzt := ROUND(v_commission_record.amount_kzt * v_percent / 100);
      
      -- Check if commission already exists
      IF EXISTS (
        SELECT 1 FROM transactions t
        WHERE t.user_id = v_recipient.user_id
          AND t.source_id = v_commission_record.subscription_id
          AND t.level = v_recipient.level
          AND t.type = 'commission'
          AND t.structure_type = 'S1'
      ) THEN
        v_skipped_count := v_skipped_count + 1;
        CONTINUE;
      END IF;
      
      -- Create commission if not dry run
      IF NOT p_dry_run THEN
        INSERT INTO transactions (
          user_id,
          type,
          amount_cents,  -- stores KZT, not cents
          currency,
          status,
          source_id,
          source_ref,
          level,
          structure_type,
          frozen_until,
          payload
        ) VALUES (
          v_recipient.user_id,
          'commission',
          v_commission_amount_kzt,
          'KZT',
          'frozen',
          v_commission_record.subscription_id,
          'subscription',
          v_recipient.level,
          'S1',
          NOW() + (v_freeze_days || ' days')::interval,
          jsonb_build_object(
            'backfill', true,
            'admin_id', p_admin_id,
            'subscriber_id', v_commission_record.subscriber_id,
            'subscriber_name', v_commission_record.subscriber_name,
            'subscription_amount_kzt', v_commission_record.amount_kzt,
            'percent', v_percent
          )
        )
        RETURNING id INTO v_new_tx_id;
      END IF;
      
      v_created_count := v_created_count + 1;
      v_total_amount_kzt := v_total_amount_kzt + v_commission_amount_kzt;
      
      v_details := v_details || jsonb_build_object(
        'recipient_id', v_recipient.user_id,
        'recipient_name', v_recipient.full_name,
        'level', v_recipient.level,
        'percent', v_percent,
        'amount_kzt', v_commission_amount_kzt,
        'subscriber_name', v_commission_record.subscriber_name,
        'subscription_id', v_commission_record.subscription_id
      );
    END LOOP;
  END LOOP;

  -- Log admin action
  IF NOT p_dry_run AND v_created_count > 0 THEN
    INSERT INTO admin_audit (
      admin_id,
      action_type,
      target_type,
      target_id,
      metadata
    ) VALUES (
      p_admin_id,
      'backfill_multilevel_commissions',
      'system',
      COALESCE(p_target_user_id::text, 'all'),
      jsonb_build_object(
        'created_count', v_created_count,
        'total_amount_kzt', v_total_amount_kzt
      )
    );
  END IF;

  RETURN json_build_object(
    'success', true,
    'dry_run', p_dry_run,
    'created_count', v_created_count,
    'skipped_count', v_skipped_count,
    'total_amount_kzt', v_total_amount_kzt,
    'details', v_details
  );
END;
$$;

-- ============================================================
-- FIX 3: get_referral_network_from_table
-- Add no_commission_reason column
-- ============================================================

CREATE OR REPLACE FUNCTION public.get_referral_network_from_table(
  root_user_id uuid,
  p_max_levels integer DEFAULT 10,
  p_structure_type integer DEFAULT 1
)
RETURNS TABLE(
  user_id uuid,
  partner_id text,
  email text,
  full_name text,
  referral_code text,
  subscription_status text,
  monthly_activation_met boolean,
  level integer,
  structure_type integer,
  created_at timestamptz,
  has_commission_received boolean,
  no_commission_reason text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  WITH RECURSIVE network AS (
    -- Direct referrals (level 1)
    SELECT 
      r.referred_user_id AS user_id,
      1 AS level
    FROM referrals r
    WHERE r.referrer_id = root_user_id
      AND r.structure_type = p_structure_type
    
    UNION ALL
    
    -- Deeper levels
    SELECT 
      r.referred_user_id,
      n.level + 1
    FROM referrals r
    INNER JOIN network n ON r.referrer_id = n.user_id
    WHERE r.structure_type = p_structure_type
      AND n.level < p_max_levels
  ),
  -- Check if commission was received from each network member
  commission_check AS (
    SELECT 
      t.source_id,
      true AS has_commission
    FROM transactions t
    WHERE t.user_id = root_user_id
      AND t.type = 'commission'
      AND t.structure_type = (CASE WHEN p_structure_type = 1 THEN 'S1' ELSE 'S2' END)::structure_type
      AND t.status IN ('available', 'frozen')
    GROUP BY t.source_id
  )
  SELECT 
    p.id AS user_id,
    p.referral_code AS partner_id,
    p.email,
    p.full_name,
    p.referral_code,
    p.subscription_status,
    COALESCE(p.monthly_activation_completed, false) AS monthly_activation_met,
    n.level,
    p_structure_type AS structure_type,
    p.created_at,
    COALESCE(cc.has_commission, false) AS has_commission_received,
    -- Determine reason for no commission
    CASE 
      WHEN cc.has_commission = true THEN NULL
      WHEN p.subscription_status IS NULL OR p.subscription_status != 'active' THEN 'partner_no_subscription'
      WHEN p_structure_type = 1 AND n.level > 5 THEN 'too_deep'
      WHEN p_structure_type = 2 AND n.level > 10 THEN 'too_deep'
      WHEN EXISTS (
        SELECT 1 FROM subscriptions s 
        WHERE s.user_id = p.id 
          AND s.status = 'active' 
          AND s.is_marketing_free_access = true
      ) THEN 'marketing_free_access'
      WHEN p_structure_type = 2 AND COALESCE(p.monthly_activation_completed, false) = false THEN 'partner_no_activation'
      ELSE 'no_commission'
    END AS no_commission_reason
  FROM network n
  INNER JOIN profiles p ON p.id = n.user_id
  LEFT JOIN subscriptions s ON s.user_id = p.id AND s.status = 'active'
  LEFT JOIN commission_check cc ON cc.source_id = s.id
  ORDER BY n.level, p.full_name;
END;
$$;
