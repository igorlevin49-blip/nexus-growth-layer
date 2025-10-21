import { useState, useEffect } from 'react';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { Switch } from '@/components/ui/switch';
import { useUpdateDocument } from '@/hooks/useLegalDocuments';

interface EditDocumentDialogProps {
  doc: any;
  onOpenChange: (open: boolean) => void;
}

export function EditDocumentDialog({ doc, onOpenChange }: EditDocumentDialogProps) {
  const [formData, setFormData] = useState({
    title: '',
    summary: '',
    is_published: false,
    effective_at: '',
    meta_title: '',
    meta_description: '',
  });

  const updateDocument = useUpdateDocument();

  useEffect(() => {
    if (doc) {
      setFormData({
        title: doc.title || '',
        summary: doc.summary || '',
        is_published: doc.is_published || false,
        effective_at: doc.effective_at ? new Date(doc.effective_at).toISOString().split('T')[0] : '',
        meta_title: doc.meta_title || '',
        meta_description: doc.meta_description || '',
      });
    }
  }, [doc]);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    await updateDocument.mutateAsync({ id: doc.id, data: formData });
    onOpenChange(false);
  };

  if (!doc) return null;

  return (
    <Dialog open={!!doc} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-2xl max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Редактировать документ</DialogTitle>
        </DialogHeader>

        <form onSubmit={handleSubmit} className="space-y-4">
          <div>
            <Label htmlFor="title">Название</Label>
            <Input
              id="title"
              value={formData.title}
              onChange={(e) => setFormData({ ...formData, title: e.target.value })}
              required
            />
          </div>

          <div>
            <Label htmlFor="summary">Краткое описание</Label>
            <Textarea
              id="summary"
              value={formData.summary}
              onChange={(e) => setFormData({ ...formData, summary: e.target.value })}
              rows={2}
            />
          </div>

          <div>
            <Label htmlFor="effective_at">Дата вступления в силу</Label>
            <Input
              id="effective_at"
              type="date"
              value={formData.effective_at}
              onChange={(e) => setFormData({ ...formData, effective_at: e.target.value })}
            />
          </div>

          <div className="flex items-center gap-2">
            <Switch
              id="is_published"
              checked={formData.is_published}
              onCheckedChange={(checked) => setFormData({ ...formData, is_published: checked })}
            />
            <Label htmlFor="is_published">Опубликован</Label>
          </div>

          <div className="border-t pt-4">
            <h3 className="font-medium mb-3">SEO</h3>
            
            <div className="space-y-3">
              <div>
                <Label htmlFor="meta_title">Meta Title</Label>
                <Input
                  id="meta_title"
                  value={formData.meta_title}
                  onChange={(e) => setFormData({ ...formData, meta_title: e.target.value })}
                  placeholder="Оставьте пустым для использования названия"
                />
              </div>

              <div>
                <Label htmlFor="meta_description">Meta Description</Label>
                <Textarea
                  id="meta_description"
                  value={formData.meta_description}
                  onChange={(e) => setFormData({ ...formData, meta_description: e.target.value })}
                  rows={2}
                  placeholder="Оставьте пустым для использования краткого описания"
                />
              </div>
            </div>
          </div>

          <div className="flex justify-end gap-2">
            <Button type="button" variant="outline" onClick={() => onOpenChange(false)}>
              Отмена
            </Button>
            <Button type="submit" disabled={updateDocument.isPending}>
              Сохранить
            </Button>
          </div>
        </form>
      </DialogContent>
    </Dialog>
  );
}