-- Fix #1: Create trigger to award S1 commission when subscription is paid
-- This handles both online and manual payment approvals with idempotency

CREATE OR REPLACE FUNCTION public.award_s1_subscription_commission()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sponsor_id UUID;
  v_commission_percent NUMERIC := 10; -- S1 default 10%
  v_commission_cents BIGINT;
  v_sponsor_is_active BOOLEAN;
  v_freeze_reason TEXT;
  v_unique_ref TEXT;
BEGIN
  -- Only process when subscription becomes active (paid)
  IF NEW.status = 'active' AND (OLD.status IS NULL OR OLD.status != 'active') THEN
    
    -- Get sponsor_id
    SELECT sponsor_id INTO v_sponsor_id
    FROM profiles
    WHERE id = NEW.user_id;
    
    -- Skip if no sponsor
    IF v_sponsor_id IS NULL THEN
      RETURN NEW;
    END IF;
    
    -- Calculate commission (10% of subscription amount)
    v_commission_cents := ROUND(NEW.amount_usd * v_commission_percent);
    
    -- Create unique reference for idempotency
    v_unique_ref := 'subscription_s1_' || NEW.id || '_sponsor_' || v_sponsor_id;
    
    -- Check if sponsor is active (has active subscription)
    SELECT (subscription_status = 'active') INTO v_sponsor_is_active
    FROM profiles
    WHERE id = v_sponsor_id;
    
    -- Determine if commission should be frozen
    IF NOT v_sponsor_is_active THEN
      v_freeze_reason := 'Sponsor subscription inactive';
    ELSE
      v_freeze_reason := NULL;
    END IF;
    
    -- Insert commission transaction (idempotent by source_ref unique constraint)
    INSERT INTO transactions (
      user_id,
      type,
      amount_cents,
      status,
      currency,
      source_id,
      source_ref,
      structure_type,
      level,
      frozen_until,
      payload
    ) VALUES (
      v_sponsor_id,
      'commission',
      v_commission_cents,
      'completed',
      'USD',
      NEW.id,
      v_unique_ref,
      'primary',
      1, -- S1 is level 1 (direct sponsor)
      CASE 
        WHEN v_freeze_reason IS NOT NULL THEN (NOW() + INTERVAL '999 years')
        ELSE NULL
      END,
      jsonb_build_object(
        'type', 'S1',
        'subscription_id', NEW.id,
        'payer_id', NEW.user_id,
        'amount_usd', NEW.amount_usd,
        'commission_percent', v_commission_percent,
        'freeze_reason', v_freeze_reason
      )
    ) ON CONFLICT (source_ref) DO NOTHING;
    
  END IF;
  
  RETURN NEW;
END;
$$;

-- Drop old trigger if exists and create new one
DROP TRIGGER IF EXISTS award_s1_on_subscription_paid ON subscriptions;
CREATE TRIGGER award_s1_on_subscription_paid
  AFTER INSERT OR UPDATE ON subscriptions
  FOR EACH ROW
  EXECUTE FUNCTION award_s1_subscription_commission();

-- Fix #2: Update get_network_stats to count from referrals table correctly
CREATE OR REPLACE FUNCTION public.get_network_stats(user_id_param uuid)
RETURNS TABLE(
  total_partners integer, 
  active_partners integer, 
  frozen_partners integer, 
  max_level integer, 
  new_this_month integer, 
  activations_this_month integer, 
  volume_this_month numeric, 
  commissions_this_month numeric
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  month_start TIMESTAMPTZ := DATE_TRUNC('month', NOW());
BEGIN
  RETURN QUERY
  WITH network AS (
    -- Get all partners from referrals table (structure_type = 1 for primary/S1)
    SELECT 
      r.referred_user_id as partner_id,
      p.subscription_status,
      p.monthly_activation_completed as monthly_activation_met,
      p.created_at,
      1 as level
    FROM referrals r
    JOIN profiles p ON p.id = r.referred_user_id
    WHERE r.referrer_id = user_id_param
      AND r.structure_type = 1
      AND (p.is_archived IS NULL OR p.is_archived = false)
      AND (p.deleted_at IS NULL)
      AND p.is_active = true
  )
  SELECT 
    -- Total partners (direct referrals)
    COUNT(DISTINCT n.partner_id)::INTEGER as total_partners,
    
    -- Active partners (with active subscription OR completed activation)
    COUNT(DISTINCT CASE 
      WHEN n.subscription_status = 'active' THEN n.partner_id
    END)::INTEGER as active_partners,
    
    -- Frozen partners
    COUNT(DISTINCT CASE 
      WHEN n.subscription_status = 'frozen' THEN n.partner_id 
    END)::INTEGER as frozen_partners,
    
    -- Max level (always 1 for direct referrals, but keeping for compatibility)
    COALESCE(MAX(n.level), 0)::INTEGER as max_level,
    
    -- New this month
    COUNT(DISTINCT CASE 
      WHEN n.created_at >= month_start THEN n.partner_id 
    END)::INTEGER as new_this_month,
    
    -- Activations this month (count of activation orders)
    COALESCE((
      SELECT COUNT(DISTINCT o.id)::INTEGER
      FROM orders o
      JOIN order_items oi ON oi.order_id = o.id
      JOIN network n2 ON n2.partner_id = o.user_id
      WHERE o.status = 'paid'
        AND oi.is_activation_snapshot = true
        AND o.created_at >= month_start
    ), 0) as activations_this_month,
    
    -- Volume this month
    COALESCE((
      SELECT SUM(oi.price_usd * oi.qty)
      FROM orders o
      JOIN order_items oi ON oi.order_id = o.id
      JOIN network n2 ON n2.partner_id = o.user_id
      WHERE o.status = 'paid'
        AND o.created_at >= month_start
    ), 0) as volume_this_month,
    
    -- Commissions this month (earned from this user's network)
    COALESCE((
      SELECT SUM(t.amount_cents) / 100.0
      FROM transactions t
      WHERE t.user_id = user_id_param
        AND t.type = 'commission'
        AND t.status = 'completed'
        AND t.created_at >= month_start
    ), 0) as commissions_this_month
  FROM network n;
END;
$$;

-- Fix #3: Function to unfreeze S1 commissions when sponsor becomes active
CREATE OR REPLACE FUNCTION public.unfreeze_sponsor_commissions()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- When profile becomes active, unfreeze their frozen S1 commissions
  IF NEW.subscription_status = 'active' AND (OLD.subscription_status IS NULL OR OLD.subscription_status != 'active') THEN
    
    UPDATE transactions
    SET 
      frozen_until = NULL,
      payload = payload || jsonb_build_object('unfrozen_at', NOW(), 'unfrozen_reason', 'Sponsor subscription activated')
    WHERE user_id = NEW.id
      AND type = 'commission'
      AND status = 'completed'
      AND frozen_until > NOW()
      AND (payload->>'type' = 'S1' OR payload->>'freeze_reason' LIKE '%Sponsor%');
      
  END IF;
  
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS unfreeze_on_activation ON profiles;
CREATE TRIGGER unfreeze_on_activation
  AFTER UPDATE ON profiles
  FOR EACH ROW
  EXECUTE FUNCTION unfreeze_sponsor_commissions();