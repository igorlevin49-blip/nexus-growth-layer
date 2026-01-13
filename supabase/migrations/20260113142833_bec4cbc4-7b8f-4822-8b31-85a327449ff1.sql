-- Fix get_sponsors_with_missing_commissions: use 'primary' instead of 'S1' for structure_type enum
CREATE OR REPLACE FUNCTION public.get_sponsors_with_missing_commissions(p_admin_id uuid)
RETURNS TABLE (
  sponsor_id uuid,
  sponsor_name text,
  sponsor_email text,
  missing_count bigint,
  missing_amount_cents bigint,
  partners_count bigint
)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Проверка прав админа
  IF NOT EXISTS (
    SELECT 1 FROM user_roles 
    WHERE user_id = p_admin_id 
    AND role IN ('admin', 'superadmin')
  ) THEN
    RAISE EXCEPTION 'Access denied: admin role required';
  END IF;

  RETURN QUERY
  WITH missing AS (
    SELECT 
      s.id AS subscription_id,
      s.user_id AS subscriber_id,
      s.amount_kzt,
      p.sponsor_id AS spid,
      sp.full_name AS sponsor_name,
      sp.email AS sponsor_email
    FROM subscriptions s
    JOIN profiles p ON p.id = s.user_id
    JOIN profiles sp ON sp.id = p.sponsor_id
    WHERE s.status = 'active'
      AND s.paid_at IS NOT NULL
      AND p.sponsor_id IS NOT NULL
      AND NOT EXISTS (
        SELECT 1 FROM transactions t
        WHERE t.source_id = s.id
          AND t.user_id = p.sponsor_id
          AND t.structure_type = 'primary'
          AND t.level = 1
          AND t.type = 'commission'
      )
  )
  SELECT 
    m.spid,
    m.sponsor_name,
    m.sponsor_email,
    COUNT(*)::BIGINT AS missing_count,
    SUM((m.amount_kzt * 0.10)::BIGINT * 100)::BIGINT AS missing_amount_cents,
    COUNT(DISTINCT m.subscriber_id)::BIGINT AS partners_count
  FROM missing m
  GROUP BY m.spid, m.sponsor_name, m.sponsor_email
  ORDER BY missing_count DESC;
END;
$$;