-- =====================================================
-- FIX #1: Remove x100 multiplier from S2 order commissions
-- =====================================================

CREATE OR REPLACE FUNCTION public.create_commission_transactions(
  p_amount_kzt numeric,
  p_source_id uuid,
  p_source_ref text,
  p_source_user_id uuid,
  p_structure_type integer DEFAULT 2
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_current_user_id uuid := p_source_user_id;
  v_sponsor_id uuid;
  v_level integer := 0;
  v_percent numeric;
  v_commission_kzt numeric;
  v_created_count integer := 0;
  v_skipped_count integer := 0;
  v_total_commission_kzt numeric := 0;
  v_freeze_days integer := 14;
  v_frozen_until timestamptz;
  v_sponsor_profile record;
  v_direct_referrals_count integer;
  v_required_referrals integer;
  v_max_level integer;
  v_skip_reason text;
  v_details jsonb := '[]'::jsonb;
  v_existing_count integer;
BEGIN
  -- Check for existing commissions to prevent duplicates
  SELECT COUNT(*) INTO v_existing_count
  FROM transactions
  WHERE source_id = p_source_id
    AND source_ref = p_source_ref
    AND type = 'commission'
    AND structure_type = CASE WHEN p_structure_type = 1 THEN 'primary'::structure_type ELSE 'secondary'::structure_type END;
  
  IF v_existing_count > 0 THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Commissions already exist for this source',
      'existing_count', v_existing_count
    );
  END IF;

  -- Get max level for this structure
  SELECT COALESCE(MAX(level), 10) INTO v_max_level
  FROM mlm_commission_rules
  WHERE structure_type = p_structure_type AND is_active = true;

  -- Calculate freeze date
  v_frozen_until := now() + (v_freeze_days || ' days')::interval;

  -- Walk up the referral chain
  LOOP
    -- Get sponsor from profiles
    SELECT sponsor_id INTO v_sponsor_id
    FROM profiles
    WHERE id = v_current_user_id;
    
    EXIT WHEN v_sponsor_id IS NULL;
    
    v_level := v_level + 1;
    EXIT WHEN v_level > v_max_level;
    
    -- Get commission percent for this level and structure
    SELECT percent INTO v_percent
    FROM mlm_commission_rules
    WHERE structure_type = p_structure_type
      AND level = v_level
      AND is_active = true
    LIMIT 1;
    
    -- Skip if no commission rule
    IF v_percent IS NULL OR v_percent <= 0 THEN
      v_current_user_id := v_sponsor_id;
      CONTINUE;
    END IF;
    
    -- Get sponsor profile for validation
    SELECT * INTO v_sponsor_profile
    FROM profiles
    WHERE id = v_sponsor_id;
    
    v_skip_reason := NULL;
    
    -- Check sponsor has active subscription (for S1) or is generally active
    IF v_sponsor_profile.subscription_status NOT IN ('active', 'paid') THEN
      v_skip_reason := 'sponsor_inactive';
    END IF;
    
    -- For S2, check monthly activation
    IF p_structure_type = 2 AND v_skip_reason IS NULL THEN
      IF NOT COALESCE(v_sponsor_profile.monthly_activation_completed, false) THEN
        v_skip_reason := 'sponsor_no_activation';
      END IF;
    END IF;
    
    -- Check unlock requirements (direct referrals needed to unlock level)
    IF v_skip_reason IS NULL AND v_level >= 2 THEN
      -- Count direct referrals
      SELECT COUNT(*) INTO v_direct_referrals_count
      FROM referrals
      WHERE referrer_id = v_sponsor_id
        AND structure_type = p_structure_type;
      
      -- Unlock requirements: level 2 needs 2, level 3 needs 3, etc.
      v_required_referrals := v_level;
      
      IF v_direct_referrals_count < v_required_referrals THEN
        v_skip_reason := 'level_locked';
      END IF;
    END IF;
    
    -- Calculate commission amount - FIX: removed x100 multiplier
    -- Now stores whole KZT (800 тенге = 800, not 80000)
    v_commission_kzt := ROUND(p_amount_kzt * (v_percent / 100.0));
    
    IF v_skip_reason IS NULL AND v_commission_kzt > 0 THEN
      -- Create commission transaction
      INSERT INTO transactions (
        user_id,
        type,
        amount_cents,
        currency,
        status,
        frozen_until,
        source_id,
        source_ref,
        level,
        structure_type,
        payload
      ) VALUES (
        v_sponsor_id,
        'commission',
        v_commission_kzt,
        'KZT',
        'frozen',
        v_frozen_until,
        p_source_id,
        p_source_ref,
        v_level,
        CASE WHEN p_structure_type = 1 THEN 'primary'::structure_type ELSE 'secondary'::structure_type END,
        jsonb_build_object(
          'source_user_id', p_source_user_id,
          'order_amount_kzt', p_amount_kzt,
          'percent', v_percent,
          'created_at', now(),
          'unit', 'KZT'
        )
      );
      
      v_created_count := v_created_count + 1;
      v_total_commission_kzt := v_total_commission_kzt + v_commission_kzt;
      
      v_details := v_details || jsonb_build_object(
        'user_id', v_sponsor_id,
        'level', v_level,
        'percent', v_percent,
        'amount_kzt', v_commission_kzt,
        'status', 'created'
      );
    ELSE
      v_skipped_count := v_skipped_count + 1;
      v_details := v_details || jsonb_build_object(
        'user_id', v_sponsor_id,
        'level', v_level,
        'percent', v_percent,
        'amount_kzt', v_commission_kzt,
        'status', 'skipped',
        'reason', COALESCE(v_skip_reason, 'zero_amount')
      );
    END IF;
    
    v_current_user_id := v_sponsor_id;
  END LOOP;
  
  RETURN jsonb_build_object(
    'success', true,
    'created_count', v_created_count,
    'skipped_count', v_skipped_count,
    'total_commission_kzt', v_total_commission_kzt,
    'frozen_until', v_frozen_until,
    'details', v_details
  );
END;
$$;

-- =====================================================
-- FIX #2: Correct existing S2 order commissions (divide by 100)
-- =====================================================

UPDATE transactions t
SET 
  amount_cents = ROUND(t.amount_cents / 100.0),
  payload = COALESCE(t.payload, '{}'::jsonb) || jsonb_build_object(
    'migrated_fix_kzt_x100', true,
    'old_amount_cents', t.amount_cents,
    'fixed_at', now(),
    'migration', '20260109_fix_s2_order_x100'
  ),
  updated_at = now()
WHERE t.type = 'commission'
  AND t.structure_type = 'secondary'
  AND t.source_ref LIKE 'order:%'
  AND t.amount_cents > 10000
  AND NOT COALESCE((t.payload->>'migrated_fix_kzt_x100')::boolean, false);

-- =====================================================
-- FIX #3: Restore get_referral_network_from_table using referrals table
-- Uses proper PostgreSQL recursive CTE syntax (not Oracle CONNECT BY)
-- =====================================================

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
  direct_referrals integer,
  total_team integer,
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
  v_is_admin boolean := false;
  v_caller_id uuid;
BEGIN
  -- Get caller info for permission checks
  v_caller_id := auth.uid();
  
  -- Check if caller is admin
  SELECT EXISTS(
    SELECT 1 FROM user_roles 
    WHERE user_roles.user_id = v_caller_id 
    AND role IN ('admin', 'superadmin')
  ) INTO v_is_admin;

  RETURN QUERY
  WITH RECURSIVE network AS (
    -- Base case: direct referrals of root user
    SELECT 
      r.referred_user_id as uid,
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
    INNER JOIN network n ON r.referrer_id = n.uid
    WHERE r.structure_type = p_structure_type
      AND n.lvl < max_level
  ),
  -- Count direct referrals for each user in this structure
  direct_counts AS (
    SELECT 
      r.referrer_id as ref_id,
      COUNT(*)::integer as cnt
    FROM referrals r
    WHERE r.structure_type = p_structure_type
    GROUP BY r.referrer_id
  ),
  -- Count total team recursively for each network member
  team_recursive AS (
    SELECT 
      n.uid as team_root,
      r.referred_user_id as member_id,
      1 as depth
    FROM network n
    JOIN referrals r ON r.referrer_id = n.uid AND r.structure_type = p_structure_type
    
    UNION ALL
    
    SELECT 
      tr.team_root,
      r.referred_user_id,
      tr.depth + 1
    FROM team_recursive tr
    JOIN referrals r ON r.referrer_id = tr.member_id AND r.structure_type = p_structure_type
    WHERE tr.depth < 10
  ),
  team_counts AS (
    SELECT team_root, COUNT(DISTINCT member_id)::integer as total
    FROM team_recursive
    GROUP BY team_root
  ),
  -- Get commission info for each network member (from their sponsor's perspective)
  commission_data AS (
    SELECT DISTINCT ON (n.uid)
      n.uid as member_id,
      t.id IS NOT NULL as has_comm,
      t.status::text as comm_status,
      t.frozen_until as frozen_date,
      CASE
        WHEN t.id IS NOT NULL THEN NULL
        WHEN p.subscription_status NOT IN ('active', 'paid') THEN 'no_active_subscription'
        WHEN sp.subscription_status NOT IN ('active', 'paid') THEN 'sponsor_inactive'
        WHEN p_structure_type = 2 AND NOT COALESCE(sp.monthly_activation_completed, false) THEN 'sponsor_no_activation'
        ELSE NULL
      END as no_comm_reason
    FROM network n
    JOIN profiles p ON p.id = n.uid
    LEFT JOIN profiles sp ON sp.id = p.sponsor_id
    LEFT JOIN transactions t ON 
      t.user_id = p.sponsor_id 
      AND t.type = 'commission'
      AND t.payload->>'source_user_id' = n.uid::text
    ORDER BY n.uid, t.created_at DESC
  )
  SELECT 
    n.uid as user_id,
    n.uid::text as partner_id,
    n.lvl as level,
    p.full_name,
    CASE 
      WHEN v_is_admin OR n.uid = v_caller_id THEN p.email
      WHEN p.email IS NULL THEN NULL
      ELSE regexp_replace(p.email, '(.{2})(.*)(@.*)', '\1***\3')
    END as email,
    CASE 
      WHEN v_is_admin OR n.uid = v_caller_id THEN p.phone
      WHEN p.phone IS NULL THEN NULL
      ELSE '***' || right(p.phone, 4)
    END as phone,
    p.avatar_url,
    p.subscription_status,
    p.subscription_expires_at,
    COALESCE(p.monthly_activation_completed, false) as monthly_activation_met,
    p.referral_code,
    p.created_at,
    COALESCE(dc.cnt, 0) as direct_referrals,
    COALESCE(tc.total, 0) as total_team,
    0::numeric as monthly_volume,
    n.parent_id::text as parent_partner_id,
    n.parent_id as parent_user_id,
    COALESCE(cd.has_comm, false) as has_commission_received,
    cd.no_comm_reason as no_commission_reason,
    cd.comm_status as commission_status,
    cd.frozen_date as commission_frozen_until
  FROM network n
  JOIN profiles p ON p.id = n.uid
  LEFT JOIN direct_counts dc ON dc.ref_id = n.uid
  LEFT JOIN team_counts tc ON tc.team_root = n.uid
  LEFT JOIN commission_data cd ON cd.member_id = n.uid
  ORDER BY n.lvl, p.created_at;
END;
$$;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION public.get_referral_network_from_table(uuid, integer, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_commission_transactions(numeric, uuid, text, uuid, integer) TO authenticated;