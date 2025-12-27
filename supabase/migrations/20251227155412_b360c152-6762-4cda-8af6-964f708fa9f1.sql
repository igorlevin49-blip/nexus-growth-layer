-- Fix: Inactive users counted as active partners for level unlocks
-- First drop the function with changed return type
DROP FUNCTION IF EXISTS public.get_referral_network_from_table(uuid, integer, integer);

-- Step 1: Update function to count only ACTIVE referrals
CREATE OR REPLACE FUNCTION public.update_direct_referrals_count()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- When sponsor_id changes
  IF NEW.sponsor_id IS NOT NULL THEN
    UPDATE profiles 
    SET direct_referrals_count = (
      SELECT COUNT(*) FROM profiles 
      WHERE sponsor_id = NEW.sponsor_id
        AND subscription_status = 'active'
        AND deleted_at IS NULL
    )
    WHERE id = NEW.sponsor_id;
  END IF;
  
  -- Also update old sponsor if changed
  IF TG_OP = 'UPDATE' AND OLD.sponsor_id IS NOT NULL AND OLD.sponsor_id != COALESCE(NEW.sponsor_id, '00000000-0000-0000-0000-000000000000'::uuid) THEN
    UPDATE profiles 
    SET direct_referrals_count = (
      SELECT COUNT(*) FROM profiles 
      WHERE sponsor_id = OLD.sponsor_id
        AND subscription_status = 'active'
        AND deleted_at IS NULL
    )
    WHERE id = OLD.sponsor_id;
  END IF;
  
  RETURN NEW;
END;
$$;

-- Step 2: Create function to update sponsor's count when subscription_status changes
CREATE OR REPLACE FUNCTION public.update_sponsor_referrals_on_status_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Recalculate for sponsor when subscription status changes
  IF NEW.sponsor_id IS NOT NULL AND NEW.subscription_status IS DISTINCT FROM OLD.subscription_status THEN
    UPDATE profiles 
    SET direct_referrals_count = (
      SELECT COUNT(*) FROM profiles 
      WHERE sponsor_id = NEW.sponsor_id
        AND subscription_status = 'active'
        AND deleted_at IS NULL
    )
    WHERE id = NEW.sponsor_id;
  END IF;
  RETURN NEW;
END;
$$;

-- Create trigger for subscription_status changes
DROP TRIGGER IF EXISTS trigger_update_referrals_on_status ON public.profiles;
CREATE TRIGGER trigger_update_referrals_on_status
  AFTER UPDATE OF subscription_status ON public.profiles
  FOR EACH ROW
  EXECUTE FUNCTION public.update_sponsor_referrals_on_status_change();

-- Step 3: Recreate get_referral_network_from_table with same return type
CREATE OR REPLACE FUNCTION public.get_referral_network_from_table(
  root_user_id UUID,
  max_level INT DEFAULT 10,
  p_structure_type INT DEFAULT 1
)
RETURNS TABLE (
  user_id UUID,
  partner_id UUID,
  parent_partner_id UUID,
  level INT,
  full_name TEXT,
  email TEXT,
  referral_code TEXT,
  subscription_status TEXT,
  monthly_activation_met BOOLEAN,
  created_at TIMESTAMPTZ,
  avatar_url TEXT,
  direct_referrals INT,
  total_team INT,
  monthly_volume BIGINT,
  has_commission_received BOOLEAN,
  no_commission_reason TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  WITH RECURSIVE network AS (
    SELECT 
      r.referred_user_id as user_id,
      r.referred_user_id as partner_id,
      r.referrer_id as parent_partner_id,
      1 as level
    FROM referrals r
    WHERE r.referrer_id = root_user_id
      AND r.structure_type = p_structure_type
    
    UNION ALL
    
    SELECT 
      r.referred_user_id,
      r.referred_user_id,
      r.referrer_id,
      n.level + 1
    FROM referrals r
    JOIN network n ON r.referrer_id = n.user_id
    WHERE n.level < max_level
      AND r.structure_type = p_structure_type
  ),
  -- Calculate team sizes - ONLY count ACTIVE direct referrals
  team_sizes AS (
    SELECT 
      n.user_id,
      (SELECT COUNT(*) FROM profiles p2 
       WHERE p2.sponsor_id = n.user_id 
         AND p2.deleted_at IS NULL 
         AND p2.subscription_status = 'active')::INT as direct,
      (SELECT COUNT(*) FROM network n2 WHERE n2.parent_partner_id = n.user_id)::INT as total_below
    FROM network n
  ),
  monthly_volumes AS (
    SELECT 
      n.user_id,
      COALESCE(SUM(
        CASE WHEN o.status = 'completed' 
             AND o.paid_at >= date_trunc('month', CURRENT_DATE)
        THEN o.total_kzt ELSE 0 END
      ), 0)::BIGINT as volume
    FROM network n
    LEFT JOIN orders o ON o.user_id = n.user_id
    GROUP BY n.user_id
  ),
  commission_status AS (
    SELECT 
      n.user_id,
      EXISTS (
        SELECT 1 FROM transactions t
        WHERE t.user_id = root_user_id
          AND t.type = 'commission'
          AND t.structure_type = p_structure_type
          AND t.payload->>'from_user_id' = n.user_id::text
          AND t.created_at >= date_trunc('month', CURRENT_DATE)
      ) as has_commission,
      CASE
        WHEN NOT EXISTS (
          SELECT 1 FROM subscriptions s 
          WHERE s.user_id = n.user_id 
            AND s.status = 'active'
            AND s.paid_at >= date_trunc('month', CURRENT_DATE)
        ) THEN 'no_subscription_this_month'
        WHEN (SELECT subscription_status FROM profiles WHERE id = root_user_id) != 'active' THEN 'sponsor_not_active'
        WHEN (SELECT monthly_activation_completed FROM profiles WHERE id = root_user_id) = false THEN 'sponsor_not_activated'
        ELSE NULL
      END as no_commission_reason
    FROM network n
  )
  SELECT 
    n.user_id,
    n.partner_id,
    n.parent_partner_id,
    n.level,
    COALESCE(p.full_name, 'Unknown') as full_name,
    p.email,
    p.referral_code,
    COALESCE(p.subscription_status, 'inactive') as subscription_status,
    COALESCE(p.monthly_activation_completed, false) as monthly_activation_met,
    p.created_at,
    p.avatar_url,
    COALESCE(ts.direct, 0) as direct_referrals,
    COALESCE(ts.direct, 0) + COALESCE(ts.total_below, 0) as total_team,
    COALESCE(mv.volume, 0) as monthly_volume,
    COALESCE(cs.has_commission, false) as has_commission_received,
    cs.no_commission_reason
  FROM network n
  JOIN profiles p ON p.id = n.user_id
  LEFT JOIN team_sizes ts ON ts.user_id = n.user_id
  LEFT JOIN monthly_volumes mv ON mv.user_id = n.user_id
  LEFT JOIN commission_status cs ON cs.user_id = n.user_id
  WHERE p.deleted_at IS NULL
  ORDER BY n.level, p.created_at;
END;
$$;

-- Step 4: Fix award_s1_subscription_commission to count only ACTIVE referrals
CREATE OR REPLACE FUNCTION public.award_s1_subscription_commission()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_subscriber_id UUID;
  v_amount_kzt NUMERIC;
  v_sponsor_id UUID;
  v_sponsor_direct_count INT;
  v_level INT := 1;
  v_max_level INT := 5;
  v_percent NUMERIC;
  v_commission_cents BIGINT;
  v_sponsor_status TEXT;
  v_sponsor_activated BOOLEAN;
  v_is_marketing_free BOOLEAN;
  v_unlock_levels JSONB;
BEGIN
  IF NEW.status != 'active' OR NEW.paid_at IS NULL THEN
    RETURN NEW;
  END IF;
  
  IF EXISTS (
    SELECT 1 FROM transactions 
    WHERE source_ref = 'subscription:' || NEW.id 
      AND type = 'commission'
  ) THEN
    RETURN NEW;
  END IF;

  v_subscriber_id := NEW.user_id;
  v_amount_kzt := NEW.amount_kzt;
  v_is_marketing_free := COALESCE(NEW.is_marketing_free_access, false);
  
  IF v_is_marketing_free THEN
    RETURN NEW;
  END IF;

  SELECT value INTO v_unlock_levels
  FROM mlm_settings
  WHERE key = 'unlock_levels';
  
  IF v_unlock_levels IS NULL THEN
    v_unlock_levels := '{"2": 1, "3": 2, "4": 3, "5": 5}'::jsonb;
  END IF;

  SELECT sponsor_id INTO v_sponsor_id
  FROM profiles
  WHERE id = v_subscriber_id;

  WHILE v_sponsor_id IS NOT NULL AND v_level <= v_max_level LOOP
    SELECT subscription_status, monthly_activation_completed
    INTO v_sponsor_status, v_sponsor_activated
    FROM profiles
    WHERE id = v_sponsor_id;

    -- FIX: Count only ACTIVE referrals for level unlock check
    SELECT COUNT(*) INTO v_sponsor_direct_count
    FROM referrals r
    JOIN profiles p ON r.referred_user_id = p.id
    WHERE r.referrer_id = v_sponsor_id
      AND r.structure_type = 1
      AND p.subscription_status = 'active'
      AND p.deleted_at IS NULL;

    IF v_level > 1 THEN
      DECLARE
        v_required_referrals INT;
      BEGIN
        v_required_referrals := COALESCE((v_unlock_levels->>v_level::text)::int, v_level - 1);
        IF v_sponsor_direct_count < v_required_referrals THEN
          SELECT sponsor_id INTO v_sponsor_id
          FROM profiles
          WHERE id = v_sponsor_id;
          v_level := v_level + 1;
          CONTINUE;
        END IF;
      END;
    END IF;

    SELECT percent INTO v_percent
    FROM mlm_commission_rules
    WHERE structure_type = 1
      AND level = v_level
      AND plan_id = 'default'
      AND is_active = true
    ORDER BY effective_from DESC
    LIMIT 1;

    IF v_percent IS NULL THEN
      v_percent := 10;
    END IF;

    v_commission_cents := ROUND(v_amount_kzt * v_percent / 100);

    IF v_sponsor_status = 'active' AND COALESCE(v_sponsor_activated, false) = true AND v_commission_cents > 0 THEN
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
        v_sponsor_id,
        'commission',
        v_commission_cents,
        'KZT',
        'frozen',
        1,
        v_level,
        'subscription:' || NEW.id,
        NEW.id,
        NOW() + INTERVAL '14 days',
        jsonb_build_object(
          'from_user_id', v_subscriber_id,
          'percent', v_percent,
          'base_amount', v_amount_kzt
        )
      );
    END IF;

    SELECT sponsor_id INTO v_sponsor_id
    FROM profiles
    WHERE id = v_sponsor_id;
    
    v_level := v_level + 1;
  END LOOP;

  RETURN NEW;
END;
$$;

-- Step 5: Recalculate direct_referrals_count for ALL users
UPDATE profiles p
SET direct_referrals_count = (
  SELECT COUNT(*) 
  FROM profiles r 
  WHERE r.sponsor_id = p.id 
    AND r.subscription_status = 'active'
    AND r.deleted_at IS NULL
);

-- Step 6: Create audit function
CREATE OR REPLACE FUNCTION public.audit_inactive_partner_commissions()
RETURNS TABLE (
  user_id UUID,
  user_email TEXT,
  user_name TEXT,
  level INT,
  total_referrals INT,
  active_referrals INT,
  inactive_referrals INT,
  required_for_level INT,
  potentially_wrong_commissions BIGINT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_unlock_levels JSONB;
BEGIN
  SELECT value INTO v_unlock_levels
  FROM mlm_settings
  WHERE key = 'unlock_levels';
  
  IF v_unlock_levels IS NULL THEN
    v_unlock_levels := '{"2": 1, "3": 2, "4": 3, "5": 5}'::jsonb;
  END IF;

  RETURN QUERY
  WITH user_stats AS (
    SELECT 
      p.id as user_id,
      p.email as user_email,
      p.full_name as user_name,
      (SELECT COUNT(*) FROM referrals r WHERE r.referrer_id = p.id AND r.structure_type = 1) as total_refs,
      (SELECT COUNT(*) FROM referrals r 
       JOIN profiles pr ON r.referred_user_id = pr.id 
       WHERE r.referrer_id = p.id AND r.structure_type = 1 AND pr.subscription_status = 'active') as active_refs
    FROM profiles p
    WHERE p.deleted_at IS NULL
  ),
  level_analysis AS (
    SELECT 
      us.*,
      CASE 
        WHEN us.active_refs >= COALESCE((v_unlock_levels->>'5')::int, 5) THEN 5
        WHEN us.active_refs >= COALESCE((v_unlock_levels->>'4')::int, 3) THEN 4
        WHEN us.active_refs >= COALESCE((v_unlock_levels->>'3')::int, 2) THEN 3
        WHEN us.active_refs >= COALESCE((v_unlock_levels->>'2')::int, 1) THEN 2
        ELSE 1
      END as correct_max_level,
      CASE 
        WHEN us.total_refs >= COALESCE((v_unlock_levels->>'5')::int, 5) THEN 5
        WHEN us.total_refs >= COALESCE((v_unlock_levels->>'4')::int, 3) THEN 4
        WHEN us.total_refs >= COALESCE((v_unlock_levels->>'3')::int, 2) THEN 3
        WHEN us.total_refs >= COALESCE((v_unlock_levels->>'2')::int, 1) THEN 2
        ELSE 1
      END as old_max_level
    FROM user_stats us
  )
  SELECT 
    la.user_id,
    la.user_email,
    la.user_name,
    la.old_max_level as level,
    la.total_refs::INT as total_referrals,
    la.active_refs::INT as active_referrals,
    (la.total_refs - la.active_refs)::INT as inactive_referrals,
    la.correct_max_level::INT as required_for_level,
    COALESCE((
      SELECT SUM(t.amount_cents)
      FROM transactions t
      WHERE t.user_id = la.user_id
        AND t.type = 'commission'
        AND t.structure_type = 1
        AND t.level > la.correct_max_level
    ), 0)::BIGINT as potentially_wrong_commissions
  FROM level_analysis la
  WHERE la.old_max_level > la.correct_max_level
  ORDER BY (la.old_max_level - la.correct_max_level) DESC, la.total_refs DESC;
END;
$$;