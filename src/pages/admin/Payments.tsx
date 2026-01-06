import { useState, useEffect } from "react";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { format } from "date-fns";
import { Archive, Trash2, CheckCircle2, XCircle, Edit2, Save, X, Search } from "lucide-react";
import { Skeleton } from "@/components/ui/skeleton";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { useArchiveRecords, useHardDeleteRecords } from "@/hooks/useArchiveRecords";
import { Checkbox } from "@/components/ui/checkbox";
import { useAuth } from "@/hooks/useAuth";
import { toast } from "sonner";
import { Switch } from "@/components/ui/switch";
import { useManualPayment } from "@/hooks/useManualPayment";
import type { Subscription } from "@/hooks/useSubscriptions";

type Order = {
  id: string;
  user_id: string;
  total_usd: number;
  total_kzt: number;
  status: string;
  created_at: string;
  approval_comment?: string;
  profiles?: {
    full_name: string;
    email: string;
  };
};

export default function AdminPayments() {
  const { userRole } = useAuth();
  const isSuperAdmin = userRole === 'superadmin';
  const queryClient = useQueryClient();
  const [selectedSubscriptions, setSelectedSubscriptions] = useState<Set<string>>(new Set());
  const [selectedOrders, setSelectedOrders] = useState<Set<string>>(new Set());
  const [deleteDialog, setDeleteDialog] = useState<{ open: boolean; type: 'subscriptions' | 'orders' }>({ open: false, type: 'subscriptions' });
  const [deleteConfirmPhrase, setDeleteConfirmPhrase] = useState("");
  const [showArchived, setShowArchived] = useState(false);
  const [searchQuery, setSearchQuery] = useState("");
  const [debouncedSearchQuery, setDebouncedSearchQuery] = useState("");
  
  // Debounce search query
  useEffect(() => {
    const timer = setTimeout(() => {
      setDebouncedSearchQuery(searchQuery);
    }, 400);
    return () => clearTimeout(timer);
  }, [searchQuery]);
  
  // Manual approval states
  const [approveDialogOpen, setApproveDialogOpen] = useState(false);
  const [rejectDialogOpen, setRejectDialogOpen] = useState(false);
  const [approveComment, setApproveComment] = useState("");
  const [rejectComment, setRejectComment] = useState("");
  const [approveProofUrl, setApproveProofUrl] = useState("");
  const [selectedRecordType, setSelectedRecordType] = useState<'subscription' | 'order'>('subscription');
  const [selectedRecordId, setSelectedRecordId] = useState<string>("");

  // Comment editing states
  const [editingComment, setEditingComment] = useState<{ type: 'subscription' | 'order'; id: string; comment: string } | null>(null);

  const archiveRecords = useArchiveRecords();
  const hardDeleteRecords = useHardDeleteRecords();
  const { approvePayment, rejectPayment } = useManualPayment();

  // Subscriptions with search
  const { data: subscriptions, isLoading: isLoadingSubscriptions, isFetching: isFetchingSubscriptions } = useQuery({
    queryKey: ['admin-subscriptions', showArchived, debouncedSearchQuery],
    placeholderData: (previousData) => previousData,
    queryFn: async () => {
      const search = debouncedSearchQuery.trim();
      let userIds: string[] | null = null;

      // If search query exists and is not a valid UUID, find matching user_ids first
      if (search) {
        const isValidUuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(search);
        
        if (!isValidUuid) {
          // Search for matching users by email or full_name
          const { data: profiles, error: profileError } = await supabase
            .from('profiles')
            .select('id')
            .or(`email.ilike.%${search}%,full_name.ilike.%${search}%`);
          
          if (profileError) throw profileError;
          userIds = profiles?.map(p => p.id) || [];
          
          // If no users found, return empty array
          if (userIds.length === 0) return [];
        }
      }

      let query = supabase
        .from('subscriptions')
        .select('*')
        .limit(1000);

      if (!showArchived) {
        query = query.or('is_archived.is.null,is_archived.eq.false');
      }

      // Apply search filters
      if (search) {
        const isValidUuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(search);
        
        if (isValidUuid) {
          // Search by subscription ID or user ID
          query = query.or(`id.eq.${search},user_id.eq.${search}`);
        } else if (userIds && userIds.length > 0) {
          // Search by user_ids found from profiles
          query = query.in('user_id', userIds);
        } else {
          // No matches, return empty
          return [];
        }
      }

      const { data, error } = await query;
      if (error) throw error;
      
      // Fetch all profiles in one query
      const allUserIds = [...new Set((data || []).map(sub => sub.user_id).filter(Boolean))];
      const profilesMap = new Map<string, { full_name: string; email: string }>();
      
      if (allUserIds.length > 0) {
        const { data: profiles } = await supabase
          .from('profiles')
          .select('id, full_name, email')
          .in('id', allUserIds);
        
        profiles?.forEach(p => {
          profilesMap.set(p.id, { full_name: p.full_name || '', email: p.email || '' });
        });
      }
      
      // Map profiles to subscriptions
      const subscriptionsWithProfiles = (data || []).map(sub => ({
        ...sub,
        profiles: profilesMap.get(sub.user_id) || { full_name: '', email: '' }
      }));
      
      // Sort: pending first, then active, then others
      const sortedSubs = subscriptionsWithProfiles.sort((a, b) => {
        const statusOrder = { pending: 0, active: 1, paid: 1, frozen: 2, cancelled: 3, declined: 3 };
        const orderA = statusOrder[a.status as keyof typeof statusOrder] ?? 99;
        const orderB = statusOrder[b.status as keyof typeof statusOrder] ?? 99;
        if (orderA !== orderB) return orderA - orderB;
        return new Date(b.created_at).getTime() - new Date(a.created_at).getTime();
      });
      
      return sortedSubs as Subscription[];
    }
  });

  // Orders with search
  const { data: orders, isLoading: isLoadingOrders, isFetching: isFetchingOrders } = useQuery({
    queryKey: ['admin-orders', showArchived, debouncedSearchQuery],
    placeholderData: (previousData) => previousData,
    queryFn: async () => {
      const search = debouncedSearchQuery.trim();
      let userIds: string[] | null = null;

      // If search query exists and is not a valid UUID, find matching user_ids first
      if (search) {
        const isValidUuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(search);
        
        if (!isValidUuid) {
          // Search for matching users by email or full_name
          const { data: profiles, error: profileError } = await supabase
            .from('profiles')
            .select('id')
            .or(`email.ilike.%${search}%,full_name.ilike.%${search}%`);
          
          if (profileError) throw profileError;
          userIds = profiles?.map(p => p.id) || [];
          
          // If no users found, return empty array
          if (userIds.length === 0) return [];
        }
      }

      let query = supabase
        .from('orders')
        .select('*')
        .limit(1000);

      if (!showArchived) {
        query = query.or('is_archived.is.null,is_archived.eq.false');
      }

      // Apply search filters
      if (search) {
        const isValidUuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(search);
        
        if (isValidUuid) {
          // Search by order ID or user ID
          query = query.or(`id.eq.${search},user_id.eq.${search}`);
        } else if (userIds && userIds.length > 0) {
          // Search by user_ids found from profiles
          query = query.in('user_id', userIds);
        } else {
          // No matches, return empty
          return [];
        }
      }

      const { data, error } = await query;
      if (error) throw error;
      
      // Fetch all profiles in one query
      const allOrderUserIds = [...new Set((data || []).map(order => order.user_id).filter(Boolean))];
      const profilesMap = new Map<string, { full_name: string; email: string }>();
      
      if (allOrderUserIds.length > 0) {
        const { data: profiles } = await supabase
          .from('profiles')
          .select('id, full_name, email')
          .in('id', allOrderUserIds);
        
        profiles?.forEach(p => {
          profilesMap.set(p.id, { full_name: p.full_name || '', email: p.email || '' });
        });
      }
      
      // Map profiles to orders
      const ordersWithProfiles = (data || []).map(order => ({
        ...order,
        profiles: profilesMap.get(order.user_id) || { full_name: '', email: '' }
      }));
      
      // Sort: pending first, then paid, then others
      const sortedOrders = ordersWithProfiles.sort((a, b) => {
        const statusOrder = { pending: 0, paid: 1, draft: 2, cancelled: 3, declined: 3 };
        const orderA = statusOrder[a.status as keyof typeof statusOrder] ?? 99;
        const orderB = statusOrder[b.status as keyof typeof statusOrder] ?? 99;
        if (orderA !== orderB) return orderA - orderB;
        return new Date(b.created_at).getTime() - new Date(a.created_at).getTime();
      });
      
      return sortedOrders as Order[];
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

  const handleSaveComment = async () => {
    if (!editingComment) return;

    try {
      const table = editingComment.type === 'subscription' ? 'subscriptions' : 'orders';
      const { error } = await supabase
        .from(table)
        .update({ 
          approval_comment: editingComment.comment,
          updated_at: new Date().toISOString()
        })
        .eq('id', editingComment.id);

      if (error) throw error;

      toast.success("Комментарий обновлён");
      setEditingComment(null);
      queryClient.invalidateQueries({ queryKey: ['admin-subscriptions'] });
      queryClient.invalidateQueries({ queryKey: ['admin-orders'] });
    } catch (error: any) {
      toast.error(error.message || "Ошибка при сохранении комментария");
    }
  };

  // Archive/delete handlers
  const handleArchiveSelected = (type: 'subscriptions' | 'orders') => {
    const ids = type === 'orders' ? Array.from(selectedOrders) : Array.from(selectedSubscriptions);
    
    if (ids.length === 0) {
      toast.error("Выберите записи для архивации");
      return;
    }

    archiveRecords.mutate({ 
      record_type: type, 
      record_ids: ids 
    }, {
      onSuccess: () => {
        if (type === 'orders') {
          setSelectedOrders(new Set());
        } else {
          setSelectedSubscriptions(new Set());
        }
        toast.success(`Записи архивированы`);
      }
    });
  };

  const handleDeleteSelected = (type: 'subscriptions' | 'orders') => {
    const ids = type === 'orders' ? Array.from(selectedOrders) : Array.from(selectedSubscriptions);
    
    if (ids.length === 0) {
      toast.error("Выберите записи для удаления");
      return;
    }

    setDeleteDialog({ open: true, type });
  };

  const handleConfirmDelete = () => {
    if (deleteConfirmPhrase !== 'УДАЛИТЬ НАВСЕГДА') {
      toast.error("Введите правильную фразу подтверждения");
      return;
    }

    const ids = deleteDialog.type === 'orders' ? Array.from(selectedOrders) : Array.from(selectedSubscriptions);

    hardDeleteRecords.mutate({
      record_type: deleteDialog.type,
      record_ids: ids,
      confirmation_phrase: deleteConfirmPhrase,
      dry_run: false
    }, {
      onSuccess: (data: any) => {
        if (data && data.success === false) {
          toast.error(data.error || "Неизвестная ошибка");
          return;
        }
        setDeleteDialog({ open: false, type: deleteDialog.type });
        setDeleteConfirmPhrase("");
        if (deleteDialog.type === 'orders') {
          setSelectedOrders(new Set());
        } else {
          setSelectedSubscriptions(new Set());
        }
        queryClient.invalidateQueries({ queryKey: ['admin-orders'] });
        queryClient.invalidateQueries({ queryKey: ['admin-subscriptions'] });
        toast.success('Записи удалены навсегда');
      },
      onError: (error: Error) => {
        toast.error(error.message || 'Ошибка при удалении');
      }
    });
  };

  const getStatusBadge = (status: string) => {
    const config: Record<string, { variant: any; label: string }> = {
      pending: { variant: 'secondary', label: 'Ожидает одобрения' },
      active: { variant: 'default', label: 'Активна' },
      frozen: { variant: 'outline', label: 'Заморожена' },
      cancelled: { variant: 'destructive', label: 'Отменена' },
      declined: { variant: 'destructive', label: 'Отклонено' },
      draft: { variant: 'outline', label: 'Черновик' },
      paid: { variant: 'default', label: 'Оплачено' }
    };
    
    const { variant, label } = config[status] || { variant: 'outline', label: status };
    return <Badge variant={variant}>{label}</Badge>;
  };

  return (
    <div className="p-6 space-y-6">
        <div>
          <h1 className="text-3xl font-bold mb-2">Управление оплатами</h1>
          <p className="text-muted-foreground">
            Одобрение и отклонение заявок на ручную оплату подписок и активаций
          </p>
        </div>

        <div className="flex items-center gap-4">
          <div className="flex items-center gap-2">
            <Switch
              id="show-archived"
              checked={showArchived}
              onCheckedChange={setShowArchived}
            />
            <Label htmlFor="show-archived">Показывать архивные</Label>
          </div>

          <div className="relative flex-1 max-w-md">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
            <Input
              placeholder="Поиск по email, имени, ID..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              className="pl-9"
            />
          </div>
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
                {isSuperAdmin && (
                  <div className="flex gap-2">
                    <Button
                      variant="outline"
                      size="sm"
                      onClick={() => handleArchiveSelected('subscriptions')}
                      disabled={selectedSubscriptions.size === 0 || archiveRecords.isPending}
                    >
                      <Archive className="h-4 w-4 mr-2" />
                      Скрыть ({selectedSubscriptions.size})
                    </Button>
                    <Button
                      variant="destructive"
                      size="sm"
                      onClick={() => handleDeleteSelected('subscriptions')}
                      disabled={selectedSubscriptions.size === 0}
                    >
                      <Trash2 className="h-4 w-4 mr-2" />
                      Удалить ({selectedSubscriptions.size})
                    </Button>
                  </div>
                )}
              </CardHeader>
              <CardContent>
                {isLoadingSubscriptions ? (
                  <div className="space-y-3 py-4">
                    {[1, 2, 3, 4, 5].map((i) => <Skeleton key={i} className="h-16 w-full" />)}
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
                            <div className="font-semibold">{sub.amount_kzt.toLocaleString('ru-RU')} ₸</div>
                          </TableCell>
                          <TableCell>{getStatusBadge(sub.status)}</TableCell>
                          <TableCell>
                            {new Date(sub.created_at).toLocaleDateString('ru-RU')}
                          </TableCell>
                          <TableCell>
                            {editingComment?.type === 'subscription' && editingComment?.id === sub.id ? (
                              <div className="flex items-center gap-2">
                                <Textarea
                                  value={editingComment.comment}
                                  onChange={(e) => setEditingComment({ ...editingComment, comment: e.target.value })}
                                  className="min-h-[60px] text-sm"
                                  placeholder="Комментарий..."
                                />
                                <div className="flex flex-col gap-1">
                                  <Button
                                    size="sm"
                                    variant="default"
                                    onClick={handleSaveComment}
                                  >
                                    <Save className="h-4 w-4" />
                                  </Button>
                                  <Button
                                    size="sm"
                                    variant="ghost"
                                    onClick={() => setEditingComment(null)}
                                  >
                                    <X className="h-4 w-4" />
                                  </Button>
                                </div>
                              </div>
                            ) : (
                              <div className="flex items-center gap-2">
                                <span className="text-sm text-muted-foreground flex-1">
                                  {sub.approval_comment || '—'}
                                </span>
                                {sub.approval_comment && userRole === 'superadmin' && (
                                  <Button
                                    size="sm"
                                    variant="ghost"
                                    onClick={() => setEditingComment({
                                      type: 'subscription',
                                      id: sub.id,
                                      comment: sub.approval_comment || ''
                                    })}
                                  >
                                    <Edit2 className="h-4 w-4" />
                                  </Button>
                                )}
                              </div>
                            )}
                          </TableCell>
                          <TableCell>
                            {sub.status === 'pending' && isSuperAdmin && (
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
                {isSuperAdmin && (
                  <div className="flex gap-2">
                    <Button
                      variant="outline"
                      size="sm"
                      onClick={() => handleArchiveSelected('orders')}
                      disabled={selectedOrders.size === 0 || archiveRecords.isPending}
                    >
                      <Archive className="h-4 w-4 mr-2" />
                      Скрыть ({selectedOrders.size})
                    </Button>
                    <Button
                      variant="destructive"
                      size="sm"
                      onClick={() => handleDeleteSelected('orders')}
                      disabled={selectedOrders.size === 0}
                    >
                      <Trash2 className="h-4 w-4 mr-2" />
                      Удалить ({selectedOrders.size})
                    </Button>
                  </div>
                )}
              </CardHeader>
              <CardContent>
                {isLoadingOrders ? (
                  <div className="space-y-3 py-4">
                    {[1, 2, 3, 4, 5].map((i) => <Skeleton key={i} className="h-16 w-full" />)}
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
                        <TableHead>Комментарий</TableHead>
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
                            <div className="font-semibold">{order.total_kzt.toLocaleString('ru-RU')} ₸</div>
                          </TableCell>
                          <TableCell>{getStatusBadge(order.status)}</TableCell>
                          <TableCell>
                            {new Date(order.created_at).toLocaleDateString('ru-RU')}
                          </TableCell>
                          <TableCell>
                            {editingComment?.type === 'order' && editingComment?.id === order.id ? (
                              <div className="flex items-center gap-2">
                                <Textarea
                                  value={editingComment.comment}
                                  onChange={(e) => setEditingComment({ ...editingComment, comment: e.target.value })}
                                  className="min-h-[60px] text-sm"
                                  placeholder="Комментарий..."
                                />
                                <div className="flex flex-col gap-1">
                                  <Button
                                    size="sm"
                                    variant="default"
                                    onClick={handleSaveComment}
                                  >
                                    <Save className="h-4 w-4" />
                                  </Button>
                                  <Button
                                    size="sm"
                                    variant="ghost"
                                    onClick={() => setEditingComment(null)}
                                  >
                                    <X className="h-4 w-4" />
                                  </Button>
                                </div>
                              </div>
                            ) : (
                              <div className="flex items-center gap-2">
                                <span className="text-sm text-muted-foreground flex-1">
                                  {order.approval_comment || '—'}
                                </span>
                                {order.approval_comment && userRole === 'superadmin' && (
                                  <Button
                                    size="sm"
                                    variant="ghost"
                                    onClick={() => setEditingComment({
                                      type: 'order',
                                      id: order.id,
                                      comment: order.approval_comment || ''
                                    })}
                                  >
                                    <Edit2 className="h-4 w-4" />
                                  </Button>
                                )}
                              </div>
                            )}
                          </TableCell>
                          <TableCell>
                            {order.status === 'pending' && isSuperAdmin && (
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
        <Dialog open={approveDialogOpen} onOpenChange={(open) => {
          if (!approvePayment.isPending) setApproveDialogOpen(open);
        }}>
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
                  disabled={approvePayment.isPending}
                />
              </div>
              <div className="space-y-2">
                <Label htmlFor="proof-url">Ссылка на подтверждение (опционально)</Label>
                <Input
                  id="proof-url"
                  placeholder="https://example.com/receipt.pdf"
                  value={approveProofUrl}
                  onChange={(e) => setApproveProofUrl(e.target.value)}
                  disabled={approvePayment.isPending}
                />
              </div>
            </div>
            <DialogFooter>
              <Button 
                variant="outline" 
                onClick={() => setApproveDialogOpen(false)}
                disabled={approvePayment.isPending}
              >
                Отмена
              </Button>
              <Button 
                onClick={handleConfirmApprove}
                disabled={approvePayment.isPending || !approveComment.trim()}
              >
                {approvePayment.isPending ? (
                  "Одобрение..."
                ) : (
                  <><CheckCircle2 className="mr-2 h-4 w-4" />Одобрить</>
                )}
              </Button>
            </DialogFooter>
          </DialogContent>
        </Dialog>

        {/* Reject Dialog */}
        <Dialog open={rejectDialogOpen} onOpenChange={(open) => {
          if (!rejectPayment.isPending) setRejectDialogOpen(open);
        }}>
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
                  disabled={rejectPayment.isPending}
                />
              </div>
            </div>
            <DialogFooter>
              <Button 
                variant="outline" 
                onClick={() => setRejectDialogOpen(false)}
                disabled={rejectPayment.isPending}
              >
                Отмена
              </Button>
              <Button 
                variant="destructive"
                onClick={handleConfirmReject}
                disabled={rejectPayment.isPending || !rejectComment.trim()}
              >
                {rejectPayment.isPending ? (
                  "Отклонение..."
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
                Для подтверждения введите фразу: <strong>УДАЛИТЬ НАВСЕГДА</strong>
              </DialogDescription>
            </DialogHeader>
            <div className="space-y-4 py-4">
              <Input
                placeholder="УДАЛИТЬ НАВСЕГДА"
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
                disabled={deleteConfirmPhrase !== 'УДАЛИТЬ НАВСЕГДА' || hardDeleteRecords.isPending}
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
