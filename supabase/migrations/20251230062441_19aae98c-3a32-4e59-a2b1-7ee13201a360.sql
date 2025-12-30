-- Drop old versions and recreate with correct column name
DROP FUNCTION IF EXISTS public.get_referral_network_from_table(uuid, integer);

CREATE OR REPLACE FUNCTION public.get_referral_network_from_table(
  root_user_id uuid,
  max_level integer DEFAULT 10
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
  root_direct_count integer;
  root_is_active boolean;
BEGIN
  -- Get root user's direct referral count for level unlock check
  SELECT COUNT(*)::integer INTO root_direct_count
  FROM referrals r
  WHERE r.referrer_id = root_user_id;
  
  -- Check if root user is active
  SELECT EXISTS (
    SELECT 1 FROM subscriptions s
    WHERE s.user_id = root_user_id
      AND s.status = 'active'
  ) INTO root_is_active;

  RETURN QUERY
  WITH RECURSIVE network AS (
    -- Base case: direct referrals of root user (level 1)
    SELECT 
      r.referred_user_id as user_id,
      1 as level,
      r.referrer_id as parent_user_id
    FROM referrals r
    WHERE r.referrer_id = root_user_id
    
    UNION ALL
    
    -- Recursive case: referrals of referrals
    SELECT 
      r.referred_user_id as user_id,
      n.level + 1 as level,
      r.referrer_id as parent_user_id
    FROM referrals r
    INNER JOIN network n ON r.referrer_id = n.user_id
    WHERE n.level < max_level
  ),
  network_with_profiles AS (
    SELECT 
      n.user_id,
      n.level,
      n.parent_user_id,
      p.partner_id,
      p.full_name,
      p.email,
      p.phone,
      p.referral_code,
      p.avatar_url,
      p.created_at,
      parent_p.partner_id as parent_partner_id
    FROM network n
    JOIN profiles p ON p.id = n.user_id
    LEFT JOIN profiles parent_p ON parent_p.id = n.parent_user_id
  ),
  network_with_subscriptions AS (
    SELECT 
      nwp.*,
      COALESCE(s.status, 'inactive') as subscription_status,
      s.expires_at as subscription_expires_at,
      COALESCE(s.is_marketing_free_access, false) as is_marketing_free_access,
      s.id as subscription_id
    FROM network_with_profiles nwp
    LEFT JOIN LATERAL (
      SELECT s2.status, s2.expires_at, s2.is_marketing_free_access, s2.id
      FROM subscriptions s2
      WHERE s2.user_id = nwp.user_id
      ORDER BY s2.created_at DESC
      LIMIT 1
    ) s ON true
  ),
  network_with_activation AS (
    SELECT 
      nws.*,
      COALESCE(
        EXISTS (
          SELECT 1 FROM monthly_activations ma
          WHERE ma.user_id = nws.user_id
            AND ma.year = EXTRACT(YEAR FROM CURRENT_DATE)::integer
            AND ma.month = EXTRACT(MONTH FROM CURRENT_DATE)::integer
            AND ma.is_activated = true
        ),
        false
      ) as monthly_activation_met
    FROM network_with_subscriptions nws
  )
  SELECT 
    nwa.user_id,
    nwa.partner_id,
    nwa.parent_user_id,
    nwa.parent_partner_id,
    nwa.level,
    nwa.full_name,
    nwa.email,
    nwa.phone,
    nwa.referral_code,
    nwa.subscription_status,
    nwa.subscription_expires_at,
    nwa.monthly_activation_met,
    nwa.created_at,
    nwa.avatar_url,
    -- Direct referrals count
    (SELECT COUNT(*) FROM referrals r WHERE r.referrer_id = nwa.user_id)::bigint as direct_referrals,
    -- Total team count (recursive)
    (
      WITH RECURSIVE team AS (
        SELECT r.referred_user_id FROM referrals r WHERE r.referrer_id = nwa.user_id
        UNION ALL
        SELECT r.referred_user_id FROM referrals r INNER JOIN team t ON r.referrer_id = t.referred_user_id
      )
      SELECT COUNT(*) FROM team
    )::bigint as total_team,
    -- Monthly volume placeholder
    0::numeric as monthly_volume,
    -- Check actual commission transaction exists for this partner
    EXISTS (
      SELECT 1 FROM transactions t
      WHERE t.user_id = root_user_id
        AND t.type = 'commission'
        AND t.source_id = nwa.subscription_id
    ) as has_commission_received,
    -- Determine reason for no commission with marketing_free_access check
    CASE
      -- Not activated (no active subscription)
      WHEN nwa.subscription_status != 'active' THEN 'not_activated'
      -- Marketing free access - no commission for these
      WHEN nwa.is_marketing_free_access = true THEN 'marketing_free_access'
      -- Too deep (beyond level 5)
      WHEN nwa.level > 5 THEN 'too_deep'
      -- Level not unlocked (need more direct referrals)
      WHEN nwa.level = 2 AND root_direct_count < 3 THEN 'level_not_unlocked'
      WHEN nwa.level = 3 AND root_direct_count < 6 THEN 'level_not_unlocked'
      WHEN nwa.level = 4 AND root_direct_count < 9 THEN 'level_not_unlocked'
      WHEN nwa.level = 5 AND root_direct_count < 12 THEN 'level_not_unlocked'
      -- Sponsor (root user) is not active
      WHEN NOT root_is_active THEN 'sponsor_inactive'
      -- No monthly activation this month
      WHEN NOT nwa.monthly_activation_met THEN 'no_payment_this_month'
      -- All good, should have commission
      ELSE NULL
    END as no_commission_reason
  FROM network_with_activation nwa
  ORDER BY nwa.level, nwa.created_at;
END;
$$;