import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Button } from "@/components/ui/button";
import { Switch } from "@/components/ui/switch";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { useMLMRules } from "@/hooks/useMLMRules";
import { useMLMSettings, useUpdateMLMSetting, useUpdateMLMRule } from "@/hooks/useMLMSettings";
import { useState, useEffect } from "react";
import { Save, Settings } from "lucide-react";
import { Skeleton } from "@/components/ui/skeleton";

export default function AdminMLMSettings() {
  const { data: settings, isLoading: settingsLoading } = useMLMSettings();
  const { data: rules1 } = useMLMRules(1);
  const { data: rules2 } = useMLMRules(2);
  const updateSetting = useUpdateMLMSetting();
  const updateRule = useUpdateMLMRule();

  const [editingRules1, setEditingRules1] = useState<Record<string, number>>({});
  const [editingRules2, setEditingRules2] = useState<Record<string, number>>({});
  const [financeSettings, setFinanceSettings] = useState({
    subscription_usd: 100,
    activation_min_usd: 40,
    usd_kzt_rate: 450
  });

  // Инициализировать финансовые настройки при загрузке
  useEffect(() => {
    if (settings) {
      setFinanceSettings({
        subscription_usd: parseFloat(settings.finance_subscription_usd) || 100,
        activation_min_usd: parseFloat(settings.finance_activation_min_usd) || 40,
        usd_kzt_rate: parseFloat(settings.finance_usd_kzt_rate) || 450
      });
    }
  }, [settings]);

  const handleSaveGlobalSettings = () => {
    if (!settings) return;
    
    // Сохранить все изменённые настройки
    Object.keys(settings).forEach(key => {
      updateSetting.mutate({ key, value: settings[key] });
    });
  };

  const handleSaveFinanceSettings = () => {
    updateSetting.mutate({ key: 'finance_subscription_usd', value: financeSettings.subscription_usd });
    updateSetting.mutate({ key: 'finance_activation_min_usd', value: financeSettings.activation_min_usd });
    updateSetting.mutate({ key: 'finance_usd_kzt_rate', value: financeSettings.usd_kzt_rate });
  };

  const handleSaveRule = (ruleId: string, structureType: 1 | 2, level: number, percent: number) => {
    updateRule.mutate({
      id: ruleId,
      structure_type: structureType,
      level,
      percent
    });
  };

  if (settingsLoading) {
    return (
      <div className="p-8 space-y-6">
        <div className="flex items-center gap-3">
          <Skeleton className="h-8 w-8 rounded-full" />
          <Skeleton className="h-9 w-48" />
        </div>
        <Skeleton className="h-12 w-full" />
        <div className="space-y-4">
          <Skeleton className="h-64 w-full" />
        </div>
      </div>
    );
  }

  return (
    <div className="p-8 space-y-6">
      <div className="flex items-center gap-3">
        <Settings className="h-8 w-8 text-primary" />
        <h1 className="text-3xl font-bold">MLM-настройки</h1>
      </div>

      <Tabs defaultValue="rules" className="space-y-4">
        <TabsList className="grid w-full grid-cols-3">
          <TabsTrigger value="rules">Проценты по уровням</TabsTrigger>
          <TabsTrigger value="finance">Финансы</TabsTrigger>
          <TabsTrigger value="global">Глобальные параметры</TabsTrigger>
        </TabsList>

        <TabsContent value="rules" className="space-y-4">
          <Tabs defaultValue="structure1">
            <TabsList className="grid w-full grid-cols-2">
              <TabsTrigger value="structure1">Абонентская (5 уровней)</TabsTrigger>
              <TabsTrigger value="structure2">Товарная (10 уровней)</TabsTrigger>
            </TabsList>

            <TabsContent value="structure1">
              <Card>
                <CardHeader>
                  <CardTitle>Структура 1 — Абонентская</CardTitle>
                </CardHeader>
                <CardContent>
                  <Table>
                    <TableHeader>
                      <TableRow>
                        <TableHead>Уровень</TableHead>
                        <TableHead>Процент (%)</TableHead>
                        <TableHead>План</TableHead>
                        <TableHead>Активно</TableHead>
                        <TableHead>Действия</TableHead>
                      </TableRow>
                    </TableHeader>
                    <TableBody>
                      {(rules1 || []).map((rule) => (
                        <TableRow key={rule.id}>
                          <TableCell>L{rule.level}</TableCell>
                          <TableCell>
                            <Input
                              type="number"
                              step="0.01"
                              defaultValue={rule.percent}
                              onChange={(e) => setEditingRules1({
                                ...editingRules1,
                                [rule.id]: parseFloat(e.target.value)
                              })}
                              className="w-24"
                            />
                          </TableCell>
                          <TableCell>{rule.plan_id}</TableCell>
                          <TableCell>
                            <Switch defaultChecked />
                          </TableCell>
                          <TableCell>
                            <Button
                              size="sm"
                              onClick={() => handleSaveRule(
                                rule.id,
                                1,
                                rule.level,
                                editingRules1[rule.id] ?? rule.percent
                              )}
                              disabled={!(rule.id in editingRules1)}
                            >
                              <Save className="h-4 w-4" />
                            </Button>
                          </TableCell>
                        </TableRow>
                      ))}
                    </TableBody>
                  </Table>
                </CardContent>
              </Card>
            </TabsContent>

            <TabsContent value="structure2">
              <Card>
                <CardHeader>
                  <CardTitle>Структура 2 — Товарная</CardTitle>
                </CardHeader>
                <CardContent>
                  <Table>
                    <TableHeader>
                      <TableRow>
                        <TableHead>Уровень</TableHead>
                        <TableHead>Процент (%)</TableHead>
                        <TableHead>План</TableHead>
                        <TableHead>Активно</TableHead>
                        <TableHead>Действия</TableHead>
                      </TableRow>
                    </TableHeader>
                    <TableBody>
                      {(rules2 || []).map((rule) => (
                        <TableRow key={rule.id}>
                          <TableCell>L{rule.level}</TableCell>
                          <TableCell>
                            <Input
                              type="number"
                              step="0.01"
                              defaultValue={rule.percent}
                              onChange={(e) => setEditingRules2({
                                ...editingRules2,
                                [rule.id]: parseFloat(e.target.value)
                              })}
                              className="w-24"
                            />
                          </TableCell>
                          <TableCell>{rule.plan_id}</TableCell>
                          <TableCell>
                            <Switch defaultChecked />
                          </TableCell>
                          <TableCell>
                            <Button
                              size="sm"
                              onClick={() => handleSaveRule(
                                rule.id,
                                2,
                                rule.level,
                                editingRules2[rule.id] ?? rule.percent
                              )}
                              disabled={!(rule.id in editingRules2)}
                            >
                              <Save className="h-4 w-4" />
                            </Button>
                          </TableCell>
                        </TableRow>
                      ))}
                    </TableBody>
                  </Table>
                </CardContent>
              </Card>
            </TabsContent>
          </Tabs>
        </TabsContent>

        <TabsContent value="finance" className="space-y-4">
          <Card>
            <CardHeader>
              <CardTitle>Финансовые настройки (SSOT)</CardTitle>
            </CardHeader>
            <CardContent className="space-y-6">
              <p className="text-sm text-muted-foreground">
                Эти параметры являются единственным источником правды для всех финансовых операций системы
              </p>
              <div className="grid gap-4">
                <div className="space-y-2">
                  <Label>Стоимость годовой подписки (USD) *</Label>
                  <Input
                    type="number"
                    step="0.01"
                    min="0"
                    value={financeSettings.subscription_usd}
                    onChange={(e) => {
                      const value = parseFloat(e.target.value) || 0;
                      setFinanceSettings(prev => ({ ...prev, subscription_usd: value }));
                    }}
                    placeholder="100.00"
                  />
                  <p className="text-xs text-muted-foreground">
                    Используется для создания платежа подписки
                  </p>
                </div>

                <div className="space-y-2">
                  <Label>Минимум для месячной активации (USD) *</Label>
                  <Input
                    type="number"
                    step="0.01"
                    min="0"
                    value={financeSettings.activation_min_usd}
                    onChange={(e) => {
                      const value = parseFloat(e.target.value) || 0;
                      setFinanceSettings(prev => ({ ...prev, activation_min_usd: value }));
                    }}
                    placeholder="40.00"
                  />
                  <p className="text-xs text-muted-foreground">
                    Минимальная сумма покупки активационных товаров
                  </p>
                </div>

                <div className="space-y-2">
                  <Label>Курс USD → KZT *</Label>
                  <Input
                    type="number"
                    step="0.01"
                    min="0"
                    value={financeSettings.usd_kzt_rate}
                    onChange={(e) => {
                      const value = parseFloat(e.target.value) || 0;
                      setFinanceSettings(prev => ({ ...prev, usd_kzt_rate: value }));
                    }}
                    placeholder="450.00"
                  />
                  <p className="text-xs text-muted-foreground">
                    Используется для автозаполнения цен товаров и расчёта платежей
                  </p>
                  {financeSettings.subscription_usd && financeSettings.usd_kzt_rate && (
                    <p className="text-xs font-semibold text-primary">
                      Подписка в KZT: {Math.round(financeSettings.subscription_usd * financeSettings.usd_kzt_rate)} ₸
                    </p>
                  )}
                </div>
              </div>

              <Button onClick={handleSaveFinanceSettings} className="w-full">
                <Save className="h-4 w-4 mr-2" />
                Сохранить финансовые настройки
              </Button>
            </CardContent>
          </Card>
        </TabsContent>

        <TabsContent value="global" className="space-y-4">
          <Card>
            <CardHeader>
              <CardTitle>Глобальные параметры</CardTitle>
            </CardHeader>
            <CardContent className="space-y-6">
              <div className="grid gap-4">
                <div className="space-y-2">
                  <Label>Стоимость подписки (USD/год)</Label>
                  <Input
                    type="number"
                    defaultValue={settings?.subscription_price_usd?.value || 100}
                    disabled
                  />
                  <p className="text-xs text-muted-foreground">
                    100 USD за 12 месяцев (фиксировано по ТЗ)
                  </p>
                </div>

                <div className="space-y-2">
                  <Label>Порог активации (USD)</Label>
                  <Input
                    type="number"
                    defaultValue={settings?.monthly_activation?.min_usd || 40}
                    disabled
                  />
                  <p className="text-xs text-muted-foreground">
                    Минимальная сумма покупки для участия в товарной структуре
                  </p>
                </div>

                <div className="space-y-2">
                  <Label>Курс USD/KZT</Label>
                  <Input
                    type="number"
                    defaultValue={settings?.currency?.usd_rate || 480}
                    disabled
                  />
                </div>

                <div className="space-y-2">
                  <Label>Условия открытия уровней (структура 1)</Label>
                  <div className="grid grid-cols-2 gap-2">
                    <div>
                      <Label className="text-xs">L2 открывается при</Label>
                      <Input
                        type="number"
                        defaultValue={settings?.unlock_levels?.l2 || 3}
                        disabled
                      />
                    </div>
                    <div>
                      <Label className="text-xs">L3 открывается при</Label>
                      <Input
                        type="number"
                        defaultValue={settings?.unlock_levels?.l3 || 5}
                        disabled
                      />
                    </div>
                    <div>
                      <Label className="text-xs">L4 открывается при</Label>
                      <Input
                        type="number"
                        defaultValue={settings?.unlock_levels?.l4 || 8}
                        disabled
                      />
                    </div>
                    <div>
                      <Label className="text-xs">L5 открывается при</Label>
                      <Input
                        type="number"
                        defaultValue={settings?.unlock_levels?.l5 || 10}
                        disabled
                      />
                    </div>
                  </div>
                  <p className="text-xs text-muted-foreground">
                    Количество прямых рефералов для открытия уровня
                  </p>
                </div>
              </div>

              <Button onClick={handleSaveGlobalSettings} className="w-full">
                <Save className="h-4 w-4 mr-2" />
                Сохранить настройки
              </Button>
            </CardContent>
          </Card>
        </TabsContent>
      </Tabs>
    </div>
  );
}