
-- ============================================================
-- Ежемесячная активация (Структура 2)
-- ============================================================

-- 1. Добавить поле порога активации в тенге
ALTER TABLE shop_settings 
ADD COLUMN IF NOT EXISTS monthly_activation_required_kzt NUMERIC DEFAULT 20000;

-- Обновить текущее значение
UPDATE shop_settings SET monthly_activation_required_kzt = 20000 WHERE id = 1;

-- 2. Создать таблицу для хранения статусов ежемесячной активации
CREATE TABLE IF NOT EXISTS monthly_activations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  year INTEGER NOT NULL,
  month INTEGER NOT NULL CHECK (month >= 1 AND month <= 12),
  total_amount_kzt NUMERIC NOT NULL DEFAULT 0,
  threshold_kzt NUMERIC NOT NULL DEFAULT 20000,
  is_activated BOOLEAN NOT NULL DEFAULT false,
  last_order_id UUID REFERENCES orders(id),
  last_order_date TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (user_id, year, month)
);

-- Index for fast lookups
CREATE INDEX IF NOT EXISTS idx_monthly_activations_user_period ON monthly_activations(user_id, year, month);
CREATE INDEX IF NOT EXISTS idx_monthly_activations_period ON monthly_activations(year, month);
CREATE INDEX IF NOT EXISTS idx_monthly_activations_status ON monthly_activations(is_activated, year, month);

-- Enable RLS
ALTER TABLE monthly_activations ENABLE ROW LEVEL SECURITY;

-- RLS policies
CREATE POLICY "Users can view their own activations"
ON monthly_activations FOR SELECT
USING (auth.uid() = user_id);

CREATE POLICY "Admins can view all activations"
ON monthly_activations FOR SELECT
USING (has_role(auth.uid(), 'admin'::app_role) OR has_role(auth.uid(), 'superadmin'::app_role));

CREATE POLICY "System can manage activations"
ON monthly_activations FOR ALL
USING (true)
WITH CHECK (true);

-- 3. Функция для получения статистики ежемесячных активаций (для админки)
CREATE OR REPLACE FUNCTION get_monthly_activation_report(
  p_year INTEGER,
  p_month INTEGER,
  p_status TEXT DEFAULT 'all', -- 'all', 'activated', 'not_activated'
  p_search TEXT DEFAULT NULL,
  p_limit INTEGER DEFAULT 50,
  p_offset INTEGER DEFAULT 0
)
RETURNS TABLE (
  user_id UUID,
  full_name TEXT,
  email TEXT,
  referral_code TEXT,
  total_amount_kzt NUMERIC,
  threshold_kzt NUMERIC,
  is_activated BOOLEAN,
  last_order_date TIMESTAMPTZ,
  orders_count BIGINT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  v_threshold NUMERIC;
  v_period_start TIMESTAMPTZ;
  v_period_end TIMESTAMPTZ;
BEGIN
  -- Get threshold from settings
  SELECT COALESCE(monthly_activation_required_kzt, 20000) INTO v_threshold FROM shop_settings WHERE id = 1;
  
  -- Calculate period boundaries
  v_period_start := make_timestamptz(p_year, p_month, 1, 0, 0, 0);
  v_period_end := v_period_start + INTERVAL '1 month';
  
  RETURN QUERY
  WITH order_stats AS (
    SELECT 
      o.user_id,
      SUM(o.total_kzt) AS total_kzt,
      COUNT(o.id) AS order_count,
      MAX(o.paid_at) AS last_paid_at
    FROM orders o
    WHERE o.status = 'paid'
      AND o.paid_at >= v_period_start
      AND o.paid_at < v_period_end
      AND COALESCE(o.is_test, false) = false
      AND COALESCE(o.is_archived, false) = false
    GROUP BY o.user_id
  )
  SELECT 
    p.id AS user_id,
    p.full_name,
    p.email,
    p.referral_code,
    COALESCE(os.total_kzt, 0) AS total_amount_kzt,
    v_threshold AS threshold_kzt,
    COALESCE(os.total_kzt, 0) >= v_threshold AS is_activated,
    os.last_paid_at AS last_order_date,
    COALESCE(os.order_count, 0) AS orders_count
  FROM profiles p
  LEFT JOIN order_stats os ON os.user_id = p.id
  WHERE p.subscription_status = 'active'
    AND p.is_active = true
    AND p.deleted_at IS NULL
    AND COALESCE(p.is_archived, false) = false
    -- Status filter
    AND (
      p_status = 'all'
      OR (p_status = 'activated' AND COALESCE(os.total_kzt, 0) >= v_threshold)
      OR (p_status = 'not_activated' AND COALESCE(os.total_kzt, 0) < v_threshold)
    )
    -- Search filter
    AND (
      p_search IS NULL 
      OR p_search = ''
      OR p.full_name ILIKE '%' || p_search || '%'
      OR p.email ILIKE '%' || p_search || '%'
      OR p.referral_code ILIKE '%' || p_search || '%'
    )
  ORDER BY COALESCE(os.total_kzt, 0) DESC, p.full_name
  LIMIT p_limit OFFSET p_offset;
END;
$$;

-- 4. Функция для получения заказов партнёра за месяц
CREATE OR REPLACE FUNCTION get_partner_orders_for_month(
  p_user_id UUID,
  p_year INTEGER,
  p_month INTEGER
)
RETURNS TABLE (
  order_id UUID,
  order_date TIMESTAMPTZ,
  total_kzt NUMERIC,
  total_usd NUMERIC,
  status TEXT,
  items JSONB
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  v_period_start TIMESTAMPTZ;
  v_period_end TIMESTAMPTZ;
BEGIN
  v_period_start := make_timestamptz(p_year, p_month, 1, 0, 0, 0);
  v_period_end := v_period_start + INTERVAL '1 month';
  
  RETURN QUERY
  SELECT 
    o.id AS order_id,
    o.paid_at AS order_date,
    o.total_kzt,
    o.total_usd,
    o.status::TEXT,
    (
      SELECT jsonb_agg(jsonb_build_object(
        'product_id', oi.product_id,
        'title', pr.title,
        'qty', oi.qty,
        'price_kzt', oi.price_kzt,
        'is_activation', oi.is_activation_snapshot
      ))
      FROM order_items oi
      LEFT JOIN products pr ON pr.id = oi.product_id
      WHERE oi.order_id = o.id
    ) AS items
  FROM orders o
  WHERE o.user_id = p_user_id
    AND o.status = 'paid'
    AND o.paid_at >= v_period_start
    AND o.paid_at < v_period_end
    AND COALESCE(o.is_test, false) = false
    AND COALESCE(o.is_archived, false) = false
  ORDER BY o.paid_at DESC;
END;
$$;

-- 5. Функция для пересчёта активаций за период
CREATE OR REPLACE FUNCTION recalculate_monthly_activations(
  p_admin_id UUID,
  p_year INTEGER DEFAULT NULL,
  p_month INTEGER DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  v_threshold NUMERIC;
  v_start_year INTEGER;
  v_start_month INTEGER;
  v_end_year INTEGER;
  v_end_month INTEGER;
  v_current_year INTEGER;
  v_current_month INTEGER;
  v_updated_count INTEGER := 0;
  v_created_count INTEGER := 0;
BEGIN
  -- Check admin role
  IF NOT (has_role(p_admin_id, 'admin'::app_role) OR has_role(p_admin_id, 'superadmin'::app_role)) THEN
    RETURN jsonb_build_object('success', false, 'error', 'UNAUTHORIZED');
  END IF;
  
  -- Get threshold
  SELECT COALESCE(monthly_activation_required_kzt, 20000) INTO v_threshold FROM shop_settings WHERE id = 1;
  
  -- Determine period range
  IF p_year IS NOT NULL AND p_month IS NOT NULL THEN
    -- Specific month
    v_start_year := p_year;
    v_start_month := p_month;
    v_end_year := p_year;
    v_end_month := p_month;
  ELSE
    -- All months from earliest order to now
    SELECT 
      EXTRACT(YEAR FROM MIN(paid_at))::INTEGER,
      EXTRACT(MONTH FROM MIN(paid_at))::INTEGER
    INTO v_start_year, v_start_month
    FROM orders
    WHERE status = 'paid' AND paid_at IS NOT NULL;
    
    v_end_year := EXTRACT(YEAR FROM NOW())::INTEGER;
    v_end_month := EXTRACT(MONTH FROM NOW())::INTEGER;
  END IF;
  
  -- If no orders exist
  IF v_start_year IS NULL THEN
    RETURN jsonb_build_object('success', true, 'message', 'No paid orders found', 'updated', 0, 'created', 0);
  END IF;
  
  -- Iterate through months
  v_current_year := v_start_year;
  v_current_month := v_start_month;
  
  WHILE (v_current_year < v_end_year) OR (v_current_year = v_end_year AND v_current_month <= v_end_month) LOOP
    -- Upsert activations for this month
    WITH order_totals AS (
      SELECT 
        o.user_id,
        SUM(o.total_kzt) AS total_kzt,
        MAX(o.id) AS last_order_id,
        MAX(o.paid_at) AS last_order_date
      FROM orders o
      WHERE o.status = 'paid'
        AND EXTRACT(YEAR FROM o.paid_at) = v_current_year
        AND EXTRACT(MONTH FROM o.paid_at) = v_current_month
        AND COALESCE(o.is_test, false) = false
        AND COALESCE(o.is_archived, false) = false
      GROUP BY o.user_id
    ),
    upserted AS (
      INSERT INTO monthly_activations (user_id, year, month, total_amount_kzt, threshold_kzt, is_activated, last_order_id, last_order_date)
      SELECT 
        ot.user_id,
        v_current_year,
        v_current_month,
        ot.total_kzt,
        v_threshold,
        ot.total_kzt >= v_threshold,
        ot.last_order_id,
        ot.last_order_date
      FROM order_totals ot
      ON CONFLICT (user_id, year, month) 
      DO UPDATE SET
        total_amount_kzt = EXCLUDED.total_amount_kzt,
        threshold_kzt = EXCLUDED.threshold_kzt,
        is_activated = EXCLUDED.is_activated,
        last_order_id = EXCLUDED.last_order_id,
        last_order_date = EXCLUDED.last_order_date,
        updated_at = now()
      RETURNING xmax = 0 AS was_inserted
    )
    SELECT 
      COUNT(*) FILTER (WHERE was_inserted) + v_created_count,
      COUNT(*) FILTER (WHERE NOT was_inserted) + v_updated_count
    INTO v_created_count, v_updated_count
    FROM upserted;
    
    -- Move to next month
    IF v_current_month = 12 THEN
      v_current_month := 1;
      v_current_year := v_current_year + 1;
    ELSE
      v_current_month := v_current_month + 1;
    END IF;
  END LOOP;
  
  -- Log admin action
  INSERT INTO admin_actions (admin_id, action_type, target_type, metadata)
  VALUES (
    p_admin_id,
    'recalculate_monthly_activations',
    'system',
    jsonb_build_object(
      'year', p_year,
      'month', p_month,
      'created', v_created_count,
      'updated', v_updated_count,
      'threshold_kzt', v_threshold
    )
  );
  
  RETURN jsonb_build_object(
    'success', true,
    'created', v_created_count,
    'updated', v_updated_count,
    'threshold_kzt', v_threshold
  );
END;
$$;

-- 6. Триггер для автоматического обновления активации при оплате заказа
CREATE OR REPLACE FUNCTION update_monthly_activation_on_order()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  v_year INTEGER;
  v_month INTEGER;
  v_threshold NUMERIC;
  v_total_kzt NUMERIC;
BEGIN
  -- Only process when order becomes paid
  IF NEW.status = 'paid' AND (OLD.status IS NULL OR OLD.status != 'paid') AND NEW.paid_at IS NOT NULL THEN
    v_year := EXTRACT(YEAR FROM NEW.paid_at)::INTEGER;
    v_month := EXTRACT(MONTH FROM NEW.paid_at)::INTEGER;
    
    -- Get threshold
    SELECT COALESCE(monthly_activation_required_kzt, 20000) INTO v_threshold FROM shop_settings WHERE id = 1;
    
    -- Calculate total for the month
    SELECT COALESCE(SUM(total_kzt), 0) INTO v_total_kzt
    FROM orders
    WHERE user_id = NEW.user_id
      AND status = 'paid'
      AND EXTRACT(YEAR FROM paid_at) = v_year
      AND EXTRACT(MONTH FROM paid_at) = v_month
      AND COALESCE(is_test, false) = false
      AND COALESCE(is_archived, false) = false;
    
    -- Upsert monthly activation record
    INSERT INTO monthly_activations (user_id, year, month, total_amount_kzt, threshold_kzt, is_activated, last_order_id, last_order_date)
    VALUES (NEW.user_id, v_year, v_month, v_total_kzt, v_threshold, v_total_kzt >= v_threshold, NEW.id, NEW.paid_at)
    ON CONFLICT (user_id, year, month)
    DO UPDATE SET
      total_amount_kzt = v_total_kzt,
      is_activated = v_total_kzt >= v_threshold,
      last_order_id = NEW.id,
      last_order_date = NEW.paid_at,
      updated_at = now();
    
    -- Also update profile monthly_activation_completed for current month
    IF v_year = EXTRACT(YEAR FROM NOW()) AND v_month = EXTRACT(MONTH FROM NOW()) THEN
      UPDATE profiles
      SET 
        monthly_activation_completed = v_total_kzt >= v_threshold,
        updated_at = now()
      WHERE id = NEW.user_id;
    END IF;
  END IF;
  
  RETURN NEW;
END;
$$;

-- Create trigger (drop if exists first)
DROP TRIGGER IF EXISTS trg_update_monthly_activation_on_order ON orders;
CREATE TRIGGER trg_update_monthly_activation_on_order
AFTER INSERT OR UPDATE ON orders
FOR EACH ROW
EXECUTE FUNCTION update_monthly_activation_on_order();

-- 7. Function to count total partners for pagination
CREATE OR REPLACE FUNCTION get_monthly_activation_count(
  p_year INTEGER,
  p_month INTEGER,
  p_status TEXT DEFAULT 'all',
  p_search TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  v_threshold NUMERIC;
  v_period_start TIMESTAMPTZ;
  v_period_end TIMESTAMPTZ;
  v_total BIGINT;
  v_activated BIGINT;
  v_not_activated BIGINT;
BEGIN
  SELECT COALESCE(monthly_activation_required_kzt, 20000) INTO v_threshold FROM shop_settings WHERE id = 1;
  
  v_period_start := make_timestamptz(p_year, p_month, 1, 0, 0, 0);
  v_period_end := v_period_start + INTERVAL '1 month';
  
  WITH order_stats AS (
    SELECT 
      o.user_id,
      SUM(o.total_kzt) AS total_kzt
    FROM orders o
    WHERE o.status = 'paid'
      AND o.paid_at >= v_period_start
      AND o.paid_at < v_period_end
      AND COALESCE(o.is_test, false) = false
      AND COALESCE(o.is_archived, false) = false
    GROUP BY o.user_id
  ),
  filtered_profiles AS (
    SELECT 
      p.id,
      COALESCE(os.total_kzt, 0) >= v_threshold AS is_activated
    FROM profiles p
    LEFT JOIN order_stats os ON os.user_id = p.id
    WHERE p.subscription_status = 'active'
      AND p.is_active = true
      AND p.deleted_at IS NULL
      AND COALESCE(p.is_archived, false) = false
      AND (
        p_search IS NULL 
        OR p_search = ''
        OR p.full_name ILIKE '%' || p_search || '%'
        OR p.email ILIKE '%' || p_search || '%'
        OR p.referral_code ILIKE '%' || p_search || '%'
      )
  )
  SELECT 
    COUNT(*),
    COUNT(*) FILTER (WHERE is_activated),
    COUNT(*) FILTER (WHERE NOT is_activated)
  INTO v_total, v_activated, v_not_activated
  FROM filtered_profiles;
  
  RETURN jsonb_build_object(
    'total', v_total,
    'activated', v_activated,
    'not_activated', v_not_activated,
    'threshold_kzt', v_threshold
  );
END;
$$;
