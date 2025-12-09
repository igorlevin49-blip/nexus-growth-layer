import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/hooks/useAuth";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { AlertTriangle, Info, Gift, Bell } from "lucide-react";

const typeConfig: Record<string, { icon: React.ReactNode; className: string }> = {
  info: {
    icon: <Info className="h-6 w-6 text-blue-500" />,
    className: "bg-blue-500/10 border-blue-500/20",
  },
  warning: {
    icon: <AlertTriangle className="h-6 w-6 text-yellow-500" />,
    className: "bg-yellow-500/10 border-yellow-500/20",
  },
  promotion: {
    icon: <Gift className="h-6 w-6 text-purple-500" />,
    className: "bg-purple-500/10 border-purple-500/20",
  },
  reminder: {
    icon: <Bell className="h-6 w-6 text-orange-500" />,
    className: "bg-orange-500/10 border-orange-500/20",
  },
};

export function SystemNotificationModal() {
  const { user } = useAuth();
  const queryClient = useQueryClient();

  const { data: notification } = useQuery({
    queryKey: ["user-modal-notification", user?.id],
    queryFn: async () => {
      if (!user?.id) return null;

      const { data, error } = await supabase
        .from("user_modal_notifications")
        .select("*")
        .eq("user_id", user.id)
        .eq("dismissed", false)
        .lte("show_after", new Date().toISOString())
        .order("created_at", { ascending: false })
        .limit(1)
        .maybeSingle();

      if (error) throw error;
      return data;
    },
    enabled: !!user?.id,
    refetchInterval: 60000, // Проверяем каждую минуту
  });

  const dismissMutation = useMutation({
    mutationFn: async (notificationId: string) => {
      const { error } = await supabase
        .from("user_modal_notifications")
        .update({ dismissed: true, read: true })
        .eq("id", notificationId);

      if (error) throw error;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["user-modal-notification", user?.id] });
    },
  });

  if (!notification) return null;

  const config = typeConfig[notification.type] || typeConfig.info;

  return (
    <Dialog open={!!notification} onOpenChange={() => dismissMutation.mutate(notification.id)}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <div className={`mx-auto mb-4 p-4 rounded-full border ${config.className}`}>
            {config.icon}
          </div>
          <DialogTitle className="text-center">{notification.title}</DialogTitle>
          <DialogDescription className="text-center whitespace-pre-wrap">
            {notification.message}
          </DialogDescription>
        </DialogHeader>
        <DialogFooter className="sm:justify-center">
          <Button onClick={() => dismissMutation.mutate(notification.id)}>
            Понятно
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
