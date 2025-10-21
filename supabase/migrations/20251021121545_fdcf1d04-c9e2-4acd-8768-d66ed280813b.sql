-- Update get_network_tree function to support 10 levels
CREATE OR REPLACE FUNCTION public.get_network_tree(root_user_id uuid, max_level integer DEFAULT 10)
 RETURNS TABLE(user_id uuid, partner_id uuid, level integer, full_name text, email text, avatar_url text, subscription_status text, monthly_activation_met boolean, referral_code text, created_at timestamp with time zone, direct_referrals integer, total_team integer, monthly_volume numeric)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  RETURN QUERY
  WITH RECURSIVE network AS (
    -- Root user
    SELECT 
      root_user_id as user_id,
      p.id as partner_id,
      0 as level,
      p.full_name,
      p.email,
      p.avatar_url,
      p.subscription_status,
      p.monthly_activation_met,
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
      p.email,
      p.avatar_url,
      p.subscription_status,
      p.monthly_activation_met,
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
$function$;

-- Update get_network_stats function to use 10 levels
CREATE OR REPLACE FUNCTION public.get_network_stats(user_id_param uuid)
 RETURNS TABLE(total_partners integer, active_partners integer, frozen_partners integer, max_level integer, new_this_month integer, activations_this_month integer, volume_this_month numeric, commissions_this_month numeric)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  RETURN QUERY
  WITH network AS (
    SELECT * FROM public.get_network_tree(user_id_param, 10)
  ),
  month_start AS (
    SELECT DATE_TRUNC('month', NOW()) as start_date
  )
  SELECT 
    COUNT(DISTINCT n.partner_id)::INTEGER as total_partners,
    COUNT(DISTINCT CASE 
      WHEN n.subscription_status = 'active' OR n.monthly_activation_met = true 
      THEN n.partner_id 
    END)::INTEGER as active_partners,
    COUNT(DISTINCT CASE 
      WHEN n.subscription_status = 'frozen' 
      THEN n.partner_id 
    END)::INTEGER as frozen_partners,
    COALESCE(MAX(n.level), 0)::INTEGER as max_level,
    COUNT(DISTINCT CASE 
      WHEN n.created_at >= (SELECT start_date FROM month_start)
      THEN n.partner_id 
    END)::INTEGER as new_this_month,
    COALESCE(SUM(CASE 
      WHEN o.status = 'paid' 
      AND oi.is_activation_snapshot = true
      AND o.created_at >= (SELECT start_date FROM month_start)
      THEN oi.qty 
    END), 0)::INTEGER as activations_this_month,
    COALESCE(SUM(CASE 
      WHEN o.status = 'paid'
      AND o.created_at >= (SELECT start_date FROM month_start)
      THEN oi.price_usd * oi.qty 
    END), 0) as volume_this_month,
    0::NUMERIC as commissions_this_month
  FROM network n
  LEFT JOIN public.orders o ON o.user_id = n.partner_id
  LEFT JOIN public.order_items oi ON oi.order_id = o.id;
END;
$function$;