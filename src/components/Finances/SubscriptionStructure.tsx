import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { CheckCircle2, Lock, Snowflake, Info } from "lucide-react";
import { formatCents } from "@/utils/formatMoney";
import { CommissionLevel } from "@/hooks/useCommissionStructure";
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from "@/components/ui/tooltip";

interface SubscriptionStructureProps {
  levels: CommissionLevel[];
  isLoading: boolean;
  directReferrals: number;
  subscriptionExpiresAt: string | null;
}

export function SubscriptionStructure({ 
  levels, 
  isLoading,
  directReferrals,
  subscriptionExpiresAt
}: SubscriptionStructureProps) {
  
  const getStatusIcon = (status: 'active' | 'frozen' | 'locked') => {
    switch (status) {
      case 'active':
        return <CheckCircle2 className="h-5 w-5 text-success" />;
      case 'frozen':
        return <Snowflake className="h-5 w-5 text-muted-foreground" />;
      case 'locked':
        return <Lock className="h-5 w-5 text-muted-foreground" />;
    }
  };

  const getStatusBadge = (status: 'active' | 'frozen' | 'locked') => {
    switch (status) {
      case 'active':
        return <Badge className="profit-indicator">Активен</Badge>;
      case 'frozen':
        return <Badge className="frozen-indicator">Заморожен</Badge>;
      case 'locked':
        return <Badge variant="outline">Заблокирован</Badge>;
    }
  };

  if (isLoading) {
    return (
      <Card className="financial-card">
        <CardHeader>
          <CardTitle>Абонентская структура (5 уровней)</CardTitle>
        </CardHeader>
        <CardContent>
          <p className="text-center text-muted-foreground">Загрузка...</p>
        </CardContent>
      </Card>
    );
  }

  return (
    <Card className="financial-card">
      <CardHeader>
        <div className="space-y-2">
          <CardTitle>Абонентская структура (5 уровней)</CardTitle>
          <div className="flex items-center gap-2 text-sm text-muted-foreground">
            <Info className="h-4 w-4" />
            <span>
              Прямых рефералов: {directReferrals} | 
              {subscriptionExpiresAt 
                ? ` Подписка активна до: ${new Date(subscriptionExpiresAt).toLocaleDateString('ru-RU')}`
                : ' Подписка не активна'}
            </span>
          </div>
        </div>
      </CardHeader>
      <CardContent>
        <div className="space-y-4">
          {!levels || levels.length === 0 ? (
            <p className="text-center text-muted-foreground">Нет данных о комиссиях</p>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full">
                <thead>
                  <tr className="border-b border-border">
                    <th className="text-left py-3 px-2 font-medium">Уровень</th>
                    <th className="text-left py-3 px-2 font-medium">Условие</th>
                    <th className="text-right py-3 px-2 font-medium">Партнёры</th>
                    <th className="text-right py-3 px-2 font-medium">Процент</th>
                    <th className="text-right py-3 px-2 font-medium">Начислено</th>
                    <th className="text-right py-3 px-2 font-medium">Статус</th>
                  </tr>
                </thead>
                <tbody>
                  {levels.map((level) => (
                    <tr key={level.id} className="border-b border-border/50 hover:bg-muted/50">
                      <td className="py-3 px-2">
                        <div className="flex items-center gap-2">
                          {getStatusIcon(level.status || 'locked')}
                          <span className="font-medium">L{level.level}</span>
                        </div>
                      </td>
                      <td className="py-3 px-2">
                        <TooltipProvider>
                          <Tooltip>
                            <TooltipTrigger asChild>
                              <div className="flex items-center gap-1 cursor-help">
                                <span className="text-sm">
                                  {level.unlock_requirement === 0 
                                    ? 'Всегда открыт' 
                                    : `${directReferrals}/${level.unlock_requirement}`}
                                </span>
                                <Info className="h-3 w-3 text-muted-foreground" />
                              </div>
                            </TooltipTrigger>
                            <TooltipContent>
                              <p className="text-xs">
                                {level.unlock_requirement === 0 
                                  ? 'Первый уровень доступен сразу'
                                  : `Для открытия уровня ${level.level} нужно ${level.unlock_requirement} лично приглашённых`}
                              </p>
                            </TooltipContent>
                          </Tooltip>
                        </TooltipProvider>
                      </td>
                      <td className="py-3 px-2 text-right">
                        <span className="text-sm">{level.partners_count || 0}</span>
                      </td>
                      <td className="py-3 px-2 text-right">
                        <span className="text-sm font-medium">{level.percent}%</span>
                      </td>
                      <td className="py-3 px-2 text-right">
                        <div className="flex flex-col items-end">
                          <span className="font-medium text-success">
                            {formatCents(level.earned || 0)}
                          </span>
                          {level.frozen && level.frozen > 0 && (
                            <span className="text-xs text-muted-foreground">
                              {formatCents(level.frozen)} заморожено
                            </span>
                          )}
                        </div>
                      </td>
                      <td className="py-3 px-2 text-right">
                        {getStatusBadge(level.status || 'locked')}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </div>
        
        <div className="mt-6 p-4 bg-muted/50 rounded-lg space-y-2">
          <h4 className="font-medium text-sm">Условия разблокировки уровней:</h4>
          <ul className="text-xs text-muted-foreground space-y-1">
            <li>• L1 — открыт сразу</li>
            <li>• L2 — при 3 лично приглашённых</li>
            <li>• L3 — при 5 лично приглашённых</li>
            <li>• L4 — при 8 лично приглашённых</li>
            <li>• L5 — при 10 лично приглашённых</li>
          </ul>
          <p className="text-xs text-muted-foreground mt-2">
            При окончании подписки начисления замораживаются. После продления — разблокируются.
          </p>
        </div>
      </CardContent>
    </Card>
  );
}
