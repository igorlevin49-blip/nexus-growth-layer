import { useState } from "react";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { Plus, Send, Clock, CheckCircle, XCircle, Mail, MessageCircle, Bell, Eye, Trash2 } from "lucide-react";
import { format } from "date-fns";
import { ru } from "date-fns/locale";
import { toast } from "sonner";
import { CreateNotificationDialog } from "@/components/Admin/CreateNotificationDialog";
import { NotificationStatsDialog } from "@/components/Admin/NotificationStatsDialog";
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "@/components/ui/alert-dialog";

type SystemNotification = {
  id: string;
  title: string;
  message: string;
  type: string;
  channels: string[];
  target_audience: string;
  target_user_ids: string[] | null;
  scheduled_at: string | null;
  sent_at: string | null;
  created_at: string;
  status: string;
};

const statusLabels: Record<string, { label: string; variant: "default" | "secondary" | "destructive" | "outline" }> = {
  draft: { label: "Черновик", variant: "secondary" },
  scheduled: { label: "Запланировано", variant: "outline" },
  sending: { label: "Отправляется", variant: "default" },
  sent: { label: "Отправлено", variant: "default" },
  failed: { label: "Ошибка", variant: "destructive" },
};

const typeLabels: Record<string, string> = {
  info: "Информация",
  warning: "Предупреждение",
  promotion: "Акция",
  reminder: "Напоминание",
};

const channelIcons: Record<string, React.ReactNode> = {
  email: <Mail className="h-4 w-4" />,
  telegram: <MessageCircle className="h-4 w-4" />,
  modal: <Bell className="h-4 w-4" />,
};

export default function Notifications() {
  const [createDialogOpen, setCreateDialogOpen] = useState(false);
  const [statsDialogOpen, setStatsDialogOpen] = useState(false);
  const [selectedNotification, setSelectedNotification] = useState<SystemNotification | null>(null);
  const [deleteDialogOpen, setDeleteDialogOpen] = useState(false);
  const [notificationToDelete, setNotificationToDelete] = useState<string | null>(null);
  const queryClient = useQueryClient();

  const { data: notifications, isLoading } = useQuery({
    queryKey: ["system-notifications"],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("system_notifications")
        .select("*")
        .order("created_at", { ascending: false });

      if (error) throw error;
      return data as SystemNotification[];
    },
  });

  const sendMutation = useMutation({
    mutationFn: async (notificationId: string) => {
      const { data, error } = await supabase.functions.invoke("send-system-notification", {
        body: { notification_id: notificationId },
      });
      if (error) throw error;
      return data;
    },
    onSuccess: () => {
      toast.success("Уведомление отправлено");
      queryClient.invalidateQueries({ queryKey: ["system-notifications"] });
    },
    onError: (error) => {
      toast.error("Ошибка отправки: " + error.message);
    },
  });

  const deleteMutation = useMutation({
    mutationFn: async (notificationId: string) => {
      const { error } = await supabase
        .from("system_notifications")
        .delete()
        .eq("id", notificationId);
      if (error) throw error;
    },
    onSuccess: () => {
      toast.success("Уведомление удалено");
      queryClient.invalidateQueries({ queryKey: ["system-notifications"] });
      setDeleteDialogOpen(false);
      setNotificationToDelete(null);
    },
    onError: (error) => {
      toast.error("Ошибка удаления: " + error.message);
    },
  });

  const handleViewStats = (notification: SystemNotification) => {
    setSelectedNotification(notification);
    setStatsDialogOpen(true);
  };

  const handleDelete = (notificationId: string) => {
    setNotificationToDelete(notificationId);
    setDeleteDialogOpen(true);
  };

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-3xl font-bold tracking-tight">Управление уведомлениями</h1>
          <p className="text-muted-foreground">
            Создание и отправка уведомлений пользователям
          </p>
        </div>
        <Button onClick={() => setCreateDialogOpen(true)}>
          <Plus className="mr-2 h-4 w-4" />
          Создать уведомление
        </Button>
      </div>

      <Tabs defaultValue="all" className="space-y-4">
        <TabsList>
          <TabsTrigger value="all">Все</TabsTrigger>
          <TabsTrigger value="draft">Черновики</TabsTrigger>
          <TabsTrigger value="sent">Отправленные</TabsTrigger>
          <TabsTrigger value="scheduled">Запланированные</TabsTrigger>
        </TabsList>

        <TabsContent value="all">
          <NotificationsTable
            notifications={notifications}
            isLoading={isLoading}
            onSend={(id) => sendMutation.mutate(id)}
            onViewStats={handleViewStats}
            onDelete={handleDelete}
            isSending={sendMutation.isPending}
          />
        </TabsContent>

        <TabsContent value="draft">
          <NotificationsTable
            notifications={notifications?.filter((n) => n.status === "draft")}
            isLoading={isLoading}
            onSend={(id) => sendMutation.mutate(id)}
            onViewStats={handleViewStats}
            onDelete={handleDelete}
            isSending={sendMutation.isPending}
          />
        </TabsContent>

        <TabsContent value="sent">
          <NotificationsTable
            notifications={notifications?.filter((n) => n.status === "sent")}
            isLoading={isLoading}
            onSend={(id) => sendMutation.mutate(id)}
            onViewStats={handleViewStats}
            onDelete={handleDelete}
            isSending={sendMutation.isPending}
          />
        </TabsContent>

        <TabsContent value="scheduled">
          <NotificationsTable
            notifications={notifications?.filter((n) => n.status === "scheduled")}
            isLoading={isLoading}
            onSend={(id) => sendMutation.mutate(id)}
            onViewStats={handleViewStats}
            onDelete={handleDelete}
            isSending={sendMutation.isPending}
          />
        </TabsContent>
      </Tabs>

      <CreateNotificationDialog 
        open={createDialogOpen} 
        onOpenChange={setCreateDialogOpen} 
      />

      {selectedNotification && (
        <NotificationStatsDialog
          open={statsDialogOpen}
          onOpenChange={setStatsDialogOpen}
          notification={selectedNotification}
        />
      )}

      <AlertDialog open={deleteDialogOpen} onOpenChange={setDeleteDialogOpen}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Удалить уведомление?</AlertDialogTitle>
            <AlertDialogDescription>
              Это действие нельзя отменить. Уведомление и все связанные логи будут удалены.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Отмена</AlertDialogCancel>
            <AlertDialogAction
              onClick={() => notificationToDelete && deleteMutation.mutate(notificationToDelete)}
              className="bg-destructive text-destructive-foreground hover:bg-destructive/90"
            >
              Удалить
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  );
}

function NotificationsTable({
  notifications,
  isLoading,
  onSend,
  onViewStats,
  onDelete,
  isSending,
}: {
  notifications: SystemNotification[] | undefined;
  isLoading: boolean;
  onSend: (id: string) => void;
  onViewStats: (notification: SystemNotification) => void;
  onDelete: (id: string) => void;
  isSending: boolean;
}) {
  if (isLoading) {
    return (
      <Card>
        <CardContent className="py-10 text-center text-muted-foreground">
          Загрузка...
        </CardContent>
      </Card>
    );
  }

  if (!notifications?.length) {
    return (
      <Card>
        <CardContent className="py-10 text-center text-muted-foreground">
          Уведомлений не найдено
        </CardContent>
      </Card>
    );
  }

  return (
    <Card>
      <Table>
        <TableHeader>
          <TableRow>
            <TableHead>Заголовок</TableHead>
            <TableHead>Тип</TableHead>
            <TableHead>Каналы</TableHead>
            <TableHead>Аудитория</TableHead>
            <TableHead>Статус</TableHead>
            <TableHead>Создано</TableHead>
            <TableHead className="text-right">Действия</TableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
          {notifications.map((notification) => (
            <TableRow key={notification.id}>
              <TableCell className="font-medium max-w-[200px] truncate">
                {notification.title}
              </TableCell>
              <TableCell>
                <Badge variant="outline">{typeLabels[notification.type] || notification.type}</Badge>
              </TableCell>
              <TableCell>
                <div className="flex gap-1">
                  {notification.channels.map((channel) => (
                    <span key={channel} className="text-muted-foreground" title={channel}>
                      {channelIcons[channel]}
                    </span>
                  ))}
                </div>
              </TableCell>
              <TableCell>
                {notification.target_audience === "all" && "Все"}
                {notification.target_audience === "active" && "Активные"}
                {notification.target_audience === "inactive" && "Неактивные"}
                {notification.target_audience === "custom" && 
                  `Выбранные (${notification.target_user_ids?.length || 0})`}
              </TableCell>
              <TableCell>
                <Badge variant={statusLabels[notification.status]?.variant || "secondary"}>
                  {statusLabels[notification.status]?.label || notification.status}
                </Badge>
              </TableCell>
              <TableCell className="text-muted-foreground">
                {format(new Date(notification.created_at), "d MMM yyyy, HH:mm", { locale: ru })}
              </TableCell>
              <TableCell className="text-right">
                <div className="flex justify-end gap-2">
                  {notification.status === "sent" && (
                    <Button
                      variant="ghost"
                      size="icon"
                      onClick={() => onViewStats(notification)}
                      title="Статистика"
                    >
                      <Eye className="h-4 w-4" />
                    </Button>
                  )}
                  {notification.status === "draft" && (
                    <Button
                      variant="ghost"
                      size="icon"
                      onClick={() => onSend(notification.id)}
                      disabled={isSending}
                      title="Отправить"
                    >
                      <Send className="h-4 w-4" />
                    </Button>
                  )}
                  {notification.status !== "sending" && (
                    <Button
                      variant="ghost"
                      size="icon"
                      onClick={() => onDelete(notification.id)}
                      title="Удалить"
                    >
                      <Trash2 className="h-4 w-4 text-destructive" />
                    </Button>
                  )}
                </div>
              </TableCell>
            </TableRow>
          ))}
        </TableBody>
      </Table>
    </Card>
  );
}
