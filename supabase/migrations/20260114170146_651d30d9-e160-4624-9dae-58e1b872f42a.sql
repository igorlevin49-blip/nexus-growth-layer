
-- Исправляем функцию backfill_missing_s1_commissions - порядок аргументов has_role
-- Правильный вызов: has_role(user_id, role), а не has_role(role, user_id)
CREATE OR REPLACE FUNCTION public.backfill_missing_s1_commissions(
  p_admin_id uuid,
  p_dry_run boolean DEFAULT true,
  p_sponsor_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rec RECORD;
  v_count integer := 0;
  v_skipped integer := 0;
  v_total_kzt bigint := 0;
  v_details jsonb := '[]'::jsonb;
  v_created_transaction_id uuid;
  v_freeze_days integer;
BEGIN
  -- Проверяем права админа (ИСПРАВЛЕНО: правильный порядок аргументов)
  IF NOT has_role(p_admin_id, 'admin') AND NOT has_role(p_admin_id, 'superadmin') THEN
    RETURN jsonb_build_object('success', false, 'error', 'Access denied: admin rights required');
  END IF;

  -- Получаем период заморозки
  SELECT COALESCE((value->>'days')::integer, 30)
  INTO v_freeze_days
  FROM mlm_settings
  WHERE key = 'commission_freeze_period';
  
  -- Если настройка не найдена, используем 30 дней
  IF v_freeze_days IS NULL THEN
    v_freeze_days := 30;
  END IF;

  -- Находим все подписки с пропущенными комиссиями
  FOR v_rec IN
    SELECT 
      s.id as subscription_id,
      s.user_id as subscriber_id,
      p_sub.full_name as subscriber_name,
      s.amount_kzt,
      s.paid_at,
      p_sub.sponsor_id,
      p_sp.full_name as sponsor_name,
      p_sp.email as sponsor_email,
      s.amount_kzt * 0.10 as expected_commission_kzt  -- 10% для S1 Level 1
    FROM subscriptions s
    JOIN profiles p_sub ON p_sub.id = s.user_id
    JOIN profiles p_sp ON p_sp.id = p_sub.sponsor_id
    WHERE s.status = 'active'
      AND s.paid_at IS NOT NULL
      AND p_sub.sponsor_id IS NOT NULL
      AND (p_sponsor_id IS NULL OR p_sub.sponsor_id = p_sponsor_id)
      -- Проверяем что комиссии нет ни по source_id, ни по payload
      AND NOT EXISTS (
        SELECT 1 FROM transactions t
        WHERE t.type = 'commission'
          AND t.structure_type = 'primary'
          AND t.level = 1
          AND t.user_id = p_sub.sponsor_id
          AND (t.source_id = s.id OR t.payload->>'subscription_id' = s.id::text)
      )
      -- Исключаем бесплатный маркетинг доступ
      AND COALESCE(s.is_marketing_free_access, false) = false
    ORDER BY s.paid_at
  LOOP
    v_count := v_count + 1;
    v_total_kzt := v_total_kzt + v_rec.expected_commission_kzt;
    
    IF NOT p_dry_run THEN
      INSERT INTO transactions (
        user_id,
        type,
        amount_cents,
        currency,
        status,
        level,
        structure_type,
        source_id,
        source_ref,
        frozen_until,
        payload,
        created_at,
        updated_at
      ) VALUES (
        v_rec.sponsor_id,
        'commission',
        v_rec.expected_commission_kzt,
        'KZT',
        'frozen',
        1,
        'primary',
        v_rec.subscription_id,
        'backfill:s1_commission',
        v_rec.paid_at + (v_freeze_days || ' days')::interval,
        jsonb_build_object(
          'subscription_id', v_rec.subscription_id,
          'subscriber_id', v_rec.subscriber_id,
          'subscriber_name', v_rec.subscriber_name,
          'subscription_amount_kzt', v_rec.amount_kzt,
          'commission_kzt', v_rec.expected_commission_kzt,
          'backfill_date', NOW()::text,
          'backfill_admin', p_admin_id
        ),
        v_rec.paid_at,
        NOW()
      )
      ON CONFLICT DO NOTHING
      RETURNING id INTO v_created_transaction_id;
      
      -- Если транзакция не создалась (duplicate), увеличиваем skipped
      IF v_created_transaction_id IS NULL THEN
        v_skipped := v_skipped + 1;
      END IF;
    END IF;
    
    v_details := v_details || jsonb_build_object(
      'subscription_id', v_rec.subscription_id,
      'sponsor_id', v_rec.sponsor_id,
      'sponsor_name', v_rec.sponsor_name,
      'sponsor_email', v_rec.sponsor_email,
      'subscriber_name', v_rec.subscriber_name,
      'subscription_amount_kzt', v_rec.amount_kzt,
      'commission_kzt', v_rec.expected_commission_kzt,
      'paid_at', v_rec.paid_at,
      'transaction_id', v_created_transaction_id
    );
  END LOOP;

  -- Логируем действие
  IF NOT p_dry_run AND v_count > 0 THEN
    INSERT INTO admin_audit (
      admin_id,
      action_type,
      target_type,
      target_id,
      metadata
    ) VALUES (
      p_admin_id,
      'backfill_s1_commissions',
      'system',
      COALESCE(p_sponsor_id::text, 'bulk'),
      jsonb_build_object(
        'commissions_created', v_count - v_skipped,
        'commissions_skipped', v_skipped,
        'total_kzt', v_total_kzt,
        'dry_run', p_dry_run
      )
    );
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'dry_run', p_dry_run,
    'subscriptions_processed', v_count,
    'commissions_created', v_count - v_skipped,
    'commissions_skipped', v_skipped,
    'total_kzt', v_total_kzt,
    'details', v_details
  );
END;
$$;

-- Добавляем комментарий
COMMENT ON FUNCTION public.backfill_missing_s1_commissions(uuid, boolean, uuid) IS 
'Backfill missing S1 commissions for subscriptions. Fixed has_role argument order.';
