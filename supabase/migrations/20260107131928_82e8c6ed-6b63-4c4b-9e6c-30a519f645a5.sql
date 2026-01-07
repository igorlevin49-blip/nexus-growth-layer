-- Drop functions that need parameter changes first
DROP FUNCTION IF EXISTS public.create_user_withdrawal(uuid, bigint, uuid);
DROP FUNCTION IF EXISTS public.admin_adjust_balance(uuid, uuid, bigint, text);

-- Recreate create_user_withdrawal function
CREATE FUNCTION public.create_user_withdrawal(
  p_user_id uuid,
  p_amount_kzt bigint,
  p_method_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_balance bigint;
  v_withdrawal_id uuid;
  v_transaction_id uuid;
BEGIN
  -- Get current available balance
  SELECT available_kzt INTO v_balance
  FROM get_user_balance(p_user_id);
  
  -- Check sufficient balance
  IF v_balance < p_amount_kzt THEN
    RETURN jsonb_build_object(
      'success', false,
      'message', 'Недостаточно средств на балансе'
    );
  END IF;
  
  -- Create withdrawal record
  INSERT INTO withdrawals (user_id, method_id, amount_kzt, fee_kzt, status)
  VALUES (p_user_id, p_method_id, p_amount_kzt, 0, 'pending')
  RETURNING id INTO v_withdrawal_id;
  
  -- Create withdrawal transaction (negative for balance)
  INSERT INTO transactions (user_id, type, amount_kzt, currency, status, source_ref)
  VALUES (p_user_id, 'withdrawal', p_amount_kzt, 'KZT', 'completed', v_withdrawal_id::text)
  RETURNING id INTO v_transaction_id;
  
  -- Link transaction to withdrawal
  UPDATE withdrawals SET transaction_id = v_transaction_id WHERE id = v_withdrawal_id;
  
  RETURN jsonb_build_object(
    'success', true,
    'withdrawal_id', v_withdrawal_id
  );
END;
$$;

-- Recreate admin_adjust_balance function
CREATE FUNCTION public.admin_adjust_balance(
  p_admin_id uuid,
  p_user_id uuid,
  p_amount_kzt bigint,
  p_reason text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_transaction_id uuid;
BEGIN
  -- Check admin role
  IF NOT EXISTS (
    SELECT 1 FROM user_roles 
    WHERE user_id = p_admin_id 
    AND role IN ('admin', 'superadmin')
  ) THEN
    RETURN jsonb_build_object('success', false, 'message', 'Unauthorized');
  END IF;

  -- Create adjustment transaction
  INSERT INTO transactions (
    user_id,
    type,
    amount_kzt,
    currency,
    status,
    payload
  ) VALUES (
    p_user_id,
    'adjustment',
    p_amount_kzt,
    'KZT',
    'completed',
    jsonb_build_object(
      'admin_id', p_admin_id,
      'reason', p_reason
    )
  )
  RETURNING id INTO v_transaction_id;

  -- Log admin action
  INSERT INTO admin_audit (
    admin_id,
    target_type,
    target_id,
    action_type,
    comment,
    metadata
  ) VALUES (
    p_admin_id,
    'user',
    p_user_id,
    'balance_adjustment',
    p_reason,
    jsonb_build_object('amount_kzt', p_amount_kzt, 'transaction_id', v_transaction_id)
  );

  RETURN jsonb_build_object(
    'success', true,
    'transaction_id', v_transaction_id
  );
END;
$$;

-- Update create_commission_transactions to use _kzt naming
CREATE OR REPLACE FUNCTION public.create_commission_transactions(
  p_source_user_id uuid,
  p_amount_kzt numeric,
  p_source_id uuid,
  p_source_ref text,
  p_structure_type integer DEFAULT 2
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_current_user_id uuid;
  v_level integer := 1;
  v_max_level integer;
  v_percent numeric;
  v_commission_kzt bigint;
  v_total_commissions integer := 0;
  v_freeze_days integer;
  v_frozen_until timestamptz;
  v_structure_type_enum structure_type;
  v_required_referrals integer;
  v_actual_referrals integer;
  v_source_subscription subscriptions%ROWTYPE;
BEGIN
  -- Convert integer to enum
  IF p_structure_type = 1 THEN
    v_structure_type_enum := 'primary';
  ELSE
    v_structure_type_enum := 'secondary';
  END IF;

  -- Get freeze period from settings
  SELECT COALESCE((value::text)::integer, 14)
  INTO v_freeze_days
  FROM mlm_settings
  WHERE key = 'commission_freeze_days';
  
  IF v_freeze_days IS NULL THEN
    v_freeze_days := 14;
  END IF;
  
  v_frozen_until := NOW() + (v_freeze_days || ' days')::interval;

  -- Get max level for this structure
  SELECT MAX(level) INTO v_max_level
  FROM mlm_commission_rules
  WHERE structure_type = p_structure_type
    AND is_active = true;

  -- For S1 (subscriptions), check if this is a marketing free access
  IF p_structure_type = 1 AND p_source_ref = 'subscription' THEN
    SELECT * INTO v_source_subscription
    FROM subscriptions
    WHERE id = p_source_id;
    
    IF v_source_subscription.is_marketing_free_access = true THEN
      RETURN jsonb_build_object(
        'success', true,
        'message', 'Skipped - marketing free access subscription',
        'commissions_created', 0
      );
    END IF;
  END IF;

  -- Start from the source user's sponsor
  SELECT sponsor_id INTO v_current_user_id
  FROM profiles
  WHERE id = p_source_user_id;

  -- Walk up the referral chain
  WHILE v_current_user_id IS NOT NULL AND v_level <= COALESCE(v_max_level, 10) LOOP
    -- Get commission percent for this level
    SELECT percent INTO v_percent
    FROM mlm_commission_rules
    WHERE structure_type = p_structure_type
      AND level = v_level
      AND is_active = true
    ORDER BY effective_from DESC
    LIMIT 1;

    IF v_percent IS NOT NULL AND v_percent > 0 THEN
      -- Check unlock level requirements
      SELECT COALESCE((value->>v_level::text)::integer, 0)
      INTO v_required_referrals
      FROM mlm_settings
      WHERE key = 'unlock_levels';
      
      -- Count actual active referrals
      SELECT COUNT(*)
      INTO v_actual_referrals
      FROM profiles
      WHERE sponsor_id = v_current_user_id
        AND is_active = true
        AND subscription_active = true;
      
      -- Only create commission if unlock requirements are met
      IF v_actual_referrals >= v_required_referrals THEN
        -- Calculate commission (amount_kzt stores whole KZT)
        v_commission_kzt := ROUND(p_amount_kzt * v_percent / 100);

        IF v_commission_kzt > 0 THEN
          -- Create frozen commission transaction
          INSERT INTO transactions (
            user_id,
            type,
            amount_kzt,
            currency,
            status,
            source_id,
            source_ref,
            level,
            structure_type,
            frozen_until,
            payload
          ) VALUES (
            v_current_user_id,
            'commission',
            v_commission_kzt,
            'KZT',
            'frozen',
            p_source_id,
            p_source_ref,
            v_level,
            v_structure_type_enum,
            v_frozen_until,
            jsonb_build_object(
              'source_user_id', p_source_user_id,
              'percent', v_percent,
              'base_amount_kzt', p_amount_kzt
            )
          );

          v_total_commissions := v_total_commissions + 1;
        END IF;
      END IF;
    END IF;

    -- Move to next level
    SELECT sponsor_id INTO v_current_user_id
    FROM profiles
    WHERE id = v_current_user_id;
    
    v_level := v_level + 1;
  END LOOP;

  RETURN jsonb_build_object(
    'success', true,
    'commissions_created', v_total_commissions
  );
END;
$$;