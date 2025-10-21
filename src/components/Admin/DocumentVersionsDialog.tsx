import { useState } from 'react';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { Input } from '@/components/ui/input';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { useDocumentVersions, useCreateVersion, useUpdateDocument } from '@/hooks/useLegalDocuments';
import { format } from 'date-fns';
import { ru } from 'date-fns/locale';
import { Plus, Check } from 'lucide-react';

interface DocumentVersionsDialogProps {
  doc: any;
  onOpenChange: (open: boolean) => void;
}

export function DocumentVersionsDialog({ doc, onOpenChange }: DocumentVersionsDialogProps) {
  const [showCreate, setShowCreate] = useState(false);
  const [formData, setFormData] = useState({
    content_md: '',
    changelog: '',
  });

  const { data: versions, isLoading } = useDocumentVersions(doc?.id);
  const createVersion = useCreateVersion();
  const updateDocument = useUpdateDocument();

  const handleCreateVersion = async (e: React.FormEvent) => {
    e.preventDefault();
    
    const maxVersion = versions?.length ? Math.max(...versions.map(v => v.version)) : 0;
    
    const newVersion = await createVersion.mutateAsync({
      document_id: doc.id,
      version: maxVersion + 1,
      content_md: formData.content_md,
      changelog: formData.changelog,
    });

    setFormData({ content_md: '', changelog: '' });
    setShowCreate(false);
  };

  const handleSetCurrent = async (versionId: string) => {
    await updateDocument.mutateAsync({
      id: doc.id,
      data: { current_version_id: versionId },
    });
  };

  if (!doc) return null;

  return (
    <Dialog open={!!doc} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-4xl max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Версии документа: {doc.title}</DialogTitle>
        </DialogHeader>

        <div className="space-y-4">
          {!showCreate && (
            <Button onClick={() => setShowCreate(true)} className="w-full">
              <Plus className="mr-2 h-4 w-4" />
              Создать новую версию
            </Button>
          )}

          {showCreate && (
            <Card>
              <CardHeader>
                <CardTitle className="text-lg">Новая версия</CardTitle>
              </CardHeader>
              <CardContent>
                <form onSubmit={handleCreateVersion} className="space-y-4">
                  <div>
                    <Label htmlFor="content_md">Содержание (Markdown)</Label>
                    <Textarea
                      id="content_md"
                      value={formData.content_md}
                      onChange={(e) => setFormData({ ...formData, content_md: e.target.value })}
                      rows={10}
                      className="font-mono text-sm"
                      required
                    />
                  </div>

                  <div>
                    <Label htmlFor="changelog">Что изменилось</Label>
                    <Input
                      id="changelog"
                      value={formData.changelog}
                      onChange={(e) => setFormData({ ...formData, changelog: e.target.value })}
                      placeholder="Описание изменений"
                    />
                  </div>

                  <div className="flex gap-2">
                    <Button type="submit" disabled={createVersion.isPending}>
                      Создать версию
                    </Button>
                    <Button type="button" variant="outline" onClick={() => setShowCreate(false)}>
                      Отмена
                    </Button>
                  </div>
                </form>
              </CardContent>
            </Card>
          )}

          {isLoading ? (
            <div className="flex justify-center py-8">
              <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-primary"></div>
            </div>
          ) : !versions || versions.length === 0 ? (
            <Card>
              <CardContent className="pt-6">
                <p className="text-center text-muted-foreground">
                  Версий пока нет
                </p>
              </CardContent>
            </Card>
          ) : (
            <div className="space-y-3">
              {versions.map((version) => (
                <Card key={version.id}>
                  <CardHeader>
                    <div className="flex items-start justify-between">
                      <div>
                        <div className="flex items-center gap-2 mb-1">
                          <CardTitle className="text-base">
                            Версия {version.version}
                          </CardTitle>
                          {doc.current_version_id === version.id && (
                            <Badge variant="default">Текущая</Badge>
                          )}
                        </div>
                        <p className="text-sm text-muted-foreground">
                          {format(new Date(version.created_at), 'dd MMMM yyyy, HH:mm', { locale: ru })}
                        </p>
                        {version.changelog && (
                          <p className="text-sm mt-2">{version.changelog}</p>
                        )}
                      </div>
                      {doc.current_version_id !== version.id && (
                        <Button
                          size="sm"
                          variant="outline"
                          onClick={() => handleSetCurrent(version.id)}
                        >
                          <Check className="mr-2 h-4 w-4" />
                          Сделать текущей
                        </Button>
                      )}
                    </div>
                  </CardHeader>
                </Card>
              ))}
            </div>
          )}
        </div>
      </DialogContent>
    </Dialog>
  );
}