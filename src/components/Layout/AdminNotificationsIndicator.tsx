import { useState } from "react";
import { Bell, Package } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import {
  Popover,
  PopoverContent,
  PopoverTrigger,
} from "@/components/ui/popover";
import { ScrollArea } from "@/components/ui/scroll-area";
import { useAdminNotifications, markNotificationAsRead, AdminNotification } from "@/hooks/useAdminNotifications";
import { usePendingOrdersCount } from "@/hooks/usePendingOrdersCount";
import { useQueryClient } from "@tanstack/react-query";
import { useAuth } from "@/hooks/useAuth";
import { format } from "date-fns";
import { ru } from "date-fns/locale";
import { cn } from "@/lib/utils";
import { NavLink } from "react-router-dom";

const getDeclension = (n: number, forms: [string, string, string]) => {
  const abs = Math.abs(n) % 100;
  const n1 = abs % 10;
  if (abs > 10 && abs < 20) return forms[2];
  if (n1 > 1 && n1 < 5) return forms[1];
  if (n1 === 1) return forms[0];
  return forms[2];
};

export function AdminNotificationsIndicator() {
  const { userRole, user } = useAuth();
  const { data: notifications, isLoading } = useAdminNotifications();
  const { data: pendingOrdersCount = 0 } = usePendingOrdersCount();
  const queryClient = useQueryClient();
  const [open, setOpen] = useState(false);

  // Only show for admins
  if (userRole !== 'admin' && userRole !== 'superadmin') {
    return null;
  }

  const unreadCount = (notifications || []).filter(n => !n.read).length;
  const totalBadgeCount = unreadCount + (pendingOrdersCount > 0 ? 1 : 0);

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
          {totalBadgeCount > 0 && (
            <Badge 
              variant="destructive" 
              className="absolute -top-1 -right-1 h-5 w-5 flex items-center justify-center p-0 text-xs"
            >
              {totalBadgeCount > 9 ? '9+' : totalBadgeCount}
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
          {/* Pending orders section */}
          {pendingOrdersCount > 0 && (
            <NavLink to="/admin/orders" onClick={() => setOpen(false)}>
              <div className="p-3 hover:bg-orange-500/20 cursor-pointer bg-orange-500/10 border-b transition-colors">
                <div className="flex gap-2 items-center">
                  <div className="h-8 w-8 rounded-full bg-orange-500/20 flex items-center justify-center">
                    <Package className="h-4 w-4 text-orange-600" />
                  </div>
                  <div className="flex-1">
                    <p className="text-sm font-medium">Новые заказы</p>
                    <p className="text-xs text-muted-foreground">
                      {pendingOrdersCount} {getDeclension(pendingOrdersCount, ['заказ', 'заказа', 'заказов'])} ожидают обработки
                    </p>
                  </div>
                  <Badge variant="destructive" className="h-5 px-1.5">
                    {pendingOrdersCount}
                  </Badge>
                </div>
              </div>
            </NavLink>
          )}
          
          {isLoading ? (
            <div className="p-4 text-center text-muted-foreground text-sm">
              Загрузка...
            </div>
          ) : !notifications?.length && pendingOrdersCount === 0 ? (
            <div className="p-4 text-center text-muted-foreground text-sm">
              Нет уведомлений
            </div>
          ) : notifications?.length ? (
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
          ) : null}
        </ScrollArea>
        {userRole === 'superadmin' && (
          <div className="p-2 border-t">
            <NavLink to="/admin/security-logs" onClick={() => setOpen(false)}>
              <Button variant="ghost" size="sm" className="w-full text-xs">
                Открыть логи безопасности
              </Button>
            </NavLink>
          </div>
        )}
      </PopoverContent>
    </Popover>
  );
}
