-- Fix: Correctly extract freeze_days from JSONB in create_commission_transactions function
-- The issue was: (value::text)::int fails because value is {"days": 14}
-- Fix: Use (value->>'days')::int to extract the integer value

CREATE OR REPLACE FUNCTION public.create_commission_transactions()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_user_id uuid;
  v_amount_kzt numeric;
  v_sponsor_id uuid;
  v_current_user uuid;
  v_level int := 1;
  v_percent numeric;
  v_commission_cents int;
  v_freeze_days int;
  v_frozen_until timestamptz;
  v_direct_referrals int;
  v_required_referrals int;
  v_source_ref text;
BEGIN
  -- Only process orders transitioning to 'paid' status
  IF NEW.status = 'paid' AND (OLD.status IS NULL OR OLD.status != 'paid') THEN
    v_user_id := NEW.user_id;
    v_amount_kzt := NEW.total_kzt;
    
    -- Get freeze period from settings (FIXED: properly extract from JSONB)
    SELECT COALESCE((value->>'days')::int, 14) INTO v_freeze_days
    FROM mlm_settings WHERE key = 'commission_freeze_period';
    
    IF v_freeze_days IS NULL THEN
      v_freeze_days := 14;
    END IF;
    
    v_frozen_until := now() + (v_freeze_days || ' days')::interval;
    v_source_ref := 'order:' || NEW.id;
    
    -- Get the user's sponsor
    SELECT sponsor_id INTO v_sponsor_id
    FROM profiles
    WHERE id = v_user_id;
    
    -- Traverse up the sponsor chain (up to 10 levels for P1-P10)
    v_current_user := v_sponsor_id;
    
    WHILE v_current_user IS NOT NULL AND v_level <= 10 LOOP
      -- Get commission percent for this level (structure_type = 2 for products)
      SELECT percent INTO v_percent
      FROM mlm_commission_rules
      WHERE structure_type = 2
        AND level = v_level
        AND is_active = true
      ORDER BY effective_from DESC
      LIMIT 1;
      
      IF v_percent IS NOT NULL AND v_percent > 0 THEN
        -- Check if user has enough direct referrals to unlock this level
        SELECT COALESCE(direct_referrals_count, 0) INTO v_direct_referrals
        FROM profiles WHERE id = v_current_user;
        
        -- Get required referrals for this level
        SELECT CASE 
          WHEN v_level = 1 THEN 0
          WHEN v_level = 2 THEN 2
          WHEN v_level = 3 THEN 3
          WHEN v_level = 4 THEN 4
          WHEN v_level = 5 THEN 5
          WHEN v_level = 6 THEN 6
          WHEN v_level = 7 THEN 7
          WHEN v_level = 8 THEN 8
          WHEN v_level = 9 THEN 9
          WHEN v_level = 10 THEN 10
          ELSE 999
        END INTO v_required_referrals;
        
        -- Only award commission if user has enough referrals
        IF v_direct_referrals >= v_required_referrals THEN
          -- Calculate commission in cents (tenge * 100)
          v_commission_cents := ROUND(v_amount_kzt * (v_percent / 100) * 100);
          
          IF v_commission_cents > 0 THEN
            -- Check if commission already exists for this source
            IF NOT EXISTS (
              SELECT 1 FROM transactions 
              WHERE source_ref = v_source_ref 
                AND user_id = v_current_user
                AND level = v_level
            ) THEN
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
                v_current_user,
                'commission',
                v_commission_cents,
                'KZT',
                'frozen',
                'secondary',
                v_level,
                NEW.id,
                v_source_ref,
                v_frozen_until,
                jsonb_build_object(
                  'order_id', NEW.id,
                  'order_amount_kzt', v_amount_kzt,
                  'buyer_id', v_user_id,
                  'percent', v_percent,
                  'freeze_days', v_freeze_days
                )
              );
            END IF;
          END IF;
        END IF;
      END IF;
      
      -- Move to next sponsor
      SELECT sponsor_id INTO v_current_user
      FROM profiles
      WHERE id = v_current_user;
      
      v_level := v_level + 1;
    END LOOP;
  END IF;
  
  RETURN NEW;
END;
$function$;