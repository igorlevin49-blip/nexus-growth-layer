-- First drop the old function to change return type
DROP FUNCTION IF EXISTS public.get_commission_structure_stats(uuid, int, timestamptz, timestamptz);

-- Fix award_s1_subscription_commission function to use correct unlock_levels key format
CREATE OR REPLACE FUNCTION public.award_s1_subscription_commission(
  p_subscription_id uuid,
  p_subscriber_id uuid,
  p_amount_kzt numeric
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_current_user_id uuid;
  v_level int := 0;
  v_max_level int := 5;
  v_percent numeric;
  v_commission_amount numeric;
  v_freeze_days int := 30;
  v_unlock_levels jsonb;
  v_required_referrals int;
  v_active_referrals int;
  v_commissions_created int := 0;
  v_commissions_skipped int := 0;
  v_skip_reasons jsonb := '[]'::jsonb;
  v_rule record;
  v_is_marketing_free boolean;
BEGIN
  -- Check if subscription is marketing_free_access
  SELECT is_marketing_free_access INTO v_is_marketing_free
  FROM subscriptions
  WHERE id = p_subscription_id;
  
  IF v_is_marketing_free = true THEN
    RETURN jsonb_build_object(
      'success', true,
      'message', 'Marketing free access - no commissions',
      'commissions_created', 0,
      'commissions_skipped', 0
    );
  END IF;

  -- Get unlock_levels from mlm_settings with CORRECT default values
  SELECT value INTO v_unlock_levels
  FROM mlm_settings
  WHERE key = 'unlock_levels';
  
  -- Default unlock levels with correct keys (l2, l3, l4, l5)
  IF v_unlock_levels IS NULL THEN
    v_unlock_levels := '{"l2": 3, "l3": 5, "l4": 8, "l5": 10}'::jsonb;
  END IF;
  
  -- Get freeze days
  SELECT COALESCE((value::text)::int, 30) INTO v_freeze_days
  FROM mlm_settings
  WHERE key = 'freeze_days';

  -- Start from subscriber's sponsor
  SELECT sponsor_id INTO v_current_user_id
  FROM profiles
  WHERE id = p_subscriber_id;

  -- Traverse up the referral chain
  WHILE v_current_user_id IS NOT NULL AND v_level < v_max_level LOOP
    v_level := v_level + 1;
    
    -- Get commission percent for this level
    SELECT percent INTO v_percent
    FROM mlm_commission_rules
    WHERE structure_type = 1
      AND level = v_level
      AND is_active = true
    ORDER BY effective_from DESC
    LIMIT 1;
    
    IF v_percent IS NULL THEN
      v_commissions_skipped := v_commissions_skipped + 1;
      v_skip_reasons := v_skip_reasons || jsonb_build_object(
        'level', v_level,
        'user_id', v_current_user_id,
        'reason', 'no_commission_rule'
      );
    ELSE
      -- Check level unlock requirements for levels > 1
      IF v_level > 1 THEN
        -- FIXED: Use correct key format 'l2', 'l3', etc.
        v_required_referrals := COALESCE(
          (v_unlock_levels->('l' || v_level::text))::int,
          CASE v_level
            WHEN 2 THEN 3
            WHEN 3 THEN 5
            WHEN 4 THEN 8
            WHEN 5 THEN 10
            ELSE v_level - 1
          END
        );
        
        -- Count ACTIVE direct referrals (subscription_status = 'active')
        SELECT COUNT(*) INTO v_active_referrals
        FROM profiles
        WHERE sponsor_id = v_current_user_id
          AND subscription_status = 'active'
          AND deleted_at IS NULL;
        
        IF v_active_referrals < v_required_referrals THEN
          v_commissions_skipped := v_commissions_skipped + 1;
          v_skip_reasons := v_skip_reasons || jsonb_build_object(
            'level', v_level,
            'user_id', v_current_user_id,
            'reason', 'level_locked',
            'required_referrals', v_required_referrals,
            'active_referrals', v_active_referrals
          );
          
          -- Move to next sponsor
          SELECT sponsor_id INTO v_current_user_id
          FROM profiles
          WHERE id = v_current_user_id;
          
          CONTINUE;
        END IF;
      END IF;
      
      -- Calculate commission (round to whole KZT)
      v_commission_amount := ROUND(p_amount_kzt * v_percent / 100);
      
      IF v_commission_amount > 0 THEN
        -- Check for duplicate
        IF NOT EXISTS (
          SELECT 1 FROM transactions
          WHERE user_id = v_current_user_id
            AND source_ref = p_subscription_id::text
            AND type = 'commission'
            AND structure_type = 'primary'
            AND level = v_level
        ) THEN
          -- Create frozen commission
          INSERT INTO transactions (
            user_id,
            type,
            amount_cents,
            currency,
            status,
            structure_type,
            level,
            source_ref,
            source_id,
            frozen_until,
            payload
          ) VALUES (
            v_current_user_id,
            'commission',
            v_commission_amount,
            'KZT',
            'frozen',
            'primary',
            v_level,
            p_subscription_id::text,
            p_subscriber_id::text,
            NOW() + (v_freeze_days || ' days')::interval,
            jsonb_build_object(
              'subscriber_id', p_subscriber_id,
              'subscription_id', p_subscription_id,
              'subscription_amount', p_amount_kzt,
              'percent', v_percent
            )
          );
          
          v_commissions_created := v_commissions_created + 1;
        ELSE
          v_commissions_skipped := v_commissions_skipped + 1;
          v_skip_reasons := v_skip_reasons || jsonb_build_object(
            'level', v_level,
            'user_id', v_current_user_id,
            'reason', 'duplicate'
          );
        END IF;
      END IF;
    END IF;
    
    -- Move to next sponsor
    SELECT sponsor_id INTO v_current_user_id
    FROM profiles
    WHERE id = v_current_user_id;
  END LOOP;

  RETURN jsonb_build_object(
    'success', true,
    'commissions_created', v_commissions_created,
    'commissions_skipped', v_commissions_skipped,
    'skip_reasons', v_skip_reasons
  );
END;
$$;

-- Recreate get_commission_structure_stats with correct key format
CREATE OR REPLACE FUNCTION public.get_commission_structure_stats(
  p_user_id uuid,
  p_structure_type int DEFAULT 1,
  p_start_date timestamptz DEFAULT NULL,
  p_end_date timestamptz DEFAULT NULL
)
RETURNS TABLE (
  level int,
  percent numeric,
  earned_cents numeric,
  frozen_cents numeric,
  volume_cents numeric,
  partners_count int,
  status text,
  unlock_requirement text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_max_level int;
  v_unlock_levels jsonb;
  v_active_referrals int;
BEGIN
  -- Get max level and unlock settings
  IF p_structure_type = 1 THEN
    v_max_level := 5;
  ELSE
    v_max_level := 10;
  END IF;
  
  -- Get unlock_levels from settings
  SELECT value INTO v_unlock_levels
  FROM mlm_settings
  WHERE key = 'unlock_levels';
  
  IF v_unlock_levels IS NULL THEN
    v_unlock_levels := '{"l2": 3, "l3": 5, "l4": 8, "l5": 10}'::jsonb;
  END IF;
  
  -- Count active direct referrals
  SELECT COUNT(*) INTO v_active_referrals
  FROM profiles
  WHERE sponsor_id = p_user_id
    AND subscription_status = 'active'
    AND deleted_at IS NULL;

  RETURN QUERY
  WITH levels AS (
    SELECT generate_series(1, v_max_level) AS lvl
  ),
  rules AS (
    SELECT DISTINCT ON (mcr.level)
      mcr.level,
      mcr.percent
    FROM mlm_commission_rules mcr
    WHERE mcr.structure_type = p_structure_type
      AND mcr.is_active = true
    ORDER BY mcr.level, mcr.effective_from DESC
  ),
  partners AS (
    SELECT 
      rn.level AS partner_level,
      COUNT(*) AS cnt
    FROM get_referral_network_from_table(p_user_id, v_max_level, p_structure_type) rn
    WHERE rn.user_id != p_user_id
    GROUP BY rn.level
  ),
  commissions AS (
    SELECT 
      t.level AS comm_level,
      SUM(CASE WHEN t.status = 'completed' THEN t.amount_cents ELSE 0 END) AS earned,
      SUM(CASE WHEN t.status = 'frozen' THEN t.amount_cents ELSE 0 END) AS frozen
    FROM transactions t
    WHERE t.user_id = p_user_id
      AND t.type = 'commission'
      AND t.structure_type = (CASE WHEN p_structure_type = 1 THEN 'primary' ELSE 'secondary' END)::structure_type
      AND (p_start_date IS NULL OR t.created_at >= p_start_date)
      AND (p_end_date IS NULL OR t.created_at <= p_end_date)
    GROUP BY t.level
  ),
  volumes AS (
    SELECT 
      rn.level AS vol_level,
      COALESCE(SUM(
        CASE 
          WHEN p_structure_type = 1 THEN s.amount_kzt
          ELSE oi.price_kzt * oi.qty
        END
      ), 0) AS volume
    FROM get_referral_network_from_table(p_user_id, v_max_level, p_structure_type) rn
    LEFT JOIN subscriptions s ON p_structure_type = 1 
      AND s.user_id = rn.partner_id 
      AND s.status = 'active'
      AND (p_start_date IS NULL OR s.paid_at >= p_start_date)
      AND (p_end_date IS NULL OR s.paid_at <= p_end_date)
    LEFT JOIN orders o ON p_structure_type = 2 
      AND o.user_id = rn.partner_id 
      AND o.status = 'paid'
      AND (p_start_date IS NULL OR o.paid_at >= p_start_date)
      AND (p_end_date IS NULL OR o.paid_at <= p_end_date)
    LEFT JOIN order_items oi ON o.id = oi.order_id
    WHERE rn.user_id != p_user_id
    GROUP BY rn.level
  )
  SELECT
    l.lvl AS level,
    COALESCE(r.percent, 0) AS percent,
    COALESCE(c.earned, 0) AS earned_cents,
    COALESCE(c.frozen, 0) AS frozen_cents,
    COALESCE(v.volume, 0) AS volume_cents,
    COALESCE(p.cnt, 0)::int AS partners_count,
    CASE
      WHEN l.lvl = 1 THEN 'active'
      WHEN p_structure_type = 2 THEN 'active'
      WHEN v_active_referrals >= COALESCE(
        (v_unlock_levels->('l' || l.lvl::text))::int,
        CASE l.lvl
          WHEN 2 THEN 3
          WHEN 3 THEN 5
          WHEN 4 THEN 8
          WHEN 5 THEN 10
          ELSE l.lvl - 1
        END
      ) THEN 'active'
      ELSE 'locked'
    END AS status,
    CASE
      WHEN l.lvl = 1 THEN NULL
      WHEN p_structure_type = 2 THEN NULL
      ELSE COALESCE(
        (v_unlock_levels->('l' || l.lvl::text))::int,
        CASE l.lvl
          WHEN 2 THEN 3
          WHEN 3 THEN 5
          WHEN 4 THEN 8
          WHEN 5 THEN 10
          ELSE l.lvl - 1
        END
      )::text || ' активных партнёров'
    END AS unlock_requirement
  FROM levels l
  LEFT JOIN rules r ON r.level = l.lvl
  LEFT JOIN partners p ON p.partner_level = l.lvl
  LEFT JOIN commissions c ON c.comm_level = l.lvl
  LEFT JOIN volumes v ON v.vol_level = l.lvl
  ORDER BY l.lvl;
END;
$$;

-- Create audit function to find incorrectly awarded commissions
CREATE OR REPLACE FUNCTION public.audit_unlock_level_violations_detailed()
RETURNS TABLE (
  transaction_id uuid,
  user_id uuid,
  user_email text,
  user_name text,
  level int,
  amount_cents numeric,
  required_referrals int,
  actual_referrals_at_time int,
  subscriber_id uuid,
  subscriber_name text,
  subscription_id text,
  created_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_unlock_levels jsonb;
BEGIN
  -- Get unlock_levels
  SELECT value INTO v_unlock_levels
  FROM mlm_settings
  WHERE key = 'unlock_levels';
  
  IF v_unlock_levels IS NULL THEN
    v_unlock_levels := '{"l2": 3, "l3": 5, "l4": 8, "l5": 10}'::jsonb;
  END IF;

  RETURN QUERY
  WITH commission_txns AS (
    SELECT 
      t.id AS txn_id,
      t.user_id,
      t.level AS txn_level,
      t.amount_cents,
      t.source_id,
      t.source_ref,
      t.created_at AS txn_created_at,
      COALESCE(
        (v_unlock_levels->('l' || t.level::text))::int,
        CASE t.level
          WHEN 2 THEN 3
          WHEN 3 THEN 5
          WHEN 4 THEN 8
          WHEN 5 THEN 10
          ELSE t.level - 1
        END
      ) AS required_refs
    FROM transactions t
    WHERE t.type = 'commission'
      AND t.structure_type = 'primary'
      AND t.level > 1
      AND t.is_test IS NOT TRUE
  )
  SELECT 
    ct.txn_id AS transaction_id,
    ct.user_id,
    p.email AS user_email,
    p.full_name AS user_name,
    ct.txn_level AS level,
    ct.amount_cents,
    ct.required_refs AS required_referrals,
    (
      SELECT COUNT(*)::int
      FROM profiles pr
      WHERE pr.sponsor_id = ct.user_id
        AND pr.subscription_status = 'active'
        AND pr.deleted_at IS NULL
        AND pr.created_at <= ct.txn_created_at
    ) AS actual_referrals_at_time,
    ct.source_id::uuid AS subscriber_id,
    sub_p.full_name AS subscriber_name,
    ct.source_ref AS subscription_id,
    ct.txn_created_at AS created_at
  FROM commission_txns ct
  JOIN profiles p ON p.id = ct.user_id
  LEFT JOIN profiles sub_p ON sub_p.id = ct.source_id::uuid
  WHERE (
    SELECT COUNT(*)
    FROM profiles pr
    WHERE pr.sponsor_id = ct.user_id
      AND pr.subscription_status = 'active'
      AND pr.deleted_at IS NULL
      AND pr.created_at <= ct.txn_created_at
  ) < ct.required_refs
  ORDER BY ct.txn_created_at DESC;
END;
$$;