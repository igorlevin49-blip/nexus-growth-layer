
-- Update get_network_stats to accept structure_type parameter
CREATE OR REPLACE FUNCTION public.get_network_stats(
  user_id_param UUID,
  p_structure_type INT DEFAULT 1
)
RETURNS TABLE (
  total_partners BIGINT,
  active_partners BIGINT,
  frozen_partners BIGINT,
  max_level INT,
  new_this_month BIGINT,
  activations_this_month BIGINT,
  volume_this_month NUMERIC,
  commissions_this_month NUMERIC
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_max_level INT;
BEGIN
  -- Set max level based on structure type
  v_max_level := CASE 
    WHEN p_structure_type = 1 THEN 5  -- S1: L1-L5
    WHEN p_structure_type = 2 THEN 10 -- S2: L1-L10
    ELSE 5
  END;

  RETURN QUERY
  WITH RECURSIVE network AS (
    -- Base: direct referrals
    SELECT 
      r.referred_user_id AS partner_id,
      1 AS level
    FROM referrals r
    WHERE r.referrer_id = user_id_param
      AND r.structure_type = p_structure_type
    
    UNION ALL
    
    -- Recursive: deeper levels
    SELECT 
      r.referred_user_id AS partner_id,
      n.level + 1 AS level
    FROM network n
    JOIN referrals r ON r.referrer_id = n.partner_id
      AND r.structure_type = p_structure_type
    WHERE n.level < v_max_level
  ),
  partner_stats AS (
    SELECT 
      n.partner_id,
      n.level,
      p.subscription_status,
      p.monthly_activation_completed,
      p.created_at
    FROM network n
    JOIN profiles p ON p.id = n.partner_id
  )
  SELECT 
    COUNT(DISTINCT ps.partner_id)::BIGINT as total_partners,
    COUNT(DISTINCT CASE 
      WHEN ps.subscription_status = 'active' OR ps.monthly_activation_completed = true 
      THEN ps.partner_id 
    END)::BIGINT as active_partners,
    COUNT(DISTINCT CASE 
      WHEN ps.subscription_status = 'frozen' 
      THEN ps.partner_id 
    END)::BIGINT as frozen_partners,
    COALESCE(MAX(ps.level), 0)::INT as max_level,
    COUNT(DISTINCT CASE 
      WHEN ps.created_at >= date_trunc('month', CURRENT_DATE) 
      THEN ps.partner_id 
    END)::BIGINT as new_this_month,
    COUNT(DISTINCT CASE 
      WHEN ps.monthly_activation_completed = true 
        AND ps.created_at >= date_trunc('month', CURRENT_DATE)
      THEN ps.partner_id 
    END)::BIGINT as activations_this_month,
    COALESCE((
      SELECT SUM(oi.price_usd * oi.qty)
      FROM orders o
      JOIN order_items oi ON oi.order_id = o.id
      WHERE o.user_id IN (SELECT partner_id FROM partner_stats)
        AND o.status = 'paid'
        AND o.created_at >= date_trunc('month', CURRENT_DATE)
    ), 0) as volume_this_month,
    COALESCE((
      SELECT SUM(t.amount_cents) / 100.0
      FROM transactions t
      WHERE t.user_id = user_id_param
        AND t.type = 'commission'
        AND t.structure_type = CASE 
          WHEN p_structure_type = 1 THEN 'primary'::structure_type
          WHEN p_structure_type = 2 THEN 'secondary'::structure_type
        END
        AND t.created_at >= date_trunc('month', CURRENT_DATE)
    ), 0) as commissions_this_month
  FROM partner_stats ps;
END;
$$;
