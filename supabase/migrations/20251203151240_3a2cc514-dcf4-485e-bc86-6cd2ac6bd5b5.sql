
-- Drop existing functions that need return type changes
DROP FUNCTION IF EXISTS public.get_commission_structure_stats(uuid, integer, timestamp with time zone, timestamp with time zone);

-- PHASE 3: Recreate get_commission_structure_stats with fixed logic
CREATE OR REPLACE FUNCTION public.get_commission_structure_stats(
  p_user_id UUID,
  p_structure_type INTEGER,
  p_start_date TIMESTAMPTZ DEFAULT NULL,
  p_end_date TIMESTAMPTZ DEFAULT NULL
)
RETURNS TABLE(
  level INTEGER,
  percent NUMERIC,
  earned_cents BIGINT,
  frozen_cents BIGINT,
  volume_cents BIGINT,
  partners_count INTEGER,
  status TEXT,
  unlock_requirement TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_direct_referrals INTEGER;
  v_subscription_active BOOLEAN;
BEGIN
  -- Get user's direct referrals count and subscription status (using subscription_expires_at)
  SELECT 
    COALESCE(p.direct_referrals_count, 0),
    p.subscription_expires_at > NOW()
  INTO v_direct_referrals, v_subscription_active
  FROM profiles p
  WHERE p.id = p_user_id;

  RETURN QUERY
  WITH rules AS (
    SELECT mcr.level, mcr.percent
    FROM mlm_commission_rules mcr
    WHERE mcr.structure_type = p_structure_type
      AND mcr.plan_id = 'default'
      AND mcr.is_active = true
    ORDER BY mcr.level
  ),
  user_transactions AS (
    SELECT 
      t.level,
      t.amount_cents,
      t.status,
      t.frozen_until
    FROM transactions t
    WHERE t.user_id = p_user_id
      AND t.type = 'commission'
      AND (
        (p_structure_type = 1 AND t.structure_type = 'primary') OR
        (p_structure_type = 2 AND t.structure_type = 'secondary')
      )
      AND (p_start_date IS NULL OR t.created_at >= p_start_date)
      AND (p_end_date IS NULL OR t.created_at <= p_end_date)
  ),
  level_stats AS (
    SELECT 
      r.level,
      r.percent,
      COALESCE(SUM(CASE WHEN ut.status = 'completed' THEN ut.amount_cents ELSE 0 END), 0)::BIGINT as earned,
      COALESCE(SUM(CASE WHEN ut.status = 'completed' AND ut.frozen_until > NOW() THEN ut.amount_cents ELSE 0 END), 0)::BIGINT as frozen,
      0::BIGINT as volume
    FROM rules r
    LEFT JOIN user_transactions ut ON ut.level = r.level
    GROUP BY r.level, r.percent
  )
  SELECT 
    ls.level,
    ls.percent,
    ls.earned,
    ls.frozen,
    ls.volume,
    0::INTEGER as partners_count,
    CASE
      WHEN NOT v_subscription_active THEN 'locked'
      WHEN p_structure_type = 1 THEN
        CASE
          WHEN ls.level = 1 THEN 'active'
          WHEN ls.level = 2 AND v_direct_referrals >= 3 THEN 'active'
          WHEN ls.level = 3 AND v_direct_referrals >= 5 THEN 'active'
          WHEN ls.level = 4 AND v_direct_referrals >= 8 THEN 'active'
          WHEN ls.level = 5 AND v_direct_referrals >= 10 THEN 'active'
          ELSE 'locked'
        END
      ELSE 'active'
    END as status,
    CASE
      WHEN NOT v_subscription_active THEN 'Требуется активная подписка'
      WHEN p_structure_type = 1 THEN
        CASE
          WHEN ls.level = 1 THEN NULL
          WHEN ls.level = 2 AND v_direct_referrals < 3 THEN '3 прямых партнёра'
          WHEN ls.level = 3 AND v_direct_referrals < 5 THEN '5 прямых партнёров'
          WHEN ls.level = 4 AND v_direct_referrals < 8 THEN '8 прямых партнёров'
          WHEN ls.level = 5 AND v_direct_referrals < 10 THEN '10 прямых партнёров'
          ELSE NULL
        END
      ELSE NULL
    END as unlock_requirement
  FROM level_stats ls
  ORDER BY ls.level;
END;
$$;

-- PHASE 4: Update get_admin_structure_stats to add available_amount_cents
DROP FUNCTION IF EXISTS public.get_admin_structure_stats(integer, timestamp with time zone, timestamp with time zone);
CREATE OR REPLACE FUNCTION public.get_admin_structure_stats(
  structure_type_param INTEGER,
  start_date TIMESTAMPTZ DEFAULT date_trunc('month', now()),
  end_date TIMESTAMPTZ DEFAULT now()
)
RETURNS TABLE(
  level INTEGER,
  percent NUMERIC,
  transactions_count BIGINT,
  total_amount_cents BIGINT,
  frozen_amount_cents BIGINT,
  available_amount_cents BIGINT,
  pass_up_count BIGINT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  RETURN QUERY
  WITH rules AS (
    SELECT mcr.level, mcr.percent
    FROM mlm_commission_rules mcr
    WHERE mcr.structure_type = structure_type_param
      AND mcr.plan_id = 'default'
      AND mcr.is_active = true
    ORDER BY mcr.level
  )
  SELECT 
    r.level,
    r.percent,
    COUNT(t.id)::BIGINT as transactions_count,
    COALESCE(SUM(CASE WHEN t.status = 'completed' THEN t.amount_cents ELSE 0 END), 0)::BIGINT as total_amount_cents,
    COALESCE(SUM(CASE WHEN t.status = 'completed' AND t.frozen_until > now() THEN t.amount_cents ELSE 0 END), 0)::BIGINT as frozen_amount_cents,
    COALESCE(SUM(CASE WHEN t.status = 'completed' AND (t.frozen_until IS NULL OR t.frozen_until <= now()) THEN t.amount_cents ELSE 0 END), 0)::BIGINT as available_amount_cents,
    COALESCE(SUM((t.payload->>'pass_up_applied')::int), 0)::BIGINT as pass_up_count
  FROM rules r
  LEFT JOIN transactions t ON 
    t.level = r.level 
    AND t.type = 'commission'
    AND (
      (structure_type_param = 1 AND t.structure_type = 'primary') OR
      (structure_type_param = 2 AND t.structure_type = 'secondary')
    )
    AND t.created_at >= start_date
    AND t.created_at <= end_date
  GROUP BY r.level, r.percent
  ORDER BY r.level;
END;
$$;

-- PHASE 5: Fix frozen_until for incorrectly frozen transactions (365 days -> 14 days)
UPDATE transactions t
SET 
  frozen_until = t.created_at + INTERVAL '14 days',
  payload = COALESCE(t.payload, '{}'::jsonb) || jsonb_build_object('freeze_corrected', true, 'corrected_at', NOW())
WHERE t.type = 'commission'
  AND t.status = 'completed'
  AND t.frozen_until > NOW() + INTERVAL '30 days'
  AND EXISTS (
    SELECT 1 FROM profiles p
    WHERE p.id = t.user_id
      AND p.subscription_expires_at > NOW()
  );

-- PHASE 6: Update award_s1_subscription_commission to use 14-day freeze
CREATE OR REPLACE FUNCTION public.award_s1_subscription_commission()
RETURNS TRIGGER AS $$
DECLARE
  v_buyer_id UUID;
  v_subscription_amount_cents BIGINT;
  v_current_sponsor_id UUID;
  v_current_level INTEGER := 1;
  v_max_levels INTEGER := 5;
  v_commission_percent NUMERIC;
  v_commission_cents BIGINT;
  v_sponsor_active BOOLEAN;
  v_freeze_days INTEGER := 14;
  v_unique_ref TEXT;
BEGIN
  IF NEW.status = 'active' AND (OLD.status IS NULL OR OLD.status != 'active') THEN
    v_buyer_id := NEW.user_id;
    v_subscription_amount_cents := (NEW.amount_usd * 100)::BIGINT;
    
    SELECT sponsor_id INTO v_current_sponsor_id
    FROM profiles WHERE id = v_buyer_id;
    
    WHILE v_current_level <= v_max_levels AND v_current_sponsor_id IS NOT NULL LOOP
      SELECT percent INTO v_commission_percent
      FROM mlm_commission_rules
      WHERE structure_type = 1 AND level = v_current_level AND plan_id = 'default' AND is_active = true;
      
      IF v_commission_percent IS NULL THEN v_commission_percent := 10; END IF;
      
      v_commission_cents := (v_subscription_amount_cents * v_commission_percent / 100)::BIGINT;
      
      SELECT subscription_expires_at > NOW() INTO v_sponsor_active
      FROM profiles WHERE id = v_current_sponsor_id;
      
      v_unique_ref := 'subscription_' || NEW.id || '_s1_level_' || v_current_level;
      
      INSERT INTO transactions (
        user_id, type, amount_cents, status, source_id, source_ref,
        level, structure_type, frozen_until, currency, payload
      ) VALUES (
        v_current_sponsor_id, 'commission', v_commission_cents, 'completed',
        NEW.id, v_unique_ref, v_current_level, 'primary',
        NOW() + (v_freeze_days || ' days')::INTERVAL, 'USD',
        jsonb_build_object('subscription_id', NEW.id, 'buyer_id', v_buyer_id, 'structure', 's1', 'level', v_current_level, 'percent', v_commission_percent)
      ) ON CONFLICT (source_ref) DO NOTHING;
      
      SELECT sponsor_id INTO v_current_sponsor_id FROM profiles WHERE id = v_current_sponsor_id;
      v_current_level := v_current_level + 1;
    END LOOP;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public';

DROP TRIGGER IF EXISTS award_s1_commission_trigger ON subscriptions;
CREATE TRIGGER award_s1_commission_trigger
  AFTER UPDATE ON subscriptions
  FOR EACH ROW
  EXECUTE FUNCTION award_s1_subscription_commission();
