import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { format } from 'date-fns';
import { ru } from 'date-fns/locale';
import { Edit } from 'lucide-react';
import ReactMarkdown from 'react-markdown';

interface ViewVersionDialogProps {
  version: any;
  doc: any;
  onOpenChange: (open: boolean) => void;
  onEdit: () => void;
}

export function ViewVersionDialog({ version, doc, onOpenChange, onEdit }: ViewVersionDialogProps) {
  if (!version) return null;

  return (
    <Dialog open={!!version} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-4xl max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-3">
              <DialogTitle>Версия {version.version}</DialogTitle>
              {doc?.current_version_id === version.id && (
                <Badge variant="default">Текущая</Badge>
              )}
            </div>
            <Button variant="outline" size="sm" onClick={onEdit}>
              <Edit className="mr-2 h-4 w-4" />
              Редактировать
            </Button>
          </div>
        </DialogHeader>

        <div className="space-y-4">
          <div className="text-sm text-muted-foreground">
            Создана: {format(new Date(version.created_at), 'dd MMMM yyyy, HH:mm', { locale: ru })}
          </div>

          {version.changelog && (
            <div className="p-3 bg-muted rounded-lg">
              <p className="text-sm font-medium mb-1">Изменения:</p>
              <p className="text-sm text-muted-foreground">{version.changelog}</p>
            </div>
          )}

          <div className="border-t pt-4">
            <p className="text-sm font-medium mb-3">Содержание:</p>
            <div className="prose prose-sm dark:prose-invert max-w-none p-4 border rounded-lg bg-background">
              <ReactMarkdown>{version.content_md || '*Содержимое отсутствует*'}</ReactMarkdown>
            </div>
          </div>
        </div>
      </DialogContent>
    </Dialog>
  );
}
