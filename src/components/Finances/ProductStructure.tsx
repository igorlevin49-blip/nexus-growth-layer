import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { CheckCircle2, Lock, Info } from "lucide-react";
import { formatKZT } from "@/utils/formatMoney";
import { CommissionLevel } from "@/hooks/useCommissionStructure";
import { useTransactions, Transaction } from "@/hooks/useTransactions";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { useState } from "react";
interface ProductStructureProps {
  levels: CommissionLevel[];
  isLoading: boolean;
  subscriptionActive: boolean;
  monthlyActivationMet: boolean;
}
export function ProductStructure({
  levels,
  isLoading,
  subscriptionActive,
  monthlyActivationMet
}: ProductStructureProps) {
  const [statusFilter, setStatusFilter] = useState<string>("all");
  const {
    data: transactions,
    isLoading: transactionsLoading
  } = useTransactions({
    type: ['commission']
  });

  // Фильтруем транзакции товарной структуры (structure_type = 'secondary' или через payload)
  const productTransactions = (transactions || []).filter(t => t.structure_type === 'secondary' || t.payload?.structure === 2);
  const getStatusBadge = (status: string) => {
    switch (status) {
      case 'completed':
        return <Badge className="profit-indicator">Выплачено</Badge>;
      case 'frozen':
        return <Badge className="frozen-indicator">Заморожено</Badge>;
      case 'pending':
        return <Badge className="pending-indicator">В ожидании</Badge>;
      default:
        return <Badge variant="outline">{status}</Badge>;
    }
  };
  if (isLoading) {
    return <Card className="financial-card">
        <CardHeader>
          <CardTitle>Товарная структура (10 уровней)</CardTitle>
        </CardHeader>
        <CardContent>
          <p className="text-center text-muted-foreground">Загрузка...</p>
        </CardContent>
      </Card>;
  }
  const canParticipate = subscriptionActive && monthlyActivationMet;
  return <Card className="financial-card">
      <CardHeader>
        <div className="space-y-2">
          <CardTitle>Товарная структура (10 уровней)</CardTitle>
          <div className="flex items-center gap-2 text-sm">
            {canParticipate ? <Badge className="profit-indicator">
                <CheckCircle2 className="h-3 w-3 mr-1" />
                Участие активно
              </Badge> : <Badge variant="outline">
                <Lock className="h-3 w-3 mr-1" />
                Требуется активация
              </Badge>}
          </div>
          {!canParticipate && <div className="flex items-start gap-2 p-3 bg-warning/10 rounded-lg">
              <Info className="h-4 w-4 text-warning mt-0.5" />
              <div className="text-xs text-muted-foreground">
                <p>Для участия в товарной структуре необходимо:</p>
                <ul className="list-disc list-inside mt-1 space-y-0.5">
                  <li>Активная подписка (100 USD/год)</li>
                  <li>Ежемесячная покупка на сумму ≥40 USD</li>
                </ul>
              </div>
            </div>}
        </div>
      </CardHeader>
      <CardContent>
        <div className="space-y-4">
          {/* Уровни комиссий */}
          <div>
            <h4 className="font-medium mb-3">Комиссионные уровни</h4>
            <div className="grid grid-cols-2 md:grid-cols-5 gap-2">
              {levels.map(level => <div key={level.level} className="p-3 border border-border rounded-lg text-center">
                  <div className="text-xs text-muted-foreground mb-1">L{level.level}</div>
                  <div className="text-lg font-bold text-primary">{level.percent}%</div>
                  <div className="text-xs text-success mt-1">
                    {(level.earned || 0).toLocaleString('ru-RU')} ₸
                  </div>
                </div>)}
            </div>
          </div>

          {/* История покупок и начислений */}
          <div>
            <div className="flex items-center justify-between mb-3">
              <h4 className="font-medium">История начислений</h4>
              <Select value={statusFilter} onValueChange={setStatusFilter}>
                <SelectTrigger className="w-40">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="all">Все</SelectItem>
                  <SelectItem value="completed">Выплачено</SelectItem>
                  <SelectItem value="frozen">Заморожено</SelectItem>
                  <SelectItem value="pending">В ожидании</SelectItem>
                </SelectContent>
              </Select>
            </div>

            <div className="overflow-x-auto">
              {transactionsLoading ? <p className="text-center text-muted-foreground py-4">Загрузка...</p> : !productTransactions || productTransactions.length === 0 ? <p className="text-center text-muted-foreground py-4">Нет транзакций</p> : <table className="w-full text-sm">
                  <thead>
                    <tr className="border-b border-border">
                      <th className="text-left py-2 px-2">Дата</th>
                      <th className="text-left py-2 px-2">Партнёр</th>
                      <th className="text-center py-2 px-2">Уровень</th>
                      <th className="text-right py-2 px-2">Сумма покупки</th>
                      <th className="text-center py-2 px-2">%</th>
                      <th className="text-right py-2 px-2">Начислено</th>
                      <th className="text-right py-2 px-2">Статус</th>
                    </tr>
                  </thead>
                  <tbody>
                    {productTransactions.filter(t => statusFilter === 'all' || t.status === statusFilter).map((trans: Transaction) => {
                  const purchaseAmount = trans.payload?.purchase_amount || 0;
                  const percent = trans.payload?.percent || 0;
                  const partnerName = trans.payload?.partner_name || 'Неизвестно';
                  return <tr key={trans.id} className="border-b border-border/50 hover:bg-muted/50">
                            <td className="py-2 px-2">
                              {new Date(trans.created_at).toLocaleDateString('ru-RU')}
                            </td>
                            <td className="py-2 px-2">{partnerName}</td>
                            <td className="py-2 px-2 text-center">
                              <Badge variant="outline" className="text-xs">L{trans.level}</Badge>
                            </td>
                            <td className="py-2 px-2 text-right">
                              {formatKZT(purchaseAmount)}
                            </td>
                            <td className="py-2 px-2 text-center text-xs">{percent}%</td>
                            <td className="py-2 px-2 text-right font-medium text-success">
                              {formatKZT(trans.amount_kzt)}
                            </td>
                            <td className="py-2 px-2 text-right">
                              {getStatusBadge(trans.status)}
                            </td>
                          </tr>;
                })}
                  </tbody>
                </table>}
            </div>
          </div>

          <div className="mt-4 p-4 bg-muted/50 rounded-lg space-y-2">
            <h4 className="font-medium text-sm">Проценты начислений:</h4>
            <ul className="text-xs text-muted-foreground space-y-1">
              <li>• 1-й уровень — 10%</li>
              <li>• 2-9 уровни — по 5%</li>
              <li>• 10-й уровень — 10%</li>
            </ul>
            <p className="text-xs text-muted-foreground mt-2">
          </p>
          </div>
        </div>
      </CardContent>
    </Card>;
}