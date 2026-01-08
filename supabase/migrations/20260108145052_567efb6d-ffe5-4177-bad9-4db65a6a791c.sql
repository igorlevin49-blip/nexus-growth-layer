
-- Fix 1: get_monthly_activation_report - replace is_activation_required with activation_due_from IS NOT NULL
CREATE OR REPLACE FUNCTION public.get_monthly_activation_report(
  p_year integer, 
  p_month integer, 
  p_status text DEFAULT 'all'::text, 
  p_search text DEFAULT NULL::text, 
  p_limit integer DEFAULT 50, 
  p_offset integer DEFAULT 0
)
RETURNS TABLE(
  user_id uuid, 
  full_name text, 
  email text, 
  referral_code text, 
  total_amount_kzt numeric, 
  threshold_kzt numeric, 
  is_activated boolean, 
  last_order_date timestamp with time zone, 
  orders_count bigint, 
  activation_due_from timestamp with time zone, 
  admin_comment text, 
  period_number integer, 
  period_start timestamp with time zone, 
  period_end timestamp with time zone
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  RETURN QUERY
  WITH user_periods AS (
    SELECT 
      p.id AS uid,
      p.full_name,
      p.email,
      p.referral_code,
      p.activation_due_from,
      gp.period_number,
      gp.period_start,
      gp.period_end,
      gp.is_grace_period
    FROM profiles p
    CROSS JOIN LATERAL get_user_activation_period(p.id, 
      make_timestamptz(p_year, p_month, 15, 12, 0, 0)
    ) gp
    WHERE p.is_active = true
      AND p.subscription_status = 'active'
      AND p.activation_due_from IS NOT NULL
  ),
  user_orders AS (
    SELECT 
      o.user_id AS uid,
      COALESCE(SUM(o.total_kzt), 0) AS total_amount,
      MAX(o.created_at) AS last_order,
      COUNT(o.id) AS order_count
    FROM orders o
    JOIN user_periods up ON up.uid = o.user_id
    WHERE o.status IN ('paid', 'completed', 'delivered')
      AND (
        up.is_grace_period = true 
        OR (o.created_at >= up.period_start AND o.created_at < up.period_end)
      )
    GROUP BY o.user_id
  ),
  activation_data AS (
    SELECT 
      ma.user_id AS uid,
      ma.admin_comment,
      ma.threshold_kzt AS ma_threshold
    FROM monthly_activations ma
    WHERE ma.year = p_year AND ma.month = p_month
  )
  SELECT 
    up.uid AS user_id,
    up.full_name,
    up.email,
    up.referral_code,
    COALESCE(uo.total_amount, 0) AS total_amount_kzt,
    COALESCE(ad.ma_threshold, (SELECT COALESCE(monthly_activation_required_kzt, 20000) FROM shop_settings WHERE id = 1)) AS threshold_kzt,
    CASE 
      WHEN up.is_grace_period THEN true
      ELSE COALESCE(uo.total_amount, 0) >= COALESCE(ad.ma_threshold, (SELECT COALESCE(monthly_activation_required_kzt, 20000) FROM shop_settings WHERE id = 1))
    END AS is_activated,
    uo.last_order AS last_order_date,
    COALESCE(uo.order_count, 0) AS orders_count,
    up.activation_due_from,
    ad.admin_comment,
    up.period_number,
    up.period_start,
    up.period_end
  FROM user_periods up
  LEFT JOIN user_orders uo ON uo.uid = up.uid
  LEFT JOIN activation_data ad ON ad.uid = up.uid
  WHERE (
    p_status = 'all'
    OR (p_status = 'activated' AND (up.is_grace_period OR COALESCE(uo.total_amount, 0) >= COALESCE(ad.ma_threshold, 20000)))
    OR (p_status = 'not_activated' AND NOT up.is_grace_period AND COALESCE(uo.total_amount, 0) < COALESCE(ad.ma_threshold, 20000))
  )
  AND (
    p_search IS NULL
    OR up.full_name ILIKE '%' || p_search || '%'
    OR up.email ILIKE '%' || p_search || '%'
    OR up.referral_code ILIKE '%' || p_search || '%'
  )
  ORDER BY up.full_name
  LIMIT p_limit
  OFFSET p_offset;
END;
$function$;

-- Fix 2: get_referral_network_from_table - add check for is_marketing_free_access
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
SET search_path TO 'public'
AS $function$
DECLARE
  current_year integer := EXTRACT(YEAR FROM CURRENT_DATE);
  current_month integer := EXTRACT(MONTH FROM CURRENT_DATE);
  root_has_subscription boolean;
  root_has_activation boolean;
BEGIN
  SELECT
    p.subscription_status = 'active',
    COALESCE(ma.is_activated, p.monthly_activation_completed, false)
  INTO root_has_subscription, root_has_activation
  FROM profiles p
  LEFT JOIN monthly_activations ma ON ma.user_id = p.id
    AND ma.year = current_year
    AND ma.month = current_month
  WHERE p.id = root_user_id;

  RETURN QUERY
  WITH RECURSIVE network AS (
    SELECT
      r.referred_user_id,
      r.referrer_id as parent_id,
      1 as lvl,
      r.structure_type
    FROM referrals r
    WHERE r.referrer_id = root_user_id
      AND r.structure_type = p_structure_type

    UNION ALL

    SELECT
      r.referred_user_id,
      r.referrer_id as parent_id,
      n.lvl + 1,
      r.structure_type
    FROM referrals r
    INNER JOIN network n ON r.referrer_id = n.referred_user_id
    WHERE n.lvl < max_level
      AND r.structure_type = p_structure_type
  ),
  commission_check AS (
    SELECT
      t.id,
      COALESCE(t.payload->>'source_user_id', t.payload->>'from_user_id') as source_user_id,
      t.payload->>'level' as commission_level,
      t.status as transaction_status,
      t.frozen_until,
      t.created_at as commission_created_at
    FROM transactions t
    WHERE t.user_id = root_user_id
      AND t.type = 'commission'
      AND EXTRACT(YEAR FROM t.created_at) = current_year
      AND EXTRACT(MONTH FROM t.created_at) = current_month
  ),
  network_with_profiles AS (
    SELECT
      n.referred_user_id,
      n.parent_id,
      n.lvl,
      p.id::text as partner_id,
      p.full_name,
      p.email,
      p.phone,
      p.avatar_url,
      p.subscription_status,
      p.subscription_expires_at,
      COALESCE(ma.is_activated, p.monthly_activation_completed, false) as activation_met,
      p.referral_code,
      p.created_at,
      parent_p.id::text as parent_partner_id,
      cc.id IS NOT NULL as has_commission,
      cc.transaction_status,
      cc.frozen_until,
      s.is_marketing_free_access as is_marketing_free,
      CASE
        WHEN s.is_marketing_free_access = true THEN 'marketing_free_access'
        WHEN NOT root_has_subscription THEN 'sponsor_inactive'
        WHEN NOT root_has_activation THEN 'sponsor_no_activation'
        WHEN p.subscription_status != 'active' THEN 'no_active_subscription'
        WHEN NOT COALESCE(ma.is_activated, p.monthly_activation_completed, false) THEN 'no_payment_this_month'
        WHEN p_structure_type = 1 AND n.lvl > 1 THEN
          CASE
            WHEN n.lvl = 2 AND (SELECT COUNT(*) FROM referrals WHERE referrer_id = root_user_id AND structure_type = 1) < 2 THEN 'level_locked'
            WHEN n.lvl = 3 AND (SELECT COUNT(*) FROM referrals WHERE referrer_id = root_user_id AND structure_type = 1) < 3 THEN 'level_locked'
            WHEN n.lvl = 4 AND (SELECT COUNT(*) FROM referrals WHERE referrer_id = root_user_id AND structure_type = 1) < 4 THEN 'level_locked'
            WHEN n.lvl = 5 AND (SELECT COUNT(*) FROM referrals WHERE referrer_id = root_user_id AND structure_type = 1) < 5 THEN 'level_locked'
            WHEN n.lvl = 6 AND (SELECT COUNT(*) FROM referrals WHERE referrer_id = root_user_id AND structure_type = 1) < 6 THEN 'level_locked'
            WHEN n.lvl = 7 AND (SELECT COUNT(*) FROM referrals WHERE referrer_id = root_user_id AND structure_type = 1) < 7 THEN 'level_locked'
            WHEN n.lvl = 8 AND (SELECT COUNT(*) FROM referrals WHERE referrer_id = root_user_id AND structure_type = 1) < 8 THEN 'level_locked'
            WHEN n.lvl = 9 AND (SELECT COUNT(*) FROM referrals WHERE referrer_id = root_user_id AND structure_type = 1) < 9 THEN 'level_locked'
            WHEN n.lvl = 10 AND (SELECT COUNT(*) FROM referrals WHERE referrer_id = root_user_id AND structure_type = 1) < 10 THEN 'level_locked'
            ELSE NULL
          END
        ELSE NULL
      END as reason
    FROM network n
    INNER JOIN profiles p ON p.id = n.referred_user_id
    LEFT JOIN profiles parent_p ON parent_p.id = n.parent_id
    LEFT JOIN monthly_activations ma ON ma.user_id = n.referred_user_id
      AND ma.year = current_year
      AND ma.month = current_month
    LEFT JOIN commission_check cc ON cc.source_user_id = n.referred_user_id::text
    LEFT JOIN subscriptions s ON s.user_id = n.referred_user_id 
      AND s.status = 'active'
  ),
  member_stats AS (
    SELECT
      nwp.referred_user_id,
      (SELECT COUNT(*) FROM referrals r WHERE r.referrer_id = nwp.referred_user_id AND r.structure_type = p_structure_type) as direct_count,
      (SELECT COUNT(*) FROM referrals r WHERE r.referrer_id = nwp.referred_user_id) as team_count,
      COALESCE((
        SELECT SUM(o.total_kzt)::numeric
        FROM orders o
        WHERE o.user_id = nwp.referred_user_id
          AND o.status::text IN ('paid','completed','delivered')
          AND EXTRACT(YEAR FROM o.created_at) = current_year
          AND EXTRACT(MONTH FROM o.created_at) = current_month
      ), 0) as volume
    FROM network_with_profiles nwp
  )
  SELECT
    nwp.referred_user_id as user_id,
    nwp.partner_id,
    nwp.lvl as level,
    nwp.full_name,
    nwp.email,
    nwp.phone,
    nwp.avatar_url,
    nwp.subscription_status,
    nwp.subscription_expires_at,
    nwp.activation_met as monthly_activation_met,
    nwp.referral_code,
    nwp.created_at,
    COALESCE(ms.direct_count, 0) as direct_referrals,
    COALESCE(ms.team_count, 0) as total_team,
    COALESCE(ms.volume, 0) as monthly_volume,
    nwp.parent_partner_id,
    nwp.parent_id as parent_user_id,
    nwp.has_commission as has_commission_received,
    nwp.reason as no_commission_reason,
    CASE
      WHEN nwp.has_commission AND nwp.transaction_status = 'frozen' THEN 'frozen'
      WHEN nwp.has_commission AND nwp.transaction_status = 'completed' THEN 'received'
      WHEN nwp.reason IS NOT NULL THEN 'not_received'
      ELSE 'pending'
    END as commission_status,
    nwp.frozen_until as commission_frozen_until
  FROM network_with_profiles nwp
  LEFT JOIN member_stats ms ON ms.referred_user_id = nwp.referred_user_id
  ORDER BY nwp.lvl, nwp.created_at;
END;
$function$;
