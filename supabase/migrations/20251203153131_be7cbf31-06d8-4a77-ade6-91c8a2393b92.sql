
-- Update get_referral_network_from_table to accept structure_type parameter
CREATE OR REPLACE FUNCTION public.get_referral_network_from_table(
  root_user_id UUID,
  max_level INT DEFAULT 10,
  p_structure_type INT DEFAULT 1
)
RETURNS TABLE (
  user_id UUID,
  partner_id UUID,
  level INT,
  full_name TEXT,
  email TEXT,
  avatar_url TEXT,
  subscription_status TEXT,
  monthly_activation_met BOOLEAN,
  referral_code TEXT,
  created_at TIMESTAMPTZ,
  direct_referrals BIGINT,
  total_team BIGINT,
  monthly_volume NUMERIC
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  WITH RECURSIVE referral_tree AS (
    -- Base case: direct referrals
    SELECT 
      r.referrer_id AS user_id,
      r.referred_user_id AS partner_id,
      1 AS level
    FROM referrals r
    WHERE r.referrer_id = root_user_id
      AND r.structure_type = p_structure_type
    
    UNION ALL
    
    -- Recursive case
    SELECT 
      rt.partner_id AS user_id,
      r.referred_user_id AS partner_id,
      rt.level + 1 AS level
    FROM referral_tree rt
    JOIN referrals r ON r.referrer_id = rt.partner_id
      AND r.structure_type = p_structure_type
    WHERE rt.level < max_level
  )
  SELECT 
    rt.user_id,
    rt.partner_id,
    rt.level,
    p.full_name,
    p.email,
    p.avatar_url,
    COALESCE(p.subscription_status, 'inactive') AS subscription_status,
    COALESCE(p.monthly_activation_completed, false) AS monthly_activation_met,
    p.referral_code,
    p.created_at,
    COALESCE((
      SELECT COUNT(*) 
      FROM referrals r2 
      WHERE r2.referrer_id = rt.partner_id 
        AND r2.structure_type = p_structure_type
    ), 0) AS direct_referrals,
    COALESCE((
      WITH RECURSIVE sub_tree AS (
        SELECT r3.referred_user_id
        FROM referrals r3
        WHERE r3.referrer_id = rt.partner_id
          AND r3.structure_type = p_structure_type
        UNION ALL
        SELECT r4.referred_user_id
        FROM sub_tree st
        JOIN referrals r4 ON r4.referrer_id = st.referred_user_id
          AND r4.structure_type = p_structure_type
      )
      SELECT COUNT(*) FROM sub_tree
    ), 0) AS total_team,
    COALESCE((
      SELECT SUM(t.amount_cents) / 100.0
      FROM transactions t
      WHERE t.source_id = rt.partner_id
        AND t.type = 'commission'
        AND t.created_at >= date_trunc('month', CURRENT_DATE)
    ), 0) AS monthly_volume
  FROM referral_tree rt
  JOIN profiles p ON p.id = rt.partner_id
  ORDER BY rt.level, p.created_at DESC;
END;
$$;
