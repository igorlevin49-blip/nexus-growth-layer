
-- Drop and recreate admin_recalculate_commissions with correct signature
DROP FUNCTION IF EXISTS public.admin_recalculate_commissions();

CREATE FUNCTION public.admin_recalculate_commissions()
RETURNS TABLE (
  recalculated_orders integer,
  recalculated_subscriptions integer,
  total_commissions_created integer,
  details jsonb
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_orders_count integer := 0;
  v_subscriptions_count integer := 0;
  v_commissions_count integer := 0;
  v_order record;
  v_subscription record;
  v_result jsonb;
BEGIN
  -- Process orders (S2 commissions)
  FOR v_order IN
    SELECT o.id, o.total_kzt, o.user_id, o.paid_at
    FROM orders o
    JOIN profiles p ON p.id = o.user_id
    WHERE o.status = 'paid'
      AND o.paid_at IS NOT NULL
      AND p.sponsor_id IS NOT NULL
      AND NOT EXISTS (
        SELECT 1 FROM transactions t 
        WHERE t.source_id = o.id 
          AND t.type = 'commission'
      )
  LOOP
    v_orders_count := v_orders_count + 1;
  END LOOP;

  -- Process subscriptions (S1 commissions) - EXCLUDING marketing_free_access
  FOR v_subscription IN
    SELECT s.id, s.amount_kzt, s.user_id, s.paid_at
    FROM subscriptions s
    JOIN profiles p ON p.id = s.user_id
    WHERE s.status = 'active'
      AND s.paid_at IS NOT NULL
      AND p.sponsor_id IS NOT NULL
      AND s.is_marketing_free_access IS NOT TRUE  -- EXCLUDE FREE MARKETING
      AND NOT EXISTS (
        SELECT 1 FROM transactions t 
        WHERE t.source_id = s.id 
          AND t.type = 'commission'
      )
  LOOP
    v_subscriptions_count := v_subscriptions_count + 1;
    
    SELECT award_s1_subscription_commission(
      v_subscription.amount_kzt,
      v_subscription.id,
      v_subscription.user_id
    ) INTO v_result;
    
    v_commissions_count := v_commissions_count + COALESCE((v_result->>'commissions_awarded')::integer, 0);
  END LOOP;

  RETURN QUERY SELECT 
    v_orders_count,
    v_subscriptions_count,
    v_commissions_count,
    jsonb_build_object(
      'orders_processed', v_orders_count,
      'subscriptions_processed', v_subscriptions_count,
      'commissions_created', v_commissions_count
    );
END;
$$;
