-- =====================================================
-- HOTFIX: Исправление ошибки "operator does not exist: structure_type = text"
-- в функции get_referral_network_from_table
-- =====================================================

CREATE OR REPLACE FUNCTION public.get_referral_network_from_table(
  root_user_id uuid,
  max_level integer DEFAULT 10,
  p_structure_type integer DEFAULT 1
)
RETURNS TABLE (
  user_id uuid,
  partner_id text,
  level integer,
  full_name text,
  email text,
  phone text,
  avatar_url text,
  subscription_status text,
  subscription_expires_at timestamptz,
  monthly_activation_met boolean,
  referral_code text,
  created_at timestamptz,
  direct_referrals bigint,
  total_team bigint,
  monthly_volume numeric,
  parent_partner_id text,
  parent_user_id uuid,
  has_commission_received boolean,
  no_commission_reason text,
  commission_status text,
  commission_frozen_until timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  WITH RECURSIVE network AS (
    -- Базовый уровень: прямые рефералы root_user_id
    SELECT 
      r.referral_id as user_id,
      r.referrer_id as parent_id,
      1 as lvl,
      r.structure_type as ref_structure_type
    FROM referrals r
    WHERE r.referrer_id = root_user_id
      AND r.structure_type = p_structure_type
    
    UNION ALL
    
    -- Рекурсивная часть
    SELECT 
      r.referral_id,
      r.referrer_id,
      n.lvl + 1,
      r.structure_type
    FROM referrals r
    INNER JOIN network n ON r.referrer_id = n.user_id
    WHERE n.lvl < max_level
      AND r.structure_type = p_structure_type
  ),
  -- Подсчёт прямых рефералов для каждого пользователя
  direct_counts AS (
    SELECT 
      r.referrer_id,
      COUNT(*) as cnt
    FROM referrals r
    WHERE r.structure_type = p_structure_type
    GROUP BY r.referrer_id
  ),
  -- Подсчёт всей команды (включая вложенных)
  team_counts AS (
    SELECT 
      n.parent_id as user_id,
      COUNT(DISTINCT n.user_id) as total
    FROM network n
    GROUP BY n.parent_id
  ),
  -- Месячный объём из транзакций
  monthly_volumes AS (
    SELECT 
      t.user_id,
      COALESCE(SUM(t.amount), 0) as volume
    FROM transactions t
    WHERE t.type IN ('purchase', 'subscription', 'activation')
      AND t.created_at >= date_trunc('month', CURRENT_DATE)
      AND t.created_at < date_trunc('month', CURRENT_DATE) + interval '1 month'
      AND t.structure_type = (CASE WHEN p_structure_type = 1 THEN 'primary'::structure_type ELSE 'secondary'::structure_type END)
    GROUP BY t.user_id
  ),
  -- Информация о комиссиях за текущий месяц
  commission_info AS (
    SELECT DISTINCT ON (t.referral_user_id)
      t.referral_user_id,
      CASE WHEN t.status = 'completed' THEN true ELSE false END as received,
      t.no_commission_reason,
      t.status as commission_status,
      t.frozen_until
    FROM transactions t
    WHERE t.type = 'commission'
      AND t.referral_user_id IS NOT NULL
      AND t.created_at >= date_trunc('month', CURRENT_DATE)
      AND t.structure_type = (CASE WHEN p_structure_type = 1 THEN 'primary'::structure_type ELSE 'secondary'::structure_type END)
    ORDER BY t.referral_user_id, t.created_at DESC
  )
  SELECT 
    n.user_id,
    p.partner_id,
    n.lvl as level,
    p.full_name,
    p.email,
    p.phone,
    p.avatar_url,
    p.subscription_status,
    p.subscription_expires_at,
    p.monthly_activation_completed as monthly_activation_met,
    p.referral_code,
    p.created_at,
    COALESCE(dc.cnt, 0)::bigint as direct_referrals,
    COALESCE(tc.total, 0)::bigint as total_team,
    COALESCE(mv.volume, 0) as monthly_volume,
    parent_p.partner_id as parent_partner_id,
    n.parent_id as parent_user_id,
    ci.received as has_commission_received,
    ci.no_commission_reason,
    ci.commission_status,
    ci.frozen_until as commission_frozen_until
  FROM network n
  JOIN profiles p ON p.id = n.user_id
  LEFT JOIN profiles parent_p ON parent_p.id = n.parent_id
  LEFT JOIN direct_counts dc ON dc.referrer_id = n.user_id
  LEFT JOIN team_counts tc ON tc.user_id = n.user_id
  LEFT JOIN monthly_volumes mv ON mv.user_id = n.user_id
  LEFT JOIN commission_info ci ON ci.referral_user_id = n.user_id
  ORDER BY n.lvl, p.created_at;
END;
$$;