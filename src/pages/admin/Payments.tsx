import { useState } from "react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Checkbox } from "@/components/ui/checkbox";
import { Switch } from "@/components/ui/switch";
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
import { CheckCircle2, Archive, Trash2 } from "lucide-react";
import { useSubscriptions, useConfirmPayment } from "@/hooks/useSubscriptions";
import { useArchiveRecords, useHardDeleteRecords } from "@/hooks/useArchiveRecords";
import { useQuery } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/hooks/useAuth";
import { toast } from "sonner";

type Order = {
  id: string;
  user_id: string;
  total_usd: number;
  total_kzt: number;
  status: string;
  created_at: string;
  profiles?: {
    full_name: string;
    email: string;
  };
};

export default function AdminPayments() {
  const { userRole } = useAuth();
  const [showArchived, setShowArchived] = useState(false);
  const [selectedOrders, setSelectedOrders] = useState<Set<string>>(new Set());
  const [selectedSubs, setSelectedSubs] = useState<Set<string>>(new Set());
  const [deleteDialog, setDeleteDialog] = useState<{ open: boolean; type: 'order' | 'subscription' }>({ open: false, type: 'order' });
  const [confirmationPhrase, setConfirmationPhrase] = useState('');

  const { data: subscriptions = [], isLoading: subsLoading } = useSubscriptions(showArchived);
  const { data: orders = [], isLoading: ordersLoading } = useQuery({
    queryKey: ['admin-orders', showArchived],
    queryFn: async () => {
      let query = supabase
        .from('orders')
        .select('*')
        .order('created_at', { ascending: false });

      if (!showArchived) {
        query = query.or('is_archived.is.null,is_archived.eq.false');
      }

      const { data, error } = await query;
      if (error) throw error;
      
      // Fetch profiles separately
      const ordersWithProfiles = await Promise.all(
        (data || []).map(async (order) => {
          const { data: profile } = await supabase
            .from('profiles')
            .select('full_name, email')
            .eq('id', order.user_id)
            .single();
          
          return {
            ...order,
            profiles: profile || { full_name: '', email: '' }
          };
        })
      );
      
      return ordersWithProfiles as Order[];
    }
  });

  const confirmPayment = useConfirmPayment();
  const archiveRecords = useArchiveRecords();
  const hardDeleteRecords = useHardDeleteRecords();
  
  const [confirmDialog, setConfirmDialog] = useState<{
    open: boolean;
    id: string;
    type: 'subscription' | 'order';
    userName: string;
  }>({ open: false, id: '', type: 'subscription', userName: '' });
  const [adminComment, setAdminComment] = useState('');

  const handleArchiveSelected = (type: 'order' | 'subscription') => {
    const ids = type === 'order' 
      ? Array.from(selectedOrders)
      : Array.from(selectedSubs);
    
    if (ids.length === 0) {
      toast.error('Выберите записи для архивации');
      return;
    }

    archiveRecords.mutate({ record_type: type, record_ids: ids }, {
      onSuccess: () => {
        if (type === 'order') setSelectedOrders(new Set());
        else setSelectedSubs(new Set());
      }
    });
  };

  const handleDeleteSelected = async (type: 'order' | 'subscription') => {
    const ids = type === 'order' 
      ? Array.from(selectedOrders)
      : Array.from(selectedSubs);
    
    if (ids.length === 0) {
      toast.error('Выберите записи для удаления');
      return;
    }

    setDeleteDialog({ open: true, type });
  };

  const handleConfirmDelete = async () => {
    const ids = deleteDialog.type === 'order' 
      ? Array.from(selectedOrders)
      : Array.from(selectedSubs);

    hardDeleteRecords.mutate({
      record_type: deleteDialog.type,
      record_ids: ids,
      confirmation_phrase: confirmationPhrase,
      dry_run: false
    }, {
      onSuccess: () => {
        setDeleteDialog({ ...deleteDialog, open: false });
        setConfirmationPhrase('');
        if (deleteDialog.type === 'order') setSelectedOrders(new Set());
        else setSelectedSubs(new Set());
      }
    });
  };

  const handleConfirm = () => {
    confirmPayment.mutate({
      id: confirmDialog.id,
      type: confirmDialog.type,
      comment: adminComment
    }, {
      onSuccess: () => {
        setConfirmDialog({ open: false, id: '', type: 'subscription', userName: '' });
        setAdminComment('');
      }
    });
  };

  const getStatusBadge = (status: string) => {
    const config: Record<string, { variant: any; label: string }> = {
      pending: { variant: 'secondary', label: 'Ожидает' },
      active: { variant: 'default', label: 'Активна' },
      frozen: { variant: 'outline', label: 'Заморожена' },
      cancelled: { variant: 'destructive', label: 'Отменена' },
      draft: { variant: 'outline', label: 'Черновик' },
      paid: { variant: 'default', label: 'Оплачено' }
    };
    
    const { variant, label } = config[status] || { variant: 'outline', label: status };
    return <Badge variant={variant}>{label}</Badge>;
  };

  return (
    <div className="p-6 space-y-6">
      <div>
        <h1 className="text-3xl font-bold">Управление оплатами</h1>
        <p className="text-muted-foreground">
          Подтверждение оплат подписок и заказов
        </p>
      </div>

      <div className="flex justify-between items-center mb-4">
        <div className="flex items-center gap-2">
          <Switch
            checked={showArchived}
            onCheckedChange={setShowArchived}
            id="show-archived"
          />
          <Label htmlFor="show-archived">Показывать архивные</Label>
        </div>
      </div>

      <Tabs defaultValue="subscriptions" className="space-y-6">
        <TabsList>
          <TabsTrigger value="subscriptions">Подписки</TabsTrigger>
          <TabsTrigger value="orders">Заказы</TabsTrigger>
        </TabsList>

        <TabsContent value="subscriptions" className="space-y-4">
          <Card>
            <CardHeader className="flex flex-row items-center justify-between">
              <CardTitle>Подписки</CardTitle>
              <div className="flex gap-2">
                <Button
                  variant="outline"
                  size="sm"
                  onClick={() => handleArchiveSelected('subscription')}
                  disabled={selectedSubs.size === 0 || archiveRecords.isPending}
                >
                  <Archive className="h-4 w-4 mr-2" />
                  Скрыть ({selectedSubs.size})
                </Button>
                {userRole === 'superadmin' && (
                  <Button
                    variant="destructive"
                    size="sm"
                    onClick={() => handleDeleteSelected('subscription')}
                    disabled={selectedSubs.size === 0}
                  >
                    <Trash2 className="h-4 w-4 mr-2" />
                    Удалить ({selectedSubs.size})
                  </Button>
                )}
              </div>
            </CardHeader>
            <CardContent>
              {subsLoading ? (
                <div>Загрузка...</div>
              ) : subscriptions.length === 0 ? (
                <div className="text-center py-8 text-muted-foreground">
                  Нет подписок
                </div>
              ) : (
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead className="w-12">
                        <Checkbox
                          checked={subscriptions.length > 0 && selectedSubs.size === subscriptions.length}
                          onCheckedChange={(checked) => {
                            if (checked) {
                              setSelectedSubs(new Set(subscriptions.map(s => s.id)));
                            } else {
                              setSelectedSubs(new Set());
                            }
                          }}
                        />
                      </TableHead>
                      <TableHead>Пользователь</TableHead>
                      <TableHead>Сумма</TableHead>
                      <TableHead>Статус</TableHead>
                      <TableHead>Дата создания</TableHead>
                      <TableHead>Комментарий</TableHead>
                      <TableHead>Действия</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {subscriptions.map((sub) => (
                      <TableRow key={sub.id}>
                        <TableCell>
                          <Checkbox
                            checked={selectedSubs.has(sub.id)}
                            onCheckedChange={(checked) => {
                              const newSet = new Set(selectedSubs);
                              if (checked) {
                                newSet.add(sub.id);
                              } else {
                                newSet.delete(sub.id);
                              }
                              setSelectedSubs(newSet);
                            }}
                          />
                        </TableCell>
                        <TableCell>
                          <div>
                            <div className="font-medium">
                              {sub.profiles?.full_name || 'N/A'}
                            </div>
                            <div className="text-xs text-muted-foreground">
                              {sub.profiles?.email}
                            </div>
                          </div>
                        </TableCell>
                        <TableCell>
                          <div>${sub.amount_usd}</div>
                          <div className="text-xs text-muted-foreground">
                            {sub.amount_kzt} ₸
                          </div>
                        </TableCell>
                        <TableCell>{getStatusBadge(sub.status)}</TableCell>
                        <TableCell>
                          {new Date(sub.created_at).toLocaleDateString('ru-RU')}
                        </TableCell>
                        <TableCell>
                          <span className="text-sm text-muted-foreground">
                            {sub.admin_comment || '—'}
                          </span>
                        </TableCell>
                        <TableCell>
                          {sub.status === 'pending' && (
                            <Button
                              size="sm"
                              onClick={() =>
                                setConfirmDialog({
                                  open: true,
                                  id: sub.id,
                                  type: 'subscription',
                                  userName: sub.profiles?.full_name || 'пользователь'
                                })
                              }
                            >
                              <CheckCircle2 className="h-4 w-4 mr-1" />
                              Подтвердить
                            </Button>
                          )}
                        </TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              )}
            </CardContent>
          </Card>
        </TabsContent>

        <TabsContent value="orders" className="space-y-4">
          <Card>
            <CardHeader className="flex flex-row items-center justify-between">
              <CardTitle>Заказы</CardTitle>
              <div className="flex gap-2">
                <Button
                  variant="outline"
                  size="sm"
                  onClick={() => handleArchiveSelected('order')}
                  disabled={selectedOrders.size === 0 || archiveRecords.isPending}
                >
                  <Archive className="h-4 w-4 mr-2" />
                  Скрыть ({selectedOrders.size})
                </Button>
                {userRole === 'superadmin' && (
                  <Button
                    variant="destructive"
                    size="sm"
                    onClick={() => handleDeleteSelected('order')}
                    disabled={selectedOrders.size === 0}
                  >
                    <Trash2 className="h-4 w-4 mr-2" />
                    Удалить ({selectedOrders.size})
                  </Button>
                )}
              </div>
            </CardHeader>
            <CardContent>
              {ordersLoading ? (
                <div>Загрузка...</div>
              ) : orders.length === 0 ? (
                <div className="text-center py-8 text-muted-foreground">
                  Нет заказов
                </div>
              ) : (
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead className="w-12">
                        <Checkbox
                          checked={orders.length > 0 && selectedOrders.size === orders.length}
                          onCheckedChange={(checked) => {
                            if (checked) {
                              setSelectedOrders(new Set(orders.map(o => o.id)));
                            } else {
                              setSelectedOrders(new Set());
                            }
                          }}
                        />
                      </TableHead>
                      <TableHead>Пользователь</TableHead>
                      <TableHead>Сумма</TableHead>
                      <TableHead>Статус</TableHead>
                      <TableHead>Дата</TableHead>
                      <TableHead>Действия</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {orders.map((order) => (
                      <TableRow key={order.id}>
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
                        <TableCell>
                          <div>
                            <div className="font-medium">
                              {order.profiles?.full_name || 'N/A'}
                            </div>
                            <div className="text-xs text-muted-foreground">
                              {order.profiles?.email}
                            </div>
                          </div>
                        </TableCell>
                        <TableCell>
                          <div>${order.total_usd}</div>
                          <div className="text-xs text-muted-foreground">
                            {order.total_kzt} ₸
                          </div>
                        </TableCell>
                        <TableCell>{getStatusBadge(order.status)}</TableCell>
                        <TableCell>
                          {new Date(order.created_at).toLocaleDateString('ru-RU')}
                        </TableCell>
                        <TableCell>
                          {order.status === 'pending' && (
                            <Button
                              size="sm"
                              onClick={() =>
                                setConfirmDialog({
                                  open: true,
                                  id: order.id,
                                  type: 'order',
                                  userName: order.profiles?.full_name || 'пользователь'
                                })
                              }
                            >
                              <CheckCircle2 className="h-4 w-4 mr-1" />
                              Подтвердить
                            </Button>
                          )}
                        </TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              )}
            </CardContent>
          </Card>
        </TabsContent>
      </Tabs>

      <Dialog open={confirmDialog.open} onOpenChange={(open) => setConfirmDialog({ ...confirmDialog, open })}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Подтверждение оплаты</DialogTitle>
            <DialogDescription>
              Подтвердить {confirmDialog.type === 'subscription' ? 'подписку' : 'заказ'} для пользователя {confirmDialog.userName}?
            </DialogDescription>
          </DialogHeader>
          <div className="space-y-4 py-4">
            <div className="space-y-2">
              <Label htmlFor="comment">Комментарий администратора</Label>
              <Input
                id="comment"
                placeholder="Оплата подтверждена вручную"
                value={adminComment}
                onChange={(e) => setAdminComment(e.target.value)}
              />
            </div>
          </div>
          <DialogFooter>
            <Button
              variant="outline"
              onClick={() => setConfirmDialog({ ...confirmDialog, open: false })}
            >
              Отмена
            </Button>
            <Button
              onClick={handleConfirm}
              disabled={confirmPayment.isPending}
            >
              <CheckCircle2 className="h-4 w-4 mr-2" />
              Подтвердить
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <Dialog open={deleteDialog.open} onOpenChange={(open) => setDeleteDialog({ ...deleteDialog, open })}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle className="text-destructive">⚠️ Безвозвратное удаление</DialogTitle>
            <DialogDescription>
              Это действие удалит выбранные записи НАВСЕГДА и не может быть отменено.
              Для подтверждения введите фразу: <strong>DELETE PERMANENTLY</strong>
            </DialogDescription>
          </DialogHeader>
          <div className="space-y-4 py-4">
            <Input
              placeholder="DELETE PERMANENTLY"
              value={confirmationPhrase}
              onChange={(e) => setConfirmationPhrase(e.target.value)}
            />
          </div>
          <DialogFooter>
            <Button
              variant="outline"
              onClick={() => {
                setDeleteDialog({ ...deleteDialog, open: false });
                setConfirmationPhrase('');
              }}
            >
              Отмена
            </Button>
            <Button
              variant="destructive"
              onClick={handleConfirmDelete}
              disabled={confirmationPhrase !== 'DELETE PERMANENTLY' || hardDeleteRecords.isPending}
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
