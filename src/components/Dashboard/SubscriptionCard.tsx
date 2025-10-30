import { useState, useEffect } from "react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Calendar, AlertCircle } from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/hooks/useAuth";
import { PaySubscriptionButton } from "./PaySubscriptionButton";
import { format } from "date-fns";
import { ru } from "date-fns/locale";

export function SubscriptionCard() {
  const { user } = useAuth();
  const [loading, setLoading] = useState(true);
  const [subscriptionStatus, setSubscriptionStatus] = useState<string>('inactive');
  const [expiresAt, setExpiresAt] = useState<Date | null>(null);
  const [subscriptionPrice, setSubscriptionPrice] = useState<number>(100);

  useEffect(() => {
    if (user) {
      fetchSubscriptionData();
    }
  }, [user]);

  const fetchSubscriptionData = async () => {
    if (!user) return;

    try {
      // Get subscription price from mlm_settings
      const { data: priceSetting, error: priceError } = await supabase
        .from('mlm_settings')
        .select('value')
        .eq('key', 'finance_subscription_usd')
        .single();

      if (priceError) throw priceError;
      if (priceSetting) {
        const val = typeof priceSetting.value === 'string' ? priceSetting.value : String(priceSetting.value);
        setSubscriptionPrice(parseFloat(val) || 100);
      }

      // Get user profile
      const { data: profile, error: profileError } = await supabase
        .from('profiles')
        .select('subscription_status, subscription_expires_at')
        .eq('id', user.id)
        .single();

      if (profileError) throw profileError;

      if (profile) {
        setSubscriptionStatus(profile.subscription_status || 'inactive');
        if (profile.subscription_expires_at) {
          setExpiresAt(new Date(profile.subscription_expires_at));
        }
      }
    } catch (error) {
      console.error('Error fetching subscription data:', error);
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

  const isActive = subscriptionStatus === 'active';
  const daysLeft = expiresAt ? Math.ceil((expiresAt.getTime() - Date.now()) / (1000 * 60 * 60 * 24)) : 0;

  return (
    <Card className={isActive ? "border-green-500/50 bg-green-500/5" : "border-amber-500/50 bg-amber-500/5"}>
      <CardHeader>
        <CardTitle className="flex items-center justify-between">
          <span>Годовая подписка</span>
          {isActive ? (
            <Badge className="bg-green-500">✓ Активна</Badge>
          ) : (
            <Badge variant="outline" className="border-amber-500 text-amber-500">
              <AlertCircle className="w-3 h-3 mr-1" />
              Требуется оплата
            </Badge>
          )}
        </CardTitle>
      </CardHeader>
      <CardContent className="space-y-4">
        {isActive && expiresAt ? (
          <>
            <div className="flex items-center gap-2 text-sm">
              <Calendar className="w-4 h-4 text-muted-foreground" />
              <span>Действует до: {format(expiresAt, 'dd MMMM yyyy', { locale: ru })}</span>
            </div>
            <p className="text-xs text-muted-foreground">
              Осталось {daysLeft} {daysLeft === 1 ? 'день' : daysLeft < 5 ? 'дня' : 'дней'}
            </p>
          </>
        ) : (
          <>
            <div className="text-2xl font-bold">
              ${subscriptionPrice}
              <span className="text-sm font-normal text-muted-foreground ml-2">/ год</span>
            </div>
            <p className="text-xs text-muted-foreground">
              Подписка открывает доступ к реферальной программе и начислениям по структуре 1
            </p>
            <div className="pt-3 border-t">
              <PaySubscriptionButton />
              <p className="text-xs text-muted-foreground text-center mt-3">
                Реферальная ссылка станет доступна после активации подписки
              </p>
            </div>
          </>
        )}
      </CardContent>
    </Card>
  );
}
