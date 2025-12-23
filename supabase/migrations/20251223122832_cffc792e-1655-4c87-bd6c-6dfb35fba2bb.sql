-- First drop the function with changed return type
DROP FUNCTION IF EXISTS public.get_commission_structure_stats(uuid, integer, timestamp with time zone, timestamp with time zone);

-- Recreate get_commission_structure_stats with correct frozen calculation
CREATE OR REPLACE FUNCTION public.get_commission_structure_stats(
  p_user_id uuid,
  p_structure_type integer,
  p_start_date timestamp with time zone DEFAULT NULL,
  p_end_date timestamp with time zone DEFAULT NULL
)
RETURNS TABLE(
  level integer,
  percent numeric,
  earned_cents bigint,
  frozen_cents bigint,
  volume_cents bigint,
  partners_count bigint,
  status text,
  unlock_requirement text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_structure_type_enum structure_type;
BEGIN
  -- Convert integer to enum
  IF p_structure_type = 1 THEN
    v_structure_type_enum := 'primary';
  ELSE
    v_structure_type_enum := 'secondary';
  END IF;

  RETURN QUERY
  WITH commission_rules AS (
    SELECT 
      mcr.level,
      mcr.percent
    FROM mlm_commission_rules mcr
    WHERE mcr.structure_type = p_structure_type
      AND mcr.is_active = true
    ORDER BY mcr.level
  ),
  user_transactions AS (
    SELECT 
      t.level,
      t.amount_cents,
      t.status,
      t.frozen_until,
      t.created_at
    FROM transactions t
    WHERE t.user_id = p_user_id
      AND t.type = 'commission'
      AND t.structure_type = v_structure_type_enum
      AND (t.is_archived IS NULL OR t.is_archived = false)
      AND (t.is_test IS NULL OR t.is_test = false)
      AND (p_start_date IS NULL OR t.created_at >= p_start_date)
      AND (p_end_date IS NULL OR t.created_at <= p_end_date)
  ),
  level_stats AS (
    SELECT 
      ut.level,
      -- Earned: completed transactions without active freeze
      SUM(CASE 
        WHEN ut.status = 'completed' AND (ut.frozen_until IS NULL OR ut.frozen_until <= NOW())
        THEN ut.amount_cents 
        ELSE 0 
      END)::bigint as earned,
      -- Frozen: frozen status OR completed with active freeze
      SUM(CASE 
        WHEN ut.status = 'frozen' OR (ut.status = 'completed' AND ut.frozen_until > NOW())
        THEN ut.amount_cents 
        ELSE 0 
      END)::bigint as frozen
    FROM user_transactions ut
    GROUP BY ut.level
  ),
  network_partners AS (
    SELECT 
      r.level,
      COUNT(DISTINCT r.partner_id)::bigint as cnt
    FROM (
      SELECT 
        ROW_NUMBER() OVER (ORDER BY rn.created_at) as level,
        rn.partner_id
      FROM get_referral_network(p_user_id, 5, p_structure_type) rn
      WHERE rn.partner_id != p_user_id
    ) r
    GROUP BY r.level
  )
  SELECT 
    cr.level::integer,
    cr.percent::numeric,
    COALESCE(ls.earned, 0)::bigint as earned_cents,
    COALESCE(ls.frozen, 0)::bigint as frozen_cents,
    0::bigint as volume_cents,
    COALESCE(np.cnt, 0)::bigint as partners_count,
    CASE 
      WHEN cr.level = 1 THEN 'active'
      WHEN EXISTS (
        SELECT 1 FROM referrals ref 
        WHERE ref.referrer_id = p_user_id 
          AND ref.structure_type = p_structure_type
        HAVING COUNT(*) >= cr.level
      ) THEN 'active'
      ELSE 'locked'
    END::text as status,
    CASE 
      WHEN cr.level = 1 THEN NULL
      ELSE 'Пригласите ' || cr.level || ' партнёров для разблокировки'
    END::text as unlock_requirement
  FROM commission_rules cr
  LEFT JOIN level_stats ls ON ls.level = cr.level
  LEFT JOIN network_partners np ON np.level = cr.level
  ORDER BY cr.level;
END;
$$;