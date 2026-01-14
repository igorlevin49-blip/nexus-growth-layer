-- Удалить старую функцию и создать новую с parent_partner_id
DROP FUNCTION IF EXISTS public.get_referral_network_from_table(uuid, integer, integer);

CREATE OR REPLACE FUNCTION public.get_referral_network_from_table(
  root_user_id uuid, 
  p_max_levels integer DEFAULT 10, 
  p_structure_type integer DEFAULT 1
)
RETURNS TABLE(
  user_id uuid, 
  partner_id text, 
  email text, 
  full_name text, 
  referral_code text, 
  subscription_status text, 
  monthly_activation_met boolean, 
  level integer, 
  structure_type integer, 
  created_at timestamp with time zone, 
  has_commission_received boolean, 
  no_commission_reason text,
  parent_partner_id text
)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_structure_type_enum structure_type;
BEGIN
  v_structure_type_enum := CASE WHEN p_structure_type = 1 THEN 'primary'::structure_type ELSE 'secondary'::structure_type END;

  RETURN QUERY
  WITH RECURSIVE network AS (
    -- Direct referrals (level 1)
    SELECT 
      r.referred_user_id AS uid,
      r.referrer_id AS parent_uid,
      1 AS lvl
    FROM referrals r
    WHERE r.referrer_id = root_user_id
      AND r.structure_type = p_structure_type
    
    UNION ALL
    
    -- Deeper levels
    SELECT 
      r.referred_user_id,
      r.referrer_id AS parent_uid,
      n.lvl + 1
    FROM referrals r
    INNER JOIN network n ON r.referrer_id = n.uid
    WHERE r.structure_type = p_structure_type
      AND n.lvl < p_max_levels
  ),
  commission_check AS (
    SELECT 
      COALESCE(t.payload->>'subscriber_id', t.payload->>'source_user_id', t.source_id::text) AS source_user,
      true AS has_commission
    FROM transactions t
    WHERE t.user_id = root_user_id
      AND t.type = 'commission'
      AND t.structure_type = v_structure_type_enum
      AND t.status IN ('completed'::transaction_status, 'frozen'::transaction_status)
    GROUP BY COALESCE(t.payload->>'subscriber_id', t.payload->>'source_user_id', t.source_id::text)
  )
  SELECT 
    p.id AS user_id,
    p.referral_code AS partner_id,
    p.email,
    p.full_name,
    p.referral_code,
    p.subscription_status,
    COALESCE(p.monthly_activation_completed, false) AS monthly_activation_met,
    n.lvl AS level,
    p_structure_type AS structure_type,
    p.created_at,
    COALESCE(cc.has_commission, false) AS has_commission_received,
    CASE 
      WHEN cc.has_commission = true THEN NULL
      WHEN p.subscription_status IS NULL OR p.subscription_status != 'active' THEN 'partner_no_subscription'
      WHEN p_structure_type = 1 AND n.lvl > 5 THEN 'too_deep'
      WHEN p_structure_type = 2 AND n.lvl > 10 THEN 'too_deep'
      WHEN EXISTS (
        SELECT 1 FROM subscriptions s 
        WHERE s.user_id = p.id 
          AND s.status = 'active' 
          AND s.is_marketing_free_access = true
      ) THEN 'marketing_free_access'
      WHEN p_structure_type = 2 AND COALESCE(p.monthly_activation_completed, false) = false THEN 'partner_no_activation'
      ELSE 'no_commission'
    END AS no_commission_reason,
    parent_p.referral_code AS parent_partner_id
  FROM network n
  INNER JOIN profiles p ON p.id = n.uid
  INNER JOIN profiles parent_p ON parent_p.id = n.parent_uid
  LEFT JOIN subscriptions s ON s.user_id = p.id AND s.status = 'active'
  LEFT JOIN commission_check cc ON cc.source_user = p.id::text
  ORDER BY n.lvl, p.full_name;
END;
$$;