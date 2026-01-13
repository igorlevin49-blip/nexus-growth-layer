
-- Fix get_sponsors_with_missing_commissions: check both source_id and payload->>'subscription_id'
-- because some commissions have source_id = user_id instead of subscription_id
CREATE OR REPLACE FUNCTION public.get_sponsors_with_missing_commissions(p_admin_id uuid)
RETURNS TABLE (
  sponsor_id uuid,
  sponsor_name text,
  sponsor_email text,
  missing_count bigint,
  missing_amount_cents bigint,
  partners_count bigint
)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Проверка прав админа
  IF NOT EXISTS (
    SELECT 1 FROM user_roles 
    WHERE user_id = p_admin_id 
    AND role IN ('admin', 'superadmin')
  ) THEN
    RAISE EXCEPTION 'Access denied: admin role required';
  END IF;

  RETURN QUERY
  WITH missing AS (
    SELECT 
      s.id AS subscription_id,
      s.user_id AS subscriber_id,
      s.amount_kzt,
      p.sponsor_id AS spid,
      sp.full_name AS sponsor_name,
      sp.email AS sponsor_email
    FROM subscriptions s
    JOIN profiles p ON p.id = s.user_id
    JOIN profiles sp ON sp.id = p.sponsor_id
    WHERE s.status = 'active'
      AND s.paid_at IS NOT NULL
      AND p.sponsor_id IS NOT NULL
      -- Check for existing commission by BOTH source_id = subscription_id OR payload->>'subscription_id'
      AND NOT EXISTS (
        SELECT 1 FROM transactions t
        WHERE t.user_id = p.sponsor_id
          AND t.structure_type = 'primary'
          AND t.level = 1
          AND t.type = 'commission'
          AND (
            t.source_id = s.id 
            OR t.payload->>'subscription_id' = s.id::text
          )
      )
  )
  SELECT 
    m.spid,
    m.sponsor_name,
    m.sponsor_email,
    COUNT(*)::BIGINT AS missing_count,
    SUM((m.amount_kzt * 0.10)::BIGINT * 100)::BIGINT AS missing_amount_cents,
    COUNT(DISTINCT m.subscriber_id)::BIGINT AS partners_count
  FROM missing m
  GROUP BY m.spid, m.sponsor_name, m.sponsor_email
  ORDER BY missing_count DESC;
END;
$$;

-- Also fix backfill_missing_s1_commissions to use the same logic
CREATE OR REPLACE FUNCTION public.backfill_missing_s1_commissions(
  p_admin_id uuid,
  p_sponsor_id uuid DEFAULT NULL,
  p_dry_run boolean DEFAULT true
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_result jsonb;
  v_processed int := 0;
  v_created int := 0;
  v_skipped int := 0;
  v_total_cents bigint := 0;
  v_details jsonb := '[]'::jsonb;
  v_rec record;
  v_new_id uuid;
BEGIN
  -- Check admin role
  IF NOT EXISTS (
    SELECT 1 FROM user_roles 
    WHERE user_id = p_admin_id 
    AND role IN ('admin', 'superadmin')
  ) THEN
    RAISE EXCEPTION 'Access denied: admin role required';
  END IF;

  -- Find all missing S1 commissions
  FOR v_rec IN
    SELECT 
      s.id AS subscription_id,
      s.user_id AS subscriber_id,
      p.full_name AS subscriber_name,
      s.amount_kzt,
      s.paid_at,
      pr.sponsor_id,
      1 AS network_level,
      (s.amount_kzt * 0.10)::int AS expected_commission_kzt
    FROM subscriptions s
    JOIN profiles pr ON pr.id = s.user_id
    JOIN profiles p ON p.id = s.user_id
    WHERE s.status = 'active'
      AND s.paid_at IS NOT NULL
      AND pr.sponsor_id IS NOT NULL
      AND (p_sponsor_id IS NULL OR pr.sponsor_id = p_sponsor_id)
      -- Check for existing commission by BOTH source_id = subscription_id OR payload->>'subscription_id'
      AND NOT EXISTS (
        SELECT 1 FROM transactions t
        WHERE t.user_id = pr.sponsor_id
          AND t.structure_type = 'primary'
          AND t.level = 1
          AND t.type = 'commission'
          AND (
            t.source_id = s.id 
            OR t.payload->>'subscription_id' = s.id::text
          )
      )
    ORDER BY s.paid_at ASC
  LOOP
    v_processed := v_processed + 1;
    
    IF NOT p_dry_run THEN
      -- Create the missing commission
      INSERT INTO transactions (
        user_id,
        type,
        structure_type,
        level,
        currency,
        amount_cents,
        source_id,
        source_ref,
        status,
        frozen_until,
        payload,
        created_at
      ) VALUES (
        v_rec.sponsor_id,
        'commission',
        'primary',
        v_rec.network_level,
        'KZT',
        v_rec.expected_commission_kzt * 100,
        v_rec.subscription_id,
        'backfill:subscription:' || v_rec.subscription_id || ':s1:l' || v_rec.network_level,
        'completed',
        NULL,
        jsonb_build_object(
          'subscription_id', v_rec.subscription_id,
          'from_user_id', v_rec.subscriber_id,
          'from_user_name', v_rec.subscriber_name,
          'base_amount_kzt', v_rec.amount_kzt,
          'percent', 10,
          'backfill', true,
          'backfill_date', now(),
          'backfill_admin_id', p_admin_id
        ),
        v_rec.paid_at
      )
      RETURNING id INTO v_new_id;
      
      v_created := v_created + 1;
      v_total_cents := v_total_cents + (v_rec.expected_commission_kzt * 100);
    ELSE
      v_created := v_created + 1;
      v_total_cents := v_total_cents + (v_rec.expected_commission_kzt * 100);
    END IF;
    
    -- Add to details (limit to first 50 for performance)
    IF v_processed <= 50 THEN
      v_details := v_details || jsonb_build_object(
        'subscription_id', v_rec.subscription_id,
        'subscriber_name', v_rec.subscriber_name,
        'amount_kzt', v_rec.amount_kzt,
        'commission_cents', v_rec.expected_commission_kzt * 100
      );
    END IF;
  END LOOP;

  v_result := jsonb_build_object(
    'success', true,
    'subscriptions_processed', v_processed,
    'commissions_created', v_created,
    'commissions_skipped', v_skipped,
    'total_amount_cents', v_total_cents,
    'dry_run', p_dry_run,
    'details', v_details
  );
  
  RETURN v_result;
END;
$$;
