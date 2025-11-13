import { useState } from "react";
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription } from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { useBindSponsor } from "@/hooks/useBindSponsor";
import { Loader2, UserPlus } from "lucide-react";

interface BindSponsorDialogProps {
  userId: string;
  userName: string;
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onSuccess?: () => void;
}

export function BindSponsorDialog({ userId, userName, open, onOpenChange, onSuccess }: BindSponsorDialogProps) {
  const [referralCode, setReferralCode] = useState("");
  const bindSponsor = useBindSponsor();

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!referralCode.trim()) return;

    await bindSponsor.mutateAsync({ userId, referralCode });
    setReferralCode("");
    onOpenChange(false);
    onSuccess?.();
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <UserPlus className="h-5 w-5" />
            Привязать спонсора
          </DialogTitle>
          <DialogDescription>
            Привязка спонсора для пользователя: <strong>{userName}</strong>
          </DialogDescription>
        </DialogHeader>

        <form onSubmit={handleSubmit} className="space-y-4">
          <div className="space-y-2">
            <Label htmlFor="referralCode">Реферальный код спонсора</Label>
            <Input
              id="referralCode"
              value={referralCode}
              onChange={(e) => setReferralCode(e.target.value)}
              placeholder="Введите реферальный код"
              disabled={bindSponsor.isPending}
            />
            <p className="text-sm text-muted-foreground">
              Введите реферальный код пользователя, который должен стать спонсором
            </p>
          </div>

          <div className="flex gap-2 justify-end">
            <Button
              type="button"
              variant="outline"
              onClick={() => onOpenChange(false)}
              disabled={bindSponsor.isPending}
            >
              Отмена
            </Button>
            <Button type="submit" disabled={!referralCode.trim() || bindSponsor.isPending}>
              {bindSponsor.isPending && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
              Привязать
            </Button>
          </div>
        </form>
      </DialogContent>
    </Dialog>
  );
}
