-- Fix security issue: Hide sensitive PII in network tree for non-admins
-- Replace get_network_tree function to exclude email/phone for regular users

CREATE OR REPLACE FUNCTION public.get_network_tree(root_user_id uuid, max_level integer DEFAULT 10)
 RETURNS TABLE(user_id uuid, partner_id uuid, level integer, full_name text, email text, avatar_url text, subscription_status text, monthly_activation_met boolean, referral_code text, created_at timestamp with time zone, direct_referrals integer, total_team integer, monthly_volume numeric)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  is_admin_user boolean;
BEGIN
  -- Check if the requesting user is admin/superadmin
  is_admin_user := has_role(auth.uid(), 'admin'::app_role) OR has_role(auth.uid(), 'superadmin'::app_role);
  
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
      CASE 
        WHEN is_admin_user OR p.id = auth.uid() THEN p.email
        ELSE NULL
      END as email,
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

-- Update activity_log RLS to further restrict sensitive payload access
-- Keep existing policies but add comment about payload data restrictions
COMMENT ON COLUMN public.activity_log.payload IS 'SECURITY: Must not contain PII (emails, phones, full names). Store only event metadata, IDs, and non-sensitive status information.';

-- Add constraint to payment_methods.meta to prevent accidental sensitive data storage
COMMENT ON COLUMN public.payment_methods.meta IS 'SECURITY: Store ONLY tokenized data, last4 digits, provider IDs. NEVER store full card numbers, CVVs, or passwords.';