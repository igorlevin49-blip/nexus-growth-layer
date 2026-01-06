DROP FUNCTION IF EXISTS public.get_referral_network_from_table(uuid, integer);

CREATE OR REPLACE FUNCTION public.get_referral_network_from_table(root_user_id uuid, max_depth integer DEFAULT 10)
RETURNS TABLE(
  user_id uuid,
  full_name text,
  partner_id text,
  parent_user_id uuid,
  parent_partner_id text,
  depth integer,
  subscription_status text,
  is_active_this_month boolean,
  personal_volume numeric,
  has_commission boolean,
  no_commission_reason text,
  registered_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  WITH RECURSIVE network AS (
    SELECT 
      r.referred_user_id as user_id,
      root_user_id as parent_user_id,
      1 as depth
    FROM referrals r
    WHERE r.referrer_id = root_user_id
    
    UNION ALL
    
    SELECT 
      r.referred_user_id as user_id,
      n.user_id as parent_user_id,
      n.depth + 1 as depth
    FROM referrals r
    INNER JOIN network n ON r.referrer_id = n.user_id
    WHERE n.depth < max_depth
  ),
  monthly_acts AS (
    SELECT 
      ma.user_id,
      ma.is_activated
    FROM monthly_activations ma
    WHERE ma.month = date_trunc('month', CURRENT_DATE)::date
  ),
  monthly_volumes AS (
    SELECT 
      o.user_id,
      COALESCE(SUM(o.total_usd), 0) as volume
    FROM orders o
    WHERE o.status = 'paid'
      AND o.created_at >= date_trunc('month', CURRENT_DATE)
    GROUP BY o.user_id
  ),
  commission_info AS (
    SELECT DISTINCT 
      (t.payload->>'from_user_id')::uuid as from_user_id,
      TRUE as has_commission
    FROM transactions t
    WHERE t.user_id = root_user_id
      AND t.type = 'commission'
      AND t.created_at >= date_trunc('month', CURRENT_DATE)
  ),
  marketing_free AS (
    SELECT p.id as user_id
    FROM profiles p
    WHERE p.is_marketing_free_access = TRUE
  )
  SELECT 
    n.user_id,
    p.full_name,
    p.referral_code as partner_id,
    n.parent_user_id,
    pp.referral_code as parent_partner_id,
    n.depth,
    p.subscription_status,
    COALESCE(ma.is_activated, FALSE) as is_active_this_month,
    COALESCE(mv.volume, 0) as personal_volume,
    COALESCE(ci.has_commission, FALSE) as has_commission,
    CASE
      WHEN n.depth = 2 AND (SELECT COUNT(*) FROM referrals WHERE referrer_id = root_user_id) < 2 THEN 'level_2_locked'
      WHEN n.depth = 3 AND (SELECT COUNT(*) FROM referrals WHERE referrer_id = root_user_id) < 3 THEN 'level_3_locked'
      WHEN n.depth = 4 AND (SELECT COUNT(*) FROM referrals WHERE referrer_id = root_user_id) < 4 THEN 'level_4_locked'
      WHEN n.depth = 5 AND (SELECT COUNT(*) FROM referrals WHERE referrer_id = root_user_id) < 5 THEN 'level_5_locked'
      WHEN n.depth = 6 AND (SELECT COUNT(*) FROM referrals WHERE referrer_id = root_user_id) < 6 THEN 'level_6_locked'
      WHEN n.depth = 7 AND (SELECT COUNT(*) FROM referrals WHERE referrer_id = root_user_id) < 7 THEN 'level_7_locked'
      WHEN n.depth = 8 AND (SELECT COUNT(*) FROM referrals WHERE referrer_id = root_user_id) < 8 THEN 'level_8_locked'
      WHEN n.depth = 9 AND (SELECT COUNT(*) FROM referrals WHERE referrer_id = root_user_id) < 9 THEN 'level_9_locked'
      WHEN n.depth = 10 AND (SELECT COUNT(*) FROM referrals WHERE referrer_id = root_user_id) < 10 THEN 'level_10_locked'
      WHEN p.subscription_status != 'active' THEN 'no_active_subscription'
      WHEN mfa.user_id IS NOT NULL THEN 'marketing_free_access'
      WHEN p.created_at >= date_trunc('month', CURRENT_DATE) THEN 'new_partner'
      WHEN NOT COALESCE(ma.is_activated, FALSE) THEN 'no_payment_this_month'
      WHEN COALESCE(ci.has_commission, FALSE) THEN NULL
      ELSE NULL
    END as no_commission_reason,
    p.created_at as registered_at
  FROM network n
  JOIN profiles p ON p.id = n.user_id
  LEFT JOIN profiles pp ON pp.id = n.parent_user_id
  LEFT JOIN monthly_acts ma ON ma.user_id = n.user_id
  LEFT JOIN monthly_volumes mv ON mv.user_id = n.user_id
  LEFT JOIN commission_info ci ON ci.from_user_id = n.user_id
  LEFT JOIN marketing_free mfa ON mfa.user_id = n.user_id
  ORDER BY n.depth, p.full_name;
END;
$$;