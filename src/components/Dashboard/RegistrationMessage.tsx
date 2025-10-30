import { useEffect, useState } from "react";
import { useAuth } from "@/hooks/useAuth";
import { supabase } from "@/integrations/supabase/client";
import { Card, CardContent } from "@/components/ui/card";
import { UserPlus, UserCheck } from "lucide-react";

export function RegistrationMessage() {
  const { user } = useAuth();
  const [message, setMessage] = useState<{
    type: 'inviter' | 'invited' | 'none';
    text: string;
  } | null>(null);

  useEffect(() => {
    const fetchRegistrationInfo = async () => {
      if (!user) return;

      // Get user's profile to check sponsor
      const { data: profile } = await supabase
        .from('profiles')
        .select('sponsor_id')
        .eq('id', user.id)
        .single();

      if (!profile) return;

      // Check if user was invited
      if (profile.sponsor_id) {
        setMessage({
          type: 'invited',
          text: 'Вы зарегистрировались по ссылке вашего пригласителя'
        });
      } else {
        setMessage({
          type: 'none',
          text: 'Вы зарегистрировались без пригласителя'
        });
      }

      // Check for recent registrations through this user's link
      const { data: recentInvites } = await supabase
        .from('activity_log')
        .select('created_at, payload')
        .eq('type', 'registration')
        .contains('payload', { sponsor_id: user.id })
        .order('created_at', { ascending: false })
        .limit(1);

      if (recentInvites && recentInvites.length > 0) {
        const lastInvite = recentInvites[0];
        const hoursSinceInvite = Math.floor(
          (Date.now() - new Date(lastInvite.created_at).getTime()) / (1000 * 60 * 60)
        );

        if (hoursSinceInvite < 24) {
          setMessage({
            type: 'inviter',
            text: 'Новый участник зарегистрировался по вашей ссылке'
          });
        }
      }
    };

    fetchRegistrationInfo();
  }, [user]);

  if (!message) return null;

  return (
    <Card className={`border-l-4 ${
      message.type === 'inviter' 
        ? 'border-l-success bg-success/5' 
        : message.type === 'invited'
        ? 'border-l-primary bg-primary/5'
        : 'border-l-muted bg-muted/5'
    }`}>
      <CardContent className="py-3 px-4">
        <div className="flex items-center space-x-3">
          {message.type === 'inviter' ? (
            <UserPlus className="h-5 w-5 text-success" />
          ) : (
            <UserCheck className="h-5 w-5 text-primary" />
          )}
          <p className="text-sm font-medium">{message.text}</p>
        </div>
      </CardContent>
    </Card>
  );
}
