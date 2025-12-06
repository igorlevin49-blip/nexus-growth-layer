-- Fix get_referral_network_from_table to show EARNED commissions for ALL TIME (not just current month)
CREATE OR REPLACE FUNCTION public.get_referral_network_from_table(
  root_user_id uuid,
  max_level integer DEFAULT 10,
  p_structure_type integer DEFAULT 1
)
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
AS $$
DECLARE
  is_admin_user boolean;
BEGIN
  -- Check if the requesting user is admin/superadmin
  is_admin_user := has_role(auth.uid(), 'admin'::app_role) OR has_role(auth.uid(), 'superadmin'::app_role);
  
  RETURN QUERY
  WITH RECURSIVE network AS (
    -- Base case: direct referrals of root user
    SELECT 
      r.referrer_id as parent_id,
      p.id as member_id,
      1 as lvl
    FROM public.referrals r
    JOIN public.profiles p ON p.id = r.referred_user_id
    WHERE r.referrer_id = root_user_id
      AND r.structure_type = p_structure_type
    
    UNION ALL
    
    -- Recursive: children of current level
    SELECT
      r.referrer_id as parent_id,
      p.id as member_id,
      n.lvl + 1 as lvl
    FROM public.referrals r
    JOIN public.profiles p ON p.id = r.referred_user_id
    INNER JOIN network n ON n.member_id = r.referrer_id
    WHERE n.lvl < max_level
      AND r.structure_type = p_structure_type
  ),
  team_counts AS (
    SELECT 
      n.member_id,
      (
        WITH RECURSIVE sub_tree AS (
          SELECT r2.referred_user_id as sub_member
          FROM referrals r2
          WHERE r2.referrer_id = n.member_id
            AND r2.structure_type = p_structure_type
          UNION ALL
          SELECT r3.referred_user_id
          FROM referrals r3
          JOIN sub_tree st ON r3.referrer_id = st.sub_member
          WHERE r3.structure_type = p_structure_type
        )
        SELECT COUNT(*) FROM sub_tree
      )::INTEGER as total_team_count
    FROM network n
  )
  SELECT 
    root_user_id as user_id,
    p.id as partner_id,
    n.lvl as level,
    p.full_name,
    CASE 
      WHEN is_admin_user OR p.id = auth.uid() THEN p.email
      ELSE NULL
    END as email,
    p.avatar_url,
    p.subscription_status,
    p.monthly_activation_completed as monthly_activation_met,
    p.referral_code,
    p.created_at,
    COALESCE(p.direct_referrals_count, 0)::INTEGER as direct_referrals,
    COALESCE(tc.total_team_count, 0)::INTEGER as total_team,
    -- Total volume: EARNED commissions for this user for ALL TIME
    COALESCE((
      SELECT SUM(t.amount_cents) / 100.0
      FROM transactions t
      WHERE t.user_id = p.id
        AND t.type = 'commission'
        AND t.status IN ('completed', 'frozen')
    ), 0) as monthly_volume,
    n.parent_id as parent_partner_id
  FROM network n
  JOIN public.profiles p ON p.id = n.member_id
  LEFT JOIN team_counts tc ON tc.member_id = n.member_id
  ORDER BY n.lvl, p.created_at;
END;
$$;