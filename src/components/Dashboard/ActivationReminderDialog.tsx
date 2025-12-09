import { useNavigate } from 'react-router-dom';
import { format } from 'date-fns';
import { ru } from 'date-fns/locale';
import { Clock, ShoppingBag, X } from 'lucide-react';
import { useActivationReminder } from '@/hooks/useActivationReminder';
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
} from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';

export function ActivationReminderDialog() {
  const navigate = useNavigate();
  const { showReminder, daysLeft, activationDueFrom, closeReminder } = useActivationReminder();

  if (!showReminder || daysLeft === null || !activationDueFrom) {
    return null;
  }

  const isUrgent = daysLeft <= 2;

  const getDaysText = (days: number) => {
    if (days === 1) return '1 день';
    if (days >= 2 && days <= 4) return `${days} дня`;
    return `${days} дней`;
  };

  const handleGoToShop = () => {
    closeReminder();
    navigate('/shop?filter=activation');
  };

  return (
    <Dialog open={showReminder} onOpenChange={(open) => !open && closeReminder()}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <div className="flex items-center gap-3">
            <div className={`p-2 rounded-full ${isUrgent ? 'bg-destructive/10' : 'bg-primary/10'}`}>
              <Clock className={`h-6 w-6 ${isUrgent ? 'text-destructive' : 'text-primary'}`} />
            </div>
            <DialogTitle className="text-xl">
              Напоминание о ежемесячной активации
            </DialogTitle>
          </div>
        </DialogHeader>
        
        <div className="space-y-4 py-4">
          <div className={`p-4 rounded-lg ${isUrgent ? 'bg-destructive/10 border border-destructive/20' : 'bg-muted'}`}>
            <p className={`text-lg font-medium ${isUrgent ? 'text-destructive' : 'text-foreground'}`}>
              Через {getDaysText(daysLeft)} у вас ежемесячная активация!
            </p>
          </div>
          
          <div className="space-y-2 text-muted-foreground">
            <p>
              <span className="font-medium text-foreground">Дата активации:</span>{' '}
              {format(activationDueFrom, 'd MMMM yyyy', { locale: ru })}
            </p>
            <p>
              Не забудьте приобрести активационные товары на сумму от $40, 
              чтобы сохранить активный статус и получать MLM-комиссии.
            </p>
          </div>
        </div>

        <div className="flex gap-3 justify-end">
          <Button variant="outline" onClick={closeReminder}>
            Напомнить позже
          </Button>
          <Button onClick={handleGoToShop} className="gap-2">
            <ShoppingBag className="h-4 w-4" />
            Перейти в магазин
          </Button>
        </div>
      </DialogContent>
    </Dialog>
  );
}
