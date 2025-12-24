-- Исправляем функцию get_network_tree: заменяем monthly_activation_met на monthly_activation_completed
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
  -- Check if caller is admin
  SELECT EXISTS(
    SELECT 1 FROM user_roles 
    WHERE user_id = auth.uid() 
    AND role IN ('admin', 'superadmin')
  ) INTO is_admin_user;

  RETURN QUERY
  WITH RECURSIVE network AS (
    -- Root user
    SELECT 
      root_user_id as user_id,
      p.id as partner_id,
      0 as level,
      p.full_name,
      CASE 
        WHEN is_admin_user OR p.id = auth.uid() THEN p.email
        ELSE NULL
      END as email,
      p.avatar_url,
      p.subscription_status,
      COALESCE(p.monthly_activation_completed, false) as monthly_activation_met,
      p.referral_code,
      p.created_at
    FROM public.profiles p
    WHERE p.id = root_user_id
    
    UNION ALL
    
    -- Recursive: children
    SELECT
      root_user_id as user_id,
      p.id as partner_id,
      n.level + 1 as level,
      p.full_name,
      CASE 
        WHEN is_admin_user OR p.id = auth.uid() THEN p.email
        ELSE NULL
      END as email,
      p.avatar_url,
      p.subscription_status,
      COALESCE(p.monthly_activation_completed, false) as monthly_activation_met,
      p.referral_code,
      p.created_at
    FROM public.profiles p
    INNER JOIN network n ON p.sponsor_id = n.partner_id
    WHERE n.level < max_level
  ),
  stats AS (
    SELECT 
      n.partner_id,
      COUNT(DISTINCT CASE WHEN p.sponsor_id = n.partner_id THEN p.id END) as direct_refs,
      COUNT(DISTINCT p2.id) as total_team_count,
      COALESCE(SUM(CASE 
        WHEN o.status = 'paid' 
        AND DATE_TRUNC('month', o.created_at) = DATE_TRUNC('month', NOW())
        THEN oi.price_usd * oi.qty 
      END), 0) as monthly_vol
    FROM network n
    LEFT JOIN public.profiles p ON p.sponsor_id = n.partner_id
    LEFT JOIN LATERAL (
      WITH RECURSIVE sub_network AS (
        SELECT id FROM public.profiles WHERE sponsor_id = n.partner_id
        UNION ALL
        SELECT p.id FROM public.profiles p
        INNER JOIN sub_network sn ON p.sponsor_id = sn.id
      )
      SELECT id FROM sub_network
    ) p2 ON true
    LEFT JOIN public.orders o ON o.user_id = p2.id
    LEFT JOIN public.order_items oi ON oi.order_id = o.id
    GROUP BY n.partner_id
  )
  SELECT 
    n.user_id,
    n.partner_id,
    n.level,
    n.full_name,
    n.email,
    n.avatar_url,
    n.subscription_status,
    n.monthly_activation_met,
    n.referral_code,
    n.created_at,
    COALESCE(s.direct_refs, 0)::INTEGER as direct_referrals,
    COALESCE(s.total_team_count, 0)::INTEGER as total_team,
    COALESCE(s.monthly_vol, 0) as monthly_volume
  FROM network n
  LEFT JOIN stats s ON s.partner_id = n.partner_id
  WHERE n.level > 0
  ORDER BY n.level, n.created_at;
END;
$$;