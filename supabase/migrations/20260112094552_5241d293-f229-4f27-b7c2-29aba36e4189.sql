-- ============================================
-- HOTFIX: Fix get_referral_network_from_table function
-- Problem: Function references non-existent columns
-- ============================================

DROP FUNCTION IF EXISTS get_referral_network_from_table(uuid, integer, integer);

CREATE OR REPLACE FUNCTION get_referral_network_from_table(
  root_user_id uuid,
  p_max_levels integer DEFAULT 10,
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
  is_activated boolean,
  created_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_structure_type_enum structure_type;
BEGIN
  v_structure_type_enum := CASE WHEN p_structure_type = 1 THEN 'primary'::structure_type ELSE 'secondary'::structure_type END;

  RETURN QUERY
  WITH RECURSIVE network AS (
    SELECT 
      p.id,
      p.full_name,
      p.avatar_url,
      1 as lvl,
      p.sponsor_id as parent_id,
      p.subscription_status,
      p.subscription_expires_at,
      p.monthly_activation_completed,
      p.created_at
    FROM profiles p
    WHERE p.sponsor_id = root_user_id
      AND p.deleted_at IS NULL
      AND p.is_archived IS NOT TRUE
    
    UNION ALL
    
    SELECT 
      p.id,
      p.full_name,
      p.avatar_url,
      n.lvl + 1,
      p.sponsor_id as parent_id,
      p.subscription_status,
      p.subscription_expires_at,
      p.monthly_activation_completed,
      p.created_at
    FROM profiles p
    INNER JOIN network n ON p.sponsor_id = n.id
    WHERE n.lvl < p_max_levels
      AND p.deleted_at IS NULL
      AND p.is_archived IS NOT TRUE
  )
  SELECT 
    n.id,
    n.full_name,
    n.avatar_url,
    n.lvl as level,
    n.parent_id,
    n.subscription_status,
    n.subscription_expires_at,
    COALESCE(ma.total_amount_kzt, 0)::numeric as personal_activation_volume,
    CASE 
      WHEN p_structure_type = 1 THEN
        EXISTS (
          SELECT 1 FROM transactions t 
          WHERE t.user_id = root_user_id 
            AND t.type = 'commission' 
            AND t.structure_type = v_structure_type_enum
            AND (t.payload->>'subscriber_id' = n.id::text OR t.payload->>'from_user_id' = n.id::text)
        )
      ELSE
        EXISTS (
          SELECT 1 FROM transactions t 
          WHERE t.user_id = root_user_id 
            AND t.type = 'commission' 
            AND t.structure_type = v_structure_type_enum
            AND t.payload->>'buyer_id' = n.id::text
        )
    END as has_commission_received,
    CASE 
      WHEN n.subscription_status IS NULL OR n.subscription_status != 'active' THEN 'partner_no_subscription'
      WHEN p_structure_type = 2 AND n.monthly_activation_completed IS NOT TRUE THEN 'partner_no_activation'
      ELSE NULL
    END as no_commission_reason,
    (
      SELECT t.frozen_until 
      FROM transactions t 
      WHERE t.user_id = root_user_id 
        AND t.type = 'commission' 
        AND t.structure_type = v_structure_type_enum
        AND t.status = 'frozen'
        AND (
          (p_structure_type = 1 AND (t.payload->>'subscriber_id' = n.id::text OR t.payload->>'from_user_id' = n.id::text))
          OR (p_structure_type = 2 AND t.payload->>'buyer_id' = n.id::text)
        )
      ORDER BY t.created_at DESC
      LIMIT 1
    ) as commission_frozen_until,
    COALESCE(n.monthly_activation_completed, false) as is_activated,
    n.created_at
  FROM network n
  LEFT JOIN monthly_activations ma ON ma.user_id = n.id 
    AND ma.year = EXTRACT(YEAR FROM CURRENT_DATE)::integer
    AND ma.month = EXTRACT(MONTH FROM CURRENT_DATE)::integer
  ORDER BY n.lvl, n.created_at;
END;
$$;