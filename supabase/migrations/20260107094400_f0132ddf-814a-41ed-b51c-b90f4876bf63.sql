
-- Drop and recreate the function to check ACTUAL commissions from transactions table
DROP FUNCTION IF EXISTS public.get_referral_network_from_table(uuid, integer, integer);
DROP FUNCTION IF EXISTS public.get_referral_network_from_table(uuid, integer);

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
  direct_referrals bigint,
  total_team bigint,
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
  current_year integer := EXTRACT(YEAR FROM CURRENT_DATE)::integer;
  current_month integer := EXTRACT(MONTH FROM CURRENT_DATE)::integer;
  sponsor_has_subscription boolean;
  sponsor_has_activation boolean;
BEGIN
  -- Check sponsor's subscription status
  SELECT (prof.subscription_status = 'active') INTO sponsor_has_subscription
  FROM profiles prof
  WHERE prof.id = root_user_id;

  -- Check sponsor's current month activation
  SELECT EXISTS(
    SELECT 1 FROM monthly_activations mact
    WHERE mact.user_id = root_user_id
      AND mact.year = current_year
      AND mact.month = current_month
  ) INTO sponsor_has_activation;

  RETURN QUERY
  WITH RECURSIVE network AS (
    -- Base case: direct referrals (level 1)
    SELECT 
      r.referred_user_id AS member_id,
      r.referrer_id AS parent_id,
      1 AS lvl
    FROM referrals r
    WHERE r.referrer_id = root_user_id
      AND (p_structure_type = 1 OR r.structure_type = p_structure_type)
    
    UNION ALL
    
    -- Recursive case: referrals of referrals
    SELECT 
      r.referred_user_id AS member_id,
      r.referrer_id AS parent_id,
      n.lvl + 1 AS lvl
    FROM referrals r
    INNER JOIN network n ON r.referrer_id = n.member_id
    WHERE n.lvl < max_level
      AND (p_structure_type = 1 OR r.structure_type = p_structure_type)
  ),
  -- Get ACTUAL commissions from transactions table
  existing_commissions AS (
    SELECT 
      t.id AS tx_id,
      (t.payload->>'from_user_id')::uuid AS partner_id,
      t.status AS tx_status,
      t.frozen_until AS tx_frozen_until
    FROM transactions t
    WHERE t.user_id = root_user_id
      AND t.type = 'commission'
      AND t.structure_type = CASE WHEN p_structure_type = 1 THEN 'primary' ELSE 'secondary' END
      AND t.is_archived = false
      AND (
        -- Current month commissions
        EXTRACT(YEAR FROM t.created_at) = current_year
        AND EXTRACT(MONTH FROM t.created_at) = current_month
      )
  ),
  member_stats AS (
    SELECT 
      n.member_id,
      n.parent_id,
      n.lvl,
      -- Direct referrals count
      (SELECT COUNT(*) FROM referrals ref WHERE ref.referrer_id = n.member_id) AS direct_refs,
      -- Total team count (recursive)
      (
        WITH RECURSIVE team AS (
          SELECT ref.referred_user_id FROM referrals ref WHERE ref.referrer_id = n.member_id
          UNION ALL
          SELECT ref.referred_user_id FROM referrals ref
          INNER JOIN team t ON ref.referrer_id = t.referred_user_id
        )
        SELECT COUNT(*) FROM team
      ) AS total_team_count
    FROM network n
  )
  SELECT 
    prof.id AS user_id,
    prof.referral_code AS partner_id,
    ms.lvl AS level,
    prof.full_name,
    prof.email,
    prof.phone,
    prof.avatar_url,
    prof.subscription_status,
    prof.subscription_expires_at,
    -- Current month activation status
    COALESCE(
      (SELECT true FROM monthly_activations mact 
       WHERE mact.user_id = prof.id 
         AND mact.year = current_year 
         AND mact.month = current_month
       LIMIT 1),
      false
    ) AS monthly_activation_met,
    prof.referral_code,
    prof.created_at,
    COALESCE(ms.direct_refs, 0) AS direct_referrals,
    COALESCE(ms.total_team_count, 0) AS total_team,
    COALESCE(
      (SELECT mact.amount FROM monthly_activations mact 
       WHERE mact.user_id = prof.id 
         AND mact.year = current_year 
         AND mact.month = current_month
       LIMIT 1),
      0
    ) AS monthly_volume,
    -- Parent info
    (SELECT p2.referral_code FROM profiles p2 WHERE p2.id = ms.parent_id) AS parent_partner_id,
    ms.parent_id AS parent_user_id,
    -- Check if ACTUAL commission exists in transactions
    CASE 
      WHEN ec.tx_id IS NOT NULL THEN true
      ELSE false
    END AS has_commission_received,
    -- Only calculate reason if NO commission exists
    CASE 
      WHEN ec.tx_id IS NOT NULL THEN null  -- Commission exists, no reason needed
      WHEN prof.subscription_status IS NULL OR prof.subscription_status != 'active' THEN 'no_active_subscription'
      WHEN prof.is_marketing_participant = true AND prof.marketing_access_type = 'free_access' THEN 'marketing_free_access'
      WHEN NOT sponsor_has_subscription THEN 'sponsor_inactive'
      WHEN NOT sponsor_has_activation THEN 'sponsor_no_activation'
      WHEN p_structure_type = 1 AND ms.lvl = 2 AND (SELECT COUNT(*) FROM referrals ref WHERE ref.referrer_id = root_user_id) < 2 THEN 'level_2_locked'
      WHEN p_structure_type = 1 AND ms.lvl = 3 AND (SELECT COUNT(*) FROM referrals ref WHERE ref.referrer_id = root_user_id) < 3 THEN 'level_3_locked'
      WHEN p_structure_type = 1 AND ms.lvl = 4 AND (SELECT COUNT(*) FROM referrals ref WHERE ref.referrer_id = root_user_id) < 4 THEN 'level_4_locked'
      WHEN p_structure_type = 1 AND ms.lvl = 5 AND (SELECT COUNT(*) FROM referrals ref WHERE ref.referrer_id = root_user_id) < 5 THEN 'level_5_locked'
      WHEN p_structure_type = 1 AND ms.lvl = 6 AND (SELECT COUNT(*) FROM referrals ref WHERE ref.referrer_id = root_user_id) < 6 THEN 'level_6_locked'
      WHEN p_structure_type = 1 AND ms.lvl = 7 AND (SELECT COUNT(*) FROM referrals ref WHERE ref.referrer_id = root_user_id) < 7 THEN 'level_7_locked'
      WHEN p_structure_type = 1 AND ms.lvl = 8 AND (SELECT COUNT(*) FROM referrals ref WHERE ref.referrer_id = root_user_id) < 8 THEN 'level_8_locked'
      WHEN p_structure_type = 1 AND ms.lvl = 9 AND (SELECT COUNT(*) FROM referrals ref WHERE ref.referrer_id = root_user_id) < 9 THEN 'level_9_locked'
      WHEN p_structure_type = 1 AND ms.lvl = 10 AND (SELECT COUNT(*) FROM referrals ref WHERE ref.referrer_id = root_user_id) < 10 THEN 'level_10_locked'
      WHEN ms.lvl > 10 THEN 'too_deep'
      ELSE null
    END AS no_commission_reason,
    -- Commission status from transactions
    ec.tx_status AS commission_status,
    ec.tx_frozen_until AS commission_frozen_until
  FROM member_stats ms
  INNER JOIN profiles prof ON prof.id = ms.member_id
  LEFT JOIN existing_commissions ec ON ec.partner_id = prof.id
  ORDER BY ms.lvl, prof.created_at;
END;
$$;

-- Create wrapper function for backward compatibility
CREATE OR REPLACE FUNCTION public.get_referral_network_from_table(
  root_user_id uuid,
  max_level integer
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
  direct_referrals bigint,
  total_team bigint,
  monthly_volume numeric,
  parent_partner_id text,
  parent_user_id uuid,
  has_commission_received boolean,
  no_commission_reason text,
  commission_status text,
  commission_frozen_until timestamptz
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT * FROM public.get_referral_network_from_table(root_user_id, max_level, 1);
$$;
