import { useState } from "react";
import { AppLayout } from "@/components/Layout/AppLayout";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { useSubscriptions } from "@/hooks/useSubscriptions";
import { useQuery } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { format } from "date-fns";
import { Loader2, Archive, Trash2, CheckCircle2, XCircle } from "lucide-react";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { useArchiveRecords } from "@/hooks/useArchiveRecords";
import { Checkbox } from "@/components/ui/checkbox";
import { useAuth } from "@/hooks/useAuth";
import { toast } from "sonner";
import { Switch } from "@/components/ui/switch";
import { useManualPayment } from "@/hooks/useManualPayment";

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
  const [selectedSubscriptions, setSelectedSubscriptions] = useState<Set<string>>(new Set());
  const [selectedOrders, setSelectedOrders] = useState<Set<string>>(new Set());
  const [deleteDialog, setDeleteDialog] = useState<{ open: boolean; type: 'subscription' | 'order' }>({ open: false, type: 'subscription' });
  const [deleteConfirmPhrase, setDeleteConfirmPhrase] = useState("");
  const [showArchived, setShowArchived] = useState(false);
  
  // Manual approval states
  const [approveDialogOpen, setApproveDialogOpen] = useState(false);
  const [rejectDialogOpen, setRejectDialogOpen] = useState(false);
  const [approveComment, setApproveComment] = useState("");
  const [rejectComment, setRejectComment] = useState("");
  const [approveProofUrl, setApproveProofUrl] = useState("");
  const [selectedRecordType, setSelectedRecordType] = useState<'subscription' | 'order'>('subscription');
  const [selectedRecordId, setSelectedRecordId] = useState<string>("");

  const { data: subscriptions, isLoading: isLoadingSubscriptions } = useSubscriptions(showArchived);
  const archiveRecords = useArchiveRecords();
  const hardDeleteRecords = useArchiveRecords();
  const { approvePayment, rejectPayment } = useManualPayment();

  const { data: orders, isLoading: isLoadingOrders } = useQuery({
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

  const handleApprove = (type: 'subscription' | 'order', id: string) => {
    setSelectedRecordType(type);
    setSelectedRecordId(id);
    setApproveComment("");
    setApproveProofUrl("");
    setApproveDialogOpen(true);
  };

  const handleReject = (type: 'subscription' | 'order', id: string) => {
    setSelectedRecordType(type);
    setSelectedRecordId(id);
    setRejectComment("");
    setRejectDialogOpen(true);
  };

  const handleConfirmApprove = async () => {
    if (!approveComment.trim()) {
      toast.error("Комментарий обязателен");
      return;
    }

    try {
      await approvePayment.mutateAsync({
        record_type: selectedRecordType,
        record_id: selectedRecordId,
        comment: approveComment,
        payment_proof_url: approveProofUrl || undefined
      });
      setApproveDialogOpen(false);
    } catch (error) {
      console.error('Approve error:', error);
    }
  };

  const handleConfirmReject = async () => {
    if (!rejectComment.trim()) {
      toast.error("Комментарий обязателен");
      return;
    }

    try {
      await rejectPayment.mutateAsync({
        record_type: selectedRecordType,
        record_id: selectedRecordId,
        comment: rejectComment
      });
      setRejectDialogOpen(false);
    } catch (error) {
      console.error('Reject error:', error);
    }
  };

  // Archive/delete handlers
  const handleArchiveSelected = (type: 'subscription' | 'order') => {
    const ids = type === 'order' ? Array.from(selectedOrders) : Array.from(selectedSubscriptions);
    
    if (ids.length === 0) {
      toast.error("Выберите записи для архивации");
      return;
    }

    archiveRecords.mutate({ 
      record_type: type, 
      record_ids: ids 
    }, {
      onSuccess: () => {
        if (type === 'order') {
          setSelectedOrders(new Set());
        } else {
          setSelectedSubscriptions(new Set());
        }
        toast.success(`Записи архивированы`);
      }
    });
  };

  const handleDeleteSelected = (type: 'subscription' | 'order') => {
    const ids = type === 'order' ? Array.from(selectedOrders) : Array.from(selectedSubscriptions);
    
    if (ids.length === 0) {
      toast.error("Выберите записи для удаления");
      return;
    }

    setDeleteDialog({ open: true, type });
  };

  const handleConfirmDelete = () => {
    const ids = deleteDialog.type === 'order' ? Array.from(selectedOrders) : Array.from(selectedSubscriptions);

    hardDeleteRecords.mutate({
      record_type: deleteDialog.type,
      record_ids: ids,
      confirmation_phrase: deleteConfirmPhrase,
      dry_run: false
    }, {
      onSuccess: () => {
        setDeleteDialog({ open: false, type: deleteDialog.type });
        setDeleteConfirmPhrase("");
        if (deleteDialog.type === 'order') {
          setSelectedOrders(new Set());
        } else {
          setSelectedSubscriptions(new Set());
        }
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
    <AppLayout>
      <>
      <div className="space-y-6">
        <div>
          <h1 className="text-3xl font-bold mb-2">Управление оплатами</h1>
          <p className="text-muted-foreground">
            Одобрение и отклонение заявок на ручную оплату подписок и активаций
          </p>
        </div>

        <div className="flex items-center gap-2">
          <Switch
            id="show-archived"
            checked={showArchived}
            onCheckedChange={setShowArchived}
          />
          <Label htmlFor="show-archived">Показывать архивные</Label>
        </div>

        <Tabs defaultValue="subscriptions" className="space-y-4">
          <TabsList>
            <TabsTrigger value="subscriptions">Подписки</TabsTrigger>
            <TabsTrigger value="orders">Заказы (Активации)</TabsTrigger>
          </TabsList>

          <TabsContent value="subscriptions" className="space-y-4">
            <Card>
              <CardHeader className="flex flex-row items-center justify-between">
                <div>
                  <CardTitle>Подписки</CardTitle>
                  <CardDescription>Управление заявками на подписку</CardDescription>
                </div>
                <div className="flex gap-2">
                  <Button
                    variant="outline"
                    size="sm"
                    onClick={() => handleArchiveSelected('subscription')}
                    disabled={selectedSubscriptions.size === 0 || archiveRecords.isPending}
                  >
                    <Archive className="h-4 w-4 mr-2" />
                    Скрыть ({selectedSubscriptions.size})
                  </Button>
                  {userRole === 'superadmin' && (
                    <Button
                      variant="destructive"
                      size="sm"
                      onClick={() => handleDeleteSelected('subscription')}
                      disabled={selectedSubscriptions.size === 0}
                    >
                      <Trash2 className="h-4 w-4 mr-2" />
                      Удалить ({selectedSubscriptions.size})
                    </Button>
                  )}
                </div>
              </CardHeader>
              <CardContent>
                {isLoadingSubscriptions ? (
                  <div className="flex justify-center py-8">
                    <Loader2 className="h-8 w-8 animate-spin" />
                  </div>
                ) : !subscriptions || subscriptions.length === 0 ? (
                  <div className="text-center py-8 text-muted-foreground">
                    Нет подписок
                  </div>
                ) : (
                  <Table>
                    <TableHeader>
                      <TableRow>
                        <TableHead className="w-12">
                          <Checkbox
                            checked={subscriptions.length > 0 && selectedSubscriptions.size === subscriptions.length}
                            onCheckedChange={(checked) => {
                              if (checked) {
                                setSelectedSubscriptions(new Set(subscriptions.map(s => s.id)));
                              } else {
                                setSelectedSubscriptions(new Set());
                              }
                            }}
                          />
                        </TableHead>
                        <TableHead>Пользователь</TableHead>
                        <TableHead>Сумма</TableHead>
                        <TableHead>Статус</TableHead>
                        <TableHead>Дата</TableHead>
                        <TableHead>Комментарий</TableHead>
                        <TableHead>Действия</TableHead>
                      </TableRow>
                    </TableHeader>
                    <TableBody>
                      {subscriptions.map((sub) => (
                        <TableRow key={sub.id}>
                          <TableCell>
                            <Checkbox
                              checked={selectedSubscriptions.has(sub.id)}
                              onCheckedChange={(checked) => {
                                const newSet = new Set(selectedSubscriptions);
                                if (checked) {
                                  newSet.add(sub.id);
                                } else {
                                  newSet.delete(sub.id);
                                }
                                setSelectedSubscriptions(newSet);
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
                              <div className="flex gap-1">
                                <Button
                                  size="sm"
                                  onClick={() => handleApprove('subscription', sub.id)}
                                >
                                  <CheckCircle2 className="h-4 w-4 mr-1" />
                                  Одобрить
                                </Button>
                                <Button
                                  size="sm"
                                  variant="destructive"
                                  onClick={() => handleReject('subscription', sub.id)}
                                >
                                  <XCircle className="h-4 w-4 mr-1" />
                                  Отклонить
                                </Button>
                              </div>
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
                <div>
                  <CardTitle>Заказы (Активации)</CardTitle>
                  <CardDescription>Управление заявками на активацию</CardDescription>
                </div>
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
                {isLoadingOrders ? (
                  <div className="flex justify-center py-8">
                    <Loader2 className="h-8 w-8 animate-spin" />
                  </div>
                ) : !orders || orders.length === 0 ? (
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
                              <div className="flex gap-1">
                                <Button
                                  size="sm"
                                  onClick={() => handleApprove('order', order.id)}
                                >
                                  <CheckCircle2 className="h-4 w-4 mr-1" />
                                  Одобрить
                                </Button>
                                <Button
                                  size="sm"
                                  variant="destructive"
                                  onClick={() => handleReject('order', order.id)}
                                >
                                  <XCircle className="h-4 w-4 mr-1" />
                                  Отклонить
                                </Button>
                              </div>
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

        {/* Approve Dialog */}
        <Dialog open={approveDialogOpen} onOpenChange={setApproveDialogOpen}>
          <DialogContent>
            <DialogHeader>
              <DialogTitle>Одобрить платёж</DialogTitle>
              <DialogDescription>
                Подтвердите одобрение {selectedRecordType === 'subscription' ? 'подписки' : 'активации'}
              </DialogDescription>
            </DialogHeader>
            <div className="space-y-4 py-4">
              <div className="space-y-2">
                <Label htmlFor="approve-comment">Комментарий *</Label>
                <Textarea
                  id="approve-comment"
                  placeholder="Оплата подтверждена, квитанция проверена..."
                  value={approveComment}
                  onChange={(e) => setApproveComment(e.target.value)}
                />
              </div>
              <div className="space-y-2">
                <Label htmlFor="proof-url">Ссылка на подтверждение (опционально)</Label>
                <Input
                  id="proof-url"
                  placeholder="https://example.com/receipt.pdf"
                  value={approveProofUrl}
                  onChange={(e) => setApproveProofUrl(e.target.value)}
                />
              </div>
            </div>
            <DialogFooter>
              <Button variant="outline" onClick={() => setApproveDialogOpen(false)}>
                Отмена
              </Button>
              <Button 
                onClick={handleConfirmApprove}
                disabled={approvePayment.isPending || !approveComment.trim()}
              >
                {approvePayment.isPending ? (
                  <><Loader2 className="mr-2 h-4 w-4 animate-spin" />Одобрение...</>
                ) : (
                  <><CheckCircle2 className="mr-2 h-4 w-4" />Одобрить</>
                )}
              </Button>
            </DialogFooter>
          </DialogContent>
        </Dialog>

        {/* Reject Dialog */}
        <Dialog open={rejectDialogOpen} onOpenChange={setRejectDialogOpen}>
          <DialogContent>
            <DialogHeader>
              <DialogTitle>Отклонить платёж</DialogTitle>
              <DialogDescription>
                Укажите причину отклонения {selectedRecordType === 'subscription' ? 'подписки' : 'активации'}
              </DialogDescription>
            </DialogHeader>
            <div className="space-y-4 py-4">
              <div className="space-y-2">
                <Label htmlFor="reject-comment">Причина отклонения *</Label>
                <Textarea
                  id="reject-comment"
                  placeholder="Недостаточно средств, некорректная квитанция..."
                  value={rejectComment}
                  onChange={(e) => setRejectComment(e.target.value)}
                />
              </div>
            </div>
            <DialogFooter>
              <Button variant="outline" onClick={() => setRejectDialogOpen(false)}>
                Отмена
              </Button>
              <Button 
                variant="destructive"
                onClick={handleConfirmReject}
                disabled={rejectPayment.isPending || !rejectComment.trim()}
              >
                {rejectPayment.isPending ? (
                  <><Loader2 className="mr-2 h-4 w-4 animate-spin" />Отклонение...</>
                ) : (
                  <><XCircle className="mr-2 h-4 w-4" />Отклонить</>
                )}
              </Button>
            </DialogFooter>
          </DialogContent>
        </Dialog>

        {/* Delete Dialog */}
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
                value={deleteConfirmPhrase}
                onChange={(e) => setDeleteConfirmPhrase(e.target.value)}
              />
            </div>
            <DialogFooter>
              <Button
                variant="outline"
                onClick={() => {
                  setDeleteDialog({ ...deleteDialog, open: false });
                  setDeleteConfirmPhrase('');
                }}
              >
                Отмена
              </Button>
              <Button
                variant="destructive"
                onClick={handleConfirmDelete}
                disabled={deleteConfirmPhrase !== 'DELETE PERMANENTLY' || hardDeleteRecords.isPending}
              >
                <Trash2 className="h-4 w-4 mr-2" />
                Удалить навсегда
              </Button>
            </DialogFooter>
          </DialogContent>
        </Dialog>
      </div>
      </>
    </AppLayout>
  );
}
