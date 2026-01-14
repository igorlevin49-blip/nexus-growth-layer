import { useState } from "react";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { useRecalculateS1Commissions } from "@/hooks/useRecalculateS1Commissions";
import { AlertCircle, CheckCircle2, RefreshCw } from "lucide-react";
import { useAuth } from "@/hooks/useAuth";

export default function RecalculateCommissions() {
  const { userRole } = useAuth();
  const isSuperAdmin = userRole === 'superadmin';
  const [showConfirmation, setShowConfirmation] = useState(false);
  const recalculateMutation = useRecalculateS1Commissions();

  const handleRecalculate = () => {
    // Вызываем без dry run - реальный backfill всех комиссий
    recalculateMutation.mutate({ dryRun: false });
    setShowConfirmation(false);
  };

  return (
    <div className="container mx-auto p-6 space-y-6">
      <div>
        <h1 className="text-3xl font-bold">Пересчет комиссий S1</h1>
        <p className="text-muted-foreground mt-2">
          Инструмент для пересчета всех комиссий по структуре 1 (абонентская)
        </p>
      </div>

      <Card>
        <CardHeader>
          <CardTitle>Пересчет комиссий по подпискам</CardTitle>
          <CardDescription>
            Эта операция пройдет по всем активным подпискам и создаст недостающие комиссии для 5 уровней спонсорской линии
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          <Alert>
            <AlertCircle className="h-4 w-4" />
            <AlertDescription>
              <strong>Что делает эта операция:</strong>
              <ul className="list-disc list-inside mt-2 space-y-1">
                <li>Проходит по всем активным подпискам</li>
                <li>Для каждой подписки создает комиссии на 5 уровней вверх по спонсорской линии</li>
                <li>Использует правила из таблицы <code>mlm_commission_rules</code> (10% на каждый уровень)</li>
                <li>Пропускает уже существующие комиссии (безопасно запускать несколько раз)</li>
                <li>Учитывает статус активации спонсоров (замораживает комиссии неактивных)</li>
              </ul>
            </AlertDescription>
          </Alert>

          {!isSuperAdmin ? (
            <Alert>
              <AlertCircle className="h-4 w-4" />
              <AlertDescription>
                Только суперадминистратор может выполнять пересчёт комиссий
              </AlertDescription>
            </Alert>
          ) : !showConfirmation ? (
            <Button 
              onClick={() => setShowConfirmation(true)}
              disabled={recalculateMutation.isPending}
              className="w-full"
            >
              <RefreshCw className="mr-2 h-4 w-4" />
              Пересчитать комиссии S1
            </Button>
          ) : (
            <div className="space-y-4">
              <Alert variant="destructive">
                <AlertCircle className="h-4 w-4" />
                <AlertDescription>
                  <strong>Подтвердите операцию</strong>
                  <p className="mt-2">
                    Вы уверены что хотите пересчитать все комиссии S1? 
                    Операция создаст недостающие транзакции комиссий для всех активных подписок.
                  </p>
                </AlertDescription>
              </Alert>
              
              <div className="flex gap-2">
                <Button
                  variant="outline"
                  onClick={() => setShowConfirmation(false)}
                  disabled={recalculateMutation.isPending}
                  className="flex-1"
                >
                  Отмена
                </Button>
                <Button
                  variant="destructive"
                  onClick={handleRecalculate}
                  disabled={recalculateMutation.isPending}
                  className="flex-1"
                >
                  {recalculateMutation.isPending ? (
                    <>
                      <RefreshCw className="mr-2 h-4 w-4 animate-spin" />
                      Пересчет...
                    </>
                  ) : (
                    'Подтвердить пересчет'
                  )}
                </Button>
              </div>
            </div>
          )}

          {recalculateMutation.isSuccess && recalculateMutation.data && (
            <Alert>
              <CheckCircle2 className="h-4 w-4 text-green-600" />
              <AlertDescription>
                <strong>Пересчет завершен</strong>
                <ul className="list-disc list-inside mt-2 space-y-1">
                  <li>Обработано подписок: {(recalculateMutation.data as any).subscriptions_processed}</li>
                  <li>Создано комиссий: {(recalculateMutation.data as any).commissions_created}</li>
                  <li>Пропущено (уже существуют): {(recalculateMutation.data as any).commissions_skipped}</li>
                </ul>
              </AlertDescription>
            </Alert>
          )}
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>Техническая информация</CardTitle>
        </CardHeader>
        <CardContent className="space-y-2 text-sm text-muted-foreground">
          <p><strong>Функция БД:</strong> recalculate_all_s1_commissions(p_admin_id)</p>
          <p><strong>Безопасность:</strong> Использует ON CONFLICT DO NOTHING - дубликаты не создаются</p>
          <p><strong>Логирование:</strong> Все действия записываются в admin_actions</p>
          <p><strong>Структура:</strong> Структура 1 (primary) - абонентская</p>
          <p><strong>Уровни:</strong> 5 уровней по 10% от стоимости подписки</p>
        </CardContent>
      </Card>
    </div>
  );
}
