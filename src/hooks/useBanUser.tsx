import { useMutation, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "sonner";

interface BanUserParams {
  userId: string;
  action: 'ban' | 'unban';
}

export function useBanUser() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async ({ userId, action }: BanUserParams) => {
      const { data, error } = await supabase.functions.invoke('ban-user', {
        body: { userId, action }
      });
      
      if (error) throw error;
      if (!data.success) throw new Error(data.error || 'Unknown error');
      
      return data;
    },
    onSuccess: (_, { action }) => {
      queryClient.invalidateQueries({ queryKey: ['admin-users'] });
      toast.success(action === 'ban' 
        ? 'Пользователь заблокирован (вход запрещён)' 
        : 'Пользователь разблокирован'
      );
    },
    onError: (error: any) => {
      toast.error(error.message || 'Ошибка при изменении статуса блокировки');
    }
  });
}

export function useReassignReferrals() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async (userId: string) => {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) throw new Error('Not authenticated');

      const { data, error } = await supabase.rpc('reassign_referrals_to_upper_sponsor', {
        p_user_id: userId,
        p_admin_id: user.id
      });

      if (error) throw error;
      return data;
    },
    onSuccess: (data: any) => {
      queryClient.invalidateQueries({ queryKey: ['admin-users'] });
      toast.success(`Рефералы пересажены (${data?.reassigned_count || 0} чел.)`);
    },
    onError: (error: any) => {
      toast.error(error.message || 'Ошибка при пересадке рефералов');
    }
  });
}

export function useCountReferrals() {
  return async (userId: string): Promise<number> => {
    const { count, error } = await supabase
      .from('profiles')
      .select('*', { count: 'exact', head: true })
      .eq('sponsor_id', userId);
    
    if (error) {
      console.error('Error counting referrals:', error);
      return 0;
    }
    
    return count || 0;
  };
}
