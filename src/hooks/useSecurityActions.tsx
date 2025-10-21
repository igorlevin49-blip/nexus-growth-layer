import { useMutation } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "sonner";

interface ChangePasswordParams {
  currentPassword: string;
  newPassword: string;
  confirmPassword: string;
}

export function useSecurityActions() {
  const changePassword = useMutation({
    mutationFn: async ({ currentPassword, newPassword, confirmPassword }: ChangePasswordParams) => {
      // Validate passwords match
      if (newPassword !== confirmPassword) {
        throw new Error('Пароли не совпадают');
      }

      // Validate password strength
      if (newPassword.length < 8) {
        throw new Error('Пароль должен быть не менее 8 символов');
      }

      const hasLetter = /[a-zA-Z]/.test(newPassword);
      const hasNumber = /[0-9]/.test(newPassword);
      
      if (!hasLetter || !hasNumber) {
        throw new Error('Пароль должен содержать минимум 1 букву и 1 цифру');
      }

      // Verify current password by attempting to sign in
      const { data: { user } } = await supabase.auth.getUser();
      if (!user?.email) throw new Error('Пользователь не найден');

      const { error: signInError } = await supabase.auth.signInWithPassword({
        email: user.email,
        password: currentPassword
      });

      if (signInError) {
        throw new Error('Неверный текущий пароль');
      }

      // Update password
      const { error: updateError } = await supabase.auth.updateUser({
        password: newPassword
      });

      if (updateError) throw updateError;

      // Log security event
      const { error: logError } = await supabase
        .from('security_events')
        .insert([{
          user_id: user.id,
          type: 'password_change',
          meta: { timestamp: new Date().toISOString() }
        }]);

      if (logError) console.error('Failed to log security event:', logError);

      return true;
    },
    onSuccess: () => {
      toast.success('Пароль обновлён');
    },
    onError: (error: Error) => {
      toast.error(error.message || 'Ошибка при изменении пароля');
    }
  });

  const revokeOtherSessions = useMutation({
    mutationFn: async () => {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) throw new Error('Not authenticated');

      // Sign out from all other sessions
      const { error } = await supabase.auth.signOut({ scope: 'others' });
      if (error) throw error;

      // Log security event
      await supabase
        .from('security_events')
        .insert([{
          user_id: user.id,
          type: 'sessions_revoked',
          meta: { timestamp: new Date().toISOString() }
        }]);

      return true;
    },
    onSuccess: () => {
      toast.success('Все другие сессии завершены');
    },
    onError: (error: Error) => {
      toast.error('Ошибка при завершении сессий');
      console.error(error);
    }
  });

  return {
    changePassword,
    revokeOtherSessions
  };
}
