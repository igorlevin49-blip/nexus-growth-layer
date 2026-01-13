-- Исправляем тесты с правильными сигнатурами функций
DROP FUNCTION IF EXISTS run_post_migration_tests();

CREATE OR REPLACE FUNCTION public.run_post_migration_tests()
RETURNS TABLE (
  test_name TEXT,
  category TEXT,
  is_critical BOOLEAN,
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
  v_result RECORD;
BEGIN
  SELECT id INTO v_test_user_id FROM profiles WHERE is_system_account = false LIMIT 1;
  
  -- CRITICAL: get_referral_network_from_table
  BEGIN
    PERFORM * FROM get_referral_network_from_table(COALESCE(v_test_user_id, '00000000-0000-0000-0000-000000000000'::uuid), 3, 1) LIMIT 1;
    RETURN QUERY SELECT 'get_referral_network_from_table'::TEXT, 'network'::TEXT, true, true, NULL::TEXT, jsonb_build_object('user_id', v_test_user_id);
  EXCEPTION WHEN OTHERS THEN
    RETURN QUERY SELECT 'get_referral_network_from_table'::TEXT, 'network'::TEXT, true, false, SQLERRM::TEXT, jsonb_build_object('sqlstate', SQLSTATE);
  END;

  -- CRITICAL: get_network_stats (с правильной сигнатурой)
  BEGIN
    PERFORM * FROM get_network_stats(COALESCE(v_test_user_id, '00000000-0000-0000-0000-000000000000'::uuid), 1);
    RETURN QUERY SELECT 'get_network_stats'::TEXT, 'network'::TEXT, true, true, NULL::TEXT, NULL::JSONB;
  EXCEPTION WHEN OTHERS THEN
    RETURN QUERY SELECT 'get_network_stats'::TEXT, 'network'::TEXT, true, false, SQLERRM::TEXT, jsonb_build_object('sqlstate', SQLSTATE);
  END;

  -- CRITICAL: get_monthly_activation_report (с правильной сигнатурой)
  BEGIN
    PERFORM * FROM get_monthly_activation_report(EXTRACT(YEAR FROM NOW())::INTEGER, EXTRACT(MONTH FROM NOW())::INTEGER, 'all', NULL, 10, 0) LIMIT 1;
    RETURN QUERY SELECT 'get_monthly_activation_report'::TEXT, 'activations'::TEXT, true, true, NULL::TEXT, NULL::JSONB;
  EXCEPTION WHEN OTHERS THEN
    RETURN QUERY SELECT 'get_monthly_activation_report'::TEXT, 'activations'::TEXT, true, false, SQLERRM::TEXT, jsonb_build_object('sqlstate', SQLSTATE);
  END;

  -- CRITICAL: get_commission_structure_stats
  BEGIN
    PERFORM * FROM get_commission_structure_stats(COALESCE(v_test_user_id, '00000000-0000-0000-0000-000000000000'::uuid));
    RETURN QUERY SELECT 'get_commission_structure_stats'::TEXT, 'commissions'::TEXT, true, true, NULL::TEXT, NULL::JSONB;
  EXCEPTION WHEN OTHERS THEN
    RETURN QUERY SELECT 'get_commission_structure_stats'::TEXT, 'commissions'::TEXT, true, false, SQLERRM::TEXT, jsonb_build_object('sqlstate', SQLSTATE);
  END;

  -- WARNING: Проверка дублей комиссий
  BEGIN
    SELECT COUNT(*) INTO v_result FROM (SELECT source_ref FROM transactions WHERE type = 'commission' AND source_ref IS NOT NULL GROUP BY source_ref, user_id HAVING COUNT(*) > 1) d;
    IF v_result.count > 0 THEN
      RETURN QUERY SELECT 'no_duplicate_commissions'::TEXT, 'data_integrity'::TEXT, false, false, format('Found %s duplicates', v_result.count)::TEXT, jsonb_build_object('count', v_result.count);
    ELSE
      RETURN QUERY SELECT 'no_duplicate_commissions'::TEXT, 'data_integrity'::TEXT, false, true, NULL::TEXT, NULL::JSONB;
    END IF;
  EXCEPTION WHEN OTHERS THEN
    RETURN QUERY SELECT 'no_duplicate_commissions'::TEXT, 'data_integrity'::TEXT, false, false, SQLERRM::TEXT, NULL::JSONB;
  END;

  -- WARNING: Проверка отрицательных балансов
  BEGIN
    SELECT COUNT(*) INTO v_result FROM profiles WHERE balance < 0;
    IF v_result.count > 0 THEN
      RETURN QUERY SELECT 'no_negative_balances'::TEXT, 'data_integrity'::TEXT, false, false, format('Found %s negative', v_result.count)::TEXT, jsonb_build_object('count', v_result.count);
    ELSE
      RETURN QUERY SELECT 'no_negative_balances'::TEXT, 'data_integrity'::TEXT, false, true, NULL::TEXT, NULL::JSONB;
    END IF;
  EXCEPTION WHEN OTHERS THEN
    RETURN QUERY SELECT 'no_negative_balances'::TEXT, 'data_integrity'::TEXT, false, false, SQLERRM::TEXT, NULL::JSONB;
  END;

  -- WARNING: get_user_balance
  BEGIN
    PERFORM * FROM get_user_balance(COALESCE(v_test_user_id, '00000000-0000-0000-0000-000000000000'::uuid));
    RETURN QUERY SELECT 'get_user_balance'::TEXT, 'balance'::TEXT, false, true, NULL::TEXT, NULL::JSONB;
  EXCEPTION WHEN OTHERS THEN
    RETURN QUERY SELECT 'get_user_balance'::TEXT, 'balance'::TEXT, false, false, SQLERRM::TEXT, NULL::JSONB;
  END;
END;
$$;

-- Запуск тестов
SELECT * FROM run_post_migration_tests();