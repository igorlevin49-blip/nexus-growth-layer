-- Add is_marketing_free_access flag to subscriptions
ALTER TABLE subscriptions 
ADD COLUMN is_marketing_free_access BOOLEAN DEFAULT false;

COMMENT ON COLUMN subscriptions.is_marketing_free_access IS 
'Бесплатный маркетинговый доступ — по этой подписке не начисляются комиссии S1';

-- Modify award_s1_subscription_commission to skip marketing free subscriptions
CREATE OR REPLACE FUNCTION public.award_s1_subscription_commission()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sponsor_id UUID;
  v_sponsor_active BOOLEAN;
  v_sponsor_name TEXT;
  v_commission_cents BIGINT;
  v_hold_days INTEGER := 7;
BEGIN
  IF NEW.status = 'active' AND (OLD.status IS NULL OR OLD.status != 'active') THEN
    
    -- Пропускаем маркетинговые подписки (бесплатный доступ)
    IF NEW.is_marketing_free_access = true THEN
      RETURN NEW;
    END IF;
    
    -- Получаем спонсора
    SELECT p.sponsor_id, p.full_name
    INTO v_sponsor_id, v_sponsor_name
    FROM profiles p
    WHERE p.id = NEW.user_id;
    
    IF v_sponsor_id IS NULL THEN
      RETURN NEW;
    END IF;
    
    -- Проверяем активность спонсора
    SELECT (subscription_active = true AND monthly_activation_completed = true)
    INTO v_sponsor_active
    FROM profiles
    WHERE id = v_sponsor_id;
    
    -- Рассчитываем комиссию S1 (10%)
    v_commission_cents := (NEW.amount_usd * 100 * 10 / 100)::BIGINT;
    
    -- Создаём начисление
    INSERT INTO transactions (
      user_id,
      type,
      amount_cents,
      status,
      currency,
      source_id,
      source_ref,
      level,
      structure_type,
      frozen_until,
      payload
    ) VALUES (
      v_sponsor_id,
      'commission',
      v_commission_cents,
      'completed',
      'USD',
      NEW.id,
      'subscription_' || NEW.id || '_s1',
      1,
      'primary',
      CASE 
        WHEN v_sponsor_active THEN NOW() + (v_hold_days || ' days')::INTERVAL
        ELSE NOW() + INTERVAL '365 days'
      END,
      jsonb_build_object(
        'type', 'S1',
        'subscription_id', NEW.id,
        'payer_id', NEW.user_id,
        'payer_name', v_sponsor_name,
        'percent', 10,
        'freeze_reason', CASE WHEN NOT v_sponsor_active THEN 'sponsor_inactive' ELSE NULL END
      )
    ) ON CONFLICT (source_ref) DO NOTHING;
  END IF;
  
  RETURN NEW;
END;
$$;

-- Create function to reverse marketing free commissions
CREATE OR REPLACE FUNCTION public.reverse_marketing_free_commissions(
  p_source_user_id UUID,
  p_admin_id UUID,
  p_comment TEXT DEFAULT ''
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_commission RECORD;
  v_total_reversed_cents BIGINT := 0;
  v_affected_users UUID[];
  v_reversal_count INT := 0;
BEGIN
  -- Проверка прав администратора
  IF NOT (has_role(p_admin_id, 'admin') OR has_role(p_admin_id, 'superadmin')) THEN
    RETURN jsonb_build_object('success', false, 'error', 'UNAUTHORIZED');
  END IF;

  -- Проверка: не проводилось ли уже обнуление для этого пользователя
  IF EXISTS (
    SELECT 1 FROM transactions 
    WHERE payload->>'reversal_source_user_id' = p_source_user_id::text
    AND payload->>'reversal_type' = 'marketing_free_access'
  ) THEN
    RETURN jsonb_build_object(
      'success', false, 
      'error', 'ALREADY_REVERSED',
      'message', 'Комиссии по этому пользователю уже были обнулены'
    );
  END IF;

  -- Находим все комиссии S1, где источник — данный пользователь
  FOR v_commission IN 
    SELECT 
      t.id,
      t.user_id AS recipient_id,
      t.amount_cents,
      t.source_id,
      t.source_ref
    FROM transactions t
    WHERE t.type = 'commission'
      AND t.structure_type = 'primary'
      AND t.payload->>'payer_id' = p_source_user_id::text
      AND t.payload->>'type' = 'S1'
      AND t.status = 'completed'
  LOOP
    -- Создаём корректирующую запись (reversal)
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
      payload
    ) VALUES (
      v_commission.recipient_id,
      'adjustment',
      v_commission.amount_cents,
      'completed',
      'USD',
      v_commission.source_id,
      'reversal_' || v_commission.id,
      'primary',
      1,
      jsonb_build_object(
        'reversal_type', 'marketing_free_access',
        'reversal_source_user_id', p_source_user_id,
        'original_commission_id', v_commission.id,
        'original_amount_cents', v_commission.amount_cents,
        'admin_id', p_admin_id,
        'comment', p_comment,
        'reversed_at', NOW()
      )
    );

    v_total_reversed_cents := v_total_reversed_cents + v_commission.amount_cents;
    v_reversal_count := v_reversal_count + 1;
    
    IF NOT (v_commission.recipient_id = ANY(v_affected_users)) THEN
      v_affected_users := array_append(v_affected_users, v_commission.recipient_id);
    END IF;
  END LOOP;

  -- Логируем в admin_actions
  INSERT INTO admin_actions (
    admin_id,
    action_type,
    target_type,
    target_id,
    metadata,
    comment
  ) VALUES (
    p_admin_id,
    'reverse_marketing_commissions',
    'user',
    p_source_user_id,
    jsonb_build_object(
      'total_reversed_cents', v_total_reversed_cents,
      'reversal_count', v_reversal_count,
      'affected_users', v_affected_users
    ),
    p_comment
  );

  RETURN jsonb_build_object(
    'success', true,
    'total_reversed_cents', v_total_reversed_cents,
    'reversal_count', v_reversal_count,
    'affected_users_count', coalesce(array_length(v_affected_users, 1), 0)
  );
END;
$$;