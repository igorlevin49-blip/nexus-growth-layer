import { useState } from "react";
import { Bell } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import {
  Popover,
  PopoverContent,
  PopoverTrigger,
} from "@/components/ui/popover";
import { ScrollArea } from "@/components/ui/scroll-area";
import { useAdminNotifications, markNotificationAsRead, AdminNotification } from "@/hooks/useAdminNotifications";
import { useQueryClient } from "@tanstack/react-query";
import { useAuth } from "@/hooks/useAuth";
import { format } from "date-fns";
import { ru } from "date-fns/locale";
import { cn } from "@/lib/utils";
import { NavLink } from "react-router-dom";

export function AdminNotificationsIndicator() {
  const { userRole, user } = useAuth();
  const { data: notifications, isLoading } = useAdminNotifications();
  const queryClient = useQueryClient();
  const [open, setOpen] = useState(false);

  // Only show for admins
  if (userRole !== 'admin' && userRole !== 'superadmin') {
    return null;
  }

  const unreadCount = (notifications || []).filter(n => !n.read).length;

  const handleMarkAsRead = async (notification: AdminNotification) => {
    if (!notification.read) {
      await markNotificationAsRead(notification.id);
      queryClient.invalidateQueries({ queryKey: ['admin-notifications', user?.id] });
    }
  };

  const handleMarkAllAsRead = async () => {
    const unread = (notifications || []).filter(n => !n.read);
    for (const n of unread) {
      await markNotificationAsRead(n.id);
    }
    queryClient.invalidateQueries({ queryKey: ['admin-notifications', user?.id] });
  };

  const getNotificationIcon = (type: string) => {
    switch (type) {
      case 'suspicious_activity':
        return '⚠️';
      case 'status_achievement':
        return '🏆';
      case 'payment':
        return '💰';
      default:
        return '📢';
    }
  };

  return (
    <Popover open={open} onOpenChange={setOpen}>
      <PopoverTrigger asChild>
        <Button variant="ghost" size="sm" className="relative">
          <Bell className="h-5 w-5" />
          {unreadCount > 0 && (
            <Badge 
              variant="destructive" 
              className="absolute -top-1 -right-1 h-5 w-5 flex items-center justify-center p-0 text-xs"
            >
              {unreadCount > 9 ? '9+' : unreadCount}
            </Badge>
          )}
        </Button>
      </PopoverTrigger>
      <PopoverContent className="w-80 p-0" align="end">
        <div className="flex items-center justify-between p-3 border-b">
          <h4 className="font-semibold text-sm">Уведомления</h4>
          {unreadCount > 0 && (
            <Button 
              variant="ghost" 
              size="sm" 
              className="text-xs h-7"
              onClick={handleMarkAllAsRead}
            >
              Прочитать все
            </Button>
          )}
        </div>
        <ScrollArea className="h-80">
          {isLoading ? (
            <div className="p-4 text-center text-muted-foreground text-sm">
              Загрузка...
            </div>
          ) : !notifications?.length ? (
            <div className="p-4 text-center text-muted-foreground text-sm">
              Нет уведомлений
            </div>
          ) : (
            <div className="divide-y">
              {notifications.slice(0, 20).map((notification) => (
                <div
                  key={notification.id}
                  className={cn(
                    "p-3 hover:bg-muted/50 cursor-pointer transition-colors",
                    !notification.read && "bg-primary/5"
                  )}
                  onClick={() => handleMarkAsRead(notification)}
                >
                  <div className="flex gap-2">
                    <span className="text-lg">
                      {getNotificationIcon(notification.type)}
                    </span>
                    <div className="flex-1 min-w-0">
                      <div className="flex items-start justify-between gap-2">
                        <p className={cn(
                          "text-sm",
                          !notification.read && "font-medium"
                        )}>
                          {notification.title}
                        </p>
                        {!notification.read && (
                          <div className="h-2 w-2 rounded-full bg-primary flex-shrink-0 mt-1.5" />
                        )}
                      </div>
                      <p className="text-xs text-muted-foreground mt-0.5 line-clamp-2">
                        {notification.message}
                      </p>
                      <p className="text-xs text-muted-foreground mt-1">
                        {format(new Date(notification.created_at), 'dd MMM HH:mm', { locale: ru })}
                      </p>
                    </div>
                  </div>
                </div>
              ))}
            </div>
          )}
        </ScrollArea>
        <div className="p-2 border-t">
          <NavLink to="/admin/security-logs" onClick={() => setOpen(false)}>
            <Button variant="ghost" size="sm" className="w-full text-xs">
              Открыть логи безопасности
            </Button>
          </NavLink>
        </div>
      </PopoverContent>
    </Popover>
  );
}
