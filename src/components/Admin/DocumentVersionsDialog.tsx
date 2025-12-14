import { useState } from 'react';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { Input } from '@/components/ui/input';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import {
  AlertDialog,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from '@/components/ui/alert-dialog';
import { useDocumentVersions, useCreateVersion, useUpdateDocument, useDeleteVersion } from '@/hooks/useLegalDocuments';
import { format } from 'date-fns';
import { ru } from 'date-fns/locale';
import { Plus, Check, Eye, Edit, Trash2 } from 'lucide-react';
import { ViewVersionDialog } from './ViewVersionDialog';
import { EditVersionDialog } from './EditVersionDialog';

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
  const [viewVersion, setViewVersion] = useState<any>(null);
  const [editVersion, setEditVersion] = useState<any>(null);
  const [deleteVersion, setDeleteVersion] = useState<any>(null);

  const { data: versions, isLoading } = useDocumentVersions(doc?.id);
  const createVersion = useCreateVersion();
  const updateDocument = useUpdateDocument();
  const deleteVersionMutation = useDeleteVersion();

  const handleCreateVersion = async (e: React.FormEvent) => {
    e.preventDefault();
    
    const maxVersion = versions?.length ? Math.max(...versions.map(v => v.version)) : 0;
    
    await createVersion.mutateAsync({
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

  const handleDeleteVersion = async () => {
    if (!deleteVersion) return;
    await deleteVersionMutation.mutateAsync({
      id: deleteVersion.id,
      documentId: doc.id,
    });
    setDeleteVersion(null);
  };

  if (!doc) return null;

  return (
    <>
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

            {isLoading ? null : !versions || versions.length === 0 ? (
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
                        <div className="flex gap-1">
                          <Button
                            size="sm"
                            variant="ghost"
                            onClick={() => setViewVersion(version)}
                            title="Просмотр"
                          >
                            <Eye className="h-4 w-4" />
                          </Button>
                          <Button
                            size="sm"
                            variant="ghost"
                            onClick={() => setEditVersion(version)}
                            title="Редактировать"
                          >
                            <Edit className="h-4 w-4" />
                          </Button>
                          {doc.current_version_id !== version.id && (
                            <>
                              <Button
                                size="sm"
                                variant="ghost"
                                onClick={() => handleSetCurrent(version.id)}
                                title="Сделать текущей"
                              >
                                <Check className="h-4 w-4" />
                              </Button>
                              <Button
                                size="sm"
                                variant="ghost"
                                onClick={() => setDeleteVersion(version)}
                                className="text-destructive hover:text-destructive"
                                title="Удалить"
                              >
                                <Trash2 className="h-4 w-4" />
                              </Button>
                            </>
                          )}
                        </div>
                      </div>
                    </CardHeader>
                  </Card>
                ))}
              </div>
            )}
          </div>
        </DialogContent>
      </Dialog>

      <ViewVersionDialog
        version={viewVersion}
        doc={doc}
        onOpenChange={(open) => !open && setViewVersion(null)}
        onEdit={() => {
          setEditVersion(viewVersion);
          setViewVersion(null);
        }}
      />

      <EditVersionDialog
        version={editVersion}
        onOpenChange={(open) => !open && setEditVersion(null)}
      />

      <AlertDialog open={!!deleteVersion} onOpenChange={(open) => !open && setDeleteVersion(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Удалить версию {deleteVersion?.version}?</AlertDialogTitle>
            <AlertDialogDescription>
              Это действие необратимо. Версия будет удалена навсегда.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <Button variant="outline" onClick={() => setDeleteVersion(null)}>
              Отмена
            </Button>
            <Button
              variant="destructive"
              onClick={handleDeleteVersion}
              disabled={deleteVersionMutation.isPending}
            >
              {deleteVersionMutation.isPending ? 'Удаление...' : 'Удалить'}
            </Button>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </>
  );
}
