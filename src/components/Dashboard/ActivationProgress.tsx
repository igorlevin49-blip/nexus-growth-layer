import { useState, useEffect } from "react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Progress } from "@/components/ui/progress";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { ShoppingCart, Calendar, AlertTriangle, Package } from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/hooks/useAuth";
import { useNavigate } from "react-router-dom";
import { PayActivationButton } from "./PayActivationButton";
import { format } from "date-fns";
import { ru } from "date-fns/locale";
import { cn } from "@/lib/utils";
import { useQueryClient } from "@tanstack/react-query";

// Helper function for Russian day declension
const getDaysText = (days: number): string => {
  const absD = Math.abs(days);
  const lastTwo = absD % 100;
  const lastOne = absD % 10;
  
  if (lastTwo >= 11 && lastTwo <= 14) return `${days} дней`;
  if (lastOne === 1) return `${days} день`;
  if (lastOne >= 2 && lastOne <= 4) return `${days} дня`;
  return `${days} дней`;
};

// Get urgency colors based on days remaining
const getUrgencyStyles = (days: number) => {
  if (days <= 2) {
    return {
      border: "border-red-500/50",
      bg: "bg-red-500/5",
      badgeClass: "bg-red-500/10 text-red-600 dark:text-red-400 border-red-500/30",
      textClass: "text-red-600 dark:text-red-400",
      pulse: true
    };
  }
  if (days <= 5) {
    return {
      border: "border-orange-500/50",
      bg: "bg-orange-500/5",
      badgeClass: "bg-orange-500/10 text-orange-600 dark:text-orange-400 border-orange-500/30",
      textClass: "text-orange-600 dark:text-orange-400",
      pulse: false
    };
  }
  if (days <= 10) {
    return {
      border: "border-blue-500/50",
      bg: "bg-blue-500/5",
      badgeClass: "bg-blue-500/10 text-blue-600 dark:text-blue-400 border-blue-500/30",
      textClass: "text-blue-600 dark:text-blue-400",
      pulse: false
    };
  }
  return {
    border: "border-green-500/50",
    bg: "bg-green-500/5",
    badgeClass: "bg-green-500/10 text-green-600 dark:text-green-400 border-green-500/30",
    textClass: "text-green-600 dark:text-green-400",
    pulse: false
  };
};

interface PersonalActivationStatus {
  period_number: number;
  period_start: string | null;
  period_end: string | null;
  is_grace_period: boolean;
  days_remaining: number | null;
  required_amount_kzt: number;
  current_amount_kzt: number;
  is_activated: boolean;
  orders_count: number;
}

export function ActivationProgress() {
  const { user } = useAuth();
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const [loading, setLoading] = useState(true);
  const [activationStatus, setActivationStatus] = useState<PersonalActivationStatus | null>(null);
  const [activationDueFrom, setActivationDueFrom] = useState<Date | null>(null);

  useEffect(() => {
    if (user) {
      fetchActivationData();
    }
  }, [user]);

  // Auto-refresh when returning to page
  useEffect(() => {
    const handleVisibilityChange = () => {
      if (document.visibilityState === 'visible' && user) {
        fetchActivationData();
        queryClient.invalidateQueries({ queryKey: ['monthly-activations'] });
      }
    };

    document.addEventListener('visibilitychange', handleVisibilityChange);
    return () => document.removeEventListener('visibilitychange', handleVisibilityChange);
  }, [user, queryClient]);

  const fetchActivationData = async () => {
    if (!user) return;

    try {
      // Get profile activation_due_from
      const { data: profile, error: profileError } = await supabase
        .from('profiles')
        .select('activation_due_from, subscription_status')
        .eq('id', user.id)
        .single();

      if (profileError) throw profileError;
      
      if (profile?.activation_due_from) {
        setActivationDueFrom(new Date(profile.activation_due_from));
      }

      // Get personal activation status using new RPC function
      const { data: status, error: statusError } = await supabase
        .rpc('get_personal_activation_status', { p_user_id: user.id });

      if (statusError) {
        console.error("Error fetching personal activation status:", statusError);
        // Fallback to old logic if RPC fails
        await fetchActivationDataFallback(profile);
        return;
      }

      if (status && status.length > 0) {
        setActivationStatus(status[0] as PersonalActivationStatus);
      }

    } catch (error) {
      console.error("Error fetching activation data:", error);
    } finally {
      setLoading(false);
    }
  };

  // Fallback function for old logic
  const fetchActivationDataFallback = async (profile: any) => {
    try {
      const { data: settings } = await supabase
        .from("shop_settings")
        .select("monthly_activation_required_kzt")
        .eq("id", 1)
        .single();

      const requiredAmount = Number(settings?.monthly_activation_required_kzt) || 20000;
      
      const dueFrom = profile?.activation_due_from ? new Date(profile.activation_due_from) : null;
      const now = new Date();
      const isGracePeriod = dueFrom === null || now < dueFrom;
      
      setActivationStatus({
        period_number: isGracePeriod ? 0 : 1,
        period_start: null,
        period_end: dueFrom?.toISOString() || null,
        is_grace_period: isGracePeriod,
        days_remaining: dueFrom ? Math.ceil((dueFrom.getTime() - now.getTime()) / (1000 * 60 * 60 * 24)) : null,
        required_amount_kzt: requiredAmount,
        current_amount_kzt: 0,
        is_activated: isGracePeriod,
        orders_count: 0
      });
    } catch (error) {
      console.error("Fallback error:", error);
    }
  };

  if (loading) {
    return (
      <Card>
        <CardContent className="p-6">
          <div className="text-center text-muted-foreground">Загрузка...</div>
        </CardContent>
      </Card>
    );
  }

  if (!activationStatus) {
    return null;
  }

  const { 
    period_number,
    period_start,
    period_end,
    is_grace_period, 
    days_remaining, 
    required_amount_kzt, 
    current_amount_kzt,
    is_activated,
    orders_count
  } = activationStatus;

  const progress = Math.min((current_amount_kzt / required_amount_kzt) * 100, 100);
  const remaining = Math.max(required_amount_kzt - current_amount_kzt, 0);

  // If in grace period (first month), show countdown
  if (is_grace_period && activationDueFrom && days_remaining !== null && days_remaining > 0) {
    const urgency = getUrgencyStyles(days_remaining);
    
    return (
      <Card className={cn(urgency.border, urgency.bg)}>
        <CardHeader>
          <CardTitle className="flex items-center justify-between">
            <span>Месячная активация</span>
            <Badge 
              variant="outline" 
              className={cn(
                urgency.badgeClass,
                urgency.pulse && "animate-pulse"
              )}
            >
              {days_remaining <= 2 && <AlertTriangle className="w-3 h-3 mr-1" />}
              {days_remaining > 2 && <Calendar className="w-3 h-3 mr-1" />}
              Через {getDaysText(days_remaining)}
            </Badge>
          </CardTitle>
        </CardHeader>
        <CardContent className="space-y-3">
          <div className="text-sm">
            <p className="font-medium mb-2">Первая месячная активация начинается:</p>
            <p className={cn("text-lg font-bold", urgency.textClass)}>
              {format(activationDueFrom, "dd MMMM yyyy", { locale: ru })}
            </p>
          </div>
          <div className="pt-3 border-t">
            <p className="text-xs text-muted-foreground">
              {days_remaining <= 5 
                ? "Скоро начнётся период активации. Рекомендуем заранее приобрести активационные товары."
                : "После оплаты годовой подписки первая ежемесячная активация становится требуемой только со второго месяца."
              }
            </p>
          </div>
          <Button
            onClick={() => navigate("/shop?filter=activation")}
            className="w-full"
            variant="outline"
          >
            <ShoppingCart className="w-4 h-4 mr-2" />
            Активационные товары
          </Button>
        </CardContent>
      </Card>
    );
  }

  // Active period - show progress
  const periodStartDate = period_start ? new Date(period_start) : null;
  const periodEndDate = period_end ? new Date(period_end) : null;

  return (
    <Card className={is_activated ? "border-green-500/50 bg-green-500/5" : ""}>
      <CardHeader>
        <CardTitle className="flex items-center justify-between">
          <span>Месячная активация</span>
          {is_activated ? (
            <Badge className="bg-green-500">✓ Активирован</Badge>
          ) : (
            <Badge variant="outline">Требуется активация</Badge>
          )}
        </CardTitle>
      </CardHeader>
      <CardContent className="space-y-4">
        {/* Personal period info */}
        {periodStartDate && periodEndDate && (
          <div className="text-xs text-muted-foreground bg-muted/50 rounded px-3 py-2 flex items-center gap-2">
            <Calendar className="w-3 h-3" />
            <span>
              Период {period_number}: {format(periodStartDate, "dd MMM", { locale: ru })} — {format(periodEndDate, "dd MMM yyyy", { locale: ru })}
            </span>
            {days_remaining !== null && days_remaining > 0 && (
              <Badge variant="outline" className="ml-auto text-xs">
                {getDaysText(days_remaining)}
              </Badge>
            )}
          </div>
        )}

        <div>
          <div className="flex justify-between text-sm mb-2">
            <span>Прогресс активации</span>
            <span className="font-semibold">
              {current_amount_kzt.toLocaleString('ru-RU')} ₸ / {required_amount_kzt.toLocaleString('ru-RU')} ₸
            </span>
          </div>
          <Progress value={progress} className="mb-2" />
          
          {/* Orders count */}
          {orders_count > 0 && (
            <div className="flex items-center gap-4 text-xs text-muted-foreground mt-1">
              <span className="flex items-center gap-1">
                <Package className="w-3 h-3" />
                Заказов в периоде: {orders_count}
              </span>
            </div>
          )}

          {is_activated ? (
            <p className="text-xs text-green-600 dark:text-green-400 mt-2">
              ✓ Вы успешно завершили месячную активацию!
            </p>
          ) : (
            <p className="text-xs text-muted-foreground mt-2">
              Осталось приобрести активационных товаров на {remaining.toLocaleString('ru-RU')} ₸
            </p>
          )}
        </div>

        {!is_activated && (
          <div className="pt-3 border-t space-y-3">
            <PayActivationButton 
              requiredAmountKZT={required_amount_kzt}
              currentAmountKZT={current_amount_kzt}
              activationDueFrom={activationDueFrom}
              isActivationRequired={!is_grace_period}
            />
            <Button
              onClick={() => navigate("/shop?filter=activation")}
              className="w-full"
              variant="outline"
            >
              <ShoppingCart className="w-4 h-4 mr-2" />
              Активационные товары
            </Button>
            <p className="text-xs text-muted-foreground text-center">
              Для получения MLM-бонусов необходима месячная активация
            </p>
          </div>
        )}
      </CardContent>
    </Card>
  );
}
