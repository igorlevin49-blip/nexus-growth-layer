-- ============================================
-- FIX 1: Add missing MLM settings for commission rates and unlock requirements
-- ============================================

-- Add s1_commission_rates (10% for all 5 levels)
INSERT INTO mlm_settings (key, value, description)
VALUES (
  's1_commission_rates',
  '{"level_1": 10, "level_2": 10, "level_3": 10, "level_4": 10, "level_5": 10}'::jsonb,
  'Проценты комиссий структуры S1 по уровням'
)
ON CONFLICT (key) DO UPDATE SET 
  value = EXCLUDED.value,
  updated_at = now();

-- Add s1_unlock_requirements (Level 1 = 0, always open!)
INSERT INTO mlm_settings (key, value, description)
VALUES (
  's1_unlock_requirements',
  '{"unlock_level_1": 0, "unlock_level_2": 3, "unlock_level_3": 5, "unlock_level_4": 8, "unlock_level_5": 10}'::jsonb,
  'Требования по личникам для разблокировки уровней S1'
)
ON CONFLICT (key) DO UPDATE SET 
  value = EXCLUDED.value,
  updated_at = now();

-- ============================================
-- FIX 2: Update get_referral_network_from_table function
-- Fix: Use 'referrals' table instead of non-existent 'referral_network'
-- Fix: Level 1 should NEVER show 'level_not_unlocked'
-- ============================================

DROP FUNCTION IF EXISTS public.get_referral_network_from_table(uuid, integer, integer);

CREATE OR REPLACE FUNCTION public.get_referral_network_from_table(
  root_user_id uuid,
  p_max_levels integer DEFAULT 10,
  p_structure_type integer DEFAULT 1
)
RETURNS TABLE (
  id uuid,
  full_name text,
  avatar_url text,
  level integer,
  parent_id uuid,
  subscription_status text,
  subscription_expires_at timestamp with time zone,
  personal_activation_volume numeric,
  has_commission_received boolean,
  no_commission_reason text,
  commission_frozen_until timestamp with time zone,
  is_activated boolean,
  created_at timestamp with time zone
) 
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_unlock_levels jsonb;
BEGIN
  -- Get unlock requirements from mlm_settings
  SELECT value INTO v_unlock_levels
  FROM mlm_settings
  WHERE key = 'unlock_levels';
  
  -- Default if not found
  IF v_unlock_levels IS NULL THEN
    v_unlock_levels := '{"l2": 3, "l3": 5, "l4": 8, "l5": 10}'::jsonb;
  END IF;

  RETURN QUERY
  WITH RECURSIVE referral_tree AS (
    -- Base case: direct referrals (level 1)
    SELECT 
      p.id,
      p.full_name,
      p.avatar_url,
      1 as level,
      p.sponsor_id as parent_id,
      p.subscription_status,
      p.subscription_expires_at,
      COALESCE(ma.total_amount_kzt, 0)::numeric as personal_activation_volume,
      p.created_at
    FROM profiles p
    LEFT JOIN monthly_activations ma ON ma.user_id = p.id 
      AND ma.year = EXTRACT(YEAR FROM now())
      AND ma.month = EXTRACT(MONTH FROM now())
    WHERE p.sponsor_id = root_user_id
      AND p.deleted_at IS NULL
    
    UNION ALL
    
    -- Recursive case: deeper levels
    SELECT 
      p.id,
      p.full_name,
      p.avatar_url,
      rt.level + 1 as level,
      p.sponsor_id as parent_id,
      p.subscription_status,
      p.subscription_expires_at,
      COALESCE(ma.total_amount_kzt, 0)::numeric as personal_activation_volume,
      p.created_at
    FROM profiles p
    INNER JOIN referral_tree rt ON p.sponsor_id = rt.id
    LEFT JOIN monthly_activations ma ON ma.user_id = p.id 
      AND ma.year = EXTRACT(YEAR FROM now())
      AND ma.month = EXTRACT(MONTH FROM now())
    WHERE rt.level < p_max_levels
      AND p.deleted_at IS NULL
  ),
  commission_info AS (
    -- Check if there are commission transactions for each referral
    SELECT DISTINCT ON (t.source_id, t.level)
      t.source_id,
      t.level as commission_level,
      t.status,
      t.frozen_until
    FROM transactions t
    WHERE t.user_id = root_user_id
      AND t.type = 'commission'
      AND t.structure_type = p_structure_type::structure_type
    ORDER BY t.source_id, t.level, t.created_at DESC
  ),
  root_referral_count AS (
    -- Get number of direct referrals for root user
    SELECT COUNT(*)::integer as cnt
    FROM profiles
    WHERE sponsor_id = root_user_id
      AND deleted_at IS NULL
      AND subscription_status = 'active'
  )
  SELECT 
    rt.id,
    rt.full_name,
    rt.avatar_url,
    rt.level,
    rt.parent_id,
    rt.subscription_status,
    rt.subscription_expires_at,
    rt.personal_activation_volume,
    -- has_commission_received
    CASE 
      WHEN ci.source_id IS NOT NULL AND ci.status IN ('completed', 'frozen') THEN true
      ELSE false
    END as has_commission_received,
    -- no_commission_reason - Level 1 is ALWAYS open, never 'level_not_unlocked'
    CASE
      -- Level 1: always open, check other conditions
      WHEN rt.level = 1 THEN
        CASE
          WHEN rt.subscription_status IS NULL OR rt.subscription_status != 'active' THEN 'partner_no_subscription'
          WHEN ci.source_id IS NOT NULL THEN NULL -- commission exists
          ELSE 'no_subscription_payment' -- no commission transaction yet
        END
      -- Level 2+: check unlock requirements
      WHEN rt.level = 2 AND (SELECT cnt FROM root_referral_count) < COALESCE((v_unlock_levels->>'l2')::integer, 3) THEN 'level_not_unlocked'
      WHEN rt.level = 3 AND (SELECT cnt FROM root_referral_count) < COALESCE((v_unlock_levels->>'l3')::integer, 5) THEN 'level_not_unlocked'
      WHEN rt.level = 4 AND (SELECT cnt FROM root_referral_count) < COALESCE((v_unlock_levels->>'l4')::integer, 8) THEN 'level_not_unlocked'
      WHEN rt.level = 5 AND (SELECT cnt FROM root_referral_count) < COALESCE((v_unlock_levels->>'l5')::integer, 10) THEN 'level_not_unlocked'
      WHEN rt.level > 5 THEN 'level_not_unlocked' -- Levels 6+ not supported in S1
      -- Check partner conditions
      WHEN rt.subscription_status IS NULL OR rt.subscription_status != 'active' THEN 'partner_no_subscription'
      WHEN ci.source_id IS NOT NULL THEN NULL -- commission exists
      ELSE 'no_subscription_payment'
    END as no_commission_reason,
    -- commission_frozen_until
    ci.frozen_until as commission_frozen_until,
    -- is_activated
    COALESCE(
      (SELECT ma2.is_activated FROM monthly_activations ma2 
       WHERE ma2.user_id = rt.id 
         AND ma2.year = EXTRACT(YEAR FROM now())
         AND ma2.month = EXTRACT(MONTH FROM now())
       LIMIT 1),
      false
    ) as is_activated,
    rt.created_at
  FROM referral_tree rt
  LEFT JOIN commission_info ci ON ci.source_id = rt.id AND ci.commission_level = rt.level
  ORDER BY rt.level, rt.full_name;
END;
$$;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION public.get_referral_network_from_table(uuid, integer, integer) TO authenticated;

-- ============================================
-- FIX 3: Update award_s1_subscription_commission to use correct sources
-- ============================================

CREATE OR REPLACE FUNCTION public.award_s1_subscription_commission(
  p_subscriber_id uuid,
  p_subscription_amount numeric,
  p_subscription_id uuid,
  p_subscription_paid_at timestamp with time zone DEFAULT now()
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_current_user_id uuid;
  v_level integer := 0;
  v_max_levels integer := 5;
  v_commission_rate numeric;
  v_commission_amount integer;
  v_required_referrals integer;
  v_actual_referrals integer;
  v_unlock_levels jsonb;
  v_freeze_days integer;
  v_frozen_until timestamp with time zone;
  v_result jsonb := '{"commissions_created": 0, "details": []}'::jsonb;
  v_details jsonb := '[]'::jsonb;
  v_subscriber_name text;
  v_recipient_name text;
BEGIN
  -- Get subscriber name for logging
  SELECT full_name INTO v_subscriber_name FROM profiles WHERE id = p_subscriber_id;
  
  -- Get unlock levels from mlm_settings
  SELECT value INTO v_unlock_levels
  FROM mlm_settings
  WHERE key = 'unlock_levels';
  
  -- Default unlock levels if not found
  IF v_unlock_levels IS NULL THEN
    v_unlock_levels := '{"l2": 3, "l3": 5, "l4": 8, "l5": 10}'::jsonb;
  END IF;
  
  -- Get freeze days setting
  SELECT COALESCE((value::text)::integer, 30) INTO v_freeze_days
  FROM mlm_settings
  WHERE key = 'commission_freeze_days';
  
  IF v_freeze_days IS NULL THEN
    v_freeze_days := 30;
  END IF;
  
  -- Start from sponsor of subscriber
  SELECT sponsor_id INTO v_current_user_id FROM profiles WHERE id = p_subscriber_id;
  
  -- Walk up the referral chain
  WHILE v_current_user_id IS NOT NULL AND v_level < v_max_levels LOOP
    v_level := v_level + 1;
    
    -- Get recipient name for logging
    SELECT full_name INTO v_recipient_name FROM profiles WHERE id = v_current_user_id;
    
    -- Get commission rate from mlm_commission_rules (the correct source!)
    SELECT percent INTO v_commission_rate
    FROM mlm_commission_rules
    WHERE structure_type = 1
      AND level = v_level
      AND plan_id = 'default'
      AND is_active = true
    LIMIT 1;
    
    -- Default to 10% if not found
    IF v_commission_rate IS NULL THEN
      v_commission_rate := 10;
    END IF;
    
    -- Determine unlock requirement for this level
    -- Level 1 is ALWAYS unlocked (0 referrals required)
    IF v_level = 1 THEN
      v_required_referrals := 0;
    ELSE
      v_required_referrals := COALESCE(
        (v_unlock_levels->>'l' || v_level::text)::integer,
        CASE v_level
          WHEN 2 THEN 3
          WHEN 3 THEN 5
          WHEN 4 THEN 8
          WHEN 5 THEN 10
          ELSE 999 -- Level not supported
        END
      );
    END IF;
    
    -- Count active direct referrals at the time of subscription payment
    SELECT COUNT(*)::integer INTO v_actual_referrals
    FROM profiles
    WHERE sponsor_id = v_current_user_id
      AND deleted_at IS NULL
      AND subscription_status = 'active'
      AND created_at <= p_subscription_paid_at;
    
    -- Check if level is unlocked
    IF v_actual_referrals >= v_required_referrals THEN
      -- Calculate commission in cents (tenge)
      v_commission_amount := ROUND(p_subscription_amount * v_commission_rate / 100);
      
      -- Calculate frozen_until (first subscription month is "zero" - frozen)
      v_frozen_until := p_subscription_paid_at + (v_freeze_days || ' days')::interval;
      
      -- Check if commission already exists for this subscription + level
      IF NOT EXISTS (
        SELECT 1 FROM transactions
        WHERE user_id = v_current_user_id
          AND source_id = p_subscription_id
          AND level = v_level
          AND structure_type = 1::structure_type
          AND type = 'commission'
      ) THEN
        -- Create commission transaction
        INSERT INTO transactions (
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
          'frozen',
          1::structure_type,
          v_level,
          p_subscription_id,
          'subscription',
          v_frozen_until,
          jsonb_build_object(
            'subscriber_id', p_subscriber_id,
            'subscriber_name', v_subscriber_name,
            'subscription_amount', p_subscription_amount,
            'commission_percent', v_commission_rate,
            'required_referrals', v_required_referrals,
            'actual_referrals', v_actual_referrals
          )
        );
        
        -- Add to details
        v_details := v_details || jsonb_build_array(jsonb_build_object(
          'recipient_id', v_current_user_id,
          'recipient_name', v_recipient_name,
          'level', v_level,
          'amount', v_commission_amount,
          'percent', v_commission_rate,
          'status', 'created'
        ));
        
        v_result := jsonb_set(v_result, '{commissions_created}', 
          to_jsonb((v_result->>'commissions_created')::integer + 1));
      ELSE
        -- Commission already exists
        v_details := v_details || jsonb_build_array(jsonb_build_object(
          'recipient_id', v_current_user_id,
          'recipient_name', v_recipient_name,
          'level', v_level,
          'status', 'already_exists'
        ));
      END IF;
    ELSE
      -- Level not unlocked
      v_details := v_details || jsonb_build_array(jsonb_build_object(
        'recipient_id', v_current_user_id,
        'recipient_name', v_recipient_name,
        'level', v_level,
        'required_referrals', v_required_referrals,
        'actual_referrals', v_actual_referrals,
        'status', 'level_not_unlocked'
      ));
    END IF;
    
    -- Move to next level (sponsor's sponsor)
    SELECT sponsor_id INTO v_current_user_id FROM profiles WHERE id = v_current_user_id;
  END LOOP;
  
  v_result := jsonb_set(v_result, '{details}', v_details);
  v_result := jsonb_set(v_result, '{subscriber_id}', to_jsonb(p_subscriber_id));
  v_result := jsonb_set(v_result, '{subscription_id}', to_jsonb(p_subscription_id));
  
  RETURN v_result;
END;
$$;