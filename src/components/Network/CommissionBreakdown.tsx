import { useMemo } from "react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { useCommissionStructure, CommissionLevel } from "@/hooks/useCommissionStructure";
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from "@/components/ui/tooltip";
import { Info } from "lucide-react";

interface CommissionBreakdownProps {
  structureType: 1 | 2;
}

export function CommissionBreakdown({ structureType }: CommissionBreakdownProps) {
  // Memoize dates to prevent infinite re-renders
  const { startDate, endDate } = useMemo(() => {
    const start = new Date();
    start.setDate(1);
    start.setHours(0, 0, 0, 0);
    return { startDate: start, endDate: new Date() };
  }, []);

  const { data: levels = [], isLoading } = useCommissionStructure({
    structureType,
    startDate,
    endDate
  });

  const totalEarned = levels.reduce((sum, l) => sum + l.earned, 0);
  const totalFrozen = levels.reduce((sum, l) => sum + l.frozen, 0);
  const totalPartners = levels.reduce((sum, l) => sum + l.partners_count, 0);
  const maxLevels = structureType === 1 ? 5 : 10;

  if (isLoading) {
    return (
      <Card>
        <CardHeader className="pb-2">
          <CardTitle className="text-base">Комиссии за месяц</CardTitle>
        </CardHeader>
        <CardContent className="space-y-2">
          <Skeleton className="h-6 w-full" />
          <Skeleton className="h-6 w-full" />
          <Skeleton className="h-6 w-full" />
        </CardContent>
      </Card>
    );
  }

  return (
    <Card>
      <CardHeader className="pb-2">
        <div className="flex items-center justify-between">
          <CardTitle className="text-base">Комиссии за месяц</CardTitle>
          <TooltipProvider>
            <Tooltip>
              <TooltipTrigger>
                <Info className="h-4 w-4 text-muted-foreground" />
              </TooltipTrigger>
              <TooltipContent>
                <p>Комиссии со всех {maxLevels} уровней вашей сети</p>
              </TooltipContent>
            </Tooltip>
          </TooltipProvider>
        </div>
      </CardHeader>
      <CardContent className="space-y-1">
        {levels.length === 0 ? (
          <p className="text-sm text-muted-foreground">Нет комиссий за этот период</p>
        ) : (
          <>
            <div className="space-y-1 text-sm">
              {levels.map((level) => (
                <div key={level.level} className="flex justify-between items-center py-1 border-b border-border/50 last:border-0">
                  <span className="text-muted-foreground">
                    L{level.level}
                    {level.partners_count > 0 && (
                      <span className="ml-1 text-xs">({level.partners_count})</span>
                    )}
                  </span>
                  <div className="flex items-center gap-2">
                    <span className="font-medium">{level.earned.toLocaleString('ru-RU')} ₸</span>
                    {level.frozen > 0 && (
                      <span className="text-xs text-warning">
                        ({level.frozen.toLocaleString('ru-RU')} ₸ ❄️)
                      </span>
                    )}
                  </div>
                </div>
              ))}
            </div>
            <div className="pt-2 border-t border-border flex justify-between items-center">
              <span className="font-medium">Итого</span>
              <div className="text-right">
                <span className="text-lg font-bold">{totalEarned.toLocaleString('ru-RU')} ₸</span>
                {totalFrozen > 0 && (
                  <div className="text-xs text-warning">
                    Заморожено: {totalFrozen.toLocaleString('ru-RU')} ₸
                  </div>
                )}
              </div>
            </div>
          </>
        )}
      </CardContent>
    </Card>
  );
}
