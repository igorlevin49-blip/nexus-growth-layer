-- Drop existing function first
DROP FUNCTION IF EXISTS public.get_commission_structure_stats(UUID, INTEGER, TIMESTAMPTZ, TIMESTAMPTZ);

-- Recreate with correct partner counting
CREATE FUNCTION public.get_commission_structure_stats(
  p_user_id UUID,
  p_structure_type INTEGER,
  p_start_date TIMESTAMPTZ DEFAULT NULL,
  p_end_date TIMESTAMPTZ DEFAULT NULL
)
RETURNS TABLE (
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
SET search_path = public
AS $func$
DECLARE
  v_direct_count INTEGER;
  v_subscription_active BOOLEAN;
  v_max_levels INTEGER;
BEGIN
  SELECT 
    COALESCE(p.direct_referrals_count, 0),
    COALESCE(p.subscription_status = 'active', FALSE)
  INTO v_direct_count, v_subscription_active
  FROM profiles p
  WHERE p.id = p_user_id;

  v_max_levels := CASE WHEN p_structure_type = 1 THEN 5 ELSE 10 END;

  RETURN QUERY
  WITH network_levels AS (
    SELECT 
      n.user_id,
      n.level as network_level
    FROM get_referral_network_from_table(p_user_id, v_max_levels, p_structure_type) n
    WHERE n.level > 0
  ),
  partners_per_level AS (
    SELECT 
      nl.network_level as lvl,
      COUNT(DISTINCT nl.user_id)::INTEGER as cnt
    FROM network_levels nl
    GROUP BY nl.network_level
  ),
  commission_rules AS (
    SELECT 
      mcr.level as rule_level,
      mcr.percent as rule_percent
    FROM mlm_commission_rules mcr
    WHERE mcr.structure_type = p_structure_type
      AND mcr.is_active = TRUE
      AND mcr.plan_id = 'default'
  ),
  level_transactions AS (
    SELECT 
      COALESCE(t.level, 1) as tx_level,
      SUM(CASE WHEN t.status = 'completed' THEN t.amount_cents ELSE 0 END) as earned,
      SUM(CASE WHEN t.status = 'frozen' THEN t.amount_cents ELSE 0 END) as frozen,
      SUM(t.amount_cents) as volume
    FROM transactions t
    WHERE t.user_id = p_user_id
      AND t.type = 'commission'
      AND (t.structure_type = (CASE WHEN p_structure_type = 1 THEN 'primary'::structure_type ELSE 'secondary'::structure_type END)
           OR (p_structure_type = 1 AND t.structure_type IS NULL))
      AND (p_start_date IS NULL OR t.created_at >= p_start_date)
      AND (p_end_date IS NULL OR t.created_at <= p_end_date)
    GROUP BY COALESCE(t.level, 1)
  ),
  all_levels AS (
    SELECT generate_series(1, v_max_levels) as lvl
  )
  SELECT 
    al.lvl::INTEGER,
    COALESCE(cr.rule_percent, CASE WHEN p_structure_type = 1 THEN 10 ELSE 
      CASE WHEN al.lvl = 1 OR al.lvl = 10 THEN 10 ELSE 5 END
    END)::NUMERIC,
    COALESCE(lt.earned, 0)::BIGINT,
    COALESCE(lt.frozen, 0)::BIGINT,
    COALESCE(lt.volume, 0)::BIGINT,
    COALESCE(ppl.cnt, 0)::INTEGER,
    CASE 
      WHEN p_structure_type = 1 THEN
        CASE
          WHEN NOT v_subscription_active THEN 'frozen'
          WHEN al.lvl = 1 THEN 'active'
          WHEN al.lvl = 2 AND v_direct_count >= 3 THEN 'active'
          WHEN al.lvl = 3 AND v_direct_count >= 5 THEN 'active'
          WHEN al.lvl = 4 AND v_direct_count >= 8 THEN 'active'
          WHEN al.lvl = 5 AND v_direct_count >= 10 THEN 'active'
          ELSE 'locked'
        END
      ELSE 'active'
    END::TEXT,
    CASE 
      WHEN p_structure_type = 1 THEN
        CASE al.lvl
          WHEN 1 THEN NULL
          WHEN 2 THEN '3 прямых реферала'
          WHEN 3 THEN '5 прямых рефералов'
          WHEN 4 THEN '8 прямых рефералов'
          WHEN 5 THEN '10 прямых рефералов'
          ELSE NULL
        END
      ELSE NULL
    END::TEXT
  FROM all_levels al
  LEFT JOIN commission_rules cr ON cr.rule_level = al.lvl
  LEFT JOIN level_transactions lt ON lt.tx_level = al.lvl
  LEFT JOIN partners_per_level ppl ON ppl.lvl = al.lvl
  ORDER BY al.lvl;
END;
$func$;