import { useState } from "react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Input } from "@/components/ui/input";
import { useSecurityLogs, useSecurityStats, SecurityLog } from "@/hooks/useSecurityLogs";
import { 
  Shield, 
  ShieldAlert, 
  ShieldCheck, 
  UserPlus, 
  UserX, 
  Search,
  RefreshCw,
  AlertTriangle,
  CheckCircle,
  XCircle,
  Users,
  CreditCard,
  RotateCcw
} from "lucide-react";
import { format } from "date-fns";
import { ru } from "date-fns/locale";

const LOG_TYPE_CONFIG: Record<string, { label: string; icon: React.ReactNode; variant: "default" | "secondary" | "destructive" | "outline" }> = {
  'referral_bound': { 
    label: 'Привязка реферала', 
    icon: <UserPlus className="h-4 w-4" />,
    variant: 'default'
  },
  'referral_bind_failed': { 
    label: 'Ошибка привязки', 
    icon: <UserX className="h-4 w-4" />,
    variant: 'destructive'
  },
  'admin_bind_sponsor_success': { 
    label: 'Админ: привязка', 
    icon: <ShieldCheck className="h-4 w-4" />,
    variant: 'default'
  },
  'admin_bind_sponsor_failed': { 
    label: 'Админ: ошибка', 
    icon: <ShieldAlert className="h-4 w-4" />,
    variant: 'destructive'
  },
  'account_restored': { 
    label: 'Восстановление', 
    icon: <RotateCcw className="h-4 w-4" />,
    variant: 'secondary'
  },
  'registration': { 
    label: 'Регистрация', 
    icon: <Users className="h-4 w-4" />,
    variant: 'outline'
  },
  'subscription_activated': { 
    label: 'Подписка', 
    icon: <CreditCard className="h-4 w-4" />,
    variant: 'outline'
  }
};

const FAILURE_REASONS: Record<string, string> = {
  'already_bound': 'Уже привязан к спонсору',
  'already_sponsor': 'Уже является спонсором для других',
  'invalid_code': 'Неверный реферальный код',
  'self_referral': 'Попытка привязки к себе',
  'sponsor_registered_later': 'Спонсор зарегистрирован позже пользователя',
  'SPONSOR_NOT_FOUND': 'Спонсор не найден',
  'SELF_REFERRAL': 'Попытка привязки к себе',
  'ALREADY_HAS_SPONSOR': 'Уже есть спонсор',
  'USER_IS_SPONSOR': 'Уже является спонсором',
  'SPONSOR_REGISTERED_LATER': 'Спонсор зарегистрирован позже'
};

export default function SecurityLogs() {
  const [days, setDays] = useState(7);
  const [filterType, setFilterType] = useState<string>('all');
  const [searchQuery, setSearchQuery] = useState("");
  
  const { data: logs, isLoading, refetch } = useSecurityLogs(days);
  const { data: stats } = useSecurityStats(days);

  const filteredLogs = (logs || []).filter(log => {
    if (filterType !== 'all' && log.type !== filterType) return false;
    
    if (searchQuery.trim()) {
      const search = searchQuery.toLowerCase();
      const userMatch = log.user?.full_name?.toLowerCase().includes(search) ||
                        log.user?.email?.toLowerCase().includes(search);
      const payloadMatch = JSON.stringify(log.payload).toLowerCase().includes(search);
      return userMatch || payloadMatch;
    }
    
    return true;
  });

  const suspiciousLogs = (logs || []).filter(log => 
    log.type === 'referral_bind_failed' && 
    (log.payload?.reason === 'sponsor_registered_later' || 
     log.payload?.reason === 'already_sponsor' ||
     log.payload?.reason === 'SPONSOR_REGISTERED_LATER' ||
     log.payload?.reason === 'USER_IS_SPONSOR')
  );

  const renderPayload = (log: SecurityLog) => {
    const payload = log.payload;
    if (!payload) return null;

    if (log.type.includes('failed')) {
      const reason = FAILURE_REASONS[payload.reason] || payload.reason || 'Неизвестная причина';
      return (
        <div className="text-sm space-y-1">
          <div className="flex items-center gap-1 text-destructive">
            <XCircle className="h-3 w-3" />
            <span>{reason}</span>
          </div>
          {payload.attempted_code && (
            <div className="text-muted-foreground">Код: {payload.attempted_code}</div>
          )}
          {payload.attempted_sponsor_name && (
            <div className="text-muted-foreground">Попытка привязки к: {payload.attempted_sponsor_name}</div>
          )}
          {payload.message && (
            <div className="text-xs text-muted-foreground italic">{payload.message}</div>
          )}
        </div>
      );
    }

    if (log.type === 'referral_bound' || log.type === 'admin_bind_sponsor_success') {
      return (
        <div className="text-sm space-y-1">
          <div className="flex items-center gap-1 text-green-600">
            <CheckCircle className="h-3 w-3" />
            <span>Успешно привязан</span>
          </div>
          {payload.sponsor_name && (
            <div className="text-muted-foreground">Спонсор: {payload.sponsor_name}</div>
          )}
          {payload.admin_id && (
            <div className="text-muted-foreground text-xs">Через админку</div>
          )}
        </div>
      );
    }

    if (log.type === 'registration') {
      return (
        <div className="text-sm">
          <div className="text-muted-foreground">
            {payload.full_name || 'Без имени'}
          </div>
          {payload.sponsor_id && (
            <div className="text-xs text-muted-foreground">С рефералом</div>
          )}
        </div>
      );
    }

    if (log.type === 'subscription_activated') {
      return (
        <div className="text-sm">
          <div className="text-green-600">{payload.amount_kzt?.toLocaleString('ru-RU') || payload.amount_usd} ₸</div>
        </div>
      );
    }

    if (log.type === 'account_restored') {
      return (
        <div className="text-sm text-muted-foreground">
          {payload.reason || 'Аккаунт восстановлен'}
        </div>
      );
    }

    return (
      <div className="text-xs text-muted-foreground max-w-xs truncate">
        {JSON.stringify(payload)}
      </div>
    );
  };

  return (
    <div className="p-8 space-y-6">
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2">
          <Shield className="h-6 w-6" />
          <h1 className="text-2xl font-bold">Логи безопасности</h1>
        </div>
        <Button onClick={() => refetch()} variant="outline" size="sm">
          <RefreshCw className="h-4 w-4 mr-2" />
          Обновить
        </Button>
      </div>

      {/* Stats Cards */}
      <div className="grid grid-cols-2 md:grid-cols-4 lg:grid-cols-7 gap-4">
        <Card>
          <CardContent className="pt-4">
            <div className="text-2xl font-bold">{stats?.total || 0}</div>
            <div className="text-xs text-muted-foreground">Всего событий</div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="pt-4">
            <div className="text-2xl font-bold text-green-600">{stats?.successful_binds || 0}</div>
            <div className="text-xs text-muted-foreground">Успешных привязок</div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="pt-4">
            <div className="text-2xl font-bold text-destructive">{stats?.failed_binds || 0}</div>
            <div className="text-xs text-muted-foreground">Неудачных привязок</div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="pt-4">
            <div className="text-2xl font-bold">{stats?.admin_actions || 0}</div>
            <div className="text-xs text-muted-foreground">Действий админов</div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="pt-4">
            <div className="text-2xl font-bold">{stats?.registrations || 0}</div>
            <div className="text-xs text-muted-foreground">Регистраций</div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="pt-4">
            <div className="text-2xl font-bold">{stats?.subscriptions || 0}</div>
            <div className="text-xs text-muted-foreground">Подписок</div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="pt-4">
            <div className="text-2xl font-bold">{stats?.restorations || 0}</div>
            <div className="text-xs text-muted-foreground">Восстановлений</div>
          </CardContent>
        </Card>
      </div>

      {/* Suspicious Activity Alert */}
      {suspiciousLogs.length > 0 && (
        <Card className="border-destructive bg-destructive/5">
          <CardHeader className="pb-2">
            <CardTitle className="text-destructive flex items-center gap-2">
              <AlertTriangle className="h-5 w-5" />
              Подозрительная активность ({suspiciousLogs.length})
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-sm text-muted-foreground mb-2">
              Обнаружены попытки привязки к спонсорам, зарегистрированным позже, или привязки уже являющихся спонсорами пользователей.
            </div>
            <div className="space-y-2">
              {suspiciousLogs.slice(0, 5).map(log => (
                <div key={log.id} className="text-sm flex items-center gap-2">
                  <Badge variant="destructive" className="text-xs">
                    {format(new Date(log.created_at), 'dd.MM HH:mm', { locale: ru })}
                  </Badge>
                  <span>{log.user?.email || log.user_id}</span>
                  <span className="text-muted-foreground">→</span>
                  <span>{log.payload?.attempted_sponsor_name || log.payload?.attempted_code}</span>
                </div>
              ))}
            </div>
          </CardContent>
        </Card>
      )}

      {/* Filters */}
      <Card>
        <CardHeader>
          <CardTitle>Фильтры</CardTitle>
        </CardHeader>
        <CardContent>
          <div className="flex flex-wrap gap-4">
            <div className="flex items-center gap-2">
              <span className="text-sm text-muted-foreground">Период:</span>
              <Select value={days.toString()} onValueChange={(v) => setDays(parseInt(v))}>
                <SelectTrigger className="w-32">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="1">1 день</SelectItem>
                  <SelectItem value="7">7 дней</SelectItem>
                  <SelectItem value="14">14 дней</SelectItem>
                  <SelectItem value="30">30 дней</SelectItem>
                  <SelectItem value="90">90 дней</SelectItem>
                </SelectContent>
              </Select>
            </div>
            
            <div className="flex items-center gap-2">
              <span className="text-sm text-muted-foreground">Тип:</span>
              <Select value={filterType} onValueChange={setFilterType}>
                <SelectTrigger className="w-48">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="all">Все события</SelectItem>
                  <SelectItem value="referral_bound">Успешные привязки</SelectItem>
                  <SelectItem value="referral_bind_failed">Неудачные привязки</SelectItem>
                  <SelectItem value="admin_bind_sponsor_success">Админ: успех</SelectItem>
                  <SelectItem value="admin_bind_sponsor_failed">Админ: ошибка</SelectItem>
                  <SelectItem value="registration">Регистрации</SelectItem>
                  <SelectItem value="subscription_activated">Подписки</SelectItem>
                  <SelectItem value="account_restored">Восстановления</SelectItem>
                </SelectContent>
              </Select>
            </div>

            <div className="flex-1 min-w-64">
              <div className="relative">
                <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
                <Input
                  placeholder="Поиск по email, имени или данным..."
                  value={searchQuery}
                  onChange={(e) => setSearchQuery(e.target.value)}
                  className="pl-9"
                />
              </div>
            </div>
          </div>
        </CardContent>
      </Card>

      {/* Logs Table */}
      <Card>
        <CardHeader>
          <CardTitle>События ({filteredLogs.length})</CardTitle>
        </CardHeader>
        <CardContent>
          {isLoading ? (
            <div className="flex items-center justify-center h-32">Загрузка...</div>
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead className="w-40">Дата/время</TableHead>
                  <TableHead className="w-48">Тип</TableHead>
                  <TableHead>Пользователь</TableHead>
                  <TableHead>Детали</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {filteredLogs.length === 0 ? (
                  <TableRow>
                    <TableCell colSpan={4} className="text-center text-muted-foreground">
                      Нет событий за выбранный период
                    </TableCell>
                  </TableRow>
                ) : (
                  filteredLogs.map((log) => {
                    const config = LOG_TYPE_CONFIG[log.type] || { 
                      label: log.type, 
                      icon: <Shield className="h-4 w-4" />,
                      variant: 'outline' as const
                    };
                    
                    return (
                      <TableRow key={log.id}>
                        <TableCell className="text-sm">
                          {format(new Date(log.created_at), 'dd.MM.yyyy HH:mm:ss', { locale: ru })}
                        </TableCell>
                        <TableCell>
                          <Badge variant={config.variant} className="flex items-center gap-1 w-fit">
                            {config.icon}
                            {config.label}
                          </Badge>
                        </TableCell>
                        <TableCell>
                          <div className="text-sm">
                            <div className="font-medium">{log.user?.full_name || 'Без имени'}</div>
                            <div className="text-muted-foreground text-xs">{log.user?.email || log.user_id}</div>
                          </div>
                        </TableCell>
                        <TableCell>
                          {renderPayload(log)}
                        </TableCell>
                      </TableRow>
                    );
                  })
                )}
              </TableBody>
            </Table>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
