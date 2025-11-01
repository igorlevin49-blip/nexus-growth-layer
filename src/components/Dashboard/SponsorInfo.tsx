import { Card, CardContent } from "@/components/ui/card";
import { UserCheck, Archive } from "lucide-react";
import { useQuery } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/hooks/useAuth";
import { useProfile } from "@/hooks/useProfile";

export function SponsorInfo() {
  const { user } = useAuth();
  const { data: profile } = useProfile();

  // Fetch sponsor data if sponsor_id exists
  const { data: sponsor } = useQuery({
    queryKey: ['sponsor', profile?.sponsor_id],
    queryFn: async () => {
      if (!profile?.sponsor_id) return null;
      
      const { data, error } = await supabase
        .from('profiles')
        .select('full_name, email, is_active, deleted_at, is_archived')
        .eq('id', profile.sponsor_id)
        .maybeSingle();
      
      if (error) throw error;
      return data;
    },
    enabled: !!profile?.sponsor_id,
  });

  // Don't show if no sponsor
  if (!profile?.sponsor_id) {
    return null;
  }

  // Use snapshot if sponsor is deleted/archived, otherwise use live data
  const sponsorIsDeleted = sponsor?.deleted_at || sponsor?.is_archived || !sponsor?.is_active;
  const displayName = sponsorIsDeleted 
    ? profile.referrer_snapshot?.full_name || 'Неизвестный пользователь'
    : sponsor?.full_name || profile.referrer_snapshot?.full_name || 'Неизвестный пользователь';

  return (
    <Card className="border-primary/20 bg-primary/5">
      <CardContent className="pt-6">
        <div className="flex items-start space-x-3">
          <div className="flex-shrink-0">
            {sponsorIsDeleted ? (
              <div className="w-10 h-10 rounded-full bg-muted flex items-center justify-center">
                <Archive className="h-5 w-5 text-muted-foreground" />
              </div>
            ) : (
              <div className="w-10 h-10 rounded-full bg-primary/10 flex items-center justify-center">
                <UserCheck className="h-5 w-5 text-primary" />
              </div>
            )}
          </div>
          <div className="flex-1 min-w-0">
            <p className="text-sm text-muted-foreground">
              Вы зарегистрированы по приглашению
            </p>
            <p className="font-medium text-base mt-1">
              {displayName}
            </p>
            {sponsorIsDeleted && (
              <p className="text-xs text-muted-foreground mt-1">
                (аккаунт архивирован)
              </p>
            )}
          </div>
        </div>
      </CardContent>
    </Card>
  );
}
