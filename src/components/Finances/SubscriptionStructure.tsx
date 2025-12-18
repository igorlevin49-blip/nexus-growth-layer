import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { CheckCircle2, Lock, Snowflake, Info } from "lucide-react";
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
                    <th className="text-left py-2 sm:py-3 px-2 font-medium text-xs sm:text-sm whitespace-nowrap">Уровень</th>
                    <th className="text-left py-2 sm:py-3 px-2 font-medium text-xs sm:text-sm whitespace-nowrap">Условие</th>
                    <th className="text-right py-2 sm:py-3 px-2 font-medium text-xs sm:text-sm whitespace-nowrap">Партнёры</th>
                    <th className="text-right py-2 sm:py-3 px-2 font-medium text-xs sm:text-sm whitespace-nowrap">Процент</th>
                    <th className="text-right py-2 sm:py-3 px-2 font-medium text-xs sm:text-sm whitespace-nowrap">Начислено</th>
                    <th className="text-right py-2 sm:py-3 px-2 font-medium text-xs sm:text-sm whitespace-nowrap">Статус</th>
                  </tr>
                </thead>
                <tbody>
                  {levels.map((level) => (
                    <tr key={level.level} className="border-b border-border/50 hover:bg-muted/50">
                      <td className="py-2 sm:py-3 px-2">
                        <div className="flex items-center gap-2">
                          {getStatusIcon(level.status || 'locked')}
                          <span className="font-medium text-xs sm:text-sm">L{level.level}</span>
                        </div>
                      </td>
                      <td className="py-2 sm:py-3 px-2">
                        <TooltipProvider>
                          <Tooltip>
                            <TooltipTrigger asChild>
                              <div className="flex items-center gap-1 cursor-help">
                                <span className="text-xs sm:text-sm">
                                  {level.unlock_requirement ? level.unlock_requirement : 'Всегда открыт'}
                                </span>
                                <Info className="h-3 w-3 text-muted-foreground" />
                              </div>
                            </TooltipTrigger>
                            <TooltipContent>
                              <p className="text-xs">
                                {level.unlock_requirement || 'Первый уровень доступен сразу'}
                              </p>
                            </TooltipContent>
                          </Tooltip>
                        </TooltipProvider>
                      </td>
                      <td className="py-2 sm:py-3 px-2 text-right">
                        <span className="text-xs sm:text-sm">{level.partners_count || 0}</span>
                      </td>
                      <td className="py-2 sm:py-3 px-2 text-right">
                        <span className="text-xs sm:text-sm font-medium">{level.percent}%</span>
                      </td>
                        <td className="py-2 sm:py-3 px-2 text-right">
                        <div className="flex flex-col items-end">
                          <span className="font-medium text-success text-xs sm:text-sm">
                            {(level.earned || 0).toLocaleString('ru-RU')} ₸
                          </span>
                          {level.frozen && level.frozen > 0 && (
                            <span className="text-xs text-muted-foreground">
                              {level.frozen.toLocaleString('ru-RU')} ₸ заморожено
                            </span>
                          )}
                        </div>
                      </td>
                      <td className="py-2 sm:py-3 px-2 text-right">
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
