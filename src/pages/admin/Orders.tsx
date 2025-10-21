import { useState, useEffect } from "react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
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
import { Eye } from "lucide-react";
import { useAuth } from "@/hooks/useAuth";

type Order = {
  id: string;
  user_id: string;
  total_usd: number;
  total_kzt: number;
  status: "draft" | "pending" | "paid" | "cancelled";
  created_at: string;
  profiles?: {
    full_name: string | null;
    email: string | null;
  } | null;
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
  const [orders, setOrders] = useState<Order[]>([]);
  const [loading, setLoading] = useState(true);
  const [selectedOrder, setSelectedOrder] = useState<Order | null>(null);
  const [orderItems, setOrderItems] = useState<OrderItem[]>([]);
  const [dialogOpen, setDialogOpen] = useState(false);
  const [filterStatus, setFilterStatus] = useState<string>("all");

  useEffect(() => {
    fetchOrders();
  }, []);

  const fetchOrders = async () => {
    try {
      const { data, error } = await supabase
        .from("orders")
        .select("*")
        .order("created_at", { ascending: false });

      if (error) throw error;
      setOrders(data || []);
    } catch (error) {
      console.error("Error fetching orders:", error);
      toast({
        title: "Ошибка",
        description: "Не удалось загрузить заказы",
        variant: "destructive",
      });
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
      const { error } = await supabase
        .from("orders")
        .update({ status })
        .eq("id", orderId);

      if (error) throw error;
      toast({ title: "Статус обновлен" });
      fetchOrders();
      if (selectedOrder?.id === orderId) {
        setSelectedOrder({ ...selectedOrder, status });
      }
    } catch (error) {
      console.error("Error updating order status:", error);
      toast({
        title: "Ошибка",
        description: "Не удалось обновить статус",
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

      <Card>
        <CardHeader>
          <CardTitle>Список заказов</CardTitle>
        </CardHeader>
        <CardContent>
          <Table>
            <TableHeader>
              <TableRow>
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
                  <TableCell className="font-mono text-xs">
                    {order.id.slice(0, 8)}
                  </TableCell>
                  <TableCell>
                    {order.user_id.slice(0, 8)}
                  </TableCell>
                  <TableCell>
                    <div>
                      <div className="font-semibold">${order.total_usd}</div>
                      <div className="text-xs text-muted-foreground">
                        {order.total_kzt} ₸
                      </div>
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
                  <p className="text-sm text-muted-foreground">ID Покупателя</p>
                  <p className="font-mono text-xs">
                    {selectedOrder.user_id.slice(0, 8)}
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
                          <div>${item.price_usd}</div>
                          <div className="text-xs text-muted-foreground">
                            {item.price_kzt} ₸
                          </div>
                        </TableCell>
                        <TableCell>
                          <div className="font-semibold">
                            ${(item.price_usd * item.qty).toFixed(2)}
                          </div>
                          <div className="text-xs text-muted-foreground">
                            {(item.price_kzt * item.qty).toFixed(2)} ₸
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
                    <div>${selectedOrder.total_usd}</div>
                    <div className="text-sm text-muted-foreground">
                      {selectedOrder.total_kzt} ₸
                    </div>
                  </div>
                </div>
              </div>
            </div>
          )}
        </DialogContent>
      </Dialog>
    </div>
  );
}
