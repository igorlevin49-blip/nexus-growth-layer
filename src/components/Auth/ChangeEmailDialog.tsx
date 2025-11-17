import { useState } from "react";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "sonner";

interface ChangeEmailDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  currentEmail: string;
}

export function ChangeEmailDialog({ open, onOpenChange, currentEmail }: ChangeEmailDialogProps) {
  const [newEmail, setNewEmail] = useState("");
  const [isLoading, setIsLoading] = useState(false);

  const handleChangeEmail = async () => {
    if (!newEmail.trim()) {
      toast.error("Введите новый email");
      return;
    }

    if (newEmail.toLowerCase() === currentEmail.toLowerCase()) {
      toast.error("Новый email совпадает с текущим");
      return;
    }

    setIsLoading(true);
    try {
      const { data, error } = await supabase.functions.invoke('change-email', {
        body: { newEmail: newEmail.trim() }
      });

      if (error) throw error;
      if (!data.success) throw new Error(data.error);

      toast.success('Email успешно изменён! Войдите заново с новым email.');
      
      // Sign out and redirect to login
      await supabase.auth.signOut();
      window.location.href = '/login';
    } catch (error: any) {
      console.error('Change email error:', error);
      toast.error(error.message || 'Ошибка при смене email');
    } finally {
      setIsLoading(false);
    }
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Изменить Email</DialogTitle>
          <DialogDescription>
            После изменения вы будете автоматически выведены из системы.
            Войдите заново используя новый email.
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-4">
          <div className="space-y-2">
            <Label htmlFor="current-email">Текущий email</Label>
            <Input
              id="current-email"
              type="email"
              value={currentEmail}
              disabled
              className="bg-muted"
            />
          </div>

          <div className="space-y-2">
            <Label htmlFor="new-email">Новый email</Label>
            <Input
              id="new-email"
              type="email"
              value={newEmail}
              onChange={(e) => setNewEmail(e.target.value)}
              placeholder="new@example.com"
              disabled={isLoading}
            />
          </div>
        </div>

        <DialogFooter>
          <Button 
            variant="outline" 
            onClick={() => onOpenChange(false)}
            disabled={isLoading}
          >
            Отмена
          </Button>
          <Button 
            onClick={handleChangeEmail} 
            disabled={isLoading || !newEmail.trim()}
          >
            {isLoading ? "Изменяем..." : "Изменить email"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}