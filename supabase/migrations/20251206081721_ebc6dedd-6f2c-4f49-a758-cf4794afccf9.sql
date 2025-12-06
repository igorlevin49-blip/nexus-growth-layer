-- Drop existing function to change return type
DROP FUNCTION IF EXISTS public.get_referral_network_from_table(uuid, integer, integer);

-- Recreate with referrer_id and fix total_team recursive calculation
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
  referrer_id uuid
)
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
  WITH RECURSIVE network_tree AS (
    -- Base case: direct referrals of root user
    SELECT 
      r.referred_user_id,
      r.referrer_id,
      1 as lvl
    FROM referrals r
    WHERE r.referrer_id = root_user_id
      AND r.structure_type = p_structure_type
    
    UNION ALL
    
    -- Recursive case: referrals of referrals
    SELECT 
      r.referred_user_id,
      r.referrer_id,
      nt.lvl + 1
    FROM referrals r
    INNER JOIN network_tree nt ON r.referrer_id = nt.referred_user_id
    WHERE r.structure_type = p_structure_type
      AND nt.lvl < max_level
  ),
  ranked_tree AS (
    SELECT 
      nt.referred_user_id,
      nt.referrer_id,
      nt.lvl,
      ROW_NUMBER() OVER (PARTITION BY nt.referred_user_id ORDER BY nt.lvl) as rn
    FROM network_tree nt
  ),
  unique_tree AS (
    SELECT referred_user_id, referrer_id, lvl
    FROM ranked_tree
    WHERE rn = 1
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
    p.monthly_activation_completed AS monthly_activation_met,
    p.referral_code,
    p.created_at,
    COALESCE(p.direct_referrals_count, 0)::INTEGER as direct_referrals,
    -- Calculate total team size recursively
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
    -- Calculate monthly volume (commissions earned by this partner)
    COALESCE((
      SELECT SUM(t.amount_cents) / 100.0
      FROM transactions t
      WHERE t.user_id = ut.referred_user_id
        AND t.type = 'commission'
        AND t.status = 'completed'
        AND t.created_at >= date_trunc('month', CURRENT_DATE)
        AND COALESCE(t.is_archived, false) = false
    ), 0) AS monthly_volume,
    -- Add referrer_id for proper tree building
    ut.referrer_id as referrer_id
  FROM unique_tree ut
  JOIN profiles p ON p.id = ut.referred_user_id
  WHERE p.is_active = true
    AND (p.deleted_at IS NULL)
    AND (p.is_archived IS NULL OR p.is_archived = false)
  ORDER BY ut.lvl, p.created_at;
END;
$function$;