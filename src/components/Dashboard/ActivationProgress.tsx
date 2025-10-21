import { useState, useEffect } from "react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Progress } from "@/components/ui/progress";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { ShoppingCart } from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/hooks/useAuth";
import { useNavigate } from "react-router-dom";

export function ActivationProgress() {
  const { user } = useAuth();
  const navigate = useNavigate();
  const [loading, setLoading] = useState(true);
  const [currentAmount, setCurrentAmount] = useState(0);
  const [requiredAmount, setRequiredAmount] = useState(40);
  const [isActivated, setIsActivated] = useState(false);

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

      // Get current month activation sum
      const startOfMonth = new Date();
      startOfMonth.setDate(1);
      startOfMonth.setHours(0, 0, 0, 0);

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
        .gte("created_at", startOfMonth.toISOString());

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
          <div className="pt-3 border-t">
            <Button
              onClick={() => navigate("/shop?filter=activation")}
              className="w-full"
              variant="default"
            >
              <ShoppingCart className="w-4 h-4 mr-2" />
              Активационные товары
            </Button>
            <p className="text-xs text-muted-foreground mt-2 text-center">
              Для получения MLM-бонусов необходима месячная активация
            </p>
          </div>
        )}
      </CardContent>
    </Card>
  );
}
