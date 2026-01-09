-- Drop existing function first
DROP FUNCTION IF EXISTS public.get_referral_network_from_table(uuid, integer, integer);

-- Fix get_referral_network_from_table: no_commission_reason should be NULL when has_commission_received=true
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
  parent_partner_id uuid,
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
  v_partner_id uuid;
BEGIN
  -- Get partner_id for root user
  SELECT p.id INTO v_partner_id 
  FROM partners p 
  WHERE p.user_id = root_user_id AND p.structure_type = p_structure_type;
  
  IF v_partner_id IS NULL THEN
    RETURN;
  END IF;

  RETURN QUERY
  WITH RECURSIVE network AS (
    -- Base: direct referrals of root
    SELECT 
      p.id as partner_id,
      p.user_id,
      p.referrer_id as parent_partner_id,
      1 as lvl
    FROM partners p
    WHERE p.referrer_id = v_partner_id
      AND p.structure_type = p_structure_type
    
    UNION ALL
    
    -- Recursive: referrals of referrals
    SELECT 
      p.id as partner_id,
      p.user_id,
      p.referrer_id as parent_partner_id,
      n.lvl + 1
    FROM partners p
    JOIN network n ON p.referrer_id = n.partner_id
    WHERE n.lvl < max_level
      AND p.structure_type = p_structure_type
  ),
  -- Get monthly activation status
  activation_status AS (
    SELECT 
      ma.user_id,
      ma.is_activated
    FROM monthly_activations ma
    WHERE ma.year = EXTRACT(YEAR FROM CURRENT_DATE)::int
      AND ma.month = EXTRACT(MONTH FROM CURRENT_DATE)::int
  ),
  -- Calculate direct referrals count for each partner
  direct_counts AS (
    SELECT 
      p.referrer_id as partner_id,
      COUNT(*) as direct_count
    FROM partners p
    WHERE p.structure_type = p_structure_type
    GROUP BY p.referrer_id
  ),
  -- Get commission info from network_with_payouts
  commission_info AS (
    SELECT 
      nwp.partner_id,
      nwp.has_commission,
      nwp.reason,
      nwp.commission_status,
      nwp.frozen_until
    FROM network_with_payouts nwp
    WHERE nwp.structure_type = p_structure_type
      AND nwp.root_user_id = root_user_id
  ),
  -- Get parent user_id
  parent_info AS (
    SELECT 
      p.id as partner_id,
      pp.user_id as parent_user_id
    FROM partners p
    LEFT JOIN partners pp ON p.referrer_id = pp.id
    WHERE p.structure_type = p_structure_type
  )
  SELECT 
    n.user_id,
    n.partner_id,
    n.lvl as level,
    pr.full_name,
    pr.email,
    pr.phone,
    pr.avatar_url,
    pr.subscription_status,
    pr.subscription_expires_at,
    COALESCE(ast.is_activated, pr.monthly_activation_completed, false) as monthly_activation_met,
    pr.referral_code,
    pr.created_at,
    COALESCE(dc.direct_count, 0)::bigint as direct_referrals,
    -- Calculate total team using subquery
    (
      WITH RECURSIVE team AS (
        SELECT p2.id FROM partners p2 WHERE p2.referrer_id = n.partner_id AND p2.structure_type = p_structure_type
        UNION ALL
        SELECT p3.id FROM partners p3 JOIN team t ON p3.referrer_id = t.id WHERE p3.structure_type = p_structure_type
      )
      SELECT COUNT(*)::bigint FROM team
    ) as total_team,
    COALESCE(pr.personal_volume, 0) as monthly_volume,
    n.parent_partner_id,
    pi.parent_user_id,
    COALESCE(ci.has_commission, false) as has_commission_received,
    -- FIX: If has_commission is true, no_commission_reason should be NULL
    CASE 
      WHEN COALESCE(ci.has_commission, false) = true THEN NULL
      ELSE ci.reason
    END as no_commission_reason,
    ci.commission_status,
    ci.frozen_until as commission_frozen_until
  FROM network n
  JOIN profiles pr ON pr.id = n.user_id
  LEFT JOIN activation_status ast ON ast.user_id = n.user_id
  LEFT JOIN direct_counts dc ON dc.partner_id = n.partner_id
  LEFT JOIN commission_info ci ON ci.partner_id = n.partner_id
  LEFT JOIN parent_info pi ON pi.partner_id = n.partner_id
  ORDER BY n.lvl, pr.full_name;
END;
$$;