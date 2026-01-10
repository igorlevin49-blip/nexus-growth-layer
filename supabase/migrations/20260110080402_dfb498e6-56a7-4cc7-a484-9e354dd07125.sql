-- Fix get_referral_network_from_table to correctly find commissions using all payload key variants
-- Problem: Function only checks payload->>'source_user_id' but transactions use different keys:
-- - S1 subscriptions (trigger): from_user_id
-- - S1 subscriptions (backfill): subscriber_id  
-- - S2 orders: buyer_id

-- First drop the existing function
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
  v_structure_type_text text;
BEGIN
  -- Convert structure type to text for comparison
  v_structure_type_text := CASE WHEN p_structure_type = 1 THEN 'primary' ELSE 'secondary' END;

  RETURN QUERY
  WITH RECURSIVE network AS (
    -- Base case: direct referrals of root user
    SELECT 
      r.referred_id as uid,
      r.referrer_id as parent_uid,
      1 as lvl
    FROM referrals r
    WHERE r.referrer_id = root_user_id
      AND r.structure_type = p_structure_type
    
    UNION ALL
    
    -- Recursive case: referrals of referrals
    SELECT 
      r.referred_id,
      r.referrer_id,
      n.lvl + 1
    FROM referrals r
    INNER JOIN network n ON r.referrer_id = n.uid
    WHERE n.lvl < max_level
      AND r.structure_type = p_structure_type
  ),
  -- Get commission data for each network member
  -- Check ALL possible payload keys: from_user_id, subscriber_id, buyer_id, source_user_id
  commission_data AS (
    SELECT DISTINCT ON (n.uid)
      n.uid,
      n.lvl,
      CASE 
        WHEN t.id IS NOT NULL THEN true 
        ELSE false 
      END as has_commission,
      t.status as comm_status,
      t.frozen_until as comm_frozen_until,
      CASE
        WHEN t.id IS NULL THEN 
          CASE 
            WHEN p.subscription_status != 'active' THEN 'no_subscription'
            WHEN NOT COALESCE(p.monthly_activation_completed, false) 
                 AND COALESCE(p.activation_due_from, '1970-01-01'::timestamptz) <= NOW() THEN 'not_activated'
            ELSE NULL
          END
        ELSE NULL
      END as no_comm_reason
    FROM network n
    JOIN profiles p ON p.id = n.uid
    LEFT JOIN transactions t ON 
      t.user_id = root_user_id  -- Commission belongs to the viewer (root user)
      AND t.type = 'commission'
      AND t.level = n.lvl  -- Match the level in the tree
      AND (
        -- Check all possible payload keys for source user identification
        t.payload->>'from_user_id' = n.uid::text OR
        t.payload->>'subscriber_id' = n.uid::text OR
        t.payload->>'buyer_id' = n.uid::text OR
        t.payload->>'source_user_id' = n.uid::text
      )
      AND (
        (p_structure_type = 1 AND t.structure_type = 'primary') OR
        (p_structure_type = 2 AND t.structure_type = 'secondary')
      )
    ORDER BY n.uid, t.created_at DESC  -- Get most recent commission if multiple exist
  )
  SELECT 
    p.id as user_id,
    p.partner_id,
    n.lvl as level,
    p.full_name,
    p.email,
    p.phone,
    p.avatar_url,
    p.subscription_status,
    p.subscription_expires_at,
    p.monthly_activation_completed as monthly_activation_met,
    p.referral_code,
    p.created_at,
    (SELECT COUNT(*) FROM referrals ref WHERE ref.referrer_id = p.id AND ref.structure_type = p_structure_type)::bigint as direct_referrals,
    (
      WITH RECURSIVE team AS (
        SELECT ref.referred_id FROM referrals ref WHERE ref.referrer_id = p.id AND ref.structure_type = p_structure_type
        UNION ALL
        SELECT ref.referred_id FROM referrals ref INNER JOIN team t ON ref.referrer_id = t.referred_id WHERE ref.structure_type = p_structure_type
      )
      SELECT COUNT(*) FROM team
    )::bigint as total_team,
    COALESCE((
      SELECT SUM(oi.price_cents * oi.quantity) 
      FROM orders o 
      JOIN order_items oi ON oi.order_id = o.id 
      WHERE o.user_id = p.id 
        AND o.status = 'completed'
        AND o.created_at >= date_trunc('month', NOW())
    ), 0)::numeric as monthly_volume,
    parent_p.partner_id as parent_partner_id,
    n.parent_uid as parent_user_id,
    cd.has_commission as has_commission_received,
    cd.no_comm_reason as no_commission_reason,
    cd.comm_status as commission_status,
    cd.comm_frozen_until as commission_frozen_until
  FROM network n
  JOIN profiles p ON p.id = n.uid
  LEFT JOIN profiles parent_p ON parent_p.id = n.parent_uid
  LEFT JOIN commission_data cd ON cd.uid = n.uid
  ORDER BY n.lvl, p.created_at;
END;
$$;