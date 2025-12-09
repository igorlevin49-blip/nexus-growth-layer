import { useMutation, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "./useAuth";
import { toast } from "sonner";

export function useBindSponsor() {
  const { user } = useAuth();
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async ({ userId, referralCode }: { userId: string; referralCode: string }) => {
      if (!user?.id) throw new Error("Not authenticated");

      const { data, error } = await supabase.rpc('admin_bind_sponsor' as any, {
        p_user_id: userId,
        p_sponsor_referral_code: referralCode.trim(),
        p_admin_id: user.id
      });

      if (error) throw error;

      const result = data as { success?: boolean; error?: string; sponsor_name?: string } | null;
      
      if (!result?.success) {
        const errorMessages: Record<string, string> = {
          'UNAUTHORIZED': 'Недостаточно прав',
          'SPONSOR_NOT_FOUND': 'Спонсор с таким кодом не найден',
          'SELF_REFERRAL': 'Нельзя указать себя в качестве спонсора',
          'ALREADY_HAS_SPONSOR': 'У пользователя уже есть спонсор',
          'USER_IS_SPONSOR': 'Пользователь уже является спонсором для других',
          'SPONSOR_REGISTERED_LATER': 'Спонсор зарегистрирован позже пользователя'
        };
        throw new Error(errorMessages[result?.error || ''] || 'Ошибка привязки спонсора');
      }

      return result;
    },
    onSuccess: (data) => {
      toast.success(`Спонсор "${data.sponsor_name}" успешно привязан`);
      queryClient.invalidateQueries({ queryKey: ['profiles'] });
      queryClient.invalidateQueries({ queryKey: ['network-tree'] });
      queryClient.invalidateQueries({ queryKey: ['referral-network'] });
    },
    onError: (error: Error) => {
      toast.error(error.message);
    }
  });
}
