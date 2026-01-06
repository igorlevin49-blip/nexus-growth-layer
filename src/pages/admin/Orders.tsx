import { useState, useEffect } from "react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Checkbox } from "@/components/ui/checkbox";
import { Switch } from "@/components/ui/switch";
import { Label } from "@/components/ui/label";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "@/hooks/use-toast";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Eye, Archive, Trash2, ExternalLink } from "lucide-react";
import { useNavigate } from "react-router-dom";
import { useAuth } from "@/hooks/useAuth";
import { useArchiveRecords, useHardDeleteRecords } from "@/hooks/useArchiveRecords";
import { Input } from "@/components/ui/input";

type OrderProfile = {
  full_name: string | null;
  email: string | null;
  first_name: string | null;
  last_name: string | null;
};

type Order = {
  id: string;
  user_id: string;
  total_usd: number;
  total_kzt: number;
  status: "draft" | "pending" | "paid" | "cancelled";
  created_at: string;
  profiles?: OrderProfile | null;
};

type OrderItem = {
  id: string;
  product_id: string;
  qty: number;
  price_usd: number;
  price_kzt: number;
  is_activation_snapshot: boolean;
  products?: {
    title: string;
  };
};

export default function AdminOrders() {
  const { userRole } = useAuth();
  const isSuperAdmin = userRole === 'superadmin';
  const navigate = useNavigate();
  const [orders, setOrders] = useState<Order[]>([]);
  const [loading, setLoading] = useState(true);
  const [selectedOrder, setSelectedOrder] = useState<Order | null>(null);
  const [orderItems, setOrderItems] = useState<OrderItem[]>([]);
  const [dialogOpen, setDialogOpen] = useState(false);
  const [filterStatus, setFilterStatus] = useState<string>("all");
  const [showArchived, setShowArchived] = useState(false);
  const [selectedOrders, setSelectedOrders] = useState<Set<string>>(new Set());
  const [deleteDialog, setDeleteDialog] = useState(false);
  const [confirmationPhrase, setConfirmationPhrase] = useState('');

  const archiveRecords = useArchiveRecords();
  const hardDeleteRecords = useHardDeleteRecords();

  useEffect(() => {
    loadOrders();
  }, [showArchived]);

  const loadOrders = async () => {
    setLoading(true);
    try {
      // Step 1: Fetch orders
      let orderQuery = supabase
        .from("orders")
        .select("*")
        .order("created_at", { ascending: false });

      if (!showArchived) {
        orderQuery = orderQuery.or('is_archived.is.null,is_archived.eq.false');
      }

      const { data: ordersData, error: ordersError } = await orderQuery;
      
      if (ordersError) {
        console.error("Error fetching orders:", ordersError);
        throw ordersError;
      }

      if (!ordersData || ordersData.length === 0) {
        setOrders([]);
        setLoading(false);
        return;
      }

      // Step 2: Fetch profiles for all user_ids in one batch
      const userIds = [...new Set(ordersData.map(o => o.user_id).filter(Boolean))];
      
      if (userIds.length === 0) {
        setOrders(ordersData.map(o => ({ ...o, profiles: null })));
        setLoading(false);
        return;
      }

      const { data: profilesData, error: profilesError } = await supabase
        .from('profiles')
        .select('id, full_name, email, first_name, last_name')
        .in('id', userIds);

      // Don't throw on profile errors, just log them
      if (profilesError) {
        console.error("Error fetching profiles:", profilesError);
      }

      // Step 3: Map profiles to orders
      const profilesMap = new Map<string, OrderProfile>();
      if (profilesData) {
        profilesData.forEach(p => {
          profilesMap.set(p.id, {
            full_name: p.full_name,
            email: p.email,
            first_name: p.first_name,
            last_name: p.last_name
          });
        });
      }

      const ordersWithProfiles: Order[] = ordersData.map(order => ({
        id: order.id,
        user_id: order.user_id,
        total_usd: order.total_usd,
        total_kzt: order.total_kzt,
        status: order.status as "draft" | "pending" | "paid" | "cancelled",
        created_at: order.created_at,
        profiles: profilesMap.get(order.user_id) || null
      }));

      setOrders(ordersWithProfiles);
    } catch (error: any) {
      console.error("Error in loadOrders:", error);
      toast({
        title: "Ошибка",
        description: "Не удалось загрузить заказы",
        variant: "destructive",
      });
      setOrders([]);
    } finally {
      setLoading(false);
    }
  };

  const fetchOrderItems = async (orderId: string) => {
    try {
      const { data, error } = await supabase
        .from("order_items")
        .select(`
          *,
          products (
            title
          )
        `)
        .eq("order_id", orderId);

      if (error) throw error;
      setOrderItems(data || []);
    } catch (error) {
      console.error("Error fetching order items:", error);
    }
  };

  const handleViewOrder = async (order: Order) => {
    setSelectedOrder(order);
    await fetchOrderItems(order.id);
    setDialogOpen(true);
  };

  const handleUpdateStatus = async (orderId: string, status: "draft" | "pending" | "paid" | "cancelled") => {
    if (userRole !== "superadmin") {
      toast({
        title: "Доступ запрещен",
        description: "Только суперадминистратор может изменять статус заказа",
        variant: "destructive",
      });
      return;
    }

    try {
      // Для статуса 'paid' используем RPC для правильного начисления комиссий
      if (status === 'paid') {
        const { data: user } = await supabase.auth.getUser();
        const { data, error } = await supabase.rpc('process_payment_completion', {
          p_record_type: 'order',
          p_record_id: orderId,
          p_admin_id: user?.user?.id,
          p_comment: 'Подтверждено администратором'
        });

        if (error) throw error;
        
        // Проверяем результат RPC
        const result = data as { success?: boolean; error?: string } | null;
        if (result && result.success === false) {
          throw new Error(result.error || 'Ошибка обработки оплаты');
        }
      } else {
        // Для других статусов - прямое обновление
        const { error } = await supabase
          .from("orders")
          .update({ status })
          .eq("id", orderId);

        if (error) throw error;
      }

      toast({ title: "Статус обновлен" });
      loadOrders();
      if (selectedOrder?.id === orderId) {
        setSelectedOrder({ ...selectedOrder, status });
      }
    } catch (error: any) {
      console.error("Error updating order status:", error);
      toast({
        title: "Ошибка",
        description: error?.message || error?.code || "Не удалось обновить статус",
        variant: "destructive",
      });
    }
  };

  const getStatusBadge = (status: string) => {
    const variants: Record<string, "default" | "secondary" | "destructive" | "outline"> = {
      draft: "outline",
      pending: "secondary",
      paid: "default",
      cancelled: "destructive",
    };
    const labels: Record<string, string> = {
      draft: "Черновик",
      pending: "В ожидании",
      paid: "Оплачен",
      cancelled: "Отменен",
    };
    return (
      <Badge variant={variants[status] || "outline"}>
        {labels[status] || status}
      </Badge>
    );
  };

  const handleArchiveSelected = () => {
    if (selectedOrders.size === 0) {
      toast({ title: "Выберите заказы для архивации", variant: "destructive" });
      return;
    }

    archiveRecords.mutate({ 
      record_type: 'orders', 
      record_ids: Array.from(selectedOrders) 
    }, {
      onSuccess: () => {
        setSelectedOrders(new Set());
        loadOrders();
      }
    });
  };

  const handleDeleteSelected = () => {
    if (selectedOrders.size === 0) {
      toast({ title: "Выберите заказы для удаления", variant: "destructive" });
      return;
    }
    setDeleteDialog(true);
  };

  const handleConfirmDelete = () => {
    if (confirmationPhrase !== 'УДАЛИТЬ НАВСЕГДА') {
      toast({ title: "Введите правильную фразу подтверждения", variant: "destructive" });
      return;
    }

    hardDeleteRecords.mutate({
      record_type: 'orders',
      record_ids: Array.from(selectedOrders),
      confirmation_phrase: confirmationPhrase,
      dry_run: false
    }, {
      onSuccess: (data: any) => {
        if (data && data.success === false) {
          toast({ title: "Ошибка удаления", description: data.error || "Неизвестная ошибка", variant: "destructive" });
          return;
        }
        toast({ title: "Записи успешно удалены" });
        setDeleteDialog(false);
        setConfirmationPhrase('');
        setSelectedOrders(new Set());
        loadOrders();
      },
      onError: (error: Error) => {
        toast({ title: "Ошибка удаления", description: error.message, variant: "destructive" });
      }
    });
  };

  const getUserDisplayName = (profile: OrderProfile | null | undefined): string => {
    if (!profile) return 'Пользователь не найден';
    
    if (profile.full_name) return profile.full_name;
    if (profile.first_name && profile.last_name) return `${profile.first_name} ${profile.last_name}`;
    if (profile.email) return profile.email;
    return 'Пользователь без имени';
  };

  let filteredOrders = orders;
  if (filterStatus !== "all") {
    filteredOrders = orders.filter((o) => o.status === filterStatus);
  }

  if (loading) {
    return <div className="p-8">Загрузка...</div>;
  }

  return (
    <div className="p-8">
      <div className="flex justify-between items-center mb-6">
        <h1 className="text-3xl font-bold">Управление заказами</h1>
        <div className="flex items-center gap-4">
          <div className="flex items-center gap-2">
            <Switch
              checked={showArchived}
              onCheckedChange={setShowArchived}
              id="show-archived-orders"
            />
            <Label htmlFor="show-archived-orders">Показывать архивные</Label>
          </div>
          <Select value={filterStatus} onValueChange={setFilterStatus}>
            <SelectTrigger className="w-[200px]">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="all">Все статусы</SelectItem>
              <SelectItem value="draft">Черновик</SelectItem>
              <SelectItem value="pending">В ожидании</SelectItem>
              <SelectItem value="paid">Оплачен</SelectItem>
              <SelectItem value="cancelled">Отменен</SelectItem>
            </SelectContent>
          </Select>
        </div>
      </div>

      <Card>
        <CardHeader className="flex flex-row items-center justify-between">
          <CardTitle>Список заказов</CardTitle>
          {isSuperAdmin && (
            <div className="flex gap-2">
              <Button
                variant="outline"
                size="sm"
                onClick={handleArchiveSelected}
                disabled={selectedOrders.size === 0 || archiveRecords.isPending}
              >
                <Archive className="h-4 w-4 mr-2" />
                Скрыть ({selectedOrders.size})
              </Button>
              <Button
                variant="destructive"
                size="sm"
                onClick={handleDeleteSelected}
                disabled={selectedOrders.size === 0}
              >
                <Trash2 className="h-4 w-4 mr-2" />
                Удалить ({selectedOrders.size})
              </Button>
            </div>
          )}
        </CardHeader>
        <CardContent>
          <Table>
            <TableHeader>
              <TableRow>
                {isSuperAdmin && (
                  <TableHead className="w-12">
                    <Checkbox
                      checked={filteredOrders.length > 0 && selectedOrders.size === filteredOrders.length}
                      onCheckedChange={(checked) => {
                        if (checked) {
                          setSelectedOrders(new Set(filteredOrders.map(o => o.id)));
                        } else {
                          setSelectedOrders(new Set());
                        }
                      }}
                    />
                  </TableHead>
                )}
                <TableHead>ID заказа</TableHead>
                <TableHead>Покупатель</TableHead>
                <TableHead>Сумма</TableHead>
                <TableHead>Статус</TableHead>
                <TableHead>Дата</TableHead>
                <TableHead>Действия</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {filteredOrders.map((order) => (
                <TableRow key={order.id}>
                  {isSuperAdmin && (
                    <TableCell>
                      <Checkbox
                        checked={selectedOrders.has(order.id)}
                        onCheckedChange={(checked) => {
                          const newSet = new Set(selectedOrders);
                          if (checked) {
                            newSet.add(order.id);
                          } else {
                            newSet.delete(order.id);
                          }
                          setSelectedOrders(newSet);
                        }}
                      />
                    </TableCell>
                  )}
                  <TableCell className="font-mono text-xs">
                    {order.id.slice(0, 8)}
                  </TableCell>
                  <TableCell>
                    {order.user_id ? (
                      <button
                        onClick={() => navigate(`/admin/users?userId=${order.user_id}`)}
                        className="flex items-center gap-2 text-primary hover:underline"
                      >
                        <span>{getUserDisplayName(order.profiles)}</span>
                        <ExternalLink className="w-3 h-3" />
                      </button>
                    ) : (
                      <span className="text-muted-foreground">Пользователь не указан</span>
                    )}
                  </TableCell>
                  <TableCell>
                    <div className="font-semibold">
                      {order.total_kzt.toLocaleString('ru-RU')} ₸
                    </div>
                  </TableCell>
                  <TableCell>{getStatusBadge(order.status)}</TableCell>
                  <TableCell>
                    {new Date(order.created_at).toLocaleDateString("ru-RU")}
                  </TableCell>
                  <TableCell>
                    <Button
                      size="icon"
                      variant="ghost"
                      onClick={() => handleViewOrder(order)}
                    >
                      <Eye className="w-4 h-4" />
                    </Button>
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </CardContent>
      </Card>

      <Dialog open={dialogOpen} onOpenChange={setDialogOpen}>
        <DialogContent className="max-w-3xl">
          <DialogHeader>
            <DialogTitle>Детали заказа</DialogTitle>
          </DialogHeader>
          {selectedOrder && (
            <div className="space-y-4">
              <div className="grid grid-cols-2 gap-4">
                <div>
                  <p className="text-sm text-muted-foreground">ID заказа</p>
                  <p className="font-mono text-xs">{selectedOrder.id}</p>
                </div>
                <div>
                  <p className="text-sm text-muted-foreground">Покупатель</p>
                  <p className="font-medium">
                    {getUserDisplayName(selectedOrder.profiles)}
                  </p>
                  <p className="font-mono text-xs text-muted-foreground">
                    ID: {selectedOrder.user_id.slice(0, 8)}
                  </p>
                </div>
                <div>
                  <p className="text-sm text-muted-foreground">Дата</p>
                  <p>
                    {new Date(selectedOrder.created_at).toLocaleString("ru-RU")}
                  </p>
                </div>
                <div>
                  <p className="text-sm text-muted-foreground mb-2">Статус</p>
                  {userRole === "superadmin" ? (
                    <Select
                      value={selectedOrder.status}
                      onValueChange={(status: "draft" | "pending" | "paid" | "cancelled") =>
                        handleUpdateStatus(selectedOrder.id, status)
                      }
                    >
                      <SelectTrigger>
                        <SelectValue />
                      </SelectTrigger>
                      <SelectContent>
                        <SelectItem value="draft">Черновик</SelectItem>
                        <SelectItem value="pending">В ожидании</SelectItem>
                        <SelectItem value="paid">Оплачен</SelectItem>
                        <SelectItem value="cancelled">Отменен</SelectItem>
                      </SelectContent>
                    </Select>
                  ) : (
                    getStatusBadge(selectedOrder.status)
                  )}
                </div>
              </div>

              <div>
                <h3 className="font-semibold mb-2">Состав заказа</h3>
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>Товар</TableHead>
                      <TableHead>Кол-во</TableHead>
                      <TableHead>Цена</TableHead>
                      <TableHead>Сумма</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {orderItems.map((item) => (
                      <TableRow key={item.id}>
                        <TableCell>
                          {item.products?.title || "N/A"}
                          {item.is_activation_snapshot && (
                            <Badge variant="default" className="ml-2">
                              Активац.
                            </Badge>
                          )}
                        </TableCell>
                        <TableCell>{item.qty}</TableCell>
                        <TableCell>
                          {item.price_kzt.toLocaleString('ru-RU')} ₸
                        </TableCell>
                        <TableCell>
                          <div className="font-semibold">
                            {(item.price_kzt * item.qty).toLocaleString('ru-RU')} ₸
                          </div>
                        </TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              </div>

              <div className="border-t pt-4">
                <div className="flex justify-between text-xl font-bold">
                  <span>Итого:</span>
                  <div className="text-right">
                    {selectedOrder.total_kzt.toLocaleString('ru-RU')} ₸
                  </div>
                </div>
              </div>
            </div>
          )}
        </DialogContent>
      </Dialog>

      <Dialog open={deleteDialog} onOpenChange={setDeleteDialog}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle className="text-destructive">⚠️ Безвозвратное удаление</DialogTitle>
            <DialogDescription>
              Это действие удалит выбранные заказы НАВСЕГДА и не может быть отменено.
              Для подтверждения введите фразу: <strong>УДАЛИТЬ НАВСЕГДА</strong>
            </DialogDescription>
          </DialogHeader>
          <div className="space-y-4 py-4">
            <Input
              placeholder="УДАЛИТЬ НАВСЕГДА"
              value={confirmationPhrase}
              onChange={(e) => setConfirmationPhrase(e.target.value)}
            />
          </div>
          <DialogFooter>
            <Button
              variant="outline"
              onClick={() => {
                setDeleteDialog(false);
                setConfirmationPhrase('');
              }}
            >
              Отмена
            </Button>
            <Button
              variant="destructive"
              onClick={handleConfirmDelete}
              disabled={confirmationPhrase !== 'УДАЛИТЬ НАВСЕГДА' || hardDeleteRecords.isPending}
            >
              <Trash2 className="h-4 w-4 mr-2" />
              Удалить навсегда
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}
