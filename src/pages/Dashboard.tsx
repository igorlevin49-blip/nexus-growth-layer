import { Calendar, Target, Users, Copy } from "lucide-react";
import { DashboardStats } from "@/components/Dashboard/DashboardStats";
import { NetworkTree } from "@/components/Dashboard/NetworkTree";
import { ActivationProgress } from "@/components/Dashboard/ActivationProgress";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";
import { useAuth } from "@/hooks/useAuth";
import { useProfile } from "@/hooks/useProfile";
import { useNetworkTree } from "@/hooks/useNetworkTree";
import { useTransactions } from "@/hooks/useTransactions";
import { toast } from "sonner";
import { formatCents } from "@/utils/formatMoney";
import { useEffect } from "react";
import { useSearchParams } from "react-router-dom";

export default function Dashboard() {
  const { user } = useAuth();
  const { data: profile, isLoading: profileLoading } = useProfile();
  const { data: networkMembers = [] } = useNetworkTree(10);
  const { data: transactions = [], isLoading: transactionsLoading } = useTransactions({ limit: 3 });
  const [searchParams, setSearchParams] = useSearchParams();

  // Handle payment result
  useEffect(() => {
    const paymentStatus = searchParams.get('payment');
    if (paymentStatus === 'success') {
      toast.success('Оплата успешно завершена!', {
        description: 'Ваша активация обновлена.',
      });
      setSearchParams({});
    } else if (paymentStatus === 'failure') {
      toast.error('Оплата не завершена', {
        description: 'Попробуйте снова или обратитесь в поддержку.',
      });
      setSearchParams({});
    }
  }, [searchParams, setSearchParams]);

  // Get user display name
  const getUserName = () => {
    if (profileLoading) return "...";
    
    if (profile?.full_name) {
      return profile.full_name;
    }
    
    if (user?.user_metadata?.full_name) {
      return user.user_metadata.full_name;
    }
    
    if (user?.email) {
      return user.email.split('@')[0];
    }
    
    return "друг";
  };

  const copyReferralLink = () => {
    const refCode = (profile as any)?.referral_code;
    if (refCode) {
      const link = `${window.location.origin}/register?ref=${refCode}`;
      navigator.clipboard.writeText(link);
      toast.success("Реферальная ссылка скопирована!");
    }
  };

  const formatDate = (dateString: string) => {
    const date = new Date(dateString);
    const now = new Date();
    const diffInHours = Math.floor((now.getTime() - date.getTime()) / (1000 * 60 * 60));
    
    if (diffInHours < 1) return "только что";
    if (diffInHours < 24) return `${diffInHours} ч. назад`;
    if (diffInHours < 48) return "1 день назад";
    return `${Math.floor(diffInHours / 24)} дней назад`;
  };

  const getTransactionLabel = (type: string) => {
    switch (type) {
      case 'commission': return 'Начисление';
      case 'bonus': return 'Бонус';
      case 'withdrawal': return 'Вывод';
      case 'purchase': return 'Покупка';
      default: return 'Операция';
    }
  };

  return (
    <div className="p-6 space-y-6">
      {/* Welcome Section */}
      <div className="hero-gradient rounded-lg p-4 sm:p-6 text-white">
        <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
          <div>
            <h1 className="text-2xl sm:text-3xl font-bold mb-2">
              {profileLoading ? (
                <Skeleton className="h-9 w-64 bg-white/20" />
              ) : (
                `Добро пожаловать, ${getUserName()}!`
              )}
            </h1>
            <p className="text-white/80 mb-4">
              {(profile as any)?.subscription_status === 'active' 
                ? 'Ваша подписка активна. Продолжайте развивать свою сеть и достигать новых целей.'
                : 'Активируйте подписку, чтобы начать зарабатывать.'}
            </p>
            <div className="flex items-center space-x-4 text-sm">
              <div className="flex items-center space-x-2">
                <div className="w-2 h-2 bg-white rounded-full"></div>
                <span>{(profile as any)?.subscription_status === 'active' ? 'Активный партнёр' : 'Партнёр'}</span>
              </div>
              {(profile as any)?.created_at && (
                <div className="flex items-center space-x-2">
                  <Calendar className="h-4 w-4" />
                  <span>С {new Date((profile as any).created_at).toLocaleDateString('ru-RU')}</span>
                </div>
              )}
            </div>
          </div>
          <div className="sm:text-right">
            {profileLoading ? (
              <Skeleton className="h-8 w-24 bg-white/20 ml-auto" />
            ) : (
              <>
                <div className="text-sm text-white/80 mb-1">Реф. код</div>
                <div className="text-xl sm:text-2xl font-bold">{(profile as any)?.referral_code || '—'}</div>
              </>
            )}
          </div>
        </div>
      </div>

      {/* Stats Grid */}
      <DashboardStats />

      {/* Quick Actions & Activation Progress */}
      <div className="grid gap-6 md:grid-cols-2">
        <Card className="financial-card">
          <CardHeader>
            <CardTitle className="flex items-center space-x-2">
              <Target className="h-5 w-5" />
              <span>Быстрые действия</span>
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-3">
            <div className="pt-3 border-t border-border">
              <p className="text-sm text-muted-foreground mb-2">
                Ваша реферальная ссылка:
              </p>
              {profileLoading ? (
                <Skeleton className="h-9 w-full" />
              ) : (
                <div className="flex items-center space-x-2">
                  <code className="flex-1 bg-muted px-3 py-2 rounded text-xs break-all">
                    {(profile as any)?.referral_code 
                      ? `${window.location.origin}/register?ref=${(profile as any).referral_code}`
                      : 'Загрузка...'}
                  </code>
                  <Button 
                    variant="outline" 
                    size="sm"
                    onClick={copyReferralLink}
                    disabled={!(profile as any)?.referral_code}
                  >
                    <Copy className="h-4 w-4" />
                  </Button>
                </div>
              )}
            </div>
          </CardContent>
        </Card>

        <ActivationProgress />
      </div>

      {/* Network Tree */}
      <NetworkTree members={networkMembers} />

      {/* Recent Activity */}
      <Card className="financial-card">
        <CardHeader>
          <CardTitle>Последние операции</CardTitle>
        </CardHeader>
        <CardContent>
          {transactionsLoading ? (
            <div className="space-y-4">
              {[1, 2, 3].map((i) => (
                <div key={i} className="flex items-center justify-between py-3">
                  <div className="space-y-2 flex-1">
                    <Skeleton className="h-4 w-32" />
                    <Skeleton className="h-3 w-48" />
                    <Skeleton className="h-3 w-24" />
                  </div>
                  <Skeleton className="h-6 w-16" />
                </div>
              ))}
            </div>
          ) : transactions.length === 0 ? (
            <div className="text-center py-8 text-muted-foreground">
              <p>Пока нет операций</p>
              <p className="text-sm mt-2">Ваши транзакции будут отображаться здесь</p>
            </div>
          ) : (
            <div className="space-y-4">
              {transactions.map((transaction) => {
                const isPositive = ['commission', 'bonus'].includes(transaction.type);
                const amount = formatCents(transaction.amount_cents, transaction.currency);
                
                return (
                  <div key={transaction.id} className="flex items-center justify-between py-3 border-b border-border last:border-b-0">
                    <div>
                      <p className="font-medium">{getTransactionLabel(transaction.type)}</p>
                      <p className="text-sm text-muted-foreground">
                        {transaction.type === 'commission' && transaction.payload?.level 
                          ? `Уровень ${transaction.payload.level}, ${transaction.structure_type === 'primary' ? 'Основная' : 'Вторичная'} структура`
                          : transaction.type === 'bonus'
                          ? 'Бонусное начисление'
                          : transaction.type === 'purchase'
                          ? 'Покупка в магазине'
                          : transaction.type === 'withdrawal'
                          ? 'Вывод средств'
                          : 'Операция'}
                      </p>
                      <p className="text-xs text-muted-foreground">{formatDate(transaction.created_at)}</p>
                    </div>
                    <div className={`font-bold ${
                      isPositive ? "text-success" : "text-muted-foreground"
                    }`}>
                      {isPositive ? '+' : '-'}{amount}
                    </div>
                  </div>
                );
              })}
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  );
}