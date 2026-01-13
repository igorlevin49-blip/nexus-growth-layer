-- Create a comprehensive post-migration test function
CREATE OR REPLACE FUNCTION public.run_post_migration_tests()
RETURNS TABLE (
  test_name TEXT,
  test_category TEXT,
  passed BOOLEAN,
  error_message TEXT,
  details JSONB
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_test_user_id UUID;
  v_count INT;
  v_result JSONB;
BEGIN
  -- Get a test user with referrals for testing
  SELECT p.id INTO v_test_user_id
  FROM profiles p
  WHERE EXISTS (SELECT 1 FROM referrals r WHERE r.referrer_id = p.id)
  LIMIT 1;

  -- ==========================================
  -- TEST 1: Network structure function works
  -- ==========================================
  test_name := 'get_referral_network_from_table';
  test_category := 'network';
  BEGIN
    IF v_test_user_id IS NOT NULL THEN
      SELECT COUNT(*) INTO v_count
      FROM get_referral_network_from_table(v_test_user_id, 3, 1);
      
      passed := true;
      error_message := NULL;
      details := jsonb_build_object('user_id', v_test_user_id, 'members_found', v_count);
    ELSE
      passed := true;
      error_message := 'No test user with referrals found';
      details := jsonb_build_object('skipped', true);
    END IF;
  EXCEPTION WHEN OTHERS THEN
    passed := false;
    error_message := SQLERRM;
    details := jsonb_build_object('sqlstate', SQLSTATE);
  END;
  RETURN NEXT;

  -- ==========================================
  -- TEST 2: Network stats function works
  -- ==========================================
  test_name := 'get_network_stats';
  test_category := 'network';
  BEGIN
    IF v_test_user_id IS NOT NULL THEN
      SELECT jsonb_agg(row_to_json(t)) INTO v_result
      FROM get_network_stats(v_test_user_id, 1) t;
      
      passed := true;
      error_message := NULL;
      details := COALESCE(v_result, '[]'::jsonb);
    ELSE
      passed := true;
      error_message := 'No test user found';
      details := jsonb_build_object('skipped', true);
    END IF;
  EXCEPTION WHEN OTHERS THEN
    passed := false;
    error_message := SQLERRM;
    details := jsonb_build_object('sqlstate', SQLSTATE);
  END;
  RETURN NEXT;

  -- ==========================================
  -- TEST 3: Monthly activation report works
  -- ==========================================
  test_name := 'get_monthly_activation_report';
  test_category := 'activations';
  BEGIN
    SELECT COUNT(*) INTO v_count
    FROM get_monthly_activation_report(
      p_year := EXTRACT(YEAR FROM CURRENT_DATE)::INT,
      p_month := EXTRACT(MONTH FROM CURRENT_DATE)::INT,
      p_limit := 10
    );
    
    passed := true;
    error_message := NULL;
    details := jsonb_build_object('records_found', v_count);
  EXCEPTION WHEN OTHERS THEN
    passed := false;
    error_message := SQLERRM;
    details := jsonb_build_object('sqlstate', SQLSTATE);
  END;
  RETURN NEXT;

  -- ==========================================
  -- TEST 4: Monthly activation count works
  -- ==========================================
  test_name := 'get_monthly_activation_count';
  test_category := 'activations';
  BEGIN
    SELECT * INTO v_result
    FROM get_monthly_activation_count(
      EXTRACT(YEAR FROM CURRENT_DATE)::INT,
      EXTRACT(MONTH FROM CURRENT_DATE)::INT
    );
    
    passed := v_result IS NOT NULL;
    error_message := CASE WHEN v_result IS NULL THEN 'NULL result' ELSE NULL END;
    details := COALESCE(v_result, '{}'::jsonb);
  EXCEPTION WHEN OTHERS THEN
    passed := false;
    error_message := SQLERRM;
    details := jsonb_build_object('sqlstate', SQLSTATE);
  END;
  RETURN NEXT;

  -- ==========================================
  -- TEST 5: No duplicate commissions
  -- ==========================================
  test_name := 'no_duplicate_commissions';
  test_category := 'commissions';
  BEGIN
    SELECT COUNT(*) INTO v_count
    FROM (
      SELECT source_ref, COUNT(*) as cnt
      FROM transactions
      WHERE type = 'commission' AND source_ref IS NOT NULL
      GROUP BY source_ref
      HAVING COUNT(*) > 1
    ) dups;
    
    passed := v_count = 0;
    error_message := CASE WHEN v_count > 0 THEN format('%s duplicate source_refs found', v_count) ELSE NULL END;
    details := jsonb_build_object('duplicate_count', v_count);
  EXCEPTION WHEN OTHERS THEN
    passed := false;
    error_message := SQLERRM;
    details := jsonb_build_object('sqlstate', SQLSTATE);
  END;
  RETURN NEXT;

  -- ==========================================
  -- TEST 6: No duplicate network links
  -- ==========================================
  test_name := 'no_duplicate_referral_links';
  test_category := 'network';
  BEGIN
    SELECT COUNT(*) INTO v_count
    FROM (
      SELECT referrer_id, referred_user_id, structure_type, COUNT(*) as cnt
      FROM referrals
      GROUP BY referrer_id, referred_user_id, structure_type
      HAVING COUNT(*) > 1
    ) dups;
    
    passed := v_count = 0;
    error_message := CASE WHEN v_count > 0 THEN format('%s duplicate referral links found', v_count) ELSE NULL END;
    details := jsonb_build_object('duplicate_count', v_count);
  EXCEPTION WHEN OTHERS THEN
    passed := false;
    error_message := SQLERRM;
    details := jsonb_build_object('sqlstate', SQLSTATE);
  END;
  RETURN NEXT;

  -- ==========================================
  -- TEST 7: All paid orders have paid_at
  -- ==========================================
  test_name := 'paid_orders_have_paid_at';
  test_category := 'orders';
  BEGIN
    SELECT COUNT(*) INTO v_count
    FROM orders
    WHERE status = 'paid' AND paid_at IS NULL;
    
    passed := v_count = 0;
    error_message := CASE WHEN v_count > 0 THEN format('%s paid orders missing paid_at', v_count) ELSE NULL END;
    details := jsonb_build_object('missing_paid_at_count', v_count);
  EXCEPTION WHEN OTHERS THEN
    passed := false;
    error_message := SQLERRM;
    details := jsonb_build_object('sqlstate', SQLSTATE);
  END;
  RETURN NEXT;

  -- ==========================================
  -- TEST 8: All paid subscriptions have paid_at
  -- ==========================================
  test_name := 'paid_subscriptions_have_paid_at';
  test_category := 'subscriptions';
  BEGIN
    SELECT COUNT(*) INTO v_count
    FROM subscriptions
    WHERE status = 'active' AND paid_at IS NULL;
    
    passed := v_count = 0;
    error_message := CASE WHEN v_count > 0 THEN format('%s active subscriptions missing paid_at', v_count) ELSE NULL END;
    details := jsonb_build_object('missing_paid_at_count', v_count);
  EXCEPTION WHEN OTHERS THEN
    passed := false;
    error_message := SQLERRM;
    details := jsonb_build_object('sqlstate', SQLSTATE);
  END;
  RETURN NEXT;

  -- ==========================================
  -- TEST 9: Commission structure stats works
  -- ==========================================
  test_name := 'get_commission_structure_stats';
  test_category := 'commissions';
  BEGIN
    IF v_test_user_id IS NOT NULL THEN
      SELECT COUNT(*) INTO v_count
      FROM get_commission_structure_stats(v_test_user_id, 1);
      
      passed := true;
      error_message := NULL;
      details := jsonb_build_object('user_id', v_test_user_id, 'levels_found', v_count);
    ELSE
      passed := true;
      error_message := 'No test user found';
      details := jsonb_build_object('skipped', true);
    END IF;
  EXCEPTION WHEN OTHERS THEN
    passed := false;
    error_message := SQLERRM;
    details := jsonb_build_object('sqlstate', SQLSTATE);
  END;
  RETURN NEXT;

  -- ==========================================
  -- TEST 10: No negative balances
  -- ==========================================
  test_name := 'no_negative_balances';
  test_category := 'finances';
  BEGIN
    SELECT COUNT(*) INTO v_count
    FROM profiles
    WHERE balance < 0;
    
    passed := v_count = 0;
    error_message := CASE WHEN v_count > 0 THEN format('%s users have negative balance', v_count) ELSE NULL END;
    details := jsonb_build_object('negative_balance_count', v_count);
  EXCEPTION WHEN OTHERS THEN
    passed := false;
    error_message := SQLERRM;
    details := jsonb_build_object('sqlstate', SQLSTATE);
  END;
  RETURN NEXT;
END;
$$;

-- Grant execute to authenticated users (admins will call it)
GRANT EXECUTE ON FUNCTION public.run_post_migration_tests() TO authenticated;

-- Add comment explaining the function
COMMENT ON FUNCTION public.run_post_migration_tests() IS 
'Runs comprehensive post-migration tests to verify key functionality:
- Network structure functions work correctly
- Commission calculations have no duplicates
- Activation reports generate properly
- Data integrity (paid_at dates, balances)
Call this after any migration to verify system health.';