
-- Исправляем функцию - используем amount_kzt вместо amount
CREATE OR REPLACE FUNCTION public.backfill_missing_multilevel_commissions(
  p_admin_id UUID,
  p_dry_run BOOLEAN DEFAULT TRUE,
  p_target_user_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin_role TEXT;
  v_sub RECORD;
  v_sponsor_id UUID;
  v_current_id UUID;
  v_level INT;
  v_commission_rate NUMERIC;
  v_commission_amount NUMERIC;
  v_required_referrals INT;
  v_active_referrals INT;
  v_sponsor_active BOOLEAN;
  v_existing_commission UUID;
  v_frozen_until TIMESTAMPTZ;
  v_subscriptions_processed INT := 0;
  v_commissions_created INT := 0;
  v_commissions_skipped INT := 0;
  v_total_amount NUMERIC := 0;
  v_details JSONB := '[]'::JSONB;
  v_subscriber_name TEXT;
  v_sponsor_name TEXT;
BEGIN
  -- Проверка прав администратора
  SELECT role INTO v_admin_role FROM user_roles WHERE user_id = p_admin_id;
  IF v_admin_role NOT IN ('admin', 'superadmin') THEN
    RAISE EXCEPTION 'Недостаточно прав для выполнения операции';
  END IF;

  FOR v_sub IN 
    SELECT 
      s.id AS subscription_id,
      s.user_id AS subscriber_id,
      s.amount_kzt AS amount,
      s.paid_at,
      p.full_name AS subscriber_name,
      p.sponsor_id AS direct_sponsor_id
    FROM subscriptions s
    JOIN profiles p ON p.id = s.user_id
    WHERE s.status = 'active'
      AND s.paid_at IS NOT NULL
      AND p.sponsor_id IS NOT NULL
      AND (p_target_user_id IS NULL OR EXISTS (
        WITH RECURSIVE sponsor_chain AS (
          SELECT id, sponsor_id, 1 as lvl FROM profiles WHERE id = s.user_id
          UNION ALL
          SELECT p2.id, p2.sponsor_id, sc.lvl + 1
          FROM profiles p2
          JOIN sponsor_chain sc ON p2.id = sc.sponsor_id
          WHERE sc.lvl < 6
        )
        SELECT 1 FROM sponsor_chain WHERE sponsor_id = p_target_user_id
      ))
    ORDER BY s.paid_at
  LOOP
    v_subscriptions_processed := v_subscriptions_processed + 1;
    v_subscriber_name := v_sub.subscriber_name;
    
    v_current_id := v_sub.direct_sponsor_id;
    
    FOR v_level IN 2..5 LOOP
      SELECT sponsor_id INTO v_sponsor_id FROM profiles WHERE id = v_current_id;
      
      IF v_sponsor_id IS NULL THEN EXIT; END IF;
      
      IF p_target_user_id IS NULL OR v_sponsor_id = p_target_user_id THEN
        SELECT full_name INTO v_sponsor_name FROM profiles WHERE id = v_sponsor_id;
        
        SELECT id INTO v_existing_commission
        FROM transactions
        WHERE user_id = v_sponsor_id
          AND type = 'commission'
          AND payload->>'subscription_id' = v_sub.subscription_id::TEXT
          AND payload->>'level' = v_level::TEXT;
        
        IF v_existing_commission IS NULL THEN
          CASE v_level
            WHEN 2 THEN v_commission_rate := 0.05; v_required_referrals := 2;
            WHEN 3 THEN v_commission_rate := 0.05; v_required_referrals := 3;
            WHEN 4 THEN v_commission_rate := 0.05; v_required_referrals := 4;
            WHEN 5 THEN v_commission_rate := 0.05; v_required_referrals := 5;
            ELSE v_commission_rate := 0; v_required_referrals := 999;
          END CASE;
          
          SELECT EXISTS (
            SELECT 1 FROM subscriptions
            WHERE user_id = v_sponsor_id AND status = 'active' AND paid_at <= v_sub.paid_at
          ) INTO v_sponsor_active;
          
          SELECT COUNT(*) INTO v_active_referrals
          FROM profiles p2
          JOIN subscriptions s2 ON s2.user_id = p2.id
          WHERE p2.sponsor_id = v_sponsor_id
            AND s2.status = 'active'
            AND s2.paid_at <= v_sub.paid_at;
          
          IF v_sponsor_active AND v_active_referrals >= v_required_referrals THEN
            v_commission_amount := v_sub.amount * v_commission_rate;
            v_frozen_until := v_sub.paid_at + INTERVAL '1 month';
            
            IF NOT p_dry_run THEN
              INSERT INTO transactions (
                user_id, type, amount_cents, status, frozen_until, payload, created_at
              ) VALUES (
                v_sponsor_id, 'commission', v_commission_amount,
                CASE WHEN v_frozen_until > NOW() THEN 'frozen' ELSE 'completed' END,
                v_frozen_until,
                jsonb_build_object(
                  'commission_type', 'S1', 'level', v_level,
                  'subscription_id', v_sub.subscription_id,
                  'subscriber_id', v_sub.subscriber_id,
                  'subscriber_name', v_subscriber_name,
                  'subscription_amount', v_sub.amount,
                  'rate', v_commission_rate,
                  'backfill', true, 'backfill_date', NOW()
                )
              );
            END IF;
            
            v_commissions_created := v_commissions_created + 1;
            v_total_amount := v_total_amount + v_commission_amount;
            
            v_details := v_details || jsonb_build_object(
              'subscription_id', v_sub.subscription_id,
              'subscriber_name', v_subscriber_name,
              'sponsor_id', v_sponsor_id,
              'sponsor_name', v_sponsor_name,
              'level', v_level,
              'amount_kzt', v_commission_amount
            );
          ELSE
            v_commissions_skipped := v_commissions_skipped + 1;
          END IF;
        ELSE
          v_commissions_skipped := v_commissions_skipped + 1;
        END IF;
      END IF;
      
      v_current_id := v_sponsor_id;
    END LOOP;
  END LOOP;
  
  IF NOT p_dry_run AND v_commissions_created > 0 THEN
    INSERT INTO activity_log (user_id, action, details)
    VALUES (p_admin_id, 'backfill_multilevel_commissions',
      jsonb_build_object(
        'target_user_id', p_target_user_id,
        'subscriptions_processed', v_subscriptions_processed,
        'commissions_created', v_commissions_created,
        'commissions_skipped', v_commissions_skipped,
        'total_amount_kzt', v_total_amount
      )
    );
  END IF;
  
  RETURN jsonb_build_object(
    'success', true, 'dry_run', p_dry_run,
    'subscriptions_processed', v_subscriptions_processed,
    'commissions_created', v_commissions_created,
    'commissions_skipped', v_commissions_skipped,
    'total_kzt', v_total_amount,
    'details', CASE WHEN jsonb_array_length(v_details) <= 100 THEN v_details ELSE '[]'::JSONB END
  );
END;
$$;
