-- Fix: disambiguate subscription_status references inside get_referral_network_from_table (PL/pgSQL output column name conflicts)

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
    -- Base case: direct referrals of root user
    SELECT 
      r.referred_user_id as user_id,
      r.referrer_id as parent_id,
      1 as lvl
    FROM referrals r
    WHERE r.referrer_id = root_user_id
      AND r.structure_type = p_structure_type

    UNION ALL

    -- Recursive case: referrals of referrals
    SELECT 
      r.referred_user_id,
      r.referrer_id,
      n.lvl + 1
    FROM referrals r
    INNER JOIN network n ON r.referrer_id = n.user_id
    WHERE n.lvl < max_level
      AND r.structure_type = p_structure_type
  ),
  -- Get team sizes for each user (counting only active partners)
  team_sizes AS (
    SELECT 
      n.user_id,
      (
        SELECT COUNT(*)
        FROM profiles p2
        WHERE p2.sponsor_id = n.user_id
          AND p2.deleted_at IS NULL
          AND p2.subscription_status = 'active'
      )::INT as direct,
      (
        WITH RECURSIVE subtree AS (
          SELECT r2.referred_user_id as uid
          FROM referrals r2
          WHERE r2.referrer_id = n.user_id AND r2.structure_type = p_structure_type

          UNION ALL

          SELECT r3.referred_user_id
          FROM referrals r3
          INNER JOIN subtree s ON r3.referrer_id = s.uid
          WHERE r3.structure_type = p_structure_type
        )
        SELECT COUNT(*)::INT FROM subtree
      ) as total
    FROM network n
  ),
  -- Get monthly volumes
  monthly_volumes AS (
    SELECT 
      n.user_id,
      COALESCE(SUM(
        CASE WHEN o.status = 'paid'
             AND o.paid_at >= date_trunc('month', CURRENT_DATE)
        THEN o.total_kzt ELSE 0 END
      ), 0)::BIGINT as volume
    FROM network n
    LEFT JOIN orders o ON o.user_id = n.user_id
    GROUP BY n.user_id
  ),
  -- Check commission status for current month subscriptions
  commission_status AS (
    SELECT 
      n.user_id,
      CASE 
        WHEN EXISTS (
          SELECT 1 FROM transactions t 
          WHERE t.source_id IN (
            SELECT s.id FROM subscriptions s 
            WHERE s.user_id = n.user_id 
              AND s.status = 'active'
              AND s.paid_at >= date_trunc('month', CURRENT_DATE)
          )
          AND t.user_id = root_user_id
          AND t.type = 'commission'
          AND t.structure_type = 'primary'
        ) THEN true
        ELSE false
      END as has_commission,
      CASE
        WHEN NOT EXISTS (
          SELECT 1 FROM subscriptions s 
          WHERE s.user_id = n.user_id 
            AND s.status = 'active'
        ) THEN 'no_active_subscription'
        WHEN n.lvl > (
          SELECT COALESCE(
            (SELECT mcr.level 
             FROM mlm_commission_rules mcr 
             WHERE mcr.structure_type = 1 
               AND mcr.is_active = true
             ORDER BY mcr.level DESC 
             LIMIT 1), 
            10
          )
        ) THEN 'level_too_deep'
        WHEN (
          SELECT COUNT(*)
          FROM profiles p3
          WHERE p3.sponsor_id = root_user_id
            AND p3.subscription_status = 'active'
        ) < (
          SELECT COALESCE(
            (SELECT (ms.value::jsonb->>('level_' || n.lvl::text))::int 
             FROM mlm_settings ms 
             WHERE ms.key = 'unlock_levels'),
            0
          )
        ) THEN 'level_not_unlocked'
        ELSE NULL
      END as no_commission_reason
    FROM network n
  )
  SELECT 
    n.user_id,
    n.user_id as partner_id,
    n.parent_id as parent_partner_id,
    n.lvl as level,
    p.full_name,
    p.email,
    p.referral_code,
    p.subscription_status,
    COALESCE(p.monthly_activation_completed, false) as monthly_activation_met,
    p.created_at,
    p.avatar_url,
    COALESCE(ts.direct, 0) as direct_referrals,
    COALESCE(ts.total, 0) as total_team,
    COALESCE(mv.volume, 0) as monthly_volume,
    COALESCE(cs.has_commission, false) as has_commission_received,
    cs.no_commission_reason
  FROM network n
  JOIN profiles p ON p.id = n.user_id
  LEFT JOIN team_sizes ts ON ts.user_id = n.user_id
  LEFT JOIN monthly_volumes mv ON mv.user_id = n.user_id
  LEFT JOIN commission_status cs ON cs.user_id = n.user_id
  WHERE p.deleted_at IS NULL
  ORDER BY n.lvl, p.created_at;
END;
$$;