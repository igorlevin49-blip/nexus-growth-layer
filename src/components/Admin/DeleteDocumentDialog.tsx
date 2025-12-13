import { useState } from 'react';
import {
  AlertDialog,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from '@/components/ui/alert-dialog';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { useDeleteDocument } from '@/hooks/useLegalDocuments';
import { AlertTriangle } from 'lucide-react';

interface DeleteDocumentDialogProps {
  doc: any;
  onOpenChange: (open: boolean) => void;
}

export function DeleteDocumentDialog({ doc, onOpenChange }: DeleteDocumentDialogProps) {
  const [confirmText, setConfirmText] = useState('');
  const deleteDocument = useDeleteDocument();

  const handleDelete = async () => {
    await deleteDocument.mutateAsync(doc.id);
    onOpenChange(false);
  };

  const isConfirmed = confirmText === doc?.title;

  if (!doc) return null;

  return (
    <AlertDialog open={!!doc} onOpenChange={onOpenChange}>
      <AlertDialogContent>
        <AlertDialogHeader>
          <AlertDialogTitle className="flex items-center gap-2 text-destructive">
            <AlertTriangle className="h-5 w-5" />
            Удалить документ
          </AlertDialogTitle>
          <AlertDialogDescription className="space-y-3">
            <p>
              Вы собираетесь удалить документ <strong>"{doc.title}"</strong>.
            </p>
            <p className="text-destructive font-medium">
              Это действие необратимо! Все версии документа также будут удалены.
            </p>
            <div className="pt-2">
              <Label htmlFor="confirm">
                Введите название документа для подтверждения:
              </Label>
              <Input
                id="confirm"
                value={confirmText}
                onChange={(e) => setConfirmText(e.target.value)}
                placeholder={doc.title}
                className="mt-1"
              />
            </div>
          </AlertDialogDescription>
        </AlertDialogHeader>
        <AlertDialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)}>
            Отмена
          </Button>
          <Button
            variant="destructive"
            onClick={handleDelete}
            disabled={!isConfirmed || deleteDocument.isPending}
          >
            {deleteDocument.isPending ? 'Удаление...' : 'Удалить'}
          </Button>
        </AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>
  );
}
