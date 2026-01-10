-- Fix: transactions table has no released_at column; remove reference to avoid RPC failures.

CREATE OR REPLACE FUNCTION public.get_referral_network_from_table(
  root_user_id uuid,
  p_max_levels integer DEFAULT 5,
  p_structure_type integer DEFAULT 1
)
RETURNS TABLE (
  id uuid,
  full_name text,
  avatar_url text,
  level integer,
  parent_id uuid,
  subscription_status text,
  subscription_expires_at timestamptz,
  personal_activation_volume numeric,
  has_commission_received boolean,
  no_commission_reason text,
  commission_frozen_until timestamptz,
  is_activated boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  WITH RECURSIVE network AS (
    SELECT 
      r.referred_user_id as uid,
      1 as lvl,
      root_user_id as parent
    FROM referrals r
    WHERE r.referrer_id = root_user_id
      AND (p_structure_type IS NULL OR r.structure_type = p_structure_type)

    UNION ALL

    SELECT 
      ref.referred_user_id as uid,
      n.lvl + 1 as lvl,
      n.uid as parent
    FROM network n
    JOIN referrals ref ON ref.referrer_id = n.uid
    WHERE n.lvl < p_max_levels
      AND (p_structure_type IS NULL OR ref.structure_type = p_structure_type)
  ),
  commission_data AS (
    SELECT DISTINCT ON (n.uid)
      n.uid,
      n.lvl,
      n.parent,
      t.id as transaction_id,
      t.frozen_until,
      (t.id IS NOT NULL) as has_commission
    FROM network n
    LEFT JOIN transactions t ON 
      t.user_id = root_user_id
      AND t.type = 'commission'
      AND t.level = n.lvl
      AND (
        t.payload->>'from_user_id' = n.uid::text OR
        t.payload->>'subscriber_id' = n.uid::text OR
        t.payload->>'buyer_id' = n.uid::text OR
        t.payload->>'source_user_id' = n.uid::text
      )
      AND (
        (p_structure_type = 1 AND t.structure_type = 'primary') OR
        (p_structure_type = 2 AND t.structure_type = 'secondary')
      )
    ORDER BY n.uid, t.created_at DESC
  )
  SELECT 
    p.id,
    p.full_name,
    p.avatar_url,
    cd.lvl as level,
    cd.parent as parent_id,
    p.subscription_status,
    p.subscription_expires_at,
    COALESCE(p.personal_activation_volume, 0) as personal_activation_volume,
    cd.has_commission as has_commission_received,
    CASE 
      WHEN NOT cd.has_commission THEN 
        CASE 
          WHEN p.subscription_status != 'active' THEN 'partner_inactive'
          ELSE 'level_not_unlocked'
        END
      ELSE NULL
    END as no_commission_reason,
    cd.frozen_until as commission_frozen_until,
    COALESCE(p.is_activated, false) as is_activated
  FROM commission_data cd
  JOIN profiles p ON p.id = cd.uid
  ORDER BY cd.lvl, p.full_name;
END;
$$;