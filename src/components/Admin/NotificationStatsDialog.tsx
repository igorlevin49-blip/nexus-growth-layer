import { useQuery } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { CheckCircle, XCircle, Mail, MessageCircle, Bell } from "lucide-react";
import { format } from "date-fns";
import { ru } from "date-fns/locale";

interface NotificationStatsDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  notification: {
    id: string;
    title: string;
    sent_at: string | null;
  };
}

const channelIcons: Record<string, React.ReactNode> = {
  email: <Mail className="h-4 w-4" />,
  telegram: <MessageCircle className="h-4 w-4" />,
  modal: <Bell className="h-4 w-4" />,
};

export function NotificationStatsDialog({
  open,
  onOpenChange,
  notification,
}: NotificationStatsDialogProps) {
  const { data: logs, isLoading } = useQuery({
    queryKey: ["notification-logs", notification.id],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("system_notification_logs")
        .select("*")
        .eq("notification_id", notification.id)
        .order("created_at", { ascending: false });

      if (error) throw error;
      return data;
    },
    enabled: open,
  });

  const stats = logs?.reduce(
    (acc, log) => {
      acc.total++;
      if (log.success) acc.success++;
      else acc.failed++;
      acc.byChannel[log.channel] = acc.byChannel[log.channel] || { success: 0, failed: 0 };
      if (log.success) acc.byChannel[log.channel].success++;
      else acc.byChannel[log.channel].failed++;
      return acc;
    },
    { total: 0, success: 0, failed: 0, byChannel: {} as Record<string, { success: number; failed: number }> }
  );

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-3xl max-h-[80vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Статистика отправки</DialogTitle>
          <DialogDescription>
            {notification.title}
            {notification.sent_at && (
              <span className="ml-2 text-muted-foreground">
                • {format(new Date(notification.sent_at), "d MMM yyyy, HH:mm", { locale: ru })}
              </span>
            )}
          </DialogDescription>
        </DialogHeader>

        {isLoading ? (
          <div className="py-8 text-center text-muted-foreground">Загрузка...</div>
        ) : (
          <div className="space-y-4">
            {/* Общая статистика */}
            <div className="grid grid-cols-3 gap-4">
              <Card>
                <CardHeader className="pb-2">
                  <CardTitle className="text-sm font-medium text-muted-foreground">
                    Всего отправок
                  </CardTitle>
                </CardHeader>
                <CardContent>
                  <div className="text-2xl font-bold">{stats?.total || 0}</div>
                </CardContent>
              </Card>
              <Card>
                <CardHeader className="pb-2">
                  <CardTitle className="text-sm font-medium text-green-600">
                    Успешно
                  </CardTitle>
                </CardHeader>
                <CardContent>
                  <div className="text-2xl font-bold text-green-600">{stats?.success || 0}</div>
                </CardContent>
              </Card>
              <Card>
                <CardHeader className="pb-2">
                  <CardTitle className="text-sm font-medium text-destructive">
                    Ошибки
                  </CardTitle>
                </CardHeader>
                <CardContent>
                  <div className="text-2xl font-bold text-destructive">{stats?.failed || 0}</div>
                </CardContent>
              </Card>
            </div>

            {/* По каналам */}
            {stats?.byChannel && Object.keys(stats.byChannel).length > 0 && (
              <Card>
                <CardHeader>
                  <CardTitle className="text-sm font-medium">По каналам</CardTitle>
                </CardHeader>
                <CardContent>
                  <div className="flex gap-4">
                    {Object.entries(stats.byChannel).map(([channel, data]) => (
                      <div key={channel} className="flex items-center gap-2">
                        {channelIcons[channel]}
                        <span className="capitalize">{channel}:</span>
                        <span className="text-green-600">{data.success}</span>
                        <span>/</span>
                        <span className="text-destructive">{data.failed}</span>
                      </div>
                    ))}
                  </div>
                </CardContent>
              </Card>
            )}

            {/* Детальные логи */}
            {logs && logs.length > 0 && (
              <Card>
                <CardHeader>
                  <CardTitle className="text-sm font-medium">Детали отправки</CardTitle>
                </CardHeader>
                <CardContent className="p-0">
                  <Table>
                    <TableHeader>
                      <TableRow>
                        <TableHead>Канал</TableHead>
                        <TableHead>Получатель</TableHead>
                        <TableHead>Статус</TableHead>
                        <TableHead>Время</TableHead>
                        <TableHead>Ошибка</TableHead>
                      </TableRow>
                    </TableHeader>
                    <TableBody>
                      {logs.slice(0, 50).map((log) => (
                        <TableRow key={log.id}>
                          <TableCell>
                            <div className="flex items-center gap-1">
                              {channelIcons[log.channel]}
                              <span className="capitalize">{log.channel}</span>
                            </div>
                          </TableCell>
                          <TableCell className="max-w-[150px] truncate">
                            {log.recipient}
                          </TableCell>
                          <TableCell>
                            {log.success ? (
                              <Badge variant="outline" className="text-green-600 border-green-600">
                                <CheckCircle className="h-3 w-3 mr-1" />
                                Успешно
                              </Badge>
                            ) : (
                              <Badge variant="destructive">
                                <XCircle className="h-3 w-3 mr-1" />
                                Ошибка
                              </Badge>
                            )}
                          </TableCell>
                          <TableCell className="text-muted-foreground text-sm">
                            {format(new Date(log.created_at), "HH:mm:ss")}
                          </TableCell>
                          <TableCell className="text-destructive text-sm max-w-[200px] truncate">
                            {log.error_message || "—"}
                          </TableCell>
                        </TableRow>
                      ))}
                    </TableBody>
                  </Table>
                  {logs.length > 50 && (
                    <div className="p-2 text-center text-muted-foreground text-sm">
                      Показано 50 из {logs.length} записей
                    </div>
                  )}
                </CardContent>
              </Card>
            )}
          </div>
        )}
      </DialogContent>
    </Dialog>
  );
}
