import { useMutation, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "sonner";

interface ArchiveRecordsParams {
  record_type: 'order' | 'subscription' | 'transaction';
  record_ids: string[];
}

interface HardDeleteParams {
  record_type: 'order' | 'subscription';
  record_ids: string[];
  confirmation_phrase: string;
  dry_run?: boolean;
}

export function useArchiveRecords() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async ({ record_type, record_ids }: ArchiveRecordsParams) => {
      const { data, error } = await supabase.rpc('archive_records', {
        record_type,
        record_ids
      });

      if (error) throw error;
      return data;
    },
    onSuccess: (data: any) => {
      queryClient.invalidateQueries({ queryKey: ['admin-orders'] });
      queryClient.invalidateQueries({ queryKey: ['subscriptions'] });
      queryClient.invalidateQueries({ queryKey: ['admin-global-stats'] });
      queryClient.invalidateQueries({ queryKey: ['admin-structure-stats'] });
      
      toast.success(`Скрыто записей: ${data?.affected_count || 0}`);
    },
    onError: (error: Error) => {
      toast.error(`Ошибка архивации: ${error.message}`);
    }
  });
}

export function useHardDeleteRecords() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async ({ record_type, record_ids, confirmation_phrase, dry_run = true }: HardDeleteParams) => {
      const { data, error } = await supabase.rpc('hard_delete_records', {
        record_type,
        record_ids,
        confirmation_phrase,
        dry_run
      });

      if (error) throw error;
      return data;
    },
    onSuccess: (data, variables) => {
      if (variables.dry_run) {
        // Just return the preview data
        return data;
      }
      
      queryClient.invalidateQueries({ queryKey: ['admin-orders'] });
      queryClient.invalidateQueries({ queryKey: ['subscriptions'] });
      queryClient.invalidateQueries({ queryKey: ['admin-global-stats'] });
      queryClient.invalidateQueries({ queryKey: ['admin-structure-stats'] });
      queryClient.invalidateQueries({ queryKey: ['transactions'] });
      
      toast.success('Записи успешно удалены');
    },
    onError: (error: Error) => {
      toast.error(`Ошибка удаления: ${error.message}`);
    }
  });
}
