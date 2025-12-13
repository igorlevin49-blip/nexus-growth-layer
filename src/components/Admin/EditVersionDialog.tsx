import { useState, useEffect } from 'react';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { Input } from '@/components/ui/input';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { useUpdateVersion } from '@/hooks/useLegalDocuments';
import ReactMarkdown from 'react-markdown';

interface EditVersionDialogProps {
  version: any;
  onOpenChange: (open: boolean) => void;
}

export function EditVersionDialog({ version, onOpenChange }: EditVersionDialogProps) {
  const [formData, setFormData] = useState({
    content_md: '',
    changelog: '',
  });
  const [activeTab, setActiveTab] = useState('edit');

  const updateVersion = useUpdateVersion();

  useEffect(() => {
    if (version) {
      setFormData({
        content_md: version.content_md || '',
        changelog: version.changelog || '',
      });
    }
  }, [version]);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    await updateVersion.mutateAsync({
      id: version.id,
      data: formData,
    });
    onOpenChange(false);
  };

  if (!version) return null;

  return (
    <Dialog open={!!version} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-5xl max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Редактировать версию {version.version}</DialogTitle>
        </DialogHeader>

        <form onSubmit={handleSubmit} className="space-y-4">
          <div>
            <Label htmlFor="changelog">Что изменилось</Label>
            <Input
              id="changelog"
              value={formData.changelog}
              onChange={(e) => setFormData({ ...formData, changelog: e.target.value })}
              placeholder="Описание изменений"
            />
          </div>

          <div>
            <Label>Содержание (Markdown)</Label>
            <Tabs value={activeTab} onValueChange={setActiveTab} className="mt-2">
              <TabsList className="grid w-full grid-cols-2">
                <TabsTrigger value="edit">Редактор</TabsTrigger>
                <TabsTrigger value="preview">Превью</TabsTrigger>
              </TabsList>
              <TabsContent value="edit" className="mt-2">
                <Textarea
                  value={formData.content_md}
                  onChange={(e) => setFormData({ ...formData, content_md: e.target.value })}
                  rows={20}
                  className="font-mono text-sm"
                  placeholder="# Заголовок&#10;&#10;Текст документа..."
                />
              </TabsContent>
              <TabsContent value="preview" className="mt-2">
                <div className="prose prose-sm dark:prose-invert max-w-none p-4 border rounded-lg bg-background min-h-[400px] max-h-[500px] overflow-y-auto">
                  <ReactMarkdown>{formData.content_md || '*Начните вводить текст...*'}</ReactMarkdown>
                </div>
              </TabsContent>
            </Tabs>
          </div>

          <div className="flex justify-end gap-2 pt-4 border-t">
            <Button type="button" variant="outline" onClick={() => onOpenChange(false)}>
              Отмена
            </Button>
            <Button type="submit" disabled={updateVersion.isPending}>
              {updateVersion.isPending ? 'Сохранение...' : 'Сохранить'}
            </Button>
          </div>
        </form>
      </DialogContent>
    </Dialog>
  );
}
