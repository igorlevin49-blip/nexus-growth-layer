-- Fix get_referral_network_from_table to correctly find commissions
-- The payload key is 'from_user_id', not 'source_user_id'

DROP FUNCTION IF EXISTS public.get_referral_network_from_table(uuid, integer, integer);

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
  direct_referrals integer,
  total_team integer,
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
DECLARE
  v_is_admin boolean := false;
  v_caller_id uuid;
BEGIN
  -- Get caller info for permission checks
  v_caller_id := auth.uid();
  
  -- Check if caller is admin
  SELECT EXISTS(
    SELECT 1 FROM user_roles 
    WHERE user_roles.user_id = v_caller_id 
    AND role IN ('admin', 'superadmin')
  ) INTO v_is_admin;

  RETURN QUERY
  WITH RECURSIVE network AS (
    -- Base case: direct referrals of root user
    SELECT 
      r.referred_user_id as uid,
      r.referrer_id as parent_id,
      1 as lvl
    FROM referrals r
    WHERE r.referrer_id = root_user_id
      AND r.structure_type = p_structure_type
    
    UNION ALL
    
    -- Recursive case: referrals of referrals
    SELECT 
      r.referred_user_id,
      r.referrer_id,
      n.lvl + 1
    FROM referrals r
    INNER JOIN network n ON r.referrer_id = n.uid
    WHERE r.structure_type = p_structure_type
      AND n.lvl < max_level
  ),
  -- Count direct referrals for each user in this structure
  direct_counts AS (
    SELECT 
      r.referrer_id as ref_id,
      COUNT(*)::integer as cnt
    FROM referrals r
    WHERE r.structure_type = p_structure_type
    GROUP BY r.referrer_id
  ),
  -- Count total team recursively for each network member
  team_recursive AS (
    SELECT 
      n.uid as team_root,
      r.referred_user_id as member_id,
      1 as depth
    FROM network n
    JOIN referrals r ON r.referrer_id = n.uid AND r.structure_type = p_structure_type
    
    UNION ALL
    
    SELECT 
      tr.team_root,
      r.referred_user_id,
      tr.depth + 1
    FROM team_recursive tr
    JOIN referrals r ON r.referrer_id = tr.member_id AND r.structure_type = p_structure_type
    WHERE tr.depth < 10
  ),
  team_counts AS (
    SELECT team_root, COUNT(DISTINCT member_id)::integer as total
    FROM team_recursive
    GROUP BY team_root
  ),
  -- Get commission info for each network member
  -- Commission is stored in sponsor's transactions where from_user_id = member's id
  commission_data AS (
    SELECT DISTINCT ON (n.uid)
      n.uid as member_id,
      t.id IS NOT NULL as has_comm,
      t.status::text as comm_status,
      t.frozen_until as frozen_date
    FROM network n
    JOIN profiles p ON p.id = n.uid
    LEFT JOIN transactions t ON 
      t.user_id = p.sponsor_id  -- Commission goes to the sponsor
      AND t.type = 'commission'
      AND t.structure_type = CASE WHEN p_structure_type = 1 THEN 'primary'::structure_type ELSE 'secondary'::structure_type END
      AND (
        -- Check both possible keys for source user
        t.payload->>'from_user_id' = n.uid::text
        OR t.payload->>'source_user_id' = n.uid::text
      )
    ORDER BY n.uid, t.created_at DESC NULLS LAST
  ),
  -- Calculate no_commission_reason separately
  reason_data AS (
    SELECT 
      n.uid as member_id,
      CASE
        WHEN cd.has_comm = true THEN NULL  -- Has commission, no reason needed
        WHEN p.subscription_status NOT IN ('active', 'paid') THEN 'no_active_subscription'
        WHEN sp.id IS NULL THEN 'no_sponsor'
        WHEN sp.subscription_status NOT IN ('active', 'paid') THEN 'sponsor_inactive'
        WHEN p_structure_type = 2 AND NOT COALESCE(sp.monthly_activation_completed, false) THEN 'sponsor_no_activation'
        ELSE NULL
      END as reason
    FROM network n
    JOIN profiles p ON p.id = n.uid
    LEFT JOIN profiles sp ON sp.id = p.sponsor_id
    LEFT JOIN commission_data cd ON cd.member_id = n.uid
  )
  SELECT 
    n.uid as user_id,
    n.uid::text as partner_id,
    n.lvl as level,
    p.full_name,
    CASE 
      WHEN v_is_admin OR n.uid = v_caller_id THEN p.email
      WHEN p.email IS NULL THEN NULL
      ELSE regexp_replace(p.email, '(.{2})(.*)(@.*)', '\1***\3')
    END as email,
    CASE 
      WHEN v_is_admin OR n.uid = v_caller_id THEN p.phone
      WHEN p.phone IS NULL THEN NULL
      ELSE '***' || right(p.phone, 4)
    END as phone,
    p.avatar_url,
    p.subscription_status,
    p.subscription_expires_at,
    COALESCE(p.monthly_activation_completed, false) as monthly_activation_met,
    p.referral_code,
    p.created_at,
    COALESCE(dc.cnt, 0) as direct_referrals,
    COALESCE(tc.total, 0) as total_team,
    0::numeric as monthly_volume,
    n.parent_id::text as parent_partner_id,
    n.parent_id as parent_user_id,
    COALESCE(cd.has_comm, false) as has_commission_received,
    rd.reason as no_commission_reason,
    cd.comm_status as commission_status,
    cd.frozen_date as commission_frozen_until
  FROM network n
  JOIN profiles p ON p.id = n.uid
  LEFT JOIN direct_counts dc ON dc.ref_id = n.uid
  LEFT JOIN team_counts tc ON tc.team_root = n.uid
  LEFT JOIN commission_data cd ON cd.member_id = n.uid
  LEFT JOIN reason_data rd ON rd.member_id = n.uid
  ORDER BY n.lvl, p.created_at;
END;
$$;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION public.get_referral_network_from_table(uuid, integer, integer) TO authenticated;