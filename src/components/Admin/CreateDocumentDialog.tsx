import { useState } from 'react';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { useCreateDocument } from '@/hooks/useLegalDocuments';

interface CreateDocumentDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
}

export function CreateDocumentDialog({ open, onOpenChange }: CreateDocumentDialogProps) {
  const [formData, setFormData] = useState({
    slug: '',
    title: '',
    summary: '',
    language: 'ru',
    effective_at: new Date().toISOString().split('T')[0],
  });

  const createDocument = useCreateDocument();

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    await createDocument.mutateAsync(formData);
    onOpenChange(false);
    setFormData({
      slug: '',
      title: '',
      summary: '',
      language: 'ru',
      effective_at: new Date().toISOString().split('T')[0],
    });
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-2xl">
        <DialogHeader>
          <DialogTitle>Создать документ</DialogTitle>
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
            <Label htmlFor="slug">Slug (URL)</Label>
            <Input
              id="slug"
              value={formData.slug}
              onChange={(e) => setFormData({ ...formData, slug: e.target.value.toLowerCase().replace(/[^a-z0-9-]/g, '-') })}
              placeholder="privacy-policy"
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

          <div className="flex justify-end gap-2">
            <Button type="button" variant="outline" onClick={() => onOpenChange(false)}>
              Отмена
            </Button>
            <Button type="submit" disabled={createDocument.isPending}>
              Создать
            </Button>
          </div>
        </form>
      </DialogContent>
    </Dialog>
  );
}