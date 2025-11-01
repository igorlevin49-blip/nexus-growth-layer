import { useState } from "react";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Checkbox } from "@/components/ui/checkbox";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { AlertTriangle, Trash2, Flag } from "lucide-react";
import { useAdminUsers, useFlagTestData, usePurgeTestData } from "@/hooks/useTestDataCleanup";
import { useCleanupTestData } from "@/hooks/useCleanupTestData";
import { AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle } from "@/components/ui/alert-dialog";

export default function TestDataCleanup() {
  const [startDate, setStartDate] = useState('2025-01-01');
  const [endDate, setEndDate] = useState(new Date().toISOString().split('T')[0]);
  const [selectedUsers, setSelectedUsers] = useState<string[]>([]);
  const [showConfirmFlag, setShowConfirmFlag] = useState(false);
  const [showConfirmPurge, setShowConfirmPurge] = useState(false);
  const [confirmPhrase, setConfirmPhrase] = useState('');
  const [dryRunResult, setDryRunResult] = useState<any>(null);
  const [purgeResult, setPurgeResult] = useState<any>(null);
  const [cleanupEmail, setCleanupEmail] = useState("egor.smart@mail.ru");
  const [cleanupConfirm, setCleanupConfirm] = useState("");
  const [cleanupPreview, setCleanupPreview] = useState<any>(null);
  const [showCleanupDialog, setShowCleanupDialog] = useState(false);

  const { data: adminUsers } = useAdminUsers();
  const flagMutation = useFlagTestData();
  const purgeMutation = usePurgeTestData();
  const cleanupMutation = useCleanupTestData();

  const handleDryRunFlag = async () => {
    const result = await flagMutation.mutateAsync({
      startDate,
      endDate,
      userIds: selectedUsers.length > 0 ? selectedUsers : undefined,
      dryRun: true
    });
    setDryRunResult(result);
  };

  const handleFlag = async () => {
    await flagMutation.mutateAsync({
      startDate,
      endDate,
      userIds: selectedUsers.length > 0 ? selectedUsers : undefined,
      dryRun: false
    });
    setShowConfirmFlag(false);
    setDryRunResult(null);
  };

  const handleDryRunPurge = async () => {
    const result = await purgeMutation.mutateAsync({
      dryRun: true
    });
    setPurgeResult(result);
  };

  const handlePurge = async () => {
    if (confirmPhrase !== 'УДАЛИТЬ ТЕСТОВЫЕ ДАННЫЕ') {
      return;
    }
    await purgeMutation.mutateAsync({
      dryRun: false,
      confirmationPhrase: confirmPhrase
    });
    setShowConfirmPurge(false);
    setPurgeResult(null);
    setConfirmPhrase('');
  };

  const toggleUser = (userId: string) => {
    setSelectedUsers(prev =>
      prev.includes(userId)
        ? prev.filter(id => id !== userId)
        : [...prev, userId]
    );
  };

  const handleCleanupPreview = async () => {
    const result = await cleanupMutation.mutateAsync({
      superadminEmail: cleanupEmail,
      confirmationPhrase: "",
      dryRun: true
    });
    setCleanupPreview(result);
  };

  const handleCleanup = async () => {
    if (cleanupConfirm !== 'ОЧИСТИТЬ ТЕСТОВЫЕ ДАННЫЕ') return;
    
    await cleanupMutation.mutateAsync({
      superadminEmail: cleanupEmail,
      confirmationPhrase: cleanupConfirm,
      dryRun: false
    });
    
    setShowCleanupDialog(false);
    setCleanupConfirm("");
    setCleanupPreview(null);
  };

  return (
    <>
      <div className="container mx-auto py-8">
        <div className="mb-6">
          <h1 className="text-3xl font-bold">Очистка тестовых транзакций</h1>
          <p className="text-muted-foreground">
            Безопасное управление тестовыми данными без удаления пользователей и настроек
          </p>
        </div>

        <Alert variant="destructive" className="mb-6">
          <AlertTriangle className="h-4 w-4" />
          <AlertDescription>
            <strong>ВНИМАНИЕ:</strong> Эти операции необратимы. Всегда используйте DRY-RUN перед выполнением реальных действий.
            Будут затронуты только финансовые записи (заказы, платежи, комиссии, выводы).
            Пользователи, роли, настройки, товары и реферальные связи останутся нетронутыми.
          </AlertDescription>
        </Alert>

        <Tabs defaultValue="flag" className="w-full">
          <TabsList className="grid w-full grid-cols-3">
            <TabsTrigger value="flag">
              <Flag className="mr-2 h-4 w-4" />
              Пометить тестовые
            </TabsTrigger>
            <TabsTrigger value="purge">
              <Trash2 className="mr-2 h-4 w-4" />
              Удалить помеченные
            </TabsTrigger>
            <TabsTrigger value="cleanup">
              <Trash2 className="mr-2 h-4 w-4" />
              Полная очистка
            </TabsTrigger>
          </TabsList>

          <TabsContent value="flag">
            <Card>
              <CardHeader>
                <CardTitle>Пометка тестовых записей</CardTitle>
                <CardDescription>
                  Выберите критерии для поиска тестовых данных. Сначала запустите DRY-RUN.
                </CardDescription>
              </CardHeader>
              <CardContent className="space-y-6">
                <div className="grid grid-cols-2 gap-4">
                  <div className="space-y-2">
                    <Label htmlFor="startDate">Дата начала</Label>
                    <Input
                      id="startDate"
                      type="date"
                      value={startDate}
                      onChange={(e) => setStartDate(e.target.value)}
                    />
                  </div>
                  <div className="space-y-2">
                    <Label htmlFor="endDate">Дата окончания</Label>
                    <Input
                      id="endDate"
                      type="date"
                      value={endDate}
                      onChange={(e) => setEndDate(e.target.value)}
                    />
                  </div>
                </div>

                <div className="space-y-2">
                  <Label>Пользователи (оставьте пустым для всех)</Label>
                  <div className="border rounded-md p-4 space-y-2 max-h-48 overflow-y-auto">
                    {adminUsers?.map(user => (
                      <div key={user.id} className="flex items-center space-x-2">
                        <Checkbox
                          id={user.id}
                          checked={selectedUsers.includes(user.id)}
                          onCheckedChange={() => toggleUser(user.id)}
                        />
                        <label htmlFor={user.id} className="text-sm cursor-pointer">
                          {user.name} ({user.email})
                        </label>
                      </div>
                    ))}
                  </div>
                </div>

                {dryRunResult && (
                  <div className="border rounded-md p-4">
                    <p className="font-semibold mb-2">DRY-RUN результат:</p>
                    <ul className="space-y-1">
                      <li>Заказы: {dryRunResult.orders}</li>
                      <li>Подписки: {dryRunResult.subscriptions}</li>
                      <li>Транзакции: {dryRunResult.transactions}</li>
                      <li>Выводы: {dryRunResult.withdrawals}</li>
                    </ul>
                  </div>
                )}

                <div className="flex gap-2">
                  <Button
                    onClick={handleDryRunFlag}
                    disabled={flagMutation.isPending}
                    variant="outline"
                  >
                    Показать что будет помечено (DRY-RUN)
                  </Button>
                  <Button
                    onClick={() => setShowConfirmFlag(true)}
                    disabled={flagMutation.isPending || !dryRunResult}
                    variant="destructive"
                  >
                    Пометить как тестовые
                  </Button>
                </div>
              </CardContent>
            </Card>
          </TabsContent>

          <TabsContent value="purge">
            <Card>
              <CardHeader>
                <CardTitle>Удаление помеченных записей</CardTitle>
                <CardDescription>
                  Удаляет все записи с флагом is_test=true. Операция необратима!
                </CardDescription>
              </CardHeader>
              <CardContent className="space-y-6">
                {purgeResult && (
                  <div className="border rounded-md p-4">
                    <p className="font-semibold mb-2">DRY-RUN результат - будет удалено:</p>
                    <ul className="space-y-1">
                      <li>Транзакции: {purgeResult.transactions}</li>
                      <li>Выводы: {purgeResult.withdrawals}</li>
                      <li>Подписки: {purgeResult.subscriptions}</li>
                      <li>Заказы: {purgeResult.orders}</li>
                    </ul>
                  </div>
                )}

                <Alert variant="destructive">
                  <AlertTriangle className="h-4 w-4" />
                  <AlertDescription>
                    Удаление происходит в правильном порядке зависимостей:
                    транзакции → выводы → подписки → заказы
                  </AlertDescription>
                </Alert>

                <div className="flex gap-2">
                  <Button
                    onClick={handleDryRunPurge}
                    disabled={purgeMutation.isPending}
                    variant="outline"
                  >
                    Показать что будет удалено (DRY-RUN)
                  </Button>
                  <Button
                    onClick={() => setShowConfirmPurge(true)}
                    disabled={purgeMutation.isPending || !purgeResult}
                    variant="destructive"
                  >
                    Удалить помеченные
                  </Button>
                </div>
              </CardContent>
            </Card>
          </TabsContent>

          <TabsContent value="cleanup">
            <Card>
              <CardHeader>
                <CardTitle>Полная очистка (сброс к заводским настройкам)</CardTitle>
                <CardDescription>
                  Удаляет ВСЕХ пользователей кроме суперадмина и все их данные. Настройки, товары и структура остаются.
                </CardDescription>
              </CardHeader>
              <CardContent className="space-y-6">
                <Alert variant="destructive">
                  <AlertTriangle className="h-4 w-4" />
                  <AlertDescription>
                    <strong>КРАЙНЕ ОПАСНО!</strong> Эта операция удалит всех пользователей (кроме одного), 
                    все заказы, подписки, транзакции, выплаты и реферальные связи. 
                    Используйте только для полного сброса перед боевым запуском!
                  </AlertDescription>
                </Alert>

                <div className="space-y-2">
                  <Label htmlFor="cleanupEmail">Email суперадмина (будет сохранён)</Label>
                  <Input
                    id="cleanupEmail"
                    type="email"
                    value={cleanupEmail}
                    onChange={(e) => setCleanupEmail(e.target.value)}
                  />
                </div>

                {cleanupPreview && (
                  <div className="border rounded-md p-4">
                    <p className="font-semibold mb-2">DRY-RUN - будет удалено:</p>
                    <div className="grid grid-cols-2 gap-4">
                      <div>
                        <p className="text-sm text-muted-foreground">Пользователи</p>
                        <p className="text-2xl font-bold">{cleanupPreview.users}</p>
                      </div>
                      <div>
                        <p className="text-sm text-muted-foreground">Заказы</p>
                        <p className="text-2xl font-bold">{cleanupPreview.orders}</p>
                      </div>
                      <div>
                        <p className="text-sm text-muted-foreground">Подписки</p>
                        <p className="text-2xl font-bold">{cleanupPreview.subscriptions}</p>
                      </div>
                      <div>
                        <p className="text-sm text-muted-foreground">Транзакции</p>
                        <p className="text-2xl font-bold">{cleanupPreview.transactions}</p>
                      </div>
                      <div>
                        <p className="text-sm text-muted-foreground">Выплаты</p>
                        <p className="text-2xl font-bold">{cleanupPreview.withdrawals}</p>
                      </div>
                      <div>
                        <p className="text-sm text-muted-foreground">Реферальные связи</p>
                        <p className="text-2xl font-bold">{cleanupPreview.referrals}</p>
                      </div>
                    </div>
                  </div>
                )}

                <div className="flex gap-2">
                  <Button
                    onClick={handleCleanupPreview}
                    disabled={cleanupMutation.isPending}
                    variant="outline"
                  >
                    Показать что будет удалено (DRY-RUN)
                  </Button>
                  <Button
                    onClick={() => setShowCleanupDialog(true)}
                    disabled={cleanupMutation.isPending || !cleanupPreview}
                    variant="destructive"
                  >
                    Выполнить полную очистку
                  </Button>
                </div>
              </CardContent>
            </Card>
          </TabsContent>
        </Tabs>
      </div>

      <AlertDialog open={showConfirmFlag} onOpenChange={setShowConfirmFlag}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Подтвердите пометку</AlertDialogTitle>
            <AlertDialogDescription>
              Вы собираетесь пометить как тестовые следующие записи:
              <ul className="mt-2 space-y-1">
                <li>Заказы: {dryRunResult?.orders || 0}</li>
                <li>Подписки: {dryRunResult?.subscriptions || 0}</li>
                <li>Транзакции: {dryRunResult?.transactions || 0}</li>
                <li>Выводы: {dryRunResult?.withdrawals || 0}</li>
              </ul>
              Эти записи будут скрыты из отчетов по умолчанию.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Отмена</AlertDialogCancel>
            <AlertDialogAction onClick={handleFlag}>
              Подтвердить
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>

      <AlertDialog open={showConfirmPurge} onOpenChange={setShowConfirmPurge}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Подтвердите удаление</AlertDialogTitle>
            <AlertDialogDescription>
              <strong className="text-destructive">ВНИМАНИЕ! Это действие необратимо.</strong>
              <br />
              Будут удалены следующие помеченные записи:
              <ul className="mt-2 space-y-1">
                <li>Транзакции: {purgeResult?.transactions || 0}</li>
                <li>Выводы: {purgeResult?.withdrawals || 0}</li>
                <li>Подписки: {purgeResult?.subscriptions || 0}</li>
                <li>Заказы: {purgeResult?.orders || 0}</li>
              </ul>
              <div className="mt-4 space-y-2">
                <Label htmlFor="confirmPhrase">
                  Введите фразу: <strong>УДАЛИТЬ ТЕСТОВЫЕ ДАННЫЕ</strong>
                </Label>
                <Input
                  id="confirmPhrase"
                  value={confirmPhrase}
                  onChange={(e) => setConfirmPhrase(e.target.value)}
                  placeholder="УДАЛИТЬ ТЕСТОВЫЕ ДАННЫЕ"
                />
              </div>
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel onClick={() => setConfirmPhrase('')}>
              Отмена
            </AlertDialogCancel>
            <AlertDialogAction
              onClick={handlePurge}
              disabled={confirmPhrase !== 'УДАЛИТЬ ТЕСТОВЫЕ ДАННЫЕ'}
              className="bg-destructive text-destructive-foreground hover:bg-destructive/90"
            >
              Удалить
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>

      <AlertDialog open={showCleanupDialog} onOpenChange={setShowCleanupDialog}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Подтвердите полную очистку</AlertDialogTitle>
            <AlertDialogDescription>
              <strong className="text-destructive">КРИТИЧЕСКОЕ ПРЕДУПРЕЖДЕНИЕ!</strong>
              <br />
              Будут БЕЗВОЗВРАТНО удалены:
              <ul className="mt-2 space-y-1">
                <li>Пользователи: {cleanupPreview?.users || 0}</li>
                <li>Заказы: {cleanupPreview?.orders || 0}</li>
                <li>Подписки: {cleanupPreview?.subscriptions || 0}</li>
                <li>Транзакции: {cleanupPreview?.transactions || 0}</li>
                <li>Выплаты: {cleanupPreview?.withdrawals || 0}</li>
                <li>Реферальные связи: {cleanupPreview?.referrals || 0}</li>
              </ul>
              <div className="mt-4 space-y-2">
                <Label htmlFor="cleanupConfirm">
                  Введите фразу: <strong>ОЧИСТИТЬ ТЕСТОВЫЕ ДАННЫЕ</strong>
                </Label>
                <Input
                  id="cleanupConfirm"
                  value={cleanupConfirm}
                  onChange={(e) => setCleanupConfirm(e.target.value)}
                  placeholder="ОЧИСТИТЬ ТЕСТОВЫЕ ДАННЫЕ"
                />
              </div>
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel onClick={() => setCleanupConfirm('')}>
              Отмена
            </AlertDialogCancel>
            <AlertDialogAction
              onClick={handleCleanup}
              disabled={cleanupConfirm !== 'ОЧИСТИТЬ ТЕСТОВЫЕ ДАННЫЕ'}
              className="bg-destructive text-destructive-foreground hover:bg-destructive/90"
            >
              Удалить безвозвратно
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </>
  );
}
