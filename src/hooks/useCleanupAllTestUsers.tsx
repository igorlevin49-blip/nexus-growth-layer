import { useMutation, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "sonner";

interface CleanupAllParams {
  keepEmails: string[];
  confirmationPhrase: string;
  dryRun: boolean;
}

interface CleanupAllResult {
  success: boolean;
  dry_run: boolean;
  users: number;
  orders: number;
  subscriptions: number;
  transactions: number;
  withdrawals: number;
  referrals: number;
  activity: number;
  keep_emails: string[];
}

export function useCleanupAllTestUsers() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async (params: CleanupAllParams) => {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) throw new Error('Not authenticated');

      const { data, error } = await supabase.rpc('cleanup_all_test_users', {
        p_keep_emails: params.keepEmails,
        p_admin_id: user.id,
        p_confirmation_phrase: params.confirmationPhrase,
        p_dry_run: params.dryRun
      });

      if (error) throw error;
      return data as unknown as CleanupAllResult;
    },
    onSuccess: (data) => {
      if (data.dry_run) {
        toast.info('Предпросмотр очистки', {
          description: `Будет удалено: ${data.users} пользователей, ${data.orders} заказов, ${data.subscriptions} подписок, ${data.referrals} связей`
        });
      } else {
        queryClient.invalidateQueries();
        toast.success('Тестовые аккаунты удалены', {
          description: `Удалено: ${data.users} пользователей. Сохранены: ${data.keep_emails.join(', ')}`
        });
      }
    },
    onError: (error: any) => {
      toast.error(error.message || 'Ошибка при очистке аккаунтов');
    }
  });
}
