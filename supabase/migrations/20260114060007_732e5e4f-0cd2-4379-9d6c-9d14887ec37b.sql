-- =====================================================
-- ЭТАП 1: Исправить статусы комиссий из backfill
-- 7 комиссий должны быть frozen вместо completed
-- =====================================================

UPDATE transactions t
SET 
  status = 'frozen'::transaction_status,
  frozen_until = s.paid_at + INTERVAL '14 days',
  updated_at = NOW()
FROM subscriptions s
WHERE t.type = 'commission'
  AND t.payload IS NOT NULL
  AND t.payload::text LIKE '%backfill%'
  AND t.status = 'completed'
  AND s.id::text = t.payload->>'subscription_id'
  AND s.paid_at > NOW() - INTERVAL '14 days';

-- =====================================================
-- ЭТАП 2: Исправить функцию admin_audit_user_commissions
-- Сначала удаляем старую версию, затем создаём новую
-- =====================================================

DROP FUNCTION IF EXISTS admin_audit_user_commissions(UUID, UUID);

CREATE FUNCTION admin_audit_user_commissions(
  p_admin_id UUID,
  p_user_id UUID
)
RETURNS TABLE (
  partner_id UUID,
  partner_name TEXT,
  partner_email TEXT,
  level INTEGER,
  subscription_id UUID,
  subscription_amount_kzt NUMERIC,
  commission_received BOOLEAN,
  commission_amount_kzt NUMERIC,
  expected_percent NUMERIC,
  expected_commission_kzt NUMERIC,
  actual_vs_expected TEXT,
  no_commission_reason TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_is_admin BOOLEAN;
BEGIN
  -- Check admin rights
  SELECT EXISTS (
    SELECT 1 FROM user_roles 
    WHERE user_id = p_admin_id 
      AND role IN ('admin', 'superadmin')
  ) INTO v_is_admin;
  
  IF NOT v_is_admin THEN
    RAISE EXCEPTION 'Access denied: admin or superadmin role required';
  END IF;

  RETURN QUERY
  WITH RECURSIVE user_network AS (
    -- Level 1: Direct referrals
    SELECT 
      p.id AS partner_id,
      p.full_name AS partner_name,
      p.email AS partner_email,
      p.sponsor_id,
      1 AS depth
    FROM profiles p
    WHERE p.sponsor_id = p_user_id
      AND p.deleted_at IS NULL
    
    UNION ALL
    
    -- Levels 2-5: Recursive descent
    SELECT 
      p.id,
      p.full_name,
      p.email,
      p.sponsor_id,
      un.depth + 1
    FROM profiles p
    INNER JOIN user_network un ON un.partner_id = p.sponsor_id
    WHERE un.depth < 5
      AND p.deleted_at IS NULL
  ),
  partner_subscriptions AS (
    SELECT 
      un.partner_id,
      un.partner_name,
      un.partner_email,
      un.depth AS partner_level,
      s.id AS sub_id,
      s.amount_kzt AS sub_amount_kzt,
      s.paid_at,
      s.is_marketing_free_access
    FROM user_network un
    LEFT JOIN subscriptions s ON s.user_id = un.partner_id 
      AND s.status = 'active'
      AND s.is_marketing_free_access IS NOT TRUE
  ),
  commission_percents AS (
    SELECT 1 AS lvl, 10.0 AS pct
    UNION ALL SELECT 2, 3.0
    UNION ALL SELECT 3, 2.0
    UNION ALL SELECT 4, 1.0
    UNION ALL SELECT 5, 1.0
  ),
  audit_rows AS (
    SELECT 
      ps.partner_id,
      ps.partner_name,
      ps.partner_email,
      ps.partner_level,
      ps.sub_id,
      ps.sub_amount_kzt,
      ps.is_marketing_free_access,
      cp.pct AS expected_pct,
      ROUND((ps.sub_amount_kzt * cp.pct / 100.0), 0) AS expected_comm,
      -- Check if commission exists for this subscription from p_user_id
      (
        SELECT t.amount_cents
        FROM transactions t
        WHERE t.user_id = p_user_id
          AND t.type = 'commission'
          AND t.structure_type = 'primary'
          AND (
            t.source_id = ps.sub_id
            OR t.payload->>'subscription_id' = ps.sub_id::text
          )
          AND t.level = ps.partner_level
        LIMIT 1
      ) AS actual_commission_cents
    FROM partner_subscriptions ps
    LEFT JOIN commission_percents cp ON cp.lvl = ps.partner_level
    WHERE ps.sub_id IS NOT NULL
  )
  SELECT 
    ar.partner_id,
    ar.partner_name,
    ar.partner_email,
    ar.partner_level AS level,
    ar.sub_id AS subscription_id,
    ar.sub_amount_kzt AS subscription_amount_kzt,
    (ar.actual_commission_cents IS NOT NULL) AS commission_received,
    COALESCE(ar.actual_commission_cents / 100.0, 0) AS commission_amount_kzt,
    ar.expected_pct AS expected_percent,
    ar.expected_comm AS expected_commission_kzt,
    CASE 
      WHEN ar.is_marketing_free_access THEN 'N/A'
      WHEN ar.actual_commission_cents IS NULL AND ar.expected_comm > 0 THEN 'MISSING'
      WHEN ar.actual_commission_cents IS NOT NULL 
        AND ABS((ar.actual_commission_cents / 100.0) - ar.expected_comm) < 1 THEN 'OK'
      WHEN ar.actual_commission_cents IS NOT NULL 
        AND (ar.actual_commission_cents / 100.0) < ar.expected_comm THEN 'UNDERPAID'
      WHEN ar.actual_commission_cents IS NOT NULL 
        AND (ar.actual_commission_cents / 100.0) > ar.expected_comm THEN 'OVERPAID'
      ELSE 'UNKNOWN'
    END AS actual_vs_expected,
    CASE 
      WHEN ar.is_marketing_free_access THEN 'marketing_free_access'
      WHEN ar.actual_commission_cents IS NULL AND ar.expected_comm > 0 THEN 'unknown'
      ELSE NULL
    END AS no_commission_reason
  FROM audit_rows ar
  ORDER BY ar.partner_level, ar.partner_name;
END;
$$;

-- =====================================================
-- ЭТАП 4: Исправить функцию get_referral_network_from_table
-- =====================================================

DROP FUNCTION IF EXISTS get_referral_network_from_table(UUID, INTEGER, INTEGER);

CREATE FUNCTION get_referral_network_from_table(
  root_user_id UUID,
  p_max_levels INTEGER DEFAULT 10,
  p_structure_type INTEGER DEFAULT 1
)
RETURNS TABLE (
  user_id UUID,
  partner_id TEXT,
  email TEXT,
  full_name TEXT,
  referral_code TEXT,
  subscription_status TEXT,
  monthly_activation_met BOOLEAN,
  level INTEGER,
  structure_type INTEGER,
  created_at TIMESTAMPTZ,
  has_commission_received BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  WITH RECURSIVE network AS (
    -- Базовый уровень: прямые рефералы
    SELECT 
      p.id AS user_id,
      p.referral_code AS partner_id,
      p.email,
      p.full_name,
      p.referral_code,
      p.subscription_status,
      p.monthly_activation_completed AS monthly_activation_met,
      1 AS level,
      p_structure_type AS structure_type,
      p.created_at
    FROM profiles p
    WHERE p.sponsor_id = root_user_id
      AND p.deleted_at IS NULL
    
    UNION ALL
    
    -- Рекурсивный спуск по дереву
    SELECT 
      p.id,
      p.referral_code,
      p.email,
      p.full_name,
      p.referral_code,
      p.subscription_status,
      p.monthly_activation_completed,
      n.level + 1,
      p_structure_type,
      p.created_at
    FROM profiles p
    INNER JOIN network n ON n.user_id = p.sponsor_id
    WHERE n.level < p_max_levels
      AND p.deleted_at IS NULL
  )
  SELECT 
    n.user_id,
    n.partner_id,
    n.email,
    n.full_name,
    n.referral_code,
    n.subscription_status,
    n.monthly_activation_met,
    n.level,
    n.structure_type,
    n.created_at,
    -- Проверяем наличие комиссии за этого партнёра (любой формат source_ref)
    EXISTS (
      SELECT 1 FROM transactions t 
      WHERE t.user_id = root_user_id 
        AND t.type = 'commission'
        AND t.structure_type = 'primary'
        AND t.status IN ('completed', 'frozen')
        AND (
          -- Проверяем source_id
          t.source_id = n.user_id
          -- Или проверяем payload.from_user_id
          OR t.payload->>'from_user_id' = n.user_id::text
          -- Или source_ref содержит ID подписки этого партнёра
          OR EXISTS (
            SELECT 1 FROM subscriptions s 
            WHERE s.user_id = n.user_id 
              AND s.status = 'active'
              AND (
                t.source_id = s.id
                OR t.payload->>'subscription_id' = s.id::text
              )
          )
        )
    ) AS has_commission_received
  FROM network n
  ORDER BY n.level, n.full_name;
END;
$$;

-- =====================================================
-- ЭТАП 5: Обновить backfill_missing_multilevel_commissions
-- =====================================================

DROP FUNCTION IF EXISTS backfill_missing_multilevel_commissions(UUID, BOOLEAN, UUID);

CREATE FUNCTION backfill_missing_multilevel_commissions(
  p_admin_id UUID,
  p_dry_run BOOLEAN DEFAULT TRUE,
  p_target_user_id UUID DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_is_admin BOOLEAN;
  v_result JSON;
  v_created_count INTEGER := 0;
  v_skipped_count INTEGER := 0;
  v_total_amount_cents BIGINT := 0;
  v_errors TEXT[] := ARRAY[]::TEXT[];
  v_details JSONB := '[]'::JSONB;
  v_commission_record RECORD;
  v_sponsor_id UUID;
  v_current_level INTEGER;
  v_percent NUMERIC;
  v_commission_amount_cents INTEGER;
  v_existing_commission_id UUID;
  v_new_transaction_id UUID;
  v_freeze_days INTEGER := 14;
  v_status transaction_status;
  v_frozen_until TIMESTAMPTZ;
BEGIN
  -- Check admin rights
  SELECT EXISTS (
    SELECT 1 FROM user_roles 
    WHERE user_id = p_admin_id 
      AND role IN ('admin', 'superadmin')
  ) INTO v_is_admin;
  
  IF NOT v_is_admin THEN
    RAISE EXCEPTION 'Access denied: admin or superadmin role required';
  END IF;

  -- Get commission percents for each level
  CREATE TEMP TABLE IF NOT EXISTS level_percents (
    level INTEGER PRIMARY KEY,
    percent NUMERIC
  ) ON COMMIT DROP;
  
  DELETE FROM level_percents;
  INSERT INTO level_percents VALUES 
    (1, 10.0), (2, 3.0), (3, 2.0), (4, 1.0), (5, 1.0);

  -- Find all active subscriptions that need commission backfill
  FOR v_commission_record IN
    SELECT 
      s.id AS subscription_id,
      s.user_id AS subscriber_id,
      s.amount_kzt,
      s.paid_at,
      p.full_name AS subscriber_name,
      p.sponsor_id AS direct_sponsor_id
    FROM subscriptions s
    INNER JOIN profiles p ON p.id = s.user_id
    WHERE s.status = 'active'
      AND s.is_marketing_free_access IS NOT TRUE
      AND s.paid_at IS NOT NULL
      AND p.sponsor_id IS NOT NULL
      AND p.deleted_at IS NULL
      -- Filter by target user if specified
      AND (p_target_user_id IS NULL OR EXISTS (
        WITH RECURSIVE upline AS (
          SELECT sponsor_id, 1 AS lvl FROM profiles WHERE id = s.user_id
          UNION ALL
          SELECT p2.sponsor_id, u.lvl + 1
          FROM profiles p2
          INNER JOIN upline u ON u.sponsor_id = p2.id
          WHERE u.lvl < 5 AND p2.sponsor_id IS NOT NULL
        )
        SELECT 1 FROM upline WHERE sponsor_id = p_target_user_id
      ))
    ORDER BY s.paid_at DESC
  LOOP
    -- Walk up the sponsor chain for levels 1-5
    v_sponsor_id := v_commission_record.direct_sponsor_id;
    v_current_level := 1;
    
    WHILE v_sponsor_id IS NOT NULL AND v_current_level <= 5 LOOP
      -- Get percent for this level
      SELECT percent INTO v_percent FROM level_percents WHERE level = v_current_level;
      
      IF v_percent IS NOT NULL AND v_percent > 0 THEN
        -- Calculate commission amount in cents (tiyn)
        v_commission_amount_cents := ROUND(v_commission_record.amount_kzt * v_percent);
        
        -- Check if commission already exists
        SELECT id INTO v_existing_commission_id
        FROM transactions
        WHERE user_id = v_sponsor_id
          AND type = 'commission'
          AND structure_type = 'primary'
          AND level = v_current_level
          AND (
            source_id = v_commission_record.subscription_id
            OR payload->>'subscription_id' = v_commission_record.subscription_id::text
          )
        LIMIT 1;
        
        IF v_existing_commission_id IS NULL THEN
          -- Determine frozen status based on subscription paid_at
          IF v_commission_record.paid_at > NOW() - (v_freeze_days || ' days')::INTERVAL THEN
            v_status := 'frozen'::transaction_status;
            v_frozen_until := v_commission_record.paid_at + (v_freeze_days || ' days')::INTERVAL;
          ELSE
            v_status := 'completed'::transaction_status;
            v_frozen_until := NULL;
          END IF;
          
          IF NOT p_dry_run THEN
            -- Create the missing commission
            INSERT INTO transactions (
              user_id,
              type,
              amount_cents,
              currency,
              structure_type,
              level,
              source_id,
              source_ref,
              status,
              frozen_until,
              payload
            ) VALUES (
              v_sponsor_id,
              'commission',
              v_commission_amount_cents,
              'KZT',
              'primary',
              v_current_level,
              v_commission_record.subscription_id,
              'backfill:subscription:' || v_commission_record.subscription_id || ':s1:l' || v_current_level,
              v_status,
              v_frozen_until,
              jsonb_build_object(
                'backfill', true,
                'backfill_date', NOW(),
                'admin_id', p_admin_id,
                'subscription_id', v_commission_record.subscription_id,
                'subscriber_id', v_commission_record.subscriber_id,
                'subscriber_name', v_commission_record.subscriber_name,
                'subscription_amount_kzt', v_commission_record.amount_kzt,
                'level', v_current_level,
                'percent', v_percent
              )
            )
            RETURNING id INTO v_new_transaction_id;
            
            -- Update user balance only if commission is not frozen
            IF v_status = 'completed' THEN
              UPDATE profiles 
              SET balance = COALESCE(balance, 0) + v_commission_amount_cents
              WHERE id = v_sponsor_id;
            END IF;
          END IF;
          
          v_created_count := v_created_count + 1;
          v_total_amount_cents := v_total_amount_cents + v_commission_amount_cents;
          
          v_details := v_details || jsonb_build_object(
            'action', 'create',
            'sponsor_id', v_sponsor_id,
            'level', v_current_level,
            'subscription_id', v_commission_record.subscription_id,
            'subscriber_name', v_commission_record.subscriber_name,
            'amount_cents', v_commission_amount_cents,
            'status', v_status::text,
            'frozen_until', v_frozen_until
          );
        ELSE
          v_skipped_count := v_skipped_count + 1;
        END IF;
      END IF;
      
      -- Move to next sponsor in chain
      SELECT sponsor_id INTO v_sponsor_id
      FROM profiles
      WHERE id = v_sponsor_id AND deleted_at IS NULL;
      
      v_current_level := v_current_level + 1;
    END LOOP;
  END LOOP;

  -- Build result
  v_result := json_build_object(
    'success', true,
    'dry_run', p_dry_run,
    'created_count', v_created_count,
    'skipped_count', v_skipped_count,
    'total_amount_cents', v_total_amount_cents,
    'total_amount_kzt', ROUND(v_total_amount_cents / 100.0, 2),
    'target_user_id', p_target_user_id,
    'errors', v_errors,
    'details', v_details
  );

  -- Log admin action
  IF NOT p_dry_run THEN
    INSERT INTO admin_actions (
      admin_id, action_type, target_type, target_id, metadata
    ) VALUES (
      p_admin_id,
      'backfill_multilevel_commissions',
      'system',
      COALESCE(p_target_user_id::text, 'all'),
      v_result::jsonb
    );
  END IF;

  RETURN v_result;
END;
$$;