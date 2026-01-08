
-- ============================================
-- ЧАСТЬ A: Создать функцию для подсчёта личников НА МОМЕНТ времени
-- ============================================
CREATE OR REPLACE FUNCTION count_direct_referrals_at_time(
  p_user_id uuid,
  p_at_time timestamptz
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_count integer;
BEGIN
  -- Считаем личников, которые активировали подписку ДО указанного времени
  SELECT COUNT(DISTINCT p.id)
  INTO v_count
  FROM profiles p
  JOIN subscriptions s ON s.user_id = p.id
  WHERE p.sponsor_id = p_user_id
    AND p.deleted_at IS NULL
    AND s.status = 'active'
    AND s.paid_at <= p_at_time;
  
  RETURN COALESCE(v_count, 0);
END;
$$;

-- ============================================
-- ЧАСТЬ B: Обновить backfill_missing_s1_commissions
-- Добавить проверку unlock requirements НА МОМЕНТ активации подписки
-- ============================================
CREATE OR REPLACE FUNCTION public.backfill_missing_s1_commissions(p_admin_id uuid, p_days_back integer DEFAULT 30)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_result json;
  v_subscriptions_processed integer := 0;
  v_commissions_created integer := 0;
  v_commissions_skipped integer := 0;
  v_sub record;
  v_ancestor record;
  v_level_counter integer;
  v_commission_amount numeric;
  v_commission_percent numeric;
  v_freeze_days integer;
  v_existing_count integer;
  v_required_referrals integer;
  v_actual_referrals integer;
  v_unlock_settings jsonb;
BEGIN
  -- Check admin role
  IF NOT (has_role(p_admin_id, 'admin') OR has_role(p_admin_id, 'superadmin')) THEN
    RAISE EXCEPTION 'Access denied: admin role required';
  END IF;

  -- Get freeze period
  SELECT COALESCE((value->>'days')::integer, 14) INTO v_freeze_days
  FROM mlm_settings WHERE key = 'commission_freeze_period';
  
  IF v_freeze_days IS NULL THEN
    v_freeze_days := 14;
  END IF;
  
  -- Get unlock settings
  SELECT value INTO v_unlock_settings
  FROM mlm_settings WHERE key = 'unlock_levels';

  -- Process all active subscriptions from last N days that may be missing commissions
  FOR v_sub IN
    SELECT s.id as subscription_id, 
           s.user_id as subscriber_id, 
           s.amount_kzt,
           s.paid_at,
           s.is_marketing_free_access,
           p.sponsor_id,
           p.full_name as subscriber_name
    FROM subscriptions s
    JOIN profiles p ON p.id = s.user_id
    WHERE s.status = 'active'
      AND s.paid_at > NOW() - (p_days_back || ' days')::interval
      AND s.is_marketing_free_access = false
      AND p.deleted_at IS NULL
    ORDER BY s.paid_at ASC
  LOOP
    v_subscriptions_processed := v_subscriptions_processed + 1;
    
    -- Walk up the sponsor chain for up to 5 levels
    v_level_counter := 0;
    
    -- Start from subscriber's sponsor
    FOR v_ancestor IN
      WITH RECURSIVE sponsor_chain AS (
        SELECT id, sponsor_id, is_active, subscription_status, full_name, 1 as chain_level
        FROM profiles
        WHERE id = v_sub.sponsor_id AND deleted_at IS NULL
        
        UNION ALL
        
        SELECT p.id, p.sponsor_id, p.is_active, p.subscription_status, p.full_name, sc.chain_level + 1
        FROM profiles p
        JOIN sponsor_chain sc ON p.id = sc.sponsor_id
        WHERE sc.chain_level < 5 AND p.deleted_at IS NULL
      )
      SELECT * FROM sponsor_chain ORDER BY chain_level
    LOOP
      v_level_counter := v_ancestor.chain_level;
      
      -- Skip if ancestor not active
      IF NOT v_ancestor.is_active OR v_ancestor.subscription_status != 'active' THEN
        v_commissions_skipped := v_commissions_skipped + 1;
        CONTINUE;
      END IF;
      
      -- ====== НОВАЯ ПРОВЕРКА: unlock requirements на момент подписки ======
      -- Получить требования для этого уровня
      v_required_referrals := CASE v_level_counter
        WHEN 1 THEN 0  -- Уровень 1 всегда открыт
        WHEN 2 THEN COALESCE((v_unlock_settings->>'l2')::integer, 3)
        WHEN 3 THEN COALESCE((v_unlock_settings->>'l3')::integer, 5)
        WHEN 4 THEN COALESCE((v_unlock_settings->>'l4')::integer, 7)
        WHEN 5 THEN COALESCE((v_unlock_settings->>'l5')::integer, 10)
        ELSE 999
      END;
      
      -- Посчитать личников НА МОМЕНТ активации подписки
      v_actual_referrals := count_direct_referrals_at_time(v_ancestor.id, v_sub.paid_at);
      
      -- Пропустить если уровень не был разблокирован на тот момент
      IF v_actual_referrals < v_required_referrals THEN
        v_commissions_skipped := v_commissions_skipped + 1;
        CONTINUE;
      END IF;
      -- ====== КОНЕЦ НОВОЙ ПРОВЕРКИ ======
      
      -- Get commission percent for this level
      SELECT percent INTO v_commission_percent
      FROM mlm_commission_rules
      WHERE structure_type = 1 
        AND level = v_level_counter 
        AND is_active = true
      LIMIT 1;
      
      IF v_commission_percent IS NULL OR v_commission_percent <= 0 THEN
        CONTINUE;
      END IF;
      
      -- Check if commission already exists
      SELECT COUNT(*) INTO v_existing_count
      FROM transactions
      WHERE source_id = v_sub.subscription_id
        AND user_id = v_ancestor.id
        AND type = 'commission'
        AND structure_type = 'primary';
      
      IF v_existing_count > 0 THEN
        v_commissions_skipped := v_commissions_skipped + 1;
        CONTINUE;
      END IF;
      
      -- Calculate commission (amount is already in KZT)
      v_commission_amount := ROUND(v_sub.amount_kzt * v_commission_percent / 100);
      
      IF v_commission_amount <= 0 THEN
        CONTINUE;
      END IF;
      
      -- Insert the commission transaction
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
        payload
      ) VALUES (
        v_ancestor.id,
        'commission',
        v_commission_amount,
        'KZT',
        'frozen',
        v_level_counter,
        'primary',
        v_sub.subscription_id,
        'subscription:' || v_sub.subscription_id,
        v_sub.paid_at + (v_freeze_days || ' days')::interval,
        jsonb_build_object(
          'base_amount', v_sub.amount_kzt,
          'percent', v_commission_percent,
          'subscriber_id', v_sub.subscriber_id,
          'backfill', true,
          'referrals_at_time', v_actual_referrals,
          'required_referrals', v_required_referrals
        )
      );
      
      v_commissions_created := v_commissions_created + 1;
    END LOOP;
  END LOOP;

  v_result := json_build_object(
    'success', true,
    'subscriptions_processed', v_subscriptions_processed,
    'commissions_created', v_commissions_created,
    'commissions_skipped', v_commissions_skipped
  );

  RETURN v_result;
END;
$function$;

-- ============================================
-- ЧАСТЬ C: Создать функцию для аудита и исправления "ранних" комиссий
-- ============================================
CREATE OR REPLACE FUNCTION admin_find_early_unlock_commissions(
  p_admin_id uuid,
  p_days_back integer DEFAULT 90
)
RETURNS TABLE(
  transaction_id uuid,
  user_id uuid,
  user_name text,
  level integer,
  amount_cents integer,
  structure_type text,
  source_id uuid,
  subscriber_name text,
  subscription_paid_at timestamptz,
  required_referrals integer,
  actual_referrals_at_time integer,
  status text,
  created_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_unlock_settings jsonb;
BEGIN
  -- Check admin role
  IF NOT (has_role(p_admin_id, 'admin') OR has_role(p_admin_id, 'superadmin')) THEN
    RAISE EXCEPTION 'Access denied: admin role required';
  END IF;
  
  -- Get unlock settings
  SELECT value INTO v_unlock_settings
  FROM mlm_settings WHERE key = 'unlock_levels';

  RETURN QUERY
  WITH commission_data AS (
    SELECT 
      t.id as t_id,
      t.user_id as t_user_id,
      p.full_name as t_user_name,
      t.level as t_level,
      t.amount_cents as t_amount_cents,
      t.structure_type::text as t_structure_type,
      t.source_id as t_source_id,
      t.status as t_status,
      t.created_at as t_created_at,
      -- Для S1 (primary) берём подписку, для S2 (secondary) - заказ
      CASE 
        WHEN t.structure_type = 'primary' THEN s.paid_at
        ELSE o.created_at
      END as source_paid_at,
      CASE 
        WHEN t.structure_type = 'primary' THEN sp.full_name
        ELSE op.full_name
      END as src_subscriber_name,
      -- Требования для уровня
      CASE t.level
        WHEN 1 THEN 0
        WHEN 2 THEN COALESCE((v_unlock_settings->>'l2')::integer, 3)
        WHEN 3 THEN COALESCE((v_unlock_settings->>'l3')::integer, 5)
        WHEN 4 THEN COALESCE((v_unlock_settings->>'l4')::integer, 7)
        WHEN 5 THEN COALESCE((v_unlock_settings->>'l5')::integer, 10)
        WHEN 6 THEN COALESCE((v_unlock_settings->>'l6')::integer, 6)
        WHEN 7 THEN COALESCE((v_unlock_settings->>'l7')::integer, 7)
        WHEN 8 THEN COALESCE((v_unlock_settings->>'l8')::integer, 8)
        WHEN 9 THEN COALESCE((v_unlock_settings->>'l9')::integer, 9)
        WHEN 10 THEN COALESCE((v_unlock_settings->>'l10')::integer, 10)
        ELSE 999
      END as req_referrals
    FROM transactions t
    JOIN profiles p ON p.id = t.user_id
    LEFT JOIN subscriptions s ON s.id = t.source_id AND t.structure_type = 'primary'
    LEFT JOIN profiles sp ON sp.id = s.user_id
    LEFT JOIN orders o ON o.id = t.source_id AND t.structure_type = 'secondary'
    LEFT JOIN profiles op ON op.id = o.user_id
    WHERE t.type = 'commission'
      AND t.level >= 2  -- Уровень 1 всегда открыт
      AND t.created_at > NOW() - (p_days_back || ' days')::interval
      AND p.deleted_at IS NULL
  )
  SELECT 
    cd.t_id,
    cd.t_user_id,
    cd.t_user_name,
    cd.t_level,
    cd.t_amount_cents,
    cd.t_structure_type,
    cd.t_source_id,
    cd.src_subscriber_name,
    cd.source_paid_at,
    cd.req_referrals,
    count_direct_referrals_at_time(cd.t_user_id, cd.source_paid_at) as actual_refs,
    cd.t_status,
    cd.t_created_at
  FROM commission_data cd
  WHERE cd.source_paid_at IS NOT NULL
    AND count_direct_referrals_at_time(cd.t_user_id, cd.source_paid_at) < cd.req_referrals;
END;
$$;

-- Функция для исправления ранних комиссий
CREATE OR REPLACE FUNCTION admin_fix_early_unlock_commissions(
  p_admin_id uuid,
  p_dry_run boolean DEFAULT true,
  p_days_back integer DEFAULT 90
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_result json;
  v_violations_found integer := 0;
  v_violations_fixed integer := 0;
  v_total_amount_fixed integer := 0;
  v_rec record;
  v_violation record;
BEGIN
  -- Check admin role
  IF NOT (has_role(p_admin_id, 'admin') OR has_role(p_admin_id, 'superadmin')) THEN
    RAISE EXCEPTION 'Access denied: admin role required';
  END IF;

  -- Найти все нарушения
  FOR v_rec IN 
    SELECT * FROM admin_find_early_unlock_commissions(p_admin_id, p_days_back)
  LOOP
    v_violations_found := v_violations_found + 1;
    v_total_amount_fixed := v_total_amount_fixed + v_rec.amount_cents;
    
    IF NOT p_dry_run THEN
      -- Для frozen комиссий - просто помечаем как failed
      IF v_rec.status = 'frozen' THEN
        UPDATE transactions 
        SET status = 'failed',
            payload = COALESCE(payload, '{}'::jsonb) || jsonb_build_object(
              'early_unlock_fix', true,
              'fixed_at', now(),
              'fixed_by', p_admin_id,
              'reason', 'Level ' || v_rec.level || ' was not unlocked at subscription time. Had ' || 
                        v_rec.actual_referrals_at_time || ' referrals, needed ' || v_rec.required_referrals
            )
        WHERE id = v_rec.transaction_id;
        
        v_violations_fixed := v_violations_fixed + 1;
        
      -- Для completed комиссий - нужно откатить баланс
      ELSIF v_rec.status = 'completed' THEN
        -- Уменьшить баланс пользователя
        UPDATE profiles 
        SET balance_cents = balance_cents - v_rec.amount_cents
        WHERE id = v_rec.user_id;
        
        -- Пометить транзакцию как failed
        UPDATE transactions 
        SET status = 'failed',
            payload = COALESCE(payload, '{}'::jsonb) || jsonb_build_object(
              'early_unlock_fix', true,
              'fixed_at', now(),
              'fixed_by', p_admin_id,
              'balance_reversed', true,
              'reason', 'Level ' || v_rec.level || ' was not unlocked at subscription time. Had ' || 
                        v_rec.actual_referrals_at_time || ' referrals, needed ' || v_rec.required_referrals
            )
        WHERE id = v_rec.transaction_id;
        
        v_violations_fixed := v_violations_fixed + 1;
      END IF;
    END IF;
  END LOOP;

  v_result := json_build_object(
    'success', true,
    'dry_run', p_dry_run,
    'violations_found', v_violations_found,
    'violations_fixed', v_violations_fixed,
    'total_amount_cents', v_total_amount_fixed
  );

  RETURN v_result;
END;
$$;
