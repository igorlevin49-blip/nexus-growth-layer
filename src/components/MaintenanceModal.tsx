import { useState, useEffect } from "react";
import { useMLMSettings } from "@/hooks/useMLMSettings";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
  DialogFooter,
} from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { PartyPopper } from "lucide-react";

const SESSION_KEY = "maintenance_modal_dismissed";

interface MaintenanceConfig {
  enabled: boolean;
  title: string;
  message: string;
}

export function MaintenanceModal() {
  const { data: settings, isLoading } = useMLMSettings();
  const [dismissed, setDismissed] = useState(false);

  useEffect(() => {
    // Check if already dismissed in this session
    const wasDismissed = sessionStorage.getItem(SESSION_KEY);
    if (wasDismissed) {
      setDismissed(true);
    }
  }, []);

  if (isLoading || dismissed) {
    return null;
  }

  const config: MaintenanceConfig = settings?.maintenance_mode || {
    enabled: false,
    title: "С Новым 2025 Годом! 🎄",
    message: "Желаем вам успехов, процветания и новых достижений в наступающем году!",
  };

  if (!config.enabled) {
    return null;
  }

  const handleDismiss = () => {
    sessionStorage.setItem(SESSION_KEY, "true");
    setDismissed(true);
  };

  return (
    <Dialog open={true} onOpenChange={(open) => !open && handleDismiss()}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader className="text-center sm:text-center">
          <div className="mx-auto mb-4 flex h-16 w-16 items-center justify-center rounded-full bg-emerald-100">
            <PartyPopper className="h-8 w-8 text-emerald-600" />
          </div>
          <DialogTitle className="text-xl">{config.title}</DialogTitle>
          <DialogDescription className="text-base pt-2">
            {config.message}
          </DialogDescription>
        </DialogHeader>
        <DialogFooter className="sm:justify-center">
          <Button onClick={handleDismiss} className="w-full sm:w-auto">
            Понятно
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
