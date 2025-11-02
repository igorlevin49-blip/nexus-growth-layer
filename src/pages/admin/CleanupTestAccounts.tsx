import { useState } from "react";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { Trash2, AlertTriangle, Info } from "lucide-react";
import { useCleanupAllTestUsers } from "@/hooks/useCleanupAllTestUsers";
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "@/components/ui/alert-dialog";

export default function CleanupTestAccounts() {
  const [confirmationPhrase, setConfirmationPhrase] = useState("");
  const [showConfirmDialog, setShowConfirmDialog] = useState(false);
  const [previewResult, setPreviewResult] = useState<any>(null);

  const cleanupMutation = useCleanupAllTestUsers();

  const keepEmails = ['egor.smart@mail.ru', 'mg-market001@mail.ru'];
  const requiredPhrase = 'УДАЛИТЬ ВСЕ ТЕСТОВЫЕ АККАУНТЫ';

  const handlePreview = async () => {
    const result = await cleanupMutation.mutateAsync({
      keepEmails,
      confirmationPhrase: '',
      dryRun: true
    });
    setPreviewResult(result);
  };

  const handleCleanup = async () => {
    if (confirmationPhrase !== requiredPhrase) {
      return;
    }

    await cleanupMutation.mutateAsync({
      keepEmails,
      confirmationPhrase,
      dryRun: false
    });

    setShowConfirmDialog(false);
    setConfirmationPhrase("");
    setPreviewResult(null);
  };

  return (
    <div className="container mx-auto p-6 space-y-6">
      <div>
        <h1 className="text-3xl font-bold mb-2">Очистка тестовых аккаунтов</h1>
        <p className="text-muted-foreground">
          Полное удаление всех пользователей кроме указанных в системе
        </p>
      </div>

      <Alert>
        <AlertTriangle className="h-4 w-4" />
        <AlertDescription>
          <strong>ВНИМАНИЕ!</strong> Эта операция необратима. Будут удалены все данные пользователей,
          включая заказы, подписки, транзакции и реферальные связи.
        </AlertDescription>
      </Alert>

      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <Trash2 className="h-5 w-5" />
            Полная очистка системы
          </CardTitle>
          <CardDescription>
            Будут сохранены только указанные аккаунты, все остальные будут полностью удалены
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-6">
          <div>
            <Label className="text-base font-semibold mb-3 block">Сохраняемые аккаунты:</Label>
            <div className="flex flex-wrap gap-2">
              {keepEmails.map((email) => (
                <Badge key={email} variant="outline" className="px-3 py-1">
                  {email}
                </Badge>
              ))}
            </div>
          </div>

          {previewResult && (
            <Alert>
              <Info className="h-4 w-4" />
              <AlertDescription>
                <div className="space-y-1">
                  <p className="font-semibold">Будет удалено:</p>
                  <ul className="list-disc list-inside space-y-1 text-sm">
                    <li>Пользователей: {previewResult.users}</li>
                    <li>Заказов: {previewResult.orders}</li>
                    <li>Подписок: {previewResult.subscriptions}</li>
                    <li>Транзакций: {previewResult.transactions}</li>
                    <li>Выводов: {previewResult.withdrawals}</li>
                    <li>Реферальных связей: {previewResult.referrals}</li>
                    <li>Записей активности: {previewResult.activity}</li>
                  </ul>
                </div>
              </AlertDescription>
            </Alert>
          )}

          <div className="space-y-4">
            <Button
              onClick={handlePreview}
              variant="outline"
              disabled={cleanupMutation.isPending}
              className="w-full"
            >
              Предпросмотр удаления
            </Button>

            <div className="space-y-2">
              <Label>Фраза подтверждения</Label>
              <Input
                type="text"
                placeholder={requiredPhrase}
                value={confirmationPhrase}
                onChange={(e) => setConfirmationPhrase(e.target.value)}
              />
              <p className="text-xs text-muted-foreground">
                Введите: <code className="bg-muted px-1 py-0.5 rounded">{requiredPhrase}</code>
              </p>
            </div>

            <Button
              onClick={() => setShowConfirmDialog(true)}
              variant="destructive"
              disabled={confirmationPhrase !== requiredPhrase || cleanupMutation.isPending}
              className="w-full"
            >
              <Trash2 className="mr-2 h-4 w-4" />
              Удалить все тестовые аккаунты
            </Button>
          </div>
        </CardContent>
      </Card>

      <AlertDialog open={showConfirmDialog} onOpenChange={setShowConfirmDialog}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Вы абсолютно уверены?</AlertDialogTitle>
            <AlertDialogDescription>
              Это действие нельзя отменить. Будут удалены все пользователи и их данные,
              кроме {keepEmails.join(' и ')}.
              <br /><br />
              Все email-адреса будут освобождены для повторной регистрации.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Отмена</AlertDialogCancel>
            <AlertDialogAction
              onClick={handleCleanup}
              className="bg-destructive text-destructive-foreground hover:bg-destructive/90"
            >
              Да, удалить всё
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  );
}
