import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "sonner";

export interface TestResult {
  test_name: string;
  test_category: string;
  passed: boolean;
  error_message: string | null;
  details: Record<string, unknown>;
}

export function usePostMigrationTests() {
  return useQuery({
    queryKey: ['post-migration-tests'],
    queryFn: async () => {
      const { data, error } = await supabase.rpc('run_post_migration_tests');
      
      if (error) throw error;
      
      return (data || []) as TestResult[];
    },
    staleTime: 0, // Always fresh
    refetchOnMount: true
  });
}

export function useRunTests() {
  const queryClient = useQueryClient();
  
  return useMutation({
    mutationFn: async () => {
      const { data, error } = await supabase.rpc('run_post_migration_tests');
      
      if (error) throw error;
      
      return (data || []) as TestResult[];
    },
    onSuccess: (data) => {
      queryClient.setQueryData(['post-migration-tests'], data);
      
      const passed = data.filter(t => t.passed).length;
      const failed = data.filter(t => !t.passed).length;
      
      if (failed === 0) {
        toast.success(`Все ${passed} тестов пройдены успешно!`);
      } else {
        toast.warning(`${passed} тестов пройдено, ${failed} не прошли`);
      }
    },
    onError: (error: Error) => {
      toast.error(`Ошибка запуска тестов: ${error.message}`);
    }
  });
}
