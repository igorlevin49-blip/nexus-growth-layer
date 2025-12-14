import { useState } from 'react';
import { useAdminLegalDocuments } from '@/hooks/useLegalDocuments';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Plus, FileText, Eye, Edit, History, Trash2 } from 'lucide-react';
import { format } from 'date-fns';
import { ru } from 'date-fns/locale';
import { Badge } from '@/components/ui/badge';
import { CreateDocumentDialog } from '@/components/Admin/CreateDocumentDialog';
import { EditDocumentDialog } from '@/components/Admin/EditDocumentDialog';
import { DocumentVersionsDialog } from '@/components/Admin/DocumentVersionsDialog';
import { DeleteDocumentDialog } from '@/components/Admin/DeleteDocumentDialog';
import { useAuth } from '@/hooks/useAuth';

export default function Documents() {
  const { userRole } = useAuth();
  const isSuperAdmin = userRole === 'superadmin';
  const { data: documents, isLoading } = useAdminLegalDocuments();
  const [createOpen, setCreateOpen] = useState(false);
  const [editDoc, setEditDoc] = useState<any>(null);
  const [versionsDoc, setVersionsDoc] = useState<any>(null);
  const [deleteDoc, setDeleteDoc] = useState<any>(null);

  if (isLoading) {
    return null;
  }

  return (
    <div className="space-y-6">
      <div className="flex justify-between items-center">
        <div>
          <h1 className="text-3xl font-bold">Юридические документы</h1>
          <p className="text-muted-foreground mt-1">
            Управление договорами, политиками и документами
          </p>
        </div>
        {isSuperAdmin && (
          <Button onClick={() => setCreateOpen(true)}>
            <Plus className="mr-2 h-4 w-4" />
            Создать документ
          </Button>
        )}
      </div>

      {!documents || documents.length === 0 ? (
        <Card>
          <CardContent className="pt-6">
            <p className="text-center text-muted-foreground">
              Документы пока не созданы
            </p>
          </CardContent>
        </Card>
      ) : (
        <div className="grid gap-4">
          {documents.map((doc) => (
            <Card key={doc.id}>
              <CardHeader>
                <div className="flex items-start justify-between">
                  <div className="flex items-start gap-4">
                    <FileText className="h-6 w-6 text-primary mt-1" />
                    <div>
                      <div className="flex items-center gap-2 mb-2">
                        <CardTitle>{doc.title}</CardTitle>
                        <Badge variant={doc.is_published ? 'default' : 'secondary'}>
                          {doc.is_published ? 'Опубликован' : 'Черновик'}
                        </Badge>
                      </div>
                      <p className="text-sm text-muted-foreground mb-2">
                        Slug: <code className="bg-muted px-1 rounded">{doc.slug}</code>
                      </p>
                      {doc.summary && (
                        <p className="text-sm text-muted-foreground mb-2">
                          {doc.summary}
                        </p>
                      )}
                      {doc.effective_at && (
                        <p className="text-sm text-muted-foreground">
                          Вступает в силу: {format(new Date(doc.effective_at), 'dd MMMM yyyy', { locale: ru })}
                        </p>
                      )}
                    </div>
                  </div>
                  <div className="flex gap-2">
                    {doc.is_published && (
                      <Button
                        variant="ghost"
                        size="sm"
                        onClick={() => window.open(`/docs/${doc.slug}`, '_blank')}
                        title="Просмотр"
                      >
                        <Eye className="h-4 w-4" />
                      </Button>
                    )}
                    {isSuperAdmin && (
                      <>
                        <Button
                          variant="ghost"
                          size="sm"
                          onClick={() => setEditDoc(doc)}
                          title="Редактировать"
                        >
                          <Edit className="h-4 w-4" />
                        </Button>
                        <Button
                          variant="ghost"
                          size="sm"
                          onClick={() => setDeleteDoc(doc)}
                          className="text-destructive hover:text-destructive"
                          title="Удалить"
                        >
                          <Trash2 className="h-4 w-4" />
                        </Button>
                      </>
                    )}
                    <Button
                      variant="ghost"
                      size="sm"
                      onClick={() => setVersionsDoc(doc)}
                      title="История версий"
                    >
                      <History className="h-4 w-4" />
                    </Button>
                  </div>
                </div>
              </CardHeader>
            </Card>
          ))}
        </div>
      )}

      <CreateDocumentDialog open={createOpen} onOpenChange={setCreateOpen} />
      <EditDocumentDialog
        doc={editDoc}
        onOpenChange={(open) => !open && setEditDoc(null)}
        onDelete={(doc) => {
          setEditDoc(null);
          setDeleteDoc(doc);
        }}
      />
      <DocumentVersionsDialog doc={versionsDoc} onOpenChange={(open) => !open && setVersionsDoc(null)} />
      <DeleteDocumentDialog doc={deleteDoc} onOpenChange={(open) => !open && setDeleteDoc(null)} />
    </div>
  );
}
