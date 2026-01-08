
-- Fix get_referral_network_from_table to properly calculate has_commission_received
DROP FUNCTION IF EXISTS public.get_referral_network_from_table(uuid, integer, integer);

CREATE OR REPLACE FUNCTION public.get_referral_network_from_table(
  root_user_id uuid, 
  max_level integer DEFAULT 10, 
  p_structure_type integer DEFAULT 1
)
RETURNS TABLE(
  user_id uuid, 
  partner_id text, 
  level integer, 
  full_name text, 
  email text, 
  phone text, 
  avatar_url text, 
  subscription_status text, 
  subscription_expires_at timestamp with time zone, 
  monthly_activation_met boolean, 
  referral_code text, 
  created_at timestamp with time zone, 
  direct_referrals bigint, 
  total_team bigint, 
  monthly_volume numeric, 
  parent_partner_id text, 
  parent_user_id uuid, 
  has_commission_received boolean, 
  no_commission_reason text, 
  commission_status text, 
  commission_frozen_until timestamp with time zone
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
BEGIN
  -- Access control: allow self, admin, or superadmin
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  IF auth.uid() <> root_user_id
     AND NOT public.has_role(auth.uid(), 'admin'::app_role)
     AND NOT public.has_role(auth.uid(), 'superadmin'::app_role) THEN
    RAISE EXCEPTION 'Forbidden';
  END IF;

  RETURN QUERY
  WITH RECURSIVE network AS (
    -- Level 1: direct referrals
    SELECT
      r.referred_user_id AS net_user_id,
      r.referrer_id AS parent_id,
      1 AS lvl
    FROM public.referrals r
    WHERE r.referrer_id = root_user_id
      AND r.structure_type = p_structure_type

    UNION ALL

    -- Next levels
    SELECT
      r.referred_user_id AS net_user_id,
      r.referrer_id AS parent_id,
      n.lvl + 1 AS lvl
    FROM public.referrals r
    JOIN network n ON r.referrer_id = n.net_user_id
    WHERE n.lvl < max_level
      AND r.structure_type = p_structure_type
  ),
  direct_counts AS (
    SELECT r.referrer_id, COUNT(*)::bigint AS cnt
    FROM public.referrals r
    WHERE r.structure_type = p_structure_type
    GROUP BY r.referrer_id
  ),
  monthly_status AS (
    SELECT ma.user_id, ma.is_activated
    FROM public.monthly_activations ma
    WHERE ma.year = EXTRACT(YEAR FROM now())::int
      AND ma.month = EXTRACT(MONTH FROM now())::int
  ),
  marketing_free AS (
    SELECT DISTINCT s.user_id
    FROM public.subscriptions s
    WHERE s.is_marketing_free_access = true
      AND s.status = 'active'
  ),
  -- Get subscription info to check for commissions
  partner_subscriptions AS (
    SELECT s.user_id, s.id as subscription_id
    FROM public.subscriptions s
    WHERE s.status = 'active'
  ),
  -- Check if root_user received commission for each partner's subscription
  received_commissions AS (
    SELECT 
      t.source_id as subscription_id,
      t.status as tx_status,
      t.frozen_until
    FROM public.transactions t
    WHERE t.user_id = root_user_id
      AND t.type = 'commission'
      AND t.structure_type = (CASE WHEN p_structure_type = 1 THEN 'primary' ELSE 'secondary' END)::structure_type
  )
  SELECT
    n.net_user_id,
    p.referral_code AS partner_id,
    n.lvl AS level,
    COALESCE(p.full_name, '') AS full_name,
    p.email,
    p.phone,
    p.avatar_url,
    p.subscription_status,
    p.subscription_expires_at,
    COALESCE(ms.is_activated, p.monthly_activation_completed, false) AS monthly_activation_met,
    p.referral_code,
    COALESCE(p.created_at, now()) AS created_at,
    COALESCE(dc.cnt, 0) AS direct_referrals,
    0::bigint AS total_team,
    0::numeric AS monthly_volume,
    parent_p.referral_code AS parent_partner_id,
    n.parent_id AS parent_user_id,
    -- Check if commission was received for this partner
    (rc.subscription_id IS NOT NULL) AS has_commission_received,
    -- Determine reason if no commission
    CASE
      WHEN rc.subscription_id IS NOT NULL THEN NULL  -- Commission received, no reason needed
      WHEN mf.user_id IS NOT NULL THEN 'marketing_free_access'
      WHEN p.subscription_status IS NULL OR p.subscription_status NOT IN ('active','trialing') THEN 'not_activated'
      WHEN n.lvl > 5 THEN 'too_deep'
      -- Check unlock requirements
      WHEN n.lvl = 2 AND (
        SELECT COALESCE(rp.direct_referrals_count, 0) FROM profiles rp WHERE rp.id = root_user_id
      ) < 2 THEN 'level_2_locked'
      WHEN n.lvl = 3 AND (
        SELECT COALESCE(rp.direct_referrals_count, 0) FROM profiles rp WHERE rp.id = root_user_id
      ) < 3 THEN 'level_3_locked'
      WHEN n.lvl = 4 AND (
        SELECT COALESCE(rp.direct_referrals_count, 0) FROM profiles rp WHERE rp.id = root_user_id
      ) < 4 THEN 'level_4_locked'
      WHEN n.lvl = 5 AND (
        SELECT COALESCE(rp.direct_referrals_count, 0) FROM profiles rp WHERE rp.id = root_user_id
      ) < 5 THEN 'level_5_locked'
      WHEN COALESCE(ms.is_activated, p.monthly_activation_completed, false) = false THEN 'no_payment_this_month'
      WHEN ps.subscription_id IS NOT NULL AND rc.subscription_id IS NULL THEN 'commission_missing'
      ELSE NULL
    END AS no_commission_reason,
    rc.tx_status::text AS commission_status,
    rc.frozen_until AS commission_frozen_until
  FROM network n
  JOIN public.profiles p ON p.id = n.net_user_id
  LEFT JOIN public.profiles parent_p ON parent_p.id = n.parent_id
  LEFT JOIN direct_counts dc ON dc.referrer_id = n.net_user_id
  LEFT JOIN monthly_status ms ON ms.user_id = n.net_user_id
  LEFT JOIN marketing_free mf ON mf.user_id = n.net_user_id
  LEFT JOIN partner_subscriptions ps ON ps.user_id = n.net_user_id
  LEFT JOIN received_commissions rc ON rc.subscription_id = ps.subscription_id
  ORDER BY n.lvl, p.created_at;
END;
$function$;

-- Also keep the 2-parameter version for backward compatibility
DROP FUNCTION IF EXISTS public.get_referral_network_from_table(uuid, integer);

CREATE OR REPLACE FUNCTION public.get_referral_network_from_table(root_user_id uuid, max_level integer DEFAULT 10)
RETURNS TABLE(
  user_id uuid, 
  partner_id text, 
  level integer, 
  full_name text, 
  email text, 
  phone text, 
  avatar_url text, 
  subscription_status text, 
  subscription_expires_at timestamp with time zone, 
  monthly_activation_met boolean, 
  referral_code text, 
  created_at timestamp with time zone, 
  direct_referrals bigint, 
  total_team bigint, 
  monthly_volume numeric, 
  parent_partner_id text, 
  parent_user_id uuid, 
  has_commission_received boolean, 
  no_commission_reason text, 
  commission_status text, 
  commission_frozen_until timestamp with time zone
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $function$
  SELECT * FROM public.get_referral_network_from_table(root_user_id, max_level, 1);
$function$;
