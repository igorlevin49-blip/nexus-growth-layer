import { useState, useEffect } from "react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Progress } from "@/components/ui/progress";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { ShoppingCart, Calendar } from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/hooks/useAuth";
import { useNavigate } from "react-router-dom";
import { PayActivationButton } from "./PayActivationButton";
import { format } from "date-fns";
import { ru } from "date-fns/locale";

export function ActivationProgress() {
  const { user } = useAuth();
  const navigate = useNavigate();
  const [loading, setLoading] = useState(true);
  const [currentAmount, setCurrentAmount] = useState(0);
  const [requiredAmount, setRequiredAmount] = useState(40);
  const [isActivated, setIsActivated] = useState(false);
  const [activationDueFrom, setActivationDueFrom] = useState<Date | null>(null);
  const [isActivationRequired, setIsActivationRequired] = useState(false);

  useEffect(() => {
    if (user) {
      fetchActivationData();
    }
  }, [user]);

  const fetchActivationData = async () => {
    if (!user) return;

    try {
      // Get required amount from settings
      const { data: settings, error: settingsError } = await supabase
        .from("shop_settings")
        .select("monthly_activation_required_usd")
        .eq("id", 1)
        .single();

      if (settingsError) throw settingsError;
      if (settings) {
        setRequiredAmount(Number(settings.monthly_activation_required_usd));
      }

      // Check profile subscription status and activation due date
      const { data: profile, error: profileError } = await supabase
        .from('profiles')
        .select('subscription_status, monthly_activation_completed, activation_due_from')
        .eq('id', user.id)
        .single();

      if (profileError) throw profileError;
      
      if (profile) {
        const dueFrom = profile.activation_due_from ? new Date(profile.activation_due_from) : null;
        setActivationDueFrom(dueFrom);
        
        // Check if activation is required (period has started)
        const now = new Date();
        const required = dueFrom !== null && now >= dueFrom;
        setIsActivationRequired(required);
        
        setIsActivated(profile.monthly_activation_completed || false);
      }

      // Calculate personal activation period if required
      if (profile?.activation_due_from && isActivationRequired) {
        const dueFrom = new Date(profile.activation_due_from);
        const now = new Date();
        
        // Calculate months passed since activation_due_from
        const monthsPassed = Math.floor(
          (now.getTime() - dueFrom.getTime()) / (30 * 24 * 60 * 60 * 1000)
        );
        
        // Current period start
        const periodStart = new Date(dueFrom);
        periodStart.setMonth(periodStart.getMonth() + monthsPassed);
        
        const { data: orders, error: ordersError } = await supabase
          .from("orders")
          .select(`
            id,
            created_at,
            order_items (
              price_usd,
              qty,
              is_activation_snapshot
            )
          `)
          .eq("user_id", user.id)
          .eq("status", "paid")
          .gte("created_at", periodStart.toISOString());

        if (ordersError) throw ordersError;

        // Calculate activation sum
        let sum = 0;
        orders?.forEach((order: any) => {
          order.order_items?.forEach((item: any) => {
            if (item.is_activation_snapshot) {
              sum += Number(item.price_usd) * item.qty;
            }
          });
        });

        setCurrentAmount(sum);
        setIsActivated(sum >= Number(settings?.monthly_activation_required_usd || 40));
      } else {
        // Activation not yet required
        setCurrentAmount(0);
        setIsActivated(false);
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

  // If activation is not yet required, show info message
  if (!isActivationRequired && activationDueFrom) {
    return (
      <Card className="border-blue-500/50 bg-blue-500/5">
        <CardHeader>
          <CardTitle className="flex items-center justify-between">
            <span>Месячная активация</span>
            <Badge variant="outline" className="bg-blue-500/10">
              <Calendar className="w-3 h-3 mr-1" />
              Не требуется
            </Badge>
          </CardTitle>
        </CardHeader>
        <CardContent className="space-y-3">
          <div className="text-sm">
            <p className="font-medium mb-2">Первая месячная активация не требуется до:</p>
            <p className="text-lg font-bold text-blue-600 dark:text-blue-400">
              {format(activationDueFrom, "dd MMMM yyyy", { locale: ru })}
            </p>
          </div>
          <div className="pt-3 border-t">
            <p className="text-xs text-muted-foreground">
              После оплаты годовой подписки первая ежемесячная активация становится требуемой только со второго месяца. Сейчас ничего делать не нужно.
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
              ${currentAmount.toFixed(2)} / ${requiredAmount.toFixed(2)}
            </span>
          </div>
          <Progress value={progress} className="mb-2" />
          {isActivated ? (
            <p className="text-xs text-green-600 dark:text-green-400">
              ✓ Вы успешно завершили месячную активацию!
            </p>
          ) : (
            <p className="text-xs text-muted-foreground">
              Осталось приобрести активационных товаров на ${remaining.toFixed(2)}
            </p>
          )}
        </div>

        {!isActivated && (
          <div className="pt-3 border-t space-y-3">
            <PayActivationButton 
              requiredAmountUSD={requiredAmount}
              currentAmountUSD={currentAmount}
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
