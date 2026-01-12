-- ============================================
-- HOTFIX: Fix create_commission_transactions trigger function
-- Problem: ON CONFLICT references non-existent constraint unique_source_ref
-- Solution: Use ON CONFLICT (user_id, source_ref) to match existing index
-- ============================================

-- First, find and drop the trigger version of create_commission_transactions
DROP FUNCTION IF EXISTS create_commission_transactions() CASCADE;

-- Recreate the trigger function with fixed ON CONFLICT clause
CREATE OR REPLACE FUNCTION create_commission_transactions()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_buyer_id uuid;
  v_order_amount_kzt numeric;
  v_current_user_id uuid;
  v_current_level integer := 1;
  v_percent numeric;
  v_commission_amount numeric;
  v_freeze_days integer;
  v_frozen_until timestamptz;
  v_max_levels integer := 10;
  v_has_activation_items boolean;
BEGIN
  -- Only process when status changes to 'paid'
  IF NEW.status = 'paid' AND (OLD.status IS NULL OR OLD.status != 'paid') THEN
    v_buyer_id := NEW.user_id;
    v_order_amount_kzt := NEW.total_kzt;
    
    -- Check if order has activation items
    SELECT EXISTS (
      SELECT 1 FROM order_items oi
      JOIN products p ON p.id = oi.product_id
      WHERE oi.order_id = NEW.id AND p.is_activation = true
    ) INTO v_has_activation_items;
    
    -- Get freeze days from settings
    SELECT COALESCE((value::text)::integer, 14)
    INTO v_freeze_days
    FROM mlm_settings
    WHERE key = 'commission_freeze_days';
    
    IF v_freeze_days IS NULL THEN
      v_freeze_days := 14;
    END IF;
    
    v_frozen_until := NOW() + (v_freeze_days || ' days')::interval;
    
    -- Start from buyer's sponsor
    SELECT sponsor_id INTO v_current_user_id
    FROM profiles
    WHERE id = v_buyer_id;
    
    -- Walk up the referral chain (S2 - secondary structure)
    WHILE v_current_user_id IS NOT NULL AND v_current_level <= v_max_levels LOOP
      BEGIN
        -- Get commission percent for this level
        SELECT percent INTO v_percent
        FROM mlm_commission_rules
        WHERE structure_type = 2
          AND level = v_current_level
          AND is_active = true
        ORDER BY effective_from DESC
        LIMIT 1;
        
        IF v_percent IS NOT NULL AND v_percent > 0 THEN
          v_commission_amount := ROUND(v_order_amount_kzt * v_percent / 100);
          
          IF v_commission_amount > 0 THEN
            -- Insert commission with fixed ON CONFLICT clause
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
              v_current_user_id,
              'commission',
              v_commission_amount,
              'KZT',
              'frozen',
              v_frozen_until,
              NEW.id,
              'order:' || NEW.id::text,
              v_current_level,
              'secondary'::structure_type,
              jsonb_build_object(
                'order_id', NEW.id,
                'buyer_id', v_buyer_id,
                'order_amount', v_order_amount_kzt,
                'percent', v_percent,
                'level', v_current_level
              )
            )
            ON CONFLICT (user_id, source_ref) WHERE source_ref IS NOT NULL DO NOTHING;
          END IF;
        END IF;
      EXCEPTION WHEN OTHERS THEN
        -- Log error but don't fail the transaction
        RAISE LOG 'Error creating commission for user % level %: %', v_current_user_id, v_current_level, SQLERRM;
      END;
      
      -- Move to next level
      SELECT sponsor_id INTO v_current_user_id
      FROM profiles
      WHERE id = v_current_user_id;
      
      v_current_level := v_current_level + 1;
    END LOOP;
  END IF;
  
  RETURN NEW;
END;
$$;

-- Recreate trigger on orders table
DROP TRIGGER IF EXISTS trg_create_commission_transactions ON orders;

CREATE TRIGGER trg_create_commission_transactions
  AFTER UPDATE ON orders
  FOR EACH ROW
  EXECUTE FUNCTION create_commission_transactions();