CREATE OR REPLACE FUNCTION public.get_referral_network_from_table(
  root_user_id uuid,
  max_level integer DEFAULT 10,
  p_structure_type integer DEFAULT 1
)
RETURNS TABLE(
  user_id uuid,
  partner_id uuid,
  parent_partner_id uuid,
  level integer,
  full_name text,
  email text,
  referral_code text,
  subscription_status text,
  monthly_activation_met boolean,
  created_at timestamp with time zone,
  avatar_url text,
  direct_referrals integer,
  total_team integer,
  monthly_volume bigint,
  has_commission_received boolean,
  no_commission_reason text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_unlock_levels JSONB;
BEGIN
  -- Get unlock levels settings
  SELECT value INTO v_unlock_levels
  FROM mlm_settings
  WHERE key = 'unlock_levels';

  IF v_unlock_levels IS NULL THEN
    v_unlock_levels := '{"l2": 3, "l3": 5, "l4": 8, "l5": 10}'::jsonb;
  END IF;

  RETURN QUERY
  WITH RECURSIVE network AS (
    -- Base case: direct referrals of root user
    SELECT
      r.referred_user_id as user_id,
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
    INNER JOIN network n ON r.referrer_id = n.user_id
    WHERE n.lvl < max_level
      AND r.structure_type = p_structure_type
  ),
  -- Get team sizes for each user (counting only active partners)
  team_sizes AS (
    SELECT
      n.user_id,
      (
        SELECT COUNT(*)
        FROM profiles p2
        WHERE p2.sponsor_id = n.user_id
          AND p2.deleted_at IS NULL
          AND p2.subscription_status = 'active'
      )::INT as direct,
      (
        WITH RECURSIVE subtree AS (
          SELECT r2.referred_user_id as uid
          FROM referrals r2
          WHERE r2.referrer_id = n.user_id AND r2.structure_type = p_structure_type

          UNION ALL

          SELECT r3.referred_user_id
          FROM referrals r3
          INNER JOIN subtree s ON r3.referrer_id = s.uid
          WHERE r3.structure_type = p_structure_type
        )
        SELECT COUNT(*)::INT FROM subtree
      ) as total
    FROM network n
  ),
  -- Get monthly volumes
  monthly_volumes AS (
    SELECT
      n.user_id,
      COALESCE(SUM(
        CASE WHEN o.status = 'paid'
             AND o.paid_at >= date_trunc('month', CURRENT_DATE)
        THEN o.total_kzt ELSE 0 END
      ), 0)::BIGINT as volume
    FROM network n
    LEFT JOIN orders o ON o.user_id = n.user_id
    GROUP BY n.user_id
  ),
  -- Get root user's active direct referrals count for level unlock check
  root_active_referrals AS (
    SELECT COUNT(*)::INT as cnt
    FROM referrals r
    JOIN profiles p ON r.referred_user_id = p.id
    WHERE r.referrer_id = root_user_id
      AND r.structure_type = 1
      AND p.subscription_status = 'active'
      AND p.deleted_at IS NULL
  ),
  -- Check commission status for current month subscriptions
  commission_status AS (
    SELECT
      n.user_id,
      n.lvl,
      -- Check if commission was received for this partner's current subscription
      CASE
        WHEN EXISTS (
          SELECT 1 FROM transactions t
          WHERE t.source_id IN (
            SELECT s.id FROM subscriptions s
            WHERE s.user_id = n.user_id
              AND s.status = 'active'
              AND s.paid_at >= date_trunc('month', CURRENT_DATE)
          )
          AND t.user_id = root_user_id
          AND t.type = 'commission'
          AND t.structure_type = 'primary'
        ) THEN true
        ELSE false
      END as has_commission,
      -- Determine reason for no commission
      CASE
        -- Only for structure type 1 (S1)
        WHEN p_structure_type != 1 THEN NULL

        -- Partner has no active subscription
        WHEN (
          SELECT p_status.subscription_status
          FROM profiles p_status
          WHERE p_status.id = n.user_id
        ) != 'active' THEN 'not_activated'

        -- Partner hasn't paid this month
        WHEN NOT EXISTS (
          SELECT 1 FROM subscriptions s
          WHERE s.user_id = n.user_id
            AND s.status = 'active'
            AND s.paid_at >= date_trunc('month', CURRENT_DATE)
        ) THEN 'no_payment_this_month'

        -- Check if partner has marketing free access
        WHEN EXISTS (
          SELECT 1 FROM subscriptions s
          WHERE s.user_id = n.user_id
            AND s.status = 'active'
            AND s.is_marketing_free_access = true
        ) THEN 'marketing_free_access'

        -- Partner is too deep (beyond level 5 for S1)
        WHEN n.lvl > 5 THEN 'too_deep'

        -- Level not unlocked - not enough active direct referrals
        WHEN n.lvl = 2 AND (SELECT cnt FROM root_active_referrals) < COALESCE((v_unlock_levels->>'l2')::int, 3) THEN 'level_not_unlocked'
        WHEN n.lvl = 3 AND (SELECT cnt FROM root_active_referrals) < COALESCE((v_unlock_levels->>'l3')::int, 5) THEN 'level_not_unlocked'
        WHEN n.lvl = 4 AND (SELECT cnt FROM root_active_referrals) < COALESCE((v_unlock_levels->>'l4')::int, 8) THEN 'level_not_unlocked'
        WHEN n.lvl = 5 AND (SELECT cnt FROM root_active_referrals) < COALESCE((v_unlock_levels->>'l5')::int, 10) THEN 'level_not_unlocked'

        -- Root user (sponsor) was inactive at the time of activation
        WHEN NOT EXISTS (
          SELECT 1 FROM transactions t
          WHERE t.source_id IN (
            SELECT s.id FROM subscriptions s
            WHERE s.user_id = n.user_id
              AND s.status = 'active'
          )
          AND t.user_id = root_user_id
          AND t.type = 'commission'
          AND t.structure_type = 'primary'
        ) AND (
          -- Check if root user was inactive when partner activated
          SELECT COALESCE(
            NOT COALESCE(p_root.monthly_activation_completed, false),
            p_root.subscription_status != 'active'
          )
          FROM profiles p_root
          WHERE p_root.id = root_user_id
        ) = false THEN 'sponsor_inactive'

        -- Commission was received in previous month (reactivation)
        WHEN EXISTS (
          SELECT 1 FROM transactions t
          WHERE t.payload->>'from_user_id' = n.user_id::text
            AND t.user_id = root_user_id
            AND t.type = 'commission'
            AND t.structure_type = 'primary'
            AND t.created_at < date_trunc('month', CURRENT_DATE)
        ) AND NOT EXISTS (
          SELECT 1 FROM transactions t
          WHERE t.source_id IN (
            SELECT s.id FROM subscriptions s
            WHERE s.user_id = n.user_id
              AND s.status = 'active'
              AND s.paid_at >= date_trunc('month', CURRENT_DATE)
          )
          AND t.user_id = root_user_id
          AND t.type = 'commission'
          AND t.structure_type = 'primary'
        ) THEN 'already_received_before'

        ELSE NULL
      END as no_commission_reason
    FROM network n
  )
  SELECT
    n.user_id,
    n.user_id as partner_id,
    n.parent_id as parent_partner_id,
    n.lvl as level,
    p.full_name,
    p.email,
    p.referral_code,
    p.subscription_status,
    COALESCE(p.monthly_activation_completed, false) as monthly_activation_met,
    p.created_at,
    p.avatar_url,
    COALESCE(ts.direct, 0) as direct_referrals,
    COALESCE(ts.total, 0) as total_team,
    COALESCE(mv.volume, 0) as monthly_volume,
    COALESCE(cs.has_commission, false) as has_commission_received,
    cs.no_commission_reason
  FROM network n
  JOIN profiles p ON p.id = n.user_id
  LEFT JOIN team_sizes ts ON ts.user_id = n.user_id
  LEFT JOIN monthly_volumes mv ON mv.user_id = n.user_id
  LEFT JOIN commission_status cs ON cs.user_id = n.user_id
  WHERE p.deleted_at IS NULL
  ORDER BY n.lvl, p.created_at;
END;
$function$;