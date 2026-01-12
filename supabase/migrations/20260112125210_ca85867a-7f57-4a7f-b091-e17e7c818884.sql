-- Step 1: Fix award_s1_subscription_commission to use mlm_commission_rules
CREATE OR REPLACE FUNCTION award_s1_subscription_commission()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_subscriber_id uuid;
  v_subscription_id uuid;
  v_amount_kzt numeric;
  v_sponsor_id uuid;
  v_current_sponsor uuid;
  v_level int := 1;
  v_max_level int := 5;
  v_percent numeric;
  v_commission_cents int;
  v_direct_count int;
  v_required_referrals int;
  v_freeze_days int := 14;
BEGIN
  -- Only process when status changes to 'active'
  IF NEW.status <> 'active' OR OLD.status = 'active' THEN
    RETURN NEW;
  END IF;
  
  -- Skip test and marketing free subscriptions
  IF NEW.is_test = true OR NEW.is_marketing_free_access = true THEN
    RETURN NEW;
  END IF;
  
  v_subscriber_id := NEW.user_id;
  v_subscription_id := NEW.id;
  v_amount_kzt := NEW.amount_kzt;
  
  -- Get subscriber's sponsor
  SELECT sponsor_id INTO v_sponsor_id
  FROM profiles
  WHERE id = v_subscriber_id;
  
  IF v_sponsor_id IS NULL THEN
    RETURN NEW;
  END IF;
  
  v_current_sponsor := v_sponsor_id;
  
  -- Walk up the sponsor chain (max 5 levels)
  WHILE v_current_sponsor IS NOT NULL AND v_level <= v_max_level LOOP
    -- Get commission percent from mlm_commission_rules (structure_type 1 = S1)
    SELECT percent INTO v_percent
    FROM mlm_commission_rules
    WHERE structure_type = 1 
      AND level = v_level 
      AND is_active = true
    ORDER BY effective_from DESC
    LIMIT 1;
    
    -- Default to 10% if not configured
    v_percent := COALESCE(v_percent, 10);
    
    -- Calculate commission in cents (tenge * 100)
    v_commission_cents := ROUND(v_amount_kzt * v_percent);
    
    -- Check unlock requirements (level 1 = 0, level 2 = 1, etc.)
    v_required_referrals := v_level - 1;
    
    SELECT COUNT(*) INTO v_direct_count
    FROM profiles
    WHERE sponsor_id = v_current_sponsor
      AND is_active = true
      AND deleted_at IS NULL;
    
    -- Check if sponsor qualifies
    IF v_direct_count >= v_required_referrals THEN
      -- Check sponsor has active subscription and monthly activation
      IF EXISTS (
        SELECT 1 FROM profiles
        WHERE id = v_current_sponsor
          AND subscription_status = 'active'
          AND monthly_activation_completed = true
          AND is_active = true
          AND deleted_at IS NULL
      ) THEN
        -- Check for existing commission (prevent duplicates)
        IF NOT EXISTS (
          SELECT 1 FROM transactions
          WHERE user_id = v_current_sponsor
            AND source_id = v_subscription_id
            AND structure_type = 'primary'::structure_type
            AND level = v_level
            AND type = 'commission'
        ) THEN
          -- Create commission transaction
          INSERT INTO transactions (
            user_id,
            type,
            amount_cents,
            currency,
            status,
            structure_type,
            level,
            source_id,
            source_ref,
            frozen_until,
            payload
          ) VALUES (
            v_current_sponsor,
            'commission',
            v_commission_cents,
            'KZT',
            'frozen',
            'primary'::structure_type,
            v_level,
            v_subscription_id,
            'subscription',
            now() + (v_freeze_days || ' days')::interval,
            jsonb_build_object(
              'subscriber_id', v_subscriber_id,
              'subscription_id', v_subscription_id,
              'subscription_amount', v_amount_kzt,
              'percent', v_percent
            )
          );
        END IF;
      END IF;
    END IF;
    
    -- Move to next sponsor in chain
    SELECT sponsor_id INTO v_current_sponsor
    FROM profiles
    WHERE id = v_current_sponsor;
    
    v_level := v_level + 1;
  END LOOP;
  
  RETURN NEW;
END;
$$;

-- Step 2: Ensure trigger exists
DROP TRIGGER IF EXISTS trg_award_s1_subscription_commission ON subscriptions;

CREATE TRIGGER trg_award_s1_subscription_commission
AFTER UPDATE OF status ON subscriptions
FOR EACH ROW
WHEN (OLD.status IS DISTINCT FROM NEW.status AND NEW.status = 'active')
EXECUTE FUNCTION award_s1_subscription_commission();

-- Step 3: Backfill missing commissions safely
INSERT INTO transactions (
  user_id, type, amount_cents, currency, status, structure_type, level,
  source_id, source_ref, frozen_until, payload
)
SELECT 
  sponsor.id as user_id,
  'commission' as type,
  ROUND(s.amount_kzt * 10) as amount_cents,
  'KZT' as currency,
  'frozen' as status,
  'primary'::structure_type as structure_type,
  1 as level,
  s.id as source_id,
  'subscription' as source_ref,
  now() + interval '14 days' as frozen_until,
  jsonb_build_object(
    'subscriber_id', s.user_id,
    'subscription_id', s.id,
    'subscription_amount', s.amount_kzt,
    'percent', 10,
    'backfill', true,
    'backfill_date', now()
  ) as payload
FROM subscriptions s
JOIN profiles buyer ON buyer.id = s.user_id
JOIN profiles sponsor ON sponsor.id = buyer.sponsor_id
WHERE s.status = 'active'
  AND s.is_test = false
  AND (s.is_marketing_free_access = false OR s.is_marketing_free_access IS NULL)
  AND buyer.sponsor_id IS NOT NULL
  AND sponsor.subscription_status = 'active'
  AND sponsor.monthly_activation_completed = true
  AND sponsor.is_active = true
  AND sponsor.deleted_at IS NULL
  AND NOT EXISTS (
    SELECT 1 FROM transactions t
    WHERE t.source_id = s.id
      AND t.structure_type = 'primary'::structure_type
      AND t.level = 1
      AND t.type = 'commission'
  )
ON CONFLICT DO NOTHING;