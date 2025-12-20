import { useMutation, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "sonner";

interface ArchiveRecordsParams {
  record_type: 'orders' | 'subscriptions' | 'transactions';
  record_ids: string[];
}

interface HardDeleteParams {
  record_type: 'orders' | 'subscriptions' | 'withdrawals' | 'transactions';
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
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['admin-orders'] });
      queryClient.invalidateQueries({ queryKey: ['admin-subscriptions'] });
      queryClient.invalidateQueries({ queryKey: ['admin-global-stats'] });
      queryClient.invalidateQueries({ queryKey: ['admin-structure-stats'] });
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
    onSuccess: (_, variables) => {
      if (!variables.dry_run) {
        queryClient.invalidateQueries({ queryKey: ['admin-orders'] });
        queryClient.invalidateQueries({ queryKey: ['admin-subscriptions'] });
        queryClient.invalidateQueries({ queryKey: ['admin-global-stats'] });
        queryClient.invalidateQueries({ queryKey: ['admin-structure-stats'] });
        queryClient.invalidateQueries({ queryKey: ['transactions'] });
      }
    }
  });
}
