
DROP FUNCTION IF EXISTS public.get_referral_network_from_table(uuid, integer, integer);

CREATE OR REPLACE FUNCTION public.get_referral_network_from_table(root_user_id uuid, max_level integer DEFAULT 10, p_structure_type integer DEFAULT 1)
RETURNS TABLE(
  user_id uuid,
  partner_id uuid,
  level integer,
  full_name text,
  email text,
  avatar_url text,
  subscription_status text,
  monthly_activation_met boolean,
  referral_code text,
  created_at timestamp with time zone,
  direct_referrals integer,
  total_team integer,
  monthly_volume numeric,
  parent_partner_id uuid
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  is_admin_user boolean;
BEGIN
  is_admin_user := has_role(auth.uid(), 'admin'::app_role) OR has_role(auth.uid(), 'superadmin'::app_role);
  
  RETURN QUERY
  WITH RECURSIVE network_tree AS (
    SELECT 
      r.referrer_id,
      r.referred_user_id,
      1 as lvl
    FROM referrals r
    WHERE r.referrer_id = root_user_id
      AND r.structure_type = p_structure_type
    
    UNION ALL
    
    SELECT
      r.referrer_id,
      r.referred_user_id,
      nt.lvl + 1 as lvl
    FROM referrals r
    INNER JOIN network_tree nt ON r.referrer_id = nt.referred_user_id
    WHERE nt.lvl < max_level
      AND r.structure_type = p_structure_type
  ),
  unique_tree AS (
    SELECT DISTINCT ON (referred_user_id)
      referrer_id,
      referred_user_id,
      lvl
    FROM network_tree
    ORDER BY referred_user_id, lvl
  )
  SELECT 
    root_user_id as user_id,
    p.id as partner_id,
    ut.lvl as level,
    p.full_name,
    CASE 
      WHEN is_admin_user OR p.id = auth.uid() THEN p.email
      ELSE NULL
    END as email,
    p.avatar_url,
    p.subscription_status,
    COALESCE(p.monthly_activation_completed, false) as monthly_activation_met,
    p.referral_code,
    p.created_at,
    COALESCE(p.direct_referrals_count, 0)::INTEGER as direct_referrals,
    (
      WITH RECURSIVE sub_team AS (
        SELECT r2.referred_user_id
        FROM referrals r2
        WHERE r2.referrer_id = p.id
          AND r2.structure_type = p_structure_type
        UNION ALL
        SELECT r3.referred_user_id
        FROM referrals r3
        INNER JOIN sub_team st ON r3.referrer_id = st.referred_user_id
        WHERE r3.structure_type = p_structure_type
      )
      SELECT COUNT(*)::INTEGER FROM sub_team
    ) as total_team,
    COALESCE((
      SELECT SUM(oi.price_usd * oi.qty)
      FROM orders o
      JOIN order_items oi ON oi.order_id = o.id
      WHERE o.user_id = p.id
        AND o.status = 'paid'
        AND DATE_TRUNC('month', o.paid_at) = DATE_TRUNC('month', NOW())
    ), 0) as monthly_volume,
    ut.referrer_id as parent_partner_id
  FROM unique_tree ut
  JOIN profiles p ON p.id = ut.referred_user_id
  WHERE p.is_active = true
    AND p.deleted_at IS NULL
  ORDER BY ut.lvl, p.created_at;
END;
$function$;
