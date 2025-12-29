-- Add is_system_account column to profiles table (if not exists from partial previous migration)
ALTER TABLE public.profiles 
ADD COLUMN IF NOT EXISTS is_system_account boolean DEFAULT false;

-- Mark mg-market001@mail.ru as system account
UPDATE public.profiles 
SET is_system_account = true 
WHERE email = 'mg-market001@mail.ru';

-- Drop existing function first to change return type
DROP FUNCTION IF EXISTS public.get_referral_network_from_table(uuid, integer, integer);

-- Recreate get_referral_network_from_table to not mark system accounts as inactive
CREATE FUNCTION public.get_referral_network_from_table(
  root_user_id uuid,
  max_level integer DEFAULT 10,
  p_structure_type integer DEFAULT 1
)
RETURNS TABLE(
  user_id uuid,
  partner_id uuid,
  parent_partner_id uuid,
  full_name text,
  email text,
  referral_code text,
  avatar_url text,
  level integer,
  subscription_status text,
  monthly_activation_met boolean,
  direct_referrals integer,
  total_team integer,
  monthly_volume numeric,
  created_at timestamptz,
  has_commission_received boolean,
  no_commission_reason text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  WITH RECURSIVE network AS (
    -- Base case: direct referrals
    SELECT 
      r.referred_user_id as user_id,
      r.id as partner_id,
      NULL::uuid as parent_partner_id,
      1 as level
    FROM referrals r
    WHERE r.referrer_id = root_user_id
      AND r.structure_type = p_structure_type
    
    UNION ALL
    
    -- Recursive case: referrals of referrals
    SELECT 
      r.referred_user_id,
      r.id as partner_id,
      n.partner_id as parent_partner_id,
      n.level + 1
    FROM referrals r
    JOIN network n ON r.referrer_id = n.user_id
    WHERE r.structure_type = p_structure_type
      AND n.level < max_level
  )
  SELECT 
    n.user_id,
    n.partner_id,
    n.parent_partner_id,
    p.full_name,
    p.email,
    p.referral_code,
    p.avatar_url,
    n.level,
    p.subscription_status,
    p.monthly_activation_completed as monthly_activation_met,
    COALESCE(p.direct_referrals_count, 0)::integer as direct_referrals,
    0::integer as total_team,
    0::numeric as monthly_volume,
    p.created_at,
    -- System accounts are always considered active
    CASE 
      WHEN COALESCE(p.is_system_account, false) THEN true
      WHEN p.subscription_status = 'active' THEN true
      WHEN p.monthly_activation_completed THEN true
      ELSE false
    END as has_commission_received,
    CASE 
      WHEN COALESCE(p.is_system_account, false) THEN NULL
      WHEN p.subscription_status = 'active' THEN NULL
      WHEN p.monthly_activation_completed THEN NULL
      WHEN p.subscription_status = 'inactive' AND NOT p.monthly_activation_completed THEN 'sponsor_inactive'
      ELSE 'other'
    END as no_commission_reason
  FROM network n
  JOIN profiles p ON p.id = n.user_id
  WHERE p.is_active = true 
    AND p.deleted_at IS NULL
    AND (p.is_archived IS NULL OR p.is_archived = false)
  ORDER BY n.level, p.created_at;
END;
$$;

-- Update get_monthly_activation_report to exclude system accounts
DROP FUNCTION IF EXISTS public.get_monthly_activation_report(integer, integer, text, text, integer, integer);

CREATE FUNCTION public.get_monthly_activation_report(
  p_year integer,
  p_month integer,
  p_status text DEFAULT 'all',
  p_search text DEFAULT NULL,
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
  last_order_date timestamptz,
  orders_count bigint,
  activation_due_from timestamptz,
  admin_comment text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    ma.user_id,
    p.full_name,
    p.email,
    p.referral_code,
    ma.total_amount_kzt,
    ma.threshold_kzt,
    ma.is_activated,
    ma.last_order_date,
    (SELECT COUNT(*) FROM orders o 
     WHERE o.user_id = ma.user_id 
       AND o.status = 'paid'
       AND EXTRACT(YEAR FROM o.paid_at) = p_year
       AND EXTRACT(MONTH FROM o.paid_at) = p_month
    ) as orders_count,
    p.activation_due_from,
    ma.admin_comment
  FROM monthly_activations ma
  JOIN profiles p ON p.id = ma.user_id
  WHERE ma.year = p_year
    AND ma.month = p_month
    AND p.is_active = true
    AND p.deleted_at IS NULL
    AND (p.is_archived IS NULL OR p.is_archived = false)
    AND COALESCE(p.is_system_account, false) = false
    AND (
      p_status = 'all' 
      OR (p_status = 'activated' AND ma.is_activated = true)
      OR (p_status = 'not_activated' AND ma.is_activated = false)
    )
    AND (
      p_search IS NULL 
      OR p.full_name ILIKE '%' || p_search || '%'
      OR p.email ILIKE '%' || p_search || '%'
      OR p.referral_code ILIKE '%' || p_search || '%'
    )
  ORDER BY ma.is_activated ASC, ma.total_amount_kzt DESC
  LIMIT p_limit
  OFFSET p_offset;
END;
$$;

-- Update get_monthly_activation_count to exclude system accounts
DROP FUNCTION IF EXISTS public.get_monthly_activation_count(integer, integer, text, text);

CREATE FUNCTION public.get_monthly_activation_count(
  p_year integer,
  p_month integer,
  p_status text DEFAULT 'all',
  p_search text DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_total integer;
  v_activated integer;
  v_not_activated integer;
  v_threshold numeric;
BEGIN
  -- Get threshold from settings
  SELECT COALESCE(monthly_activation_required_kzt, 20000) INTO v_threshold
  FROM shop_settings WHERE id = 1;

  SELECT 
    COUNT(*),
    COUNT(*) FILTER (WHERE ma.is_activated = true),
    COUNT(*) FILTER (WHERE ma.is_activated = false)
  INTO v_total, v_activated, v_not_activated
  FROM monthly_activations ma
  JOIN profiles p ON p.id = ma.user_id
  WHERE ma.year = p_year
    AND ma.month = p_month
    AND p.is_active = true
    AND p.deleted_at IS NULL
    AND (p.is_archived IS NULL OR p.is_archived = false)
    AND COALESCE(p.is_system_account, false) = false
    AND (
      p_search IS NULL 
      OR p.full_name ILIKE '%' || p_search || '%'
      OR p.email ILIKE '%' || p_search || '%'
      OR p.referral_code ILIKE '%' || p_search || '%'
    );

  RETURN json_build_object(
    'total', v_total,
    'activated', v_activated,
    'not_activated', v_not_activated,
    'threshold_kzt', v_threshold
  );
END;
$$;