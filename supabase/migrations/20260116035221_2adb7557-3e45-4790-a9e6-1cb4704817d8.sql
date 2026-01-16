-- =====================================================
-- Part 1: Backfill L2 commissions for users with 3+ active L1s
-- Using correct source_ref format: subscription_{id}_s1_level_2
-- =====================================================

WITH sponsors_with_unlocked_l2 AS (
  SELECT r.referrer_id, COUNT(*) as active_l1_count
  FROM referrals r
  JOIN subscriptions s ON s.user_id = r.referred_user_id AND s.status = 'active'
  WHERE r.structure_type = 1
  GROUP BY r.referrer_id
  HAVING COUNT(*) >= 3
),
l2_partners_with_subscriptions AS (
  SELECT DISTINCT
    sponsor.referrer_id as sponsor_id,
    l2r.referred_user_id as l2_partner_id,
    l2s.id as subscription_id,
    l2s.paid_at,
    l2s.amount_kzt
  FROM sponsors_with_unlocked_l2 sponsor
  JOIN referrals l1r ON l1r.referrer_id = sponsor.referrer_id AND l1r.structure_type = 1
  JOIN referrals l2r ON l2r.referrer_id = l1r.referred_user_id AND l2r.structure_type = 1
  JOIN subscriptions l2s ON l2s.user_id = l2r.referred_user_id AND l2s.status = 'active' AND l2s.paid_at IS NOT NULL
),
l2_commission_percent AS (
  SELECT COALESCE(
    (SELECT percent FROM mlm_commission_rules 
     WHERE structure_type = 1 AND level = 2 AND is_active = true 
     ORDER BY effective_from DESC LIMIT 1),
    10
  ) as percent
)
INSERT INTO transactions (
  user_id, type, amount_cents, currency, status, 
  source_id, source_ref, level, structure_type, 
  frozen_until, payload, created_at
)
SELECT 
  lp.sponsor_id,
  'commission',
  ROUND(lp.amount_kzt * cp.percent / 100),
  'KZT',
  CASE WHEN lp.paid_at + interval '14 days' > NOW() THEN 'frozen'::transaction_status ELSE 'completed'::transaction_status END,
  lp.subscription_id,
  'subscription_' || lp.subscription_id || '_s1_level_2',
  2,
  'primary'::structure_type,
  lp.paid_at + interval '14 days',
  jsonb_build_object(
    'structure_type', 1,
    'level', 2,
    'subscriber_id', lp.l2_partner_id::text,
    'subscription_id', lp.subscription_id::text,
    'backfill', 'true',
    'backfill_date', NOW()::text,
    'backfill_reason', 'L2 commission backfill for unlocked level'
  ),
  lp.paid_at
FROM l2_partners_with_subscriptions lp
CROSS JOIN l2_commission_percent cp
WHERE NOT EXISTS (
  SELECT 1 FROM transactions t 
  WHERE t.user_id = lp.sponsor_id 
    AND t.type = 'commission' 
    AND t.source_id = lp.subscription_id
    AND t.level = 2
    AND t.structure_type = 'primary'
);

-- =====================================================
-- Part 2: Update get_referral_network_from_table function
-- to properly check unlock levels and show correct reasons
-- =====================================================

CREATE OR REPLACE FUNCTION get_referral_network_from_table(
  root_user_id UUID,
  p_max_levels INT DEFAULT 10,
  p_structure_type INT DEFAULT 1
)
RETURNS TABLE (
  user_id UUID,
  partner_id TEXT,
  email TEXT,
  full_name TEXT,
  referral_code TEXT,
  subscription_status TEXT,
  monthly_activation_met BOOLEAN,
  level INT,
  structure_type INT,
  created_at TIMESTAMPTZ,
  has_commission_received BOOLEAN,
  no_commission_reason TEXT,
  parent_partner_id TEXT
) AS $$
DECLARE
  v_l2_unlock INT := 3;
  v_l3_unlock INT := 5;
  v_l4_unlock INT := 8;
  v_l5_unlock INT := 10;
  v_active_l1_count INT;
BEGIN
  -- Get unlock levels from mlm_settings
  SELECT 
    COALESCE((value->>'l2')::int, 3),
    COALESCE((value->>'l3')::int, 5),
    COALESCE((value->>'l4')::int, 8),
    COALESCE((value->>'l5')::int, 10)
  INTO v_l2_unlock, v_l3_unlock, v_l4_unlock, v_l5_unlock
  FROM mlm_settings 
  WHERE key = 'unlock_levels';

  -- Count active L1 referrals for the root user
  SELECT COUNT(*)::int INTO v_active_l1_count
  FROM referrals r
  JOIN subscriptions s ON s.user_id = r.referred_user_id AND s.status = 'active'
  WHERE r.referrer_id = root_user_id 
    AND r.structure_type = p_structure_type;

  RETURN QUERY
  WITH RECURSIVE network AS (
    -- Base case: direct referrals (level 1)
    SELECT 
      r.referred_user_id,
      r.referrer_id as parent_id,
      1 as lvl
    FROM referrals r
    WHERE r.referrer_id = root_user_id
      AND r.structure_type = p_structure_type
    
    UNION ALL
    
    -- Recursive case: deeper levels
    SELECT 
      r.referred_user_id,
      r.referrer_id as parent_id,
      n.lvl + 1
    FROM referrals r
    JOIN network n ON r.referrer_id = n.referred_user_id
    WHERE n.lvl < p_max_levels
      AND r.structure_type = p_structure_type
  ),
  network_with_profiles AS (
    SELECT 
      n.referred_user_id,
      n.parent_id,
      n.lvl,
      p.referral_code,
      p.email,
      p.full_name,
      p.subscription_status,
      p.monthly_activation_completed,
      p.created_at,
      pp.referral_code as parent_referral_code
    FROM network n
    JOIN profiles p ON p.id = n.referred_user_id
    LEFT JOIN profiles pp ON pp.id = n.parent_id
  ),
  commission_check AS (
    -- Check if commission was received for each network member's subscription
    SELECT 
      s.user_id as subscriber_id,
      t.id IS NOT NULL as has_commission,
      t.frozen_until,
      t.status as tx_status
    FROM subscriptions s
    LEFT JOIN transactions t ON t.source_id = s.id 
      AND t.user_id = root_user_id 
      AND t.type = 'commission'
      AND t.structure_type = (CASE WHEN p_structure_type = 1 THEN 'primary' ELSE 'secondary' END)::structure_type
    WHERE s.status = 'active'
  )
  SELECT 
    nwp.referred_user_id as user_id,
    nwp.referral_code as partner_id,
    nwp.email,
    nwp.full_name,
    nwp.referral_code,
    nwp.subscription_status,
    COALESCE(nwp.monthly_activation_completed, false) as monthly_activation_met,
    nwp.lvl as level,
    p_structure_type as structure_type,
    nwp.created_at,
    COALESCE(cc.has_commission, false) as has_commission_received,
    CASE
      -- Level 1 always unlocked
      WHEN nwp.lvl = 1 AND cc.has_commission THEN NULL
      WHEN nwp.lvl = 1 AND NOT COALESCE(cc.has_commission, false) AND nwp.subscription_status != 'active' THEN 'inactive_subscription'
      WHEN nwp.lvl = 1 AND NOT COALESCE(cc.has_commission, false) THEN 'awaiting_commission'
      
      -- Level 2: need 3 active L1
      WHEN nwp.lvl = 2 AND v_active_l1_count < v_l2_unlock THEN 'level_2_locked'
      WHEN nwp.lvl = 2 AND cc.has_commission THEN NULL
      WHEN nwp.lvl = 2 AND nwp.subscription_status != 'active' THEN 'inactive_subscription'
      WHEN nwp.lvl = 2 THEN 'awaiting_commission'
      
      -- Level 3: need 5 active L1
      WHEN nwp.lvl = 3 AND v_active_l1_count < v_l3_unlock THEN 'level_3_locked'
      WHEN nwp.lvl = 3 AND cc.has_commission THEN NULL
      WHEN nwp.lvl = 3 AND nwp.subscription_status != 'active' THEN 'inactive_subscription'
      WHEN nwp.lvl = 3 THEN 'awaiting_commission'
      
      -- Level 4: need 8 active L1
      WHEN nwp.lvl = 4 AND v_active_l1_count < v_l4_unlock THEN 'level_4_locked'
      WHEN nwp.lvl = 4 AND cc.has_commission THEN NULL
      WHEN nwp.lvl = 4 AND nwp.subscription_status != 'active' THEN 'inactive_subscription'
      WHEN nwp.lvl = 4 THEN 'awaiting_commission'
      
      -- Level 5: need 10 active L1
      WHEN nwp.lvl = 5 AND v_active_l1_count < v_l5_unlock THEN 'level_5_locked'
      WHEN nwp.lvl = 5 AND cc.has_commission THEN NULL
      WHEN nwp.lvl = 5 AND nwp.subscription_status != 'active' THEN 'inactive_subscription'
      WHEN nwp.lvl = 5 THEN 'awaiting_commission'
      
      -- Levels 6+: structure 2 only, no unlock requirements for now
      WHEN nwp.lvl > 5 AND cc.has_commission THEN NULL
      WHEN nwp.lvl > 5 AND nwp.subscription_status != 'active' THEN 'inactive_subscription'
      WHEN nwp.lvl > 5 THEN 'awaiting_commission'
      
      ELSE 'no_commission'
    END as no_commission_reason,
    nwp.parent_referral_code as parent_partner_id
  FROM network_with_profiles nwp
  LEFT JOIN commission_check cc ON cc.subscriber_id = nwp.referred_user_id
  ORDER BY nwp.lvl, nwp.created_at;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;