-- Drop existing function overloads first
DROP FUNCTION IF EXISTS public.get_referral_network_from_table(uuid, integer, integer);
DROP FUNCTION IF EXISTS public.get_referral_network_from_table(uuid, integer);

-- Recreate function with fix: change source_id to user_id for monthly_volume calculation
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
  monthly_volume numeric
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  is_admin_user boolean;
BEGIN
  -- Check if requesting user is admin
  is_admin_user := has_role(auth.uid(), 'admin'::app_role) OR 
                   has_role(auth.uid(), 'superadmin'::app_role);

  RETURN QUERY
  WITH RECURSIVE referral_tree AS (
    -- Base case: direct referrals of root user
    SELECT 
      r.referrer_id,
      r.referred_user_id,
      1 as lvl
    FROM referrals r
    WHERE r.referrer_id = root_user_id
      AND r.structure_type = p_structure_type
    
    UNION ALL
    
    -- Recursive case: referrals of referrals
    SELECT 
      r.referrer_id,
      r.referred_user_id,
      rt.lvl + 1 as lvl
    FROM referrals r
    INNER JOIN referral_tree rt ON r.referrer_id = rt.referred_user_id
    WHERE rt.lvl < max_level
      AND r.structure_type = p_structure_type
  )
  SELECT 
    root_user_id as user_id,
    rt.referred_user_id as partner_id,
    rt.lvl as level,
    p.full_name,
    CASE 
      WHEN is_admin_user OR p.id = auth.uid() THEN p.email
      ELSE NULL
    END as email,
    p.avatar_url,
    p.subscription_status,
    p.monthly_activation_met,
    p.referral_code,
    p.created_at,
    COALESCE(p.direct_referrals_count, 0)::integer as direct_referrals,
    COALESCE((
      WITH RECURSIVE sub_tree AS (
        SELECT r2.referred_user_id
        FROM referrals r2
        WHERE r2.referrer_id = rt.referred_user_id
          AND r2.structure_type = p_structure_type
        UNION ALL
        SELECT r3.referred_user_id
        FROM referrals r3
        INNER JOIN sub_tree st ON r3.referrer_id = st.referred_user_id
        WHERE r3.structure_type = p_structure_type
      )
      SELECT COUNT(*) FROM sub_tree
    ), 0)::integer as total_team,
    -- FIX: Changed source_id to user_id - transactions where partner RECEIVED the commission
    COALESCE((
      SELECT SUM(t.amount_cents) / 100.0
      FROM transactions t
      WHERE t.user_id = rt.referred_user_id
        AND t.type = 'commission'
        AND t.status = 'completed'
        AND t.created_at >= date_trunc('month', CURRENT_DATE)
        AND COALESCE(t.is_archived, false) = false
    ), 0) AS monthly_volume
  FROM referral_tree rt
  INNER JOIN profiles p ON p.id = rt.referred_user_id
  WHERE p.is_active = true
    AND p.deleted_at IS NULL
  ORDER BY rt.lvl, p.created_at;
END;
$function$;