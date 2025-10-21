import { useState, useEffect } from "react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "@/hooks/use-toast";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";

type ShopSettings = {
  monthly_activation_required_usd: number;
  currency: string;
  rate_usd_kzt: number;
};

export default function AdminShopSettings() {
  const [settings, setSettings] = useState<ShopSettings>({
    monthly_activation_required_usd: 40,
    currency: "USD",
    rate_usd_kzt: 450,
  });
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    fetchSettings();
  }, []);

  const fetchSettings = async () => {
    try {
      const { data, error } = await supabase
        .from("shop_settings")
        .select("*")
        .eq("id", 1)
        .single();

      if (error) throw error;
      if (data) {
        setSettings({
          monthly_activation_required_usd: Number(data.monthly_activation_required_usd),
          currency: data.currency,
          rate_usd_kzt: Number(data.rate_usd_kzt),
        });
      }
    } catch (error) {
      console.error("Error fetching settings:", error);
      toast({
        title: "Ошибка",
        description: "Не удалось загрузить настройки",
        variant: "destructive",
      });
    } finally {
      setLoading(false);
    }
  };

  const handleSave = async () => {
    setSaving(true);
    try {
      const { error } = await supabase
        .from("shop_settings")
        .update({
          monthly_activation_required_usd: settings.monthly_activation_required_usd,
          currency: settings.currency,
          rate_usd_kzt: settings.rate_usd_kzt,
        })
        .eq("id", 1);

      if (error) throw error;
      toast({
        title: "Настройки сохранены",
        description: "Изменения применены успешно",
      });
    } catch (error) {
      console.error("Error saving settings:", error);
      toast({
        title: "Ошибка",
        description: "Не удалось сохранить настройки",
        variant: "destructive",
      });
    } finally {
      setSaving(false);
    }
  };

  if (loading) {
    return <div className="p-8">Загрузка...</div>;
  }

  return (
    <div className="p-8">
      <h1 className="text-3xl font-bold mb-6">Настройки магазина</h1>

      <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
        <Card>
          <CardHeader>
            <CardTitle>Требования активации</CardTitle>
          </CardHeader>
          <CardContent className="space-y-4">
            <div>
              <Label>Требуемая сумма для месячной активации (USD)</Label>
              <Input
                type="number"
                step="0.01"
                value={settings.monthly_activation_required_usd}
                onChange={(e) =>
                  setSettings({
                    ...settings,
                    monthly_activation_required_usd: parseFloat(e.target.value),
                  })
                }
              />
              <p className="text-sm text-muted-foreground mt-2">
                Минимальная сумма покупки активационных товаров за месяц для получения
                активного статуса
              </p>
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>Валюта и курсы</CardTitle>
          </CardHeader>
          <CardContent className="space-y-4">
            <div>
              <Label>Основная валюта</Label>
              <Select
                value={settings.currency}
                onValueChange={(value) =>
                  setSettings({ ...settings, currency: value })
                }
              >
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="USD">USD (Доллар США)</SelectItem>
                  <SelectItem value="KZT">KZT (Тенге)</SelectItem>
                </SelectContent>
              </Select>
            </div>
            <div>
              <Label>Курс USD к KZT</Label>
              <Input
                type="number"
                step="0.01"
                value={settings.rate_usd_kzt}
                onChange={(e) =>
                  setSettings({
                    ...settings,
                    rate_usd_kzt: parseFloat(e.target.value),
                  })
                }
              />
              <p className="text-sm text-muted-foreground mt-2">
                1 USD = {settings.rate_usd_kzt} KZT
              </p>
            </div>
          </CardContent>
        </Card>
      </div>

      <div className="mt-6">
        <Button onClick={handleSave} disabled={saving}>
          {saving ? "Сохранение..." : "Сохранить настройки"}
        </Button>
      </div>
    </div>
  );
}
