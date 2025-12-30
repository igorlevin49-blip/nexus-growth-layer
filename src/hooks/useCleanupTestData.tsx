import { useMutation } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "sonner";

interface CleanupParams {
  superadminEmail: string;
  confirmationPhrase: string;
  dryRun: boolean;
}

interface CleanupResult {
  success: boolean;
  dry_run: boolean;
  superadmin_id: string;
  users: number;
  orders: number;
  subscriptions: number;
  transactions: number;
  withdrawals: number;
  referrals: number;
  activity: number;
}

export function useCleanupTestData() {
  return useMutation({
    mutationFn: async (params: CleanupParams) => {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) throw new Error('Not authenticated');

      const { data, error } = await supabase.rpc('cleanup_test_data', {
        p_superadmin_email: params.superadminEmail,
        p_admin_id: user.id,
        p_confirmation_phrase: params.confirmationPhrase,
        p_dry_run: params.dryRun
      });

      if (error) throw error;
      return data as unknown as CleanupResult;
    },
    onSuccess: (data) => {
      if (data.dry_run) {
        toast.info('Предпросмотр очистки', {
          description: `Будет удалено: ${data.users} пользователей, ${data.orders} заказов, ${data.subscriptions} подписок`
        });
      } else {
        toast.success('Тестовые данные удалены', {
          description: `Удалено: ${data.users} пользователей, ${data.orders} заказов, ${data.subscriptions} подписок`
        });
      }
    },
    onError: (error: any) => {
      toast.error(error.message || 'Ошибка при очистке данных');
    }
  });
}

// Soft delete - archives user, keeps data
export function useSoftDeleteUser() {
  return useMutation({
    mutationFn: async (userId: string) => {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) throw new Error('Not authenticated');

      const { data, error } = await supabase.rpc('soft_delete_user', {
        p_user_id: userId,
        p_admin_id: user.id
      });

      if (error) throw error;
      return data;
    },
    onSuccess: () => {
      toast.success('Пользователь архивирован');
    },
    onError: (error: any) => {
      toast.error(error.message || 'Ошибка при архивировании пользователя');
    }
  });
}

// Hard delete - permanently removes all user data
export function useHardDeleteUser() {
  return useMutation({
    mutationFn: async (userId: string) => {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) throw new Error('Not authenticated');

      const { data, error } = await supabase.rpc('hard_delete_user', {
        p_user_id: userId,
        p_admin_id: user.id
      });

      if (error) throw error;
      return data;
    },
    onSuccess: () => {
      toast.success('Пользователь полностью удалён из системы');
    },
    onError: (error: any) => {
      toast.error(error.message || 'Ошибка при удалении пользователя');
    }
  });
}

export function useRestoreUser() {
  return useMutation({
    mutationFn: async (userId: string) => {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) throw new Error('Not authenticated');

      const { data, error } = await supabase.rpc('restore_user', {
        p_user_id: userId,
        p_admin_id: user.id
      });

      if (error) throw error;
      return data;
    },
    onSuccess: () => {
      toast.success('Пользователь восстановлен');
    },
    onError: (error: any) => {
      toast.error(error.message || 'Ошибка при восстановлении пользователя');
    }
  });
}
