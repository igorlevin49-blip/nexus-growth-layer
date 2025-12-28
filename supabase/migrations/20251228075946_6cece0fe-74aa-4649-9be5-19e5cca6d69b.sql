
-- Fix: Сначала удаляем constraint, потом создаём новый с user_id
ALTER TABLE transactions DROP CONSTRAINT unique_source_ref;

-- Create new unique constraint on (user_id, source_ref)
CREATE UNIQUE INDEX unique_user_source_ref ON public.transactions (user_id, source_ref) 
WHERE source_ref IS NOT NULL;

-- Also update the duplicate check in the trigger to be more specific
CREATE OR REPLACE FUNCTION public.award_s1_subscription_commission()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_subscriber_id UUID;
  v_amount_kzt NUMERIC;
  v_sponsor_id UUID;
  v_sponsor_direct_count INT;
  v_level INT := 1;
  v_max_level INT := 5;
  v_percent NUMERIC;
  v_commission_cents BIGINT;
  v_sponsor_status TEXT;
  v_sponsor_activated BOOLEAN;
  v_is_marketing_free BOOLEAN;
  v_unlock_levels JSONB;
  v_source_ref TEXT;
BEGIN
  -- Only process when subscription becomes active with payment
  IF NEW.status != 'active' OR NEW.paid_at IS NULL THEN
    RETURN NEW;
  END IF;
  
  v_source_ref := 'subscription:' || NEW.id;
  v_subscriber_id := NEW.user_id;
  v_amount_kzt := NEW.amount_kzt;
  v_is_marketing_free := COALESCE(NEW.is_marketing_free_access, false);
  
  -- Skip marketing free access subscriptions
  IF v_is_marketing_free THEN
    RETURN NEW;
  END IF;

  -- Get unlock levels settings
  SELECT value INTO v_unlock_levels
  FROM mlm_settings
  WHERE key = 'unlock_levels';
  
  IF v_unlock_levels IS NULL THEN
    v_unlock_levels := '{"l2": 3, "l3": 5, "l4": 8, "l5": 10}'::jsonb;
  END IF;

  -- Get first sponsor
  SELECT sponsor_id INTO v_sponsor_id
  FROM profiles
  WHERE id = v_subscriber_id;

  -- Loop through upline sponsors up to max level
  WHILE v_sponsor_id IS NOT NULL AND v_level <= v_max_level LOOP
    -- Check if commission already exists for THIS sponsor and THIS subscription
    IF EXISTS (
      SELECT 1 FROM transactions 
      WHERE source_ref = v_source_ref
        AND user_id = v_sponsor_id
        AND type = 'commission'
    ) THEN
      -- Already has commission, move to next sponsor
      SELECT sponsor_id INTO v_sponsor_id
      FROM profiles
      WHERE id = v_sponsor_id;
      v_level := v_level + 1;
      CONTINUE;
    END IF;

    -- Get sponsor status
    SELECT subscription_status, monthly_activation_completed
    INTO v_sponsor_status, v_sponsor_activated
    FROM profiles
    WHERE id = v_sponsor_id;

    -- Count only ACTIVE referrals for level unlock check
    SELECT COUNT(*) INTO v_sponsor_direct_count
    FROM referrals r
    JOIN profiles p ON r.referred_user_id = p.id
    WHERE r.referrer_id = v_sponsor_id
      AND r.structure_type = 1
      AND p.subscription_status = 'active'
      AND p.deleted_at IS NULL;

    -- Check level unlock requirements (levels 2-5 require certain number of active referrals)
    IF v_level > 1 THEN
      DECLARE
        v_required_referrals INT;
        v_level_key TEXT;
      BEGIN
        v_level_key := 'l' || v_level::text;
        v_required_referrals := COALESCE((v_unlock_levels->>v_level_key)::int, v_level);
        
        IF v_sponsor_direct_count < v_required_referrals THEN
          -- Level not unlocked, skip this sponsor
          SELECT sponsor_id INTO v_sponsor_id
          FROM profiles
          WHERE id = v_sponsor_id;
          v_level := v_level + 1;
          CONTINUE;
        END IF;
      END;
    END IF;

    -- Get commission percent for this level
    SELECT percent INTO v_percent
    FROM mlm_commission_rules
    WHERE structure_type = 1
      AND level = v_level
      AND plan_id = 'default'
      AND is_active = true
    ORDER BY effective_from DESC
    LIMIT 1;

    IF v_percent IS NULL THEN
      v_percent := 10;
    END IF;

    -- Calculate commission amount
    v_commission_cents := ROUND(v_amount_kzt * v_percent / 100);

    -- Create commission if sponsor is active and activated
    IF v_sponsor_status = 'active' AND COALESCE(v_sponsor_activated, false) = true AND v_commission_cents > 0 THEN
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
        frozen_until,
        payload
      ) VALUES (
        v_sponsor_id,
        'commission',
        v_commission_cents,
        'KZT',
        'frozen',
        'primary'::structure_type,
        v_level,
        v_source_ref,
        NEW.id,
        NOW() + INTERVAL '14 days',
        jsonb_build_object(
          'from_user_id', v_subscriber_id,
          'percent', v_percent,
          'base_amount', v_amount_kzt
        )
      );
    END IF;

    -- Move to next sponsor in upline
    SELECT sponsor_id INTO v_sponsor_id
    FROM profiles
    WHERE id = v_sponsor_id;
    
    v_level := v_level + 1;
  END LOOP;

  RETURN NEW;
END;
$$;
