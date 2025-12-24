-- Исправляем функцию get_network_tree: устраняем конфликт имён столбцов
CREATE OR REPLACE FUNCTION public.get_network_tree(root_user_id UUID, max_level INTEGER DEFAULT 5)
RETURNS TABLE (
  user_id UUID,
  partner_id UUID,
  level INTEGER,
  full_name TEXT,
  email TEXT,
  avatar_url TEXT,
  subscription_status TEXT,
  monthly_activation_met BOOLEAN,
  referral_code TEXT,
  created_at TIMESTAMPTZ,
  direct_referrals INTEGER,
  total_team INTEGER,
  monthly_volume NUMERIC
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  is_admin_user BOOLEAN;
BEGIN
  -- Check if caller is admin (using explicit table alias to avoid ambiguity)
  SELECT EXISTS(
    SELECT 1 FROM user_roles ur
    WHERE ur.user_id = auth.uid() 
    AND ur.role IN ('admin', 'superadmin')
  ) INTO is_admin_user;

  RETURN QUERY
  WITH RECURSIVE network AS (
    -- Root user
    SELECT 
      root_user_id as uid,
      p.id as pid,
      0 as lvl,
      p.full_name as fname,
      CASE 
        WHEN is_admin_user OR p.id = auth.uid() THEN p.email
        ELSE NULL
      END as em,
      p.avatar_url as av,
      p.subscription_status as ss,
      COALESCE(p.monthly_activation_completed, false) as mac,
      p.referral_code as rc,
      p.created_at as ca
    FROM public.profiles p
    WHERE p.id = root_user_id
    
    UNION ALL
    
    -- Recursive: children
    SELECT
      root_user_id as uid,
      p.id as pid,
      n.lvl + 1 as lvl,
      p.full_name as fname,
      CASE 
        WHEN is_admin_user OR p.id = auth.uid() THEN p.email
        ELSE NULL
      END as em,
      p.avatar_url as av,
      p.subscription_status as ss,
      COALESCE(p.monthly_activation_completed, false) as mac,
      p.referral_code as rc,
      p.created_at as ca
    FROM public.profiles p
    INNER JOIN network n ON p.sponsor_id = n.pid
    WHERE n.lvl < max_level
  ),
  stats AS (
    SELECT 
      n.pid as partner,
      COUNT(DISTINCT CASE WHEN pr.sponsor_id = n.pid THEN pr.id END) as direct_refs,
      COUNT(DISTINCT p2.id) as total_team_count,
      COALESCE(SUM(CASE 
        WHEN o.status = 'paid' 
        AND DATE_TRUNC('month', o.created_at) = DATE_TRUNC('month', NOW())
        THEN oi.price_usd * oi.qty 
      END), 0) as monthly_vol
    FROM network n
    LEFT JOIN public.profiles pr ON pr.sponsor_id = n.pid
    LEFT JOIN LATERAL (
      WITH RECURSIVE sub_network AS (
        SELECT id FROM public.profiles WHERE sponsor_id = n.pid
        UNION ALL
        SELECT prf.id FROM public.profiles prf
        INNER JOIN sub_network sn ON prf.sponsor_id = sn.id
      )
      SELECT id FROM sub_network
    ) p2 ON true
    LEFT JOIN public.orders o ON o.user_id = p2.id
    LEFT JOIN public.order_items oi ON oi.order_id = o.id
    GROUP BY n.pid
  )
  SELECT 
    n.uid as user_id,
    n.pid as partner_id,
    n.lvl as level,
    n.fname as full_name,
    n.em as email,
    n.av as avatar_url,
    n.ss as subscription_status,
    n.mac as monthly_activation_met,
    n.rc as referral_code,
    n.ca as created_at,
    COALESCE(s.direct_refs, 0)::INTEGER as direct_referrals,
    COALESCE(s.total_team_count, 0)::INTEGER as total_team,
    COALESCE(s.monthly_vol, 0) as monthly_volume
  FROM network n
  LEFT JOIN stats s ON s.partner = n.pid
  WHERE n.lvl > 0
  ORDER BY n.lvl, n.ca;
END;
$$;