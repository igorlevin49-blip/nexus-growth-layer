-- Fix has_commission_received check in get_referral_network_from_table
-- The source_id in transactions contains subscription_id, not user_id
-- So we need to join through subscriptions table to find the user

DROP FUNCTION IF EXISTS public.get_referral_network_from_table(uuid, integer, integer);

CREATE OR REPLACE FUNCTION public.get_referral_network_from_table(
  root_user_id uuid,
  max_level integer DEFAULT 10,
  p_structure_type integer DEFAULT 1
)
RETURNS TABLE (
  user_id uuid,
  partner_id text,
  parent_user_id uuid,
  parent_partner_id text,
  level integer,
  full_name text,
  email text,
  phone text,
  referral_code text,
  subscription_status text,
  subscription_expires_at timestamptz,
  monthly_activation_met boolean,
  created_at timestamptz,
  avatar_url text,
  direct_referrals bigint,
  total_team bigint,
  monthly_volume numeric,
  has_commission_received boolean,
  no_commission_reason text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_current_month integer := EXTRACT(MONTH FROM CURRENT_DATE);
  v_current_year integer := EXTRACT(YEAR FROM CURRENT_DATE);
BEGIN
  RETURN QUERY
  WITH RECURSIVE network AS (
    -- Base case: direct referrals of root user
    SELECT
      r.referred_user_id as user_id,
      r.referrer_id as parent_user_id,
      1 as level
    FROM referrals r
    WHERE r.referrer_id = root_user_id
      AND r.structure_type = p_structure_type
    
    UNION ALL
    
    -- Recursive case
    SELECT
      r.referred_user_id as user_id,
      r.referrer_id as parent_user_id,
      n.level + 1 as level
    FROM referrals r
    INNER JOIN network n ON r.referrer_id = n.user_id
    WHERE n.level < max_level
      AND r.structure_type = p_structure_type
  ),
  network_with_ancestors AS (
    SELECT 
      n.user_id,
      n.parent_user_id,
      n.level,
      (SELECT p2.referral_code FROM profiles p2 WHERE p2.id = n.parent_user_id) as parent_partner_id
    FROM network n
  )
  SELECT
    nwa.user_id,
    p.referral_code as partner_id,
    nwa.parent_user_id,
    nwa.parent_partner_id,
    nwa.level,
    p.full_name,
    p.email,
    p.phone,
    p.referral_code,
    p.subscription_status,
    p.subscription_expires_at,
    COALESCE(p.monthly_activation_completed, false) as monthly_activation_met,
    p.created_at,
    p.avatar_url,
    -- Direct referrals count for this structure type
    (SELECT COUNT(*) FROM referrals r WHERE r.referrer_id = nwa.user_id AND r.structure_type = p_structure_type)::bigint as direct_referrals,
    -- Total team count for this structure type
    (
      WITH RECURSIVE team AS (
        SELECT r.referred_user_id FROM referrals r WHERE r.referrer_id = nwa.user_id AND r.structure_type = p_structure_type
        UNION ALL
        SELECT r.referred_user_id FROM referrals r INNER JOIN team t ON r.referrer_id = t.referred_user_id WHERE r.structure_type = p_structure_type
      )
      SELECT COUNT(*) FROM team
    )::bigint as total_team,
    -- Monthly volume
    COALESCE((
      SELECT ma.total_amount_kzt
      FROM monthly_activations ma
      WHERE ma.user_id = nwa.user_id
        AND ma.month = v_current_month
        AND ma.year = v_current_year
    ), 0)::numeric as monthly_volume,
    -- Commission received - FIX: join through subscriptions to get user_id
    CASE WHEN p_structure_type = 1 THEN
      EXISTS (
        SELECT 1 FROM transactions t
        JOIN subscriptions s ON s.id = t.source_id
        WHERE s.user_id = nwa.user_id
          AND t.user_id = root_user_id
          AND t.type = 'commission'
          AND t.structure_type = 'primary'
          AND t.created_at >= date_trunc('month', CURRENT_DATE)
      )
    ELSE false END as has_commission_received,
    -- No commission reason (only for S1)
    CASE 
      WHEN p_structure_type != 1 THEN NULL
      WHEN p.subscription_status NOT IN ('active', 'paid') THEN 'no_subscription'
      WHEN p.subscription_status = 'frozen' THEN 'frozen_status'
      WHEN NOT COALESCE(p.monthly_activation_completed, false) THEN 'no_activation'
      WHEN nwa.level > (
        SELECT COALESCE(
          (SELECT COUNT(*) FROM referrals r2 
           WHERE r2.referrer_id = root_user_id 
             AND r2.structure_type = 1
             AND EXISTS (
               SELECT 1 FROM profiles p3 
               WHERE p3.id = r2.referred_user_id 
                 AND p3.subscription_status IN ('active', 'paid')
             )
          ), 0
        )
      ) THEN 'level_locked'
      ELSE NULL
    END as no_commission_reason
  FROM network_with_ancestors nwa
  JOIN profiles p ON p.id = nwa.user_id
  WHERE p.deleted_at IS NULL
  ORDER BY nwa.level, p.created_at;
END;
$$;