import { AppLayout } from "@/components/Layout/AppLayout";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { usePostMigrationTests, useRunTests, TestResult } from "@/hooks/usePostMigrationTests";
import { RefreshCw, CheckCircle, XCircle, AlertTriangle, Database, Users, DollarSign, ShoppingCart, CreditCard } from "lucide-react";
import { cn } from "@/lib/utils";

const getCategoryIcon = (category: string) => {
  switch (category) {
    case 'network': return Users;
    case 'commissions': return DollarSign;
    case 'activations': return ShoppingCart;
    case 'orders': return ShoppingCart;
    case 'subscriptions': return CreditCard;
    case 'finances': return DollarSign;
    default: return Database;
  }
};

const getCategoryName = (category: string) => {
  switch (category) {
    case 'network': return 'Сеть';
    case 'commissions': return 'Комиссии';
    case 'activations': return 'Активации';
    case 'orders': return 'Заказы';
    case 'subscriptions': return 'Подписки';
    case 'finances': return 'Финансы';
    default: return category;
  }
};

function TestResultCard({ test }: { test: TestResult }) {
  const Icon = getCategoryIcon(test.category);
  
  return (
    <div className={cn(
      "p-4 rounded-lg border",
      test.passed 
        ? "bg-success/10 border-success/30" 
        : "bg-destructive/10 border-destructive/30"
    )}>
      <div className="flex items-start justify-between gap-4">
        <div className="flex items-start gap-3">
          <div className={cn(
            "p-2 rounded-lg",
            test.passed ? "bg-success/20" : "bg-destructive/20"
          )}>
            {test.passed 
              ? <CheckCircle className="h-4 w-4 text-success" />
              : <XCircle className="h-4 w-4 text-destructive" />
            }
          </div>
          <div>
            <div className="flex items-center gap-2 mb-1">
              <span className="font-medium">{test.test_name}</span>
              <Badge variant="outline" className="gap-1 text-xs">
                <Icon className="h-3 w-3" />
                {getCategoryName(test.category)}
              </Badge>
              {test.is_critical && (
                <Badge variant="destructive" className="text-xs">
                  Critical
                </Badge>
              )}
            </div>
            {test.error_message && (
              <p className="text-sm text-destructive">{test.error_message}</p>
            )}
            {test.details && !(test.details as Record<string, unknown>).skipped && (
              <p className="text-xs text-muted-foreground mt-1">
                {JSON.stringify(test.details)}
              </p>
            )}
          </div>
        </div>
        <Badge className={test.passed ? "bg-success" : "bg-destructive"}>
          {test.passed ? "OK" : "FAIL"}
        </Badge>
      </div>
    </div>
  );
}

export default function SystemTests() {
  const { data: tests, isLoading } = usePostMigrationTests();
  const runTests = useRunTests();
  
  const passedCount = tests?.filter(t => t.passed).length || 0;
  const failedCount = tests?.filter(t => !t.passed).length || 0;
  const criticalFailedCount = tests?.filter(t => t.is_critical && !t.passed).length || 0;
  const totalCount = tests?.length || 0;
  
  // Group by category
  const categories = tests?.reduce((acc, test) => {
    if (!acc[test.category]) {
      acc[test.category] = [];
    }
    acc[test.category].push(test);
    return acc;
  }, {} as Record<string, TestResult[]>) || {};

  return (
    <div className="space-y-6 p-6">
        <div className="flex items-center justify-between">
          <div>
            <h1 className="text-2xl font-bold">Системные тесты</h1>
            <p className="text-muted-foreground">
              Автоматическая проверка работоспособности ключевых функций
            </p>
          </div>
          <Button 
            onClick={() => runTests.mutate()}
            disabled={runTests.isPending}
            className="gap-2"
          >
            <RefreshCw className={cn("h-4 w-4", runTests.isPending && "animate-spin")} />
            Запустить тесты
          </Button>
        </div>

        {/* Summary */}
        <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
          <Card>
            <CardContent className="pt-6">
              <div className="flex items-center gap-3">
                <div className="p-3 rounded-full bg-muted">
                  <Database className="h-5 w-5 text-muted-foreground" />
                </div>
                <div>
                  <p className="text-2xl font-bold">{totalCount}</p>
                  <p className="text-sm text-muted-foreground">Всего тестов</p>
                </div>
              </div>
            </CardContent>
          </Card>
          
          <Card>
            <CardContent className="pt-6">
              <div className="flex items-center gap-3">
                <div className="p-3 rounded-full bg-success/20">
                  <CheckCircle className="h-5 w-5 text-success" />
                </div>
                <div>
                  <p className="text-2xl font-bold text-success">{passedCount}</p>
                  <p className="text-sm text-muted-foreground">Пройдено</p>
                </div>
              </div>
            </CardContent>
          </Card>
          
          <Card>
            <CardContent className="pt-6">
              <div className="flex items-center gap-3">
                <div className="p-3 rounded-full bg-destructive/20">
                  <XCircle className="h-5 w-5 text-destructive" />
                </div>
                <div>
                  <p className="text-2xl font-bold text-destructive">{failedCount}</p>
                  <p className="text-sm text-muted-foreground">Не пройдено</p>
                </div>
              </div>
            </CardContent>
          </Card>
        </div>

        {/* Loading */}
        {isLoading && (
          <div className="flex items-center justify-center py-12">
            <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-primary"></div>
          </div>
        )}

        {/* Results by category */}
        {!isLoading && Object.entries(categories).map(([category, categoryTests]) => (
          <Card key={category}>
            <CardHeader>
              <div className="flex items-center gap-2">
                {(() => {
                  const Icon = getCategoryIcon(category);
                  return <Icon className="h-5 w-5 text-primary" />;
                })()}
                <CardTitle>{getCategoryName(category)}</CardTitle>
              </div>
              <CardDescription>
                {categoryTests.filter(t => t.passed).length} из {categoryTests.length} тестов пройдено
              </CardDescription>
            </CardHeader>
            <CardContent className="space-y-3">
              {categoryTests.map((test) => (
                <TestResultCard key={test.test_name} test={test} />
              ))}
            </CardContent>
          </Card>
        ))}

        {/* No tests warning */}
        {!isLoading && totalCount === 0 && (
          <Card>
            <CardContent className="py-12">
              <div className="flex flex-col items-center gap-4 text-center">
                <AlertTriangle className="h-12 w-12 text-warning" />
                <div>
                  <p className="font-medium">Тесты не найдены</p>
                  <p className="text-sm text-muted-foreground">
                    Нажмите "Запустить тесты" для проверки системы
                  </p>
                </div>
              </div>
            </CardContent>
          </Card>
        )}
    </div>
  );
}
