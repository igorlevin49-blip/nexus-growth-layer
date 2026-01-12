-- Fix duplicate commissions: Remove commissions with short source_ref format
-- These are duplicates created due to inconsistent source_ref formatting

-- Step 1: Delete duplicate commissions (keep originals with full format)
DELETE FROM transactions
WHERE id IN (
  SELECT t.id
  FROM transactions t
  WHERE t.type = 'commission'
    AND t.structure_type = 'primary'
    AND t.level = 1
    AND t.payload->>'subscription_id' IS NOT NULL
    AND t.source_ref = t.payload->>'subscription_id'  -- short format = duplicate
    AND EXISTS (
      SELECT 1 FROM transactions t2
      WHERE t2.type = 'commission'
        AND t2.structure_type = 'primary'
        AND t2.level = 1
        AND t2.payload->>'subscription_id' = t.payload->>'subscription_id'
        AND t2.source_ref LIKE 'subscription_%'  -- original with full format
    )
);

-- Step 2: Create unique index to prevent future duplicate commissions
CREATE UNIQUE INDEX IF NOT EXISTS unique_subscription_commission 
ON transactions (
  (payload->>'subscription_id'),
  level,
  structure_type,
  user_id
)
WHERE type = 'commission' 
  AND payload->>'subscription_id' IS NOT NULL
  AND status IN ('completed', 'frozen', 'pending');

-- Step 3: Fix award_s1_subscription_commission - DROP first then CREATE
DROP FUNCTION IF EXISTS award_s1_subscription_commission(uuid, uuid, numeric);

CREATE FUNCTION award_s1_subscription_commission(
  p_subscriber_id uuid,
  p_subscription_id uuid,
  p_amount_kzt numeric
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sponsor_id uuid;
  v_commission_amount bigint;
  v_source_ref text;
  v_existing_count integer;
BEGIN
  -- Get sponsor
  SELECT sponsor_id INTO v_sponsor_id
  FROM profiles
  WHERE id = p_subscriber_id;
  
  IF v_sponsor_id IS NULL THEN
    RAISE NOTICE 'No sponsor found for subscriber %', p_subscriber_id;
    RETURN;
  END IF;
  
  -- Calculate commission (10% for L1 in S1)
  v_commission_amount := (p_amount_kzt * 0.10)::bigint * 100; -- Convert to cents
  
  -- Unified source_ref format
  v_source_ref := 'subscription_' || p_subscription_id::text || '_s1_level_1';
  
  -- Check if commission already exists (by subscription_id + level + user)
  SELECT COUNT(*) INTO v_existing_count
  FROM transactions
  WHERE type = 'commission'
    AND structure_type = 'primary'
    AND level = 1
    AND user_id = v_sponsor_id
    AND payload->>'subscription_id' = p_subscription_id::text
    AND status IN ('completed', 'frozen', 'pending');
  
  IF v_existing_count > 0 THEN
    RAISE NOTICE 'Commission already exists for subscription % level 1 user %', p_subscription_id, v_sponsor_id;
    RETURN;
  END IF;
  
  -- Create commission transaction
  INSERT INTO transactions (
    user_id,
    type,
    amount_cents,
    currency,
    status,
    structure_type,
    level,
    source_ref,
    source_id,
    payload
  ) VALUES (
    v_sponsor_id,
    'commission',
    v_commission_amount,
    'KZT',
    'completed',
    'primary',
    1,
    v_source_ref,
    p_subscription_id,
    jsonb_build_object(
      'subscription_id', p_subscription_id::text,
      'subscriber_id', p_subscriber_id::text,
      'amount_kzt', p_amount_kzt,
      'commission_percent', 10
    )
  );
  
  RAISE NOTICE 'Created S1 L1 commission for user % amount % cents', v_sponsor_id, v_commission_amount;
END;
$$;