-- Удаляем функцию и создаём заново
DROP FUNCTION IF EXISTS public.get_referral_network_from_table(uuid, integer, integer);

-- =============================================
-- FIX 1: Исправить get_referral_network_from_table
-- Заменить referred_id на referred_user_id
-- =============================================

CREATE OR REPLACE FUNCTION public.get_referral_network_from_table(
  root_user_id uuid,
  p_max_levels integer DEFAULT 5,
  p_structure_type integer DEFAULT 1
)
RETURNS TABLE (
  id uuid,
  full_name text,
  avatar_url text,
  level integer,
  parent_id uuid,
  subscription_status text,
  subscription_expires_at timestamptz,
  personal_activation_volume numeric,
  has_commission_received boolean,
  no_commission_reason text,
  commission_frozen_until timestamptz,
  is_activated boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  WITH RECURSIVE network AS (
    -- Первый уровень: прямые рефералы
    SELECT 
      r.referred_user_id as uid,
      1 as lvl,
      root_user_id as parent
    FROM referrals r
    WHERE r.referrer_id = root_user_id
      AND (
        (p_structure_type = 1 AND r.structure_type = 'primary') OR
        (p_structure_type = 2 AND r.structure_type = 'secondary')
      )
    
    UNION ALL
    
    -- Рекурсивно получаем следующие уровни
    SELECT 
      ref.referred_user_id as uid,
      n.lvl + 1 as lvl,
      n.uid as parent
    FROM network n
    JOIN referrals ref ON ref.referrer_id = n.uid
    WHERE n.lvl < p_max_levels
      AND (
        (p_structure_type = 1 AND ref.structure_type = 'primary') OR
        (p_structure_type = 2 AND ref.structure_type = 'secondary')
      )
  ),
  -- Получаем данные о комиссиях
  commission_data AS (
    SELECT DISTINCT ON (n.uid)
      n.uid,
      n.lvl,
      n.parent,
      t.id as transaction_id,
      t.frozen_until,
      t.released_at,
      CASE 
        WHEN t.id IS NOT NULL THEN true
        ELSE false
      END as has_commission
    FROM network n
    LEFT JOIN transactions t ON 
      t.user_id = root_user_id
      AND t.type = 'commission'
      AND t.level = n.lvl
      AND (
        t.payload->>'from_user_id' = n.uid::text OR
        t.payload->>'subscriber_id' = n.uid::text OR
        t.payload->>'buyer_id' = n.uid::text OR
        t.payload->>'source_user_id' = n.uid::text
      )
      AND (
        (p_structure_type = 1 AND t.structure_type = 'primary') OR
        (p_structure_type = 2 AND t.structure_type = 'secondary')
      )
    ORDER BY n.uid, t.created_at DESC
  )
  SELECT 
    p.id,
    p.full_name,
    p.avatar_url,
    cd.lvl as level,
    cd.parent as parent_id,
    p.subscription_status,
    p.subscription_expires_at,
    COALESCE(p.personal_activation_volume, 0) as personal_activation_volume,
    cd.has_commission as has_commission_received,
    CASE 
      WHEN NOT cd.has_commission THEN 
        CASE 
          WHEN p.subscription_status != 'active' THEN 'partner_inactive'
          ELSE 'level_not_unlocked'
        END
      ELSE NULL
    END as no_commission_reason,
    cd.frozen_until as commission_frozen_until,
    COALESCE(p.is_activated, false) as is_activated
  FROM commission_data cd
  JOIN profiles p ON p.id = cd.uid
  ORDER BY cd.lvl, p.full_name;
END;
$$;

-- =============================================
-- FIX 2: Исправить award_s1_subscription_commission
-- Заменить ON CONFLICT ON CONSTRAINT на ON CONFLICT (columns)
-- =============================================

CREATE OR REPLACE FUNCTION public.award_s1_subscription_commission()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_subscriber_id uuid;
  v_sponsor_id uuid;
  v_current_sponsor uuid;
  v_level integer := 0;
  v_commission_rate numeric;
  v_commission_amount numeric;
  v_subscription_price numeric;
  v_sponsor_qualified boolean;
  v_max_levels integer := 5;
  v_freeze_days integer;
  v_frozen_until timestamptz;
  v_source_ref text;
  v_direct_referrals_count integer;
  v_required_referrals integer;
BEGIN
  -- Только для активных подписок
  IF NEW.subscription_status != 'active' THEN
    RETURN NEW;
  END IF;
  
  -- Только если статус изменился на active
  IF OLD IS NOT NULL AND OLD.subscription_status = 'active' THEN
    RETURN NEW;
  END IF;
  
  v_subscriber_id := NEW.id;
  
  -- Получаем настройки заморозки
  SELECT COALESCE((value->>'commission_freeze_days')::integer, 30)
  INTO v_freeze_days
  FROM mlm_settings
  WHERE key = 'freeze_settings';
  
  IF v_freeze_days > 0 THEN
    v_frozen_until := NOW() + (v_freeze_days || ' days')::interval;
  END IF;
  
  -- Получаем цену подписки
  SELECT COALESCE((value->>'subscription_price')::numeric, 11000)
  INTO v_subscription_price
  FROM mlm_settings
  WHERE key = 'subscription_settings';
  
  -- Находим primary спонсора
  SELECT referrer_id INTO v_sponsor_id
  FROM referrals
  WHERE referred_user_id = v_subscriber_id
    AND structure_type = 'primary'
  LIMIT 1;
  
  IF v_sponsor_id IS NULL THEN
    RETURN NEW;
  END IF;
  
  v_current_sponsor := v_sponsor_id;
  
  -- Проходим по уровням
  WHILE v_current_sponsor IS NOT NULL AND v_level < v_max_levels LOOP
    v_level := v_level + 1;
    
    -- Получаем процент для уровня
    SELECT COALESCE((value->>('level_' || v_level))::numeric, 0)
    INTO v_commission_rate
    FROM mlm_settings
    WHERE key = 's1_commission_rates';
    
    IF v_commission_rate IS NULL OR v_commission_rate = 0 THEN
      -- Переходим к следующему спонсору
      SELECT referrer_id INTO v_current_sponsor
      FROM referrals
      WHERE referred_user_id = v_current_sponsor
        AND structure_type = 'primary'
      LIMIT 1;
      CONTINUE;
    END IF;
    
    -- Проверяем квалификацию спонсора
    SELECT 
      subscription_status = 'active' AND COALESCE(is_activated, false)
    INTO v_sponsor_qualified
    FROM profiles
    WHERE id = v_current_sponsor;
    
    IF NOT COALESCE(v_sponsor_qualified, false) THEN
      -- Переходим к следующему спонсору
      SELECT referrer_id INTO v_current_sponsor
      FROM referrals
      WHERE referred_user_id = v_current_sponsor
        AND structure_type = 'primary'
      LIMIT 1;
      CONTINUE;
    END IF;
    
    -- Проверяем количество прямых рефералов для разблокировки уровня
    IF v_level > 1 THEN
      SELECT COUNT(*) INTO v_direct_referrals_count
      FROM referrals r
      JOIN profiles p ON p.id = r.referred_user_id
      WHERE r.referrer_id = v_current_sponsor
        AND r.structure_type = 'primary'
        AND p.subscription_status = 'active';
      
      -- Требования по рефералам для уровней
      v_required_referrals := CASE v_level
        WHEN 2 THEN 2
        WHEN 3 THEN 3
        WHEN 4 THEN 4
        WHEN 5 THEN 5
        ELSE 1
      END;
      
      IF v_direct_referrals_count < v_required_referrals THEN
        -- Переходим к следующему спонсору
        SELECT referrer_id INTO v_current_sponsor
        FROM referrals
        WHERE referred_user_id = v_current_sponsor
          AND structure_type = 'primary'
        LIMIT 1;
        CONTINUE;
      END IF;
    END IF;
    
    -- Рассчитываем комиссию
    v_commission_amount := v_subscription_price * v_commission_rate / 100;
    
    -- Уникальный source_ref
    v_source_ref := 's1_sub_' || v_subscriber_id || '_' || v_current_sponsor || '_L' || v_level;
    
    -- Создаем транзакцию комиссии
    INSERT INTO transactions (
      user_id,
      type,
      amount,
      status,
      description,
      source_ref,
      level,
      structure_type,
      frozen_until,
      payload
    ) VALUES (
      v_current_sponsor,
      'commission',
      v_commission_amount,
      CASE WHEN v_frozen_until IS NOT NULL THEN 'frozen' ELSE 'completed' END,
      'Комиссия L' || v_level || ' за подписку партнера',
      v_source_ref,
      v_level,
      'primary',
      v_frozen_until,
      jsonb_build_object(
        'from_user_id', v_subscriber_id,
        'source_user_id', v_subscriber_id,
        'level', v_level,
        'rate', v_commission_rate,
        'subscription_price', v_subscription_price
      )
    )
    ON CONFLICT (user_id, source_ref) WHERE source_ref IS NOT NULL DO NOTHING;
    
    -- Если не заморожена, начисляем на баланс
    IF v_frozen_until IS NULL THEN
      UPDATE profiles
      SET balance = COALESCE(balance, 0) + v_commission_amount
      WHERE id = v_current_sponsor;
    END IF;
    
    -- Переходим к следующему спонсору
    SELECT referrer_id INTO v_current_sponsor
    FROM referrals
    WHERE referred_user_id = v_current_sponsor
      AND structure_type = 'primary'
    LIMIT 1;
  END LOOP;
  
  RETURN NEW;
END;
$$;

-- =============================================
-- FIX 3: Исправить create_commission_transactions
-- Заменить ON CONFLICT ON CONSTRAINT на ON CONFLICT (columns)
-- =============================================

CREATE OR REPLACE FUNCTION public.create_commission_transactions(
  p_recipient_id uuid,
  p_source_user_id uuid,
  p_order_id uuid,
  p_level integer,
  p_amount numeric,
  p_freeze_days integer DEFAULT 0,
  p_structure_type text DEFAULT 'secondary'
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_transaction_id uuid;
  v_frozen_until timestamptz;
  v_source_ref text;
  v_status text;
BEGIN
  -- Рассчитываем дату разморозки
  IF p_freeze_days > 0 THEN
    v_frozen_until := NOW() + (p_freeze_days || ' days')::interval;
    v_status := 'frozen';
  ELSE
    v_status := 'completed';
  END IF;
  
  -- Уникальный source_ref
  v_source_ref := 's2_order_' || p_order_id || '_' || p_recipient_id || '_L' || p_level;
  
  -- Создаем транзакцию
  INSERT INTO transactions (
    user_id,
    type,
    amount,
    status,
    description,
    source_ref,
    level,
    structure_type,
    frozen_until,
    payload
  ) VALUES (
    p_recipient_id,
    'commission',
    p_amount,
    v_status,
    'Комиссия L' || p_level || ' за заказ S2',
    v_source_ref,
    p_level,
    p_structure_type,
    v_frozen_until,
    jsonb_build_object(
      'order_id', p_order_id,
      'buyer_id', p_source_user_id,
      'source_user_id', p_source_user_id,
      'level', p_level
    )
  )
  ON CONFLICT (user_id, source_ref) WHERE source_ref IS NOT NULL DO NOTHING
  RETURNING id INTO v_transaction_id;
  
  -- Если не заморожена и транзакция создана, начисляем на баланс
  IF v_frozen_until IS NULL AND v_transaction_id IS NOT NULL THEN
    UPDATE profiles
    SET balance = COALESCE(balance, 0) + p_amount
    WHERE id = p_recipient_id;
  END IF;
  
  RETURN v_transaction_id;
END;
$$;