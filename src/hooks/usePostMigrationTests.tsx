import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "sonner";

export interface TestResult {
  test_name: string;
  category: string;
  is_critical: boolean;
  passed: boolean;
  error_message: string | null;
  details: Record<string, unknown> | null;
}

interface DbTestResult {
  test_name: string;
  category: string;
  is_critical: boolean;
  passed: boolean;
  error_message: string | null;
  details: unknown;
}

export function usePostMigrationTests() {
  return useQuery({
    queryKey: ['post-migration-tests'],
    queryFn: async () => {
      const { data, error } = await supabase.rpc('run_post_migration_tests');
      
      if (error) throw error;
      
      return ((data || []) as DbTestResult[]).map(item => ({
        test_name: item.test_name,
        category: item.category,
        is_critical: item.is_critical,
        passed: item.passed,
        error_message: item.error_message,
        details: item.details as Record<string, unknown> | null
      })) as TestResult[];
    },
    staleTime: 0,
    refetchOnMount: true
  });
}

export function useRunTests() {
  const queryClient = useQueryClient();
  
  return useMutation({
    mutationFn: async () => {
      const { data, error } = await supabase.rpc('run_post_migration_tests');
      
      if (error) throw error;
      
      return ((data || []) as DbTestResult[]).map(item => ({
        test_name: item.test_name,
        category: item.category,
        is_critical: item.is_critical,
        passed: item.passed,
        error_message: item.error_message,
        details: item.details as Record<string, unknown> | null
      })) as TestResult[];
    },
    onSuccess: (data) => {
      queryClient.setQueryData(['post-migration-tests'], data);
      
      const passed = data.filter(t => t.passed).length;
      const failed = data.filter(t => !t.passed).length;
      const criticalFailed = data.filter(t => t.is_critical && !t.passed).length;
      
      if (failed === 0) {
        toast.success(`Все ${passed} тестов пройдены успешно!`);
      } else if (criticalFailed > 0) {
        toast.error(`${criticalFailed} критических тестов не прошли!`);
      } else {
        toast.warning(`${passed} тестов пройдено, ${failed} не прошли`);
      }
    },
    onError: (error: Error) => {
      toast.error(`Ошибка запуска тестов: ${error.message}`);
    }
  });
}
