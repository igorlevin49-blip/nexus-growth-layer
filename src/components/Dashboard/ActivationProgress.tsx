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

export function ActivationProgress() {
  const { user } = useAuth();
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const [loading, setLoading] = useState(true);
  const [currentAmount, setCurrentAmount] = useState(0);
  const [requiredAmount, setRequiredAmount] = useState(20000);
  const [isActivated, setIsActivated] = useState(false);
  const [activationDueFrom, setActivationDueFrom] = useState<Date | null>(null);
  const [isActivationRequired, setIsActivationRequired] = useState(false);
  const [lastOrderDate, setLastOrderDate] = useState<Date | null>(null);
  const [ordersCount, setOrdersCount] = useState(0);

  useEffect(() => {
    if (user) {
      fetchActivationData();
    }
  }, [user]);

  // Автообновление при возвращении на страницу
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
      // Get required amount from settings (KZT only)
      const { data: settings, error: settingsError } = await supabase
        .from("shop_settings")
        .select("monthly_activation_required_kzt")
        .eq("id", 1)
        .single();

      if (settingsError) throw settingsError;
      if (settings) {
        setRequiredAmount(Number(settings.monthly_activation_required_kzt) || 20000);
      }

      // Check profile subscription status and activation due date
      const { data: profile, error: profileError } = await supabase
        .from('profiles')
        .select('subscription_status, monthly_activation_completed, activation_due_from')
        .eq('id', user.id)
        .single();

      if (profileError) throw profileError;
      
      let required = false;
      if (profile) {
        const dueFrom = profile.activation_due_from ? new Date(profile.activation_due_from) : null;
        setActivationDueFrom(dueFrom);
        
        // Check if activation is required (period has started)
        const now = new Date();
        required = dueFrom !== null && now >= dueFrom;
        setIsActivationRequired(required);
      }

      // If activation is required, fetch from monthly_activations table
      if (profile?.activation_due_from && required) {
        const now = new Date();
        const currentYear = now.getFullYear();
        const currentMonth = now.getMonth() + 1;

        // Fetch from monthly_activations table (populated by admin recalculation)
        const { data: activation, error: activationError } = await supabase
          .from('monthly_activations')
          .select('total_amount_kzt, threshold_kzt, is_activated, last_order_date')
          .eq('user_id', user.id)
          .eq('year', currentYear)
          .eq('month', currentMonth)
          .single();

        if (activationError && activationError.code !== 'PGRST116') {
          // PGRST116 = no rows found, which is OK
          throw activationError;
        }

        // Calculate period start for orders count
        const periodStart = new Date(currentYear, currentMonth - 1, 1);
        
        // Fetch orders count for this month
        const { count: orderCount, error: orderCountError } = await supabase
          .from('orders')
          .select('id', { count: 'exact', head: true })
          .eq('user_id', user.id)
          .eq('status', 'paid')
          .gte('created_at', periodStart.toISOString());

        if (orderCountError) throw orderCountError;
        setOrdersCount(orderCount || 0);

        if (activation) {
          // Use KZT directly - no conversion needed
          setCurrentAmount(Number(activation.total_amount_kzt) || 0);
          setIsActivated(activation.is_activated);
          setLastOrderDate(activation.last_order_date ? new Date(activation.last_order_date) : null);
        } else {
          // No record yet - user hasn't made any activation purchases this month
          setCurrentAmount(0);
          setIsActivated(false);
          setLastOrderDate(null);
        }
      } else {
        // Activation not yet required
        setCurrentAmount(0);
        setIsActivated(false);
        setLastOrderDate(null);
        setOrdersCount(0);
      }

    } catch (error) {
      console.error("Error fetching activation data:", error);
    } finally {
      setLoading(false);
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

  const progress = Math.min((currentAmount / requiredAmount) * 100, 100);
  const remaining = Math.max(requiredAmount - currentAmount, 0);

  // Calculate days until activation is required
  const now = new Date();
  const daysUntilDue = activationDueFrom 
    ? Math.ceil((activationDueFrom.getTime() - now.getTime()) / (1000 * 60 * 60 * 24))
    : null;

  // If activation is not yet required, show countdown with urgency colors
  if (!isActivationRequired && activationDueFrom && daysUntilDue !== null) {
    const urgency = getUrgencyStyles(daysUntilDue);
    
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
              {daysUntilDue <= 2 && <AlertTriangle className="w-3 h-3 mr-1" />}
              {daysUntilDue > 2 && <Calendar className="w-3 h-3 mr-1" />}
              Через {getDaysText(daysUntilDue)}
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
              {daysUntilDue <= 5 
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

  return (
    <Card className={isActivated ? "border-green-500/50 bg-green-500/5" : ""}>
      <CardHeader>
        <CardTitle className="flex items-center justify-between">
          <span>Месячная активация</span>
          {isActivated ? (
            <Badge className="bg-green-500">✓ Активирован</Badge>
          ) : (
            <Badge variant="outline">Требуется активация</Badge>
          )}
        </CardTitle>
      </CardHeader>
      <CardContent className="space-y-4">
        <div>
          <div className="flex justify-between text-sm mb-2">
            <span>Прогресс активации</span>
            <span className="font-semibold">
              {currentAmount.toLocaleString('ru-RU')} ₸ / {requiredAmount.toLocaleString('ru-RU')} ₸
            </span>
          </div>
          <Progress value={progress} className="mb-2" />
          
          {/* Дата последнего заказа и количество заказов */}
          {(lastOrderDate || ordersCount > 0) && (
            <div className="flex items-center gap-4 text-xs text-muted-foreground mt-1">
              {lastOrderDate && (
                <span className="flex items-center gap-1">
                  <Calendar className="w-3 h-3" />
                  Последний: {format(lastOrderDate, "dd MMM", { locale: ru })}
                </span>
              )}
              {ordersCount > 0 && (
                <span className="flex items-center gap-1">
                  <Package className="w-3 h-3" />
                  Заказов: {ordersCount}
                </span>
              )}
            </div>
          )}

          {isActivated ? (
            <p className="text-xs text-green-600 dark:text-green-400 mt-2">
              ✓ Вы успешно завершили месячную активацию!
            </p>
          ) : (
            <p className="text-xs text-muted-foreground mt-2">
              Осталось приобрести активационных товаров на {remaining.toLocaleString('ru-RU')} ₸
            </p>
          )}
        </div>

        {!isActivated && (
          <div className="pt-3 border-t space-y-3">
            <PayActivationButton 
              requiredAmountKZT={requiredAmount}
              currentAmountKZT={currentAmount}
              activationDueFrom={activationDueFrom}
              isActivationRequired={isActivationRequired}
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
