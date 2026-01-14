
-- Исправляем функцию backfill_missing_multilevel_commissions
-- 1. Убираем временную таблицу (не работает через read-only RPC)
-- 2. Исправляем structure_type: 'S1' → 'primary'
CREATE OR REPLACE FUNCTION public.backfill_missing_multilevel_commissions(
  p_admin_id uuid,
  p_dry_run boolean DEFAULT true,
  p_target_user_id uuid DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_created_count integer := 0;
  v_skipped_count integer := 0;
  v_total_amount_kzt numeric := 0;
  v_commission_record record;
  v_recipient record;
  v_percent numeric;
  v_commission_amount_kzt numeric;
  v_freeze_days integer := 30;
  v_new_tx_id uuid;
BEGIN
  -- Check admin access
  IF NOT EXISTS (
    SELECT 1 FROM user_roles 
    WHERE user_id = p_admin_id AND role IN ('admin', 'superadmin')
  ) THEN
    RETURN json_build_object('success', false, 'error', 'Unauthorized');
  END IF;

  -- Find subscriptions that need multilevel commissions
  FOR v_commission_record IN
    SELECT 
      s.id AS subscription_id,
      s.user_id AS subscriber_id,
      s.amount_kzt,
      s.paid_at,
      p.sponsor_id,
      p.full_name AS subscriber_name
    FROM subscriptions s
    INNER JOIN profiles p ON p.id = s.user_id
    WHERE s.status = 'active'
      AND s.paid_at IS NOT NULL
      AND s.is_marketing_free_access IS NOT TRUE
      AND (p_target_user_id IS NULL OR p.sponsor_id = p_target_user_id)
    ORDER BY s.paid_at
  LOOP
    -- Traverse upline for levels 1-5
    FOR v_recipient IN
      WITH RECURSIVE upline AS (
        SELECT 
          p.id AS user_id,
          p.sponsor_id,
          p.full_name,
          p.email,
          1 AS level
        FROM profiles p
        WHERE p.id = v_commission_record.sponsor_id
        
        UNION ALL
        
        SELECT 
          p.id,
          p.sponsor_id,
          p.full_name,
          p.email,
          u.level + 1
        FROM profiles p
        INNER JOIN upline u ON p.id = u.sponsor_id
        WHERE u.level < 5
      )
      SELECT * FROM upline
    LOOP
      -- Get percentage for this level from mlm_commission_rules
      SELECT percent INTO v_percent 
      FROM mlm_commission_rules 
      WHERE structure_type = 1 
        AND plan_id = 'default' 
        AND is_active = true
        AND level = v_recipient.level;
      
      IF v_percent IS NULL OR v_percent = 0 THEN
        CONTINUE;
      END IF;
      
      v_commission_amount_kzt := ROUND(v_commission_record.amount_kzt * v_percent / 100);
      
      -- Check if commission already exists (ИСПРАВЛЕНО: 'primary' вместо 'S1')
      IF EXISTS (
        SELECT 1 FROM transactions t
        WHERE t.user_id = v_recipient.user_id
          AND t.source_id = v_commission_record.subscription_id
          AND t.level = v_recipient.level
          AND t.type = 'commission'
          AND t.structure_type = 'primary'
      ) THEN
        v_skipped_count := v_skipped_count + 1;
        CONTINUE;
      END IF;
      
      -- Create commission if not dry run
      IF NOT p_dry_run THEN
        INSERT INTO transactions (
          user_id, type, amount_cents, currency, status,
          source_id, source_ref, level, structure_type,
          frozen_until, payload
        ) VALUES (
          v_recipient.user_id, 'commission', v_commission_amount_kzt, 'KZT', 'frozen',
          v_commission_record.subscription_id, 'subscription', v_recipient.level, 'primary',
          NOW() + (v_freeze_days || ' days')::interval,
          jsonb_build_object(
            'backfill', true,
            'admin_id', p_admin_id,
            'subscriber_id', v_commission_record.subscriber_id,
            'subscriber_name', v_commission_record.subscriber_name,
            'subscription_amount_kzt', v_commission_record.amount_kzt,
            'percent', v_percent
          )
        )
        RETURNING id INTO v_new_tx_id;
      END IF;
      
      v_created_count := v_created_count + 1;
      v_total_amount_kzt := v_total_amount_kzt + v_commission_amount_kzt;
    END LOOP;
  END LOOP;

  RETURN json_build_object(
    'success', true,
    'dry_run', p_dry_run,
    'subscriptions_processed', v_created_count + v_skipped_count,
    'commissions_created', v_created_count,
    'commissions_skipped', v_skipped_count,
    'total_kzt', v_total_amount_kzt
  );
END;
$$;

COMMENT ON FUNCTION public.backfill_missing_multilevel_commissions(uuid, boolean, uuid) IS 
'Backfill missing multilevel commissions. Fixed: removed temp table, corrected structure_type to primary.';
