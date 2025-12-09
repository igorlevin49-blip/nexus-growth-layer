import { useState } from "react";
import { useMutation, useQueryClient, useQuery } from "@tanstack/react-query";
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
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { Checkbox } from "@/components/ui/checkbox";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { toast } from "sonner";
import { Mail, MessageCircle, Bell, Send, Save } from "lucide-react";

interface CreateNotificationDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
}

type NotificationType = "info" | "warning" | "promotion" | "reminder";
type TargetAudience = "all" | "active" | "inactive" | "custom";

export function CreateNotificationDialog({ open, onOpenChange }: CreateNotificationDialogProps) {
  const { user } = useAuth();
  const queryClient = useQueryClient();
  
  const [title, setTitle] = useState("");
  const [message, setMessage] = useState("");
  const [type, setType] = useState<NotificationType>("info");
  const [channels, setChannels] = useState<string[]>(["modal"]);
  const [targetAudience, setTargetAudience] = useState<TargetAudience>("all");
  const [selectedUsers, setSelectedUsers] = useState<string[]>([]);
  const [searchEmail, setSearchEmail] = useState("");

  // Поиск пользователей для custom аудитории
  const { data: searchResults } = useQuery({
    queryKey: ["search-users", searchEmail],
    queryFn: async () => {
      if (!searchEmail || searchEmail.length < 3) return [];
      const { data, error } = await supabase
        .from("profiles")
        .select("id, full_name, email")
        .ilike("email", `%${searchEmail}%`)
        .limit(10);
      if (error) throw error;
      return data;
    },
    enabled: searchEmail.length >= 3 && targetAudience === "custom",
  });

  const createMutation = useMutation({
    mutationFn: async (sendNow: boolean) => {
      const { data, error } = await supabase
        .from("system_notifications")
        .insert({
          title,
          message,
          type,
          channels,
          target_audience: targetAudience,
          target_user_ids: targetAudience === "custom" ? selectedUsers : null,
          status: sendNow ? "sending" : "draft",
          created_by: user?.id,
        })
        .select()
        .single();

      if (error) throw error;

      // Если отправляем сразу - вызываем edge function
      if (sendNow) {
        const { error: sendError } = await supabase.functions.invoke("send-system-notification", {
          body: { notification_id: data.id },
        });
        if (sendError) throw sendError;
      }

      return data;
    },
    onSuccess: (_, sendNow) => {
      toast.success(sendNow ? "Уведомление отправлено" : "Черновик сохранён");
      queryClient.invalidateQueries({ queryKey: ["system-notifications"] });
      resetForm();
      onOpenChange(false);
    },
    onError: (error) => {
      toast.error("Ошибка: " + error.message);
    },
  });

  const resetForm = () => {
    setTitle("");
    setMessage("");
    setType("info");
    setChannels(["modal"]);
    setTargetAudience("all");
    setSelectedUsers([]);
    setSearchEmail("");
  };

  const toggleChannel = (channel: string) => {
    setChannels((prev) =>
      prev.includes(channel) ? prev.filter((c) => c !== channel) : [...prev, channel]
    );
  };

  const addUser = (userId: string) => {
    if (!selectedUsers.includes(userId)) {
      setSelectedUsers([...selectedUsers, userId]);
    }
    setSearchEmail("");
  };

  const removeUser = (userId: string) => {
    setSelectedUsers(selectedUsers.filter((id) => id !== userId));
  };

  const isValid = title.trim() && message.trim() && channels.length > 0;

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-2xl max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Создать уведомление</DialogTitle>
          <DialogDescription>
            Отправьте уведомление пользователям через выбранные каналы
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-4 py-4">
          {/* Заголовок */}
          <div className="space-y-2">
            <Label htmlFor="title">Заголовок</Label>
            <Input
              id="title"
              value={title}
              onChange={(e) => setTitle(e.target.value)}
              placeholder="Например: Важное обновление системы"
            />
          </div>

          {/* Сообщение */}
          <div className="space-y-2">
            <Label htmlFor="message">Сообщение</Label>
            <Textarea
              id="message"
              value={message}
              onChange={(e) => setMessage(e.target.value)}
              placeholder="Текст уведомления..."
              rows={5}
            />
          </div>

          {/* Тип */}
          <div className="space-y-2">
            <Label>Тип уведомления</Label>
            <Select value={type} onValueChange={(v) => setType(v as NotificationType)}>
              <SelectTrigger>
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="info">Информация</SelectItem>
                <SelectItem value="warning">Предупреждение</SelectItem>
                <SelectItem value="promotion">Акция</SelectItem>
                <SelectItem value="reminder">Напоминание</SelectItem>
              </SelectContent>
            </Select>
          </div>

          {/* Каналы */}
          <div className="space-y-2">
            <Label>Каналы отправки</Label>
            <div className="flex gap-4">
              <div className="flex items-center space-x-2">
                <Checkbox
                  id="channel-modal"
                  checked={channels.includes("modal")}
                  onCheckedChange={() => toggleChannel("modal")}
                />
                <Label htmlFor="channel-modal" className="flex items-center gap-1 cursor-pointer">
                  <Bell className="h-4 w-4" />
                  Модалка
                </Label>
              </div>
              <div className="flex items-center space-x-2">
                <Checkbox
                  id="channel-email"
                  checked={channels.includes("email")}
                  onCheckedChange={() => toggleChannel("email")}
                />
                <Label htmlFor="channel-email" className="flex items-center gap-1 cursor-pointer">
                  <Mail className="h-4 w-4" />
                  Email
                </Label>
              </div>
              <div className="flex items-center space-x-2">
                <Checkbox
                  id="channel-telegram"
                  checked={channels.includes("telegram")}
                  onCheckedChange={() => toggleChannel("telegram")}
                />
                <Label htmlFor="channel-telegram" className="flex items-center gap-1 cursor-pointer">
                  <MessageCircle className="h-4 w-4" />
                  Telegram
                </Label>
              </div>
            </div>
          </div>

          {/* Аудитория */}
          <div className="space-y-2">
            <Label>Аудитория</Label>
            <Select value={targetAudience} onValueChange={(v) => setTargetAudience(v as TargetAudience)}>
              <SelectTrigger>
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="all">Все пользователи</SelectItem>
                <SelectItem value="active">Активные (с подпиской)</SelectItem>
                <SelectItem value="inactive">Неактивные (без подписки)</SelectItem>
                <SelectItem value="custom">Выбрать пользователей</SelectItem>
              </SelectContent>
            </Select>
          </div>

          {/* Выбор пользователей для custom */}
          {targetAudience === "custom" && (
            <div className="space-y-2">
              <Label>Поиск пользователей по email</Label>
              <Input
                value={searchEmail}
                onChange={(e) => setSearchEmail(e.target.value)}
                placeholder="Введите email для поиска..."
              />
              {searchResults && searchResults.length > 0 && (
                <div className="border rounded-md p-2 space-y-1 max-h-32 overflow-y-auto">
                  {searchResults.map((user) => (
                    <button
                      key={user.id}
                      onClick={() => addUser(user.id)}
                      className="w-full text-left px-2 py-1 hover:bg-muted rounded text-sm"
                    >
                      {user.full_name} ({user.email})
                    </button>
                  ))}
                </div>
              )}
              {selectedUsers.length > 0 && (
                <div className="flex flex-wrap gap-2 mt-2">
                  {selectedUsers.map((userId) => (
                    <span
                      key={userId}
                      className="bg-primary/10 text-primary px-2 py-1 rounded-full text-xs flex items-center gap-1"
                    >
                      {userId.slice(0, 8)}...
                      <button onClick={() => removeUser(userId)} className="hover:text-destructive">
                        ×
                      </button>
                    </span>
                  ))}
                </div>
              )}
            </div>
          )}
        </div>

        <DialogFooter className="gap-2">
          <Button
            variant="outline"
            onClick={() => createMutation.mutate(false)}
            disabled={!isValid || createMutation.isPending}
          >
            <Save className="mr-2 h-4 w-4" />
            Сохранить черновик
          </Button>
          <Button
            onClick={() => createMutation.mutate(true)}
            disabled={!isValid || createMutation.isPending}
          >
            <Send className="mr-2 h-4 w-4" />
            Отправить сейчас
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
