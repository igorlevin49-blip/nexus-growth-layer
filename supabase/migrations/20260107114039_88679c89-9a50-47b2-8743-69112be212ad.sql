-- =====================================================
-- HOTFIX: backfill_missing_s1_commissions
-- Fixes runtime error: profiles.role column does not exist
-- Aligns with current schema (subscriptions.amount_kzt, status='active', paid_at)
-- Keeps return shape used by frontend hooks.
-- =====================================================

CREATE OR REPLACE FUNCTION public.backfill_missing_s1_commissions(
  p_admin_id uuid,
  p_days_back integer DEFAULT 30
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_subscription RECORD;
  v_result jsonb;
  v_subscriptions_processed integer := 0;
  v_commissions_created integer := 0;
  v_commissions_skipped integer := 0;
BEGIN
  -- Require authenticated admin/superadmin and parameter must match caller
  IF auth.uid() IS NULL OR auth.uid() <> p_admin_id THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  IF NOT public.has_role(auth.uid(), 'admin'::app_role)
     AND NOT public.has_role(auth.uid(), 'superadmin'::app_role) THEN
    RAISE EXCEPTION 'Only admins can run this function';
  END IF;

  FOR v_subscription IN
    SELECT s.id as subscription_id,
           s.user_id,
           s.amount_kzt,
           s.paid_at
    FROM public.subscriptions s
    WHERE s.status = 'active'
      AND s.paid_at IS NOT NULL
      AND s.paid_at >= now() - (p_days_back || ' days')::interval
      AND s.is_marketing_free_access IS NOT TRUE
      AND (s.is_archived IS NULL OR s.is_archived = false)
  LOOP
    v_subscriptions_processed := v_subscriptions_processed + 1;

    -- Skip if any commission tx already exists for this subscription
    IF EXISTS (
      SELECT 1
      FROM public.transactions t
      WHERE t.source_id = v_subscription.subscription_id
        AND t.type = 'commission'
        AND t.structure_type = 'primary'
    ) THEN
      v_commissions_skipped := v_commissions_skipped + 1;
      CONTINUE;
    END IF;

    SELECT public.award_s1_subscription_commission(
      v_subscription.amount_kzt,
      v_subscription.subscription_id,
      v_subscription.user_id
    ) INTO v_result;

    v_commissions_created := v_commissions_created + COALESCE((v_result->>'commissions_awarded')::integer, 0);
  END LOOP;

  RETURN jsonb_build_object(
    'success', true,
    'subscriptions_processed', v_subscriptions_processed,
    'commissions_created', v_commissions_created,
    'commissions_skipped', v_commissions_skipped
  );
END;
$$;