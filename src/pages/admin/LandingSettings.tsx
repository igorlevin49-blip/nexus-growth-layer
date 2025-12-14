import { useState } from "react";
import { Card, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { Switch } from "@/components/ui/switch";
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar";
import { Loader2, Plus, Pencil, Trash2, Upload, GripVertical } from "lucide-react";
import {
  useAdminTeamMembers,
  useCreateTeamMember,
  useUpdateTeamMember,
  useDeleteTeamMember,
  useUploadTeamPhoto,
  TeamMember,
} from "@/hooks/useTeamMembers";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
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

const LandingSettings = () => {
  const { data: teamMembers, isLoading } = useAdminTeamMembers();
  const createMember = useCreateTeamMember();
  const updateMember = useUpdateTeamMember();
  const deleteMember = useDeleteTeamMember();
  const uploadPhoto = useUploadTeamPhoto();

  const [isCreateDialogOpen, setIsCreateDialogOpen] = useState(false);
  const [isEditDialogOpen, setIsEditDialogOpen] = useState(false);
  const [deleteConfirmId, setDeleteConfirmId] = useState<string | null>(null);
  const [editingMember, setEditingMember] = useState<TeamMember | null>(null);
  const [photoFile, setPhotoFile] = useState<File | null>(null);
  const [photoPreview, setPhotoPreview] = useState<string | null>(null);

  const [formData, setFormData] = useState({
    name: "",
    position: "",
    description: "",
    display_order: 0,
    is_active: true,
  });

  const handlePhotoChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (file) {
      setPhotoFile(file);
      const reader = new FileReader();
      reader.onloadend = () => {
        setPhotoPreview(reader.result as string);
      };
      reader.readAsDataURL(file);
    }
  };

  const resetForm = () => {
    setFormData({
      name: "",
      position: "",
      description: "",
      display_order: 0,
      is_active: true,
    });
    setPhotoFile(null);
    setPhotoPreview(null);
  };

  const handleCreate = async () => {
    let photo_url = null;

    if (photoFile) {
      const tempId = `temp-${Date.now()}`;
      photo_url = await uploadPhoto.mutateAsync({ file: photoFile, memberId: tempId });
    }

    await createMember.mutateAsync({
      ...formData,
      photo_url,
    });

    setIsCreateDialogOpen(false);
    resetForm();
  };

  const handleEdit = (member: TeamMember) => {
    setEditingMember(member);
    setFormData({
      name: member.name,
      position: member.position,
      description: member.description,
      display_order: member.display_order,
      is_active: member.is_active,
    });
    setPhotoPreview(member.photo_url);
    setIsEditDialogOpen(true);
  };

  const handleUpdate = async () => {
    if (!editingMember) return;

    let photo_url = editingMember.photo_url;

    if (photoFile) {
      photo_url = await uploadPhoto.mutateAsync({
        file: photoFile,
        memberId: editingMember.id,
      });
    }

    await updateMember.mutateAsync({
      id: editingMember.id,
      ...formData,
      photo_url,
    });

    setIsEditDialogOpen(false);
    setEditingMember(null);
    resetForm();
  };

  const handleDelete = async (id: string) => {
    await deleteMember.mutateAsync(id);
    setDeleteConfirmId(null);
  };

  if (isLoading) {
    return null;
  }

  return (
    <div className="space-y-6">
      <div className="flex justify-between items-center">
        <div>
          <h1 className="text-3xl font-bold">Управление лендингом</h1>
          <p className="text-muted-foreground">Редактирование членов команды на главной странице</p>
        </div>
        <Button onClick={() => setIsCreateDialogOpen(true)}>
          <Plus className="h-4 w-4 mr-2" />
          Добавить члена команды
        </Button>
      </div>

      <div className="grid gap-4">
        {teamMembers?.map((member) => (
          <Card key={member.id}>
            <CardContent className="p-6">
              <div className="flex items-start gap-4">
                <GripVertical className="h-5 w-5 text-muted-foreground mt-2 cursor-move" />
                <Avatar className="h-16 w-16">
                  <AvatarImage src={member.photo_url || undefined} />
                  <AvatarFallback>{member.name.charAt(0)}</AvatarFallback>
                </Avatar>
                <div className="flex-1">
                  <div className="flex items-center gap-2 mb-1">
                    <h3 className="text-lg font-semibold">{member.name}</h3>
                    {!member.is_active && (
                      <span className="text-xs bg-muted px-2 py-1 rounded">Скрыт</span>
                    )}
                  </div>
                  <p className="text-sm text-primary mb-2">{member.position}</p>
                  <p className="text-sm text-muted-foreground">{member.description}</p>
                  <p className="text-xs text-muted-foreground mt-2">Порядок: {member.display_order}</p>
                </div>
                <div className="flex gap-2">
                  <Button variant="outline" size="icon" onClick={() => handleEdit(member)}>
                    <Pencil className="h-4 w-4" />
                  </Button>
                  <Button
                    variant="outline"
                    size="icon"
                    onClick={() => setDeleteConfirmId(member.id)}
                  >
                    <Trash2 className="h-4 w-4" />
                  </Button>
                </div>
              </div>
            </CardContent>
          </Card>
        ))}
      </div>

      <Dialog open={isCreateDialogOpen} onOpenChange={setIsCreateDialogOpen}>
        <DialogContent className="max-w-2xl">
          <DialogHeader>
            <DialogTitle>Добавить члена команды</DialogTitle>
            <DialogDescription>Заполните информацию о новом члене команды</DialogDescription>
          </DialogHeader>
          <div className="space-y-4">
            <div>
              <Label>Фотография</Label>
              <div className="flex items-center gap-4 mt-2">
                <Avatar className="h-20 w-20">
                  <AvatarImage src={photoPreview || undefined} />
                  <AvatarFallback>
                    <Upload className="h-8 w-8" />
                  </AvatarFallback>
                </Avatar>
                <Input type="file" accept="image/*" onChange={handlePhotoChange} />
              </div>
            </div>
            <div>
              <Label htmlFor="name">Имя</Label>
              <Input
                id="name"
                value={formData.name}
                onChange={(e) => setFormData({ ...formData, name: e.target.value })}
              />
            </div>
            <div>
              <Label htmlFor="position">Должность</Label>
              <Input
                id="position"
                value={formData.position}
                onChange={(e) => setFormData({ ...formData, position: e.target.value })}
              />
            </div>
            <div>
              <Label htmlFor="description">Описание</Label>
              <Textarea
                id="description"
                value={formData.description}
                onChange={(e) => setFormData({ ...formData, description: e.target.value })}
                rows={3}
              />
            </div>
            <div>
              <Label htmlFor="order">Порядок отображения</Label>
              <Input
                id="order"
                type="number"
                value={formData.display_order}
                onChange={(e) =>
                  setFormData({ ...formData, display_order: parseInt(e.target.value) })
                }
              />
            </div>
            <div className="flex items-center space-x-2">
              <Switch
                id="active"
                checked={formData.is_active}
                onCheckedChange={(checked) => setFormData({ ...formData, is_active: checked })}
              />
              <Label htmlFor="active">Активен (отображать на сайте)</Label>
            </div>
          </div>
          <div className="flex justify-end gap-2 mt-6">
            <Button variant="outline" onClick={() => setIsCreateDialogOpen(false)}>
              Отмена
            </Button>
            <Button onClick={handleCreate} disabled={createMember.isPending}>
              {createMember.isPending && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
              Добавить
            </Button>
          </div>
        </DialogContent>
      </Dialog>

      <Dialog open={isEditDialogOpen} onOpenChange={setIsEditDialogOpen}>
        <DialogContent className="max-w-2xl">
          <DialogHeader>
            <DialogTitle>Редактировать члена команды</DialogTitle>
            <DialogDescription>Измените информацию о члене команды</DialogDescription>
          </DialogHeader>
          <div className="space-y-4">
            <div>
              <Label>Фотография</Label>
              <div className="flex items-center gap-4 mt-2">
                <Avatar className="h-20 w-20">
                  <AvatarImage src={photoPreview || undefined} />
                  <AvatarFallback>
                    <Upload className="h-8 w-8" />
                  </AvatarFallback>
                </Avatar>
                <Input type="file" accept="image/*" onChange={handlePhotoChange} />
              </div>
            </div>
            <div>
              <Label htmlFor="edit-name">Имя</Label>
              <Input
                id="edit-name"
                value={formData.name}
                onChange={(e) => setFormData({ ...formData, name: e.target.value })}
              />
            </div>
            <div>
              <Label htmlFor="edit-position">Должность</Label>
              <Input
                id="edit-position"
                value={formData.position}
                onChange={(e) => setFormData({ ...formData, position: e.target.value })}
              />
            </div>
            <div>
              <Label htmlFor="edit-description">Описание</Label>
              <Textarea
                id="edit-description"
                value={formData.description}
                onChange={(e) => setFormData({ ...formData, description: e.target.value })}
                rows={3}
              />
            </div>
            <div>
              <Label htmlFor="edit-order">Порядок отображения</Label>
              <Input
                id="edit-order"
                type="number"
                value={formData.display_order}
                onChange={(e) =>
                  setFormData({ ...formData, display_order: parseInt(e.target.value) })
                }
              />
            </div>
            <div className="flex items-center space-x-2">
              <Switch
                id="edit-active"
                checked={formData.is_active}
                onCheckedChange={(checked) => setFormData({ ...formData, is_active: checked })}
              />
              <Label htmlFor="edit-active">Активен (отображать на сайте)</Label>
            </div>
          </div>
          <div className="flex justify-end gap-2 mt-6">
            <Button variant="outline" onClick={() => setIsEditDialogOpen(false)}>
              Отмена
            </Button>
            <Button onClick={handleUpdate} disabled={updateMember.isPending}>
              {updateMember.isPending && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
              Сохранить
            </Button>
          </div>
        </DialogContent>
      </Dialog>

      <AlertDialog open={!!deleteConfirmId} onOpenChange={() => setDeleteConfirmId(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Удалить члена команды?</AlertDialogTitle>
            <AlertDialogDescription>
              Это действие нельзя отменить. Член команды будет удалён из базы данных.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Отмена</AlertDialogCancel>
            <AlertDialogAction
              onClick={() => deleteConfirmId && handleDelete(deleteConfirmId)}
              className="bg-destructive text-destructive-foreground hover:bg-destructive/90"
            >
              Удалить
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  );
};

export default LandingSettings;
