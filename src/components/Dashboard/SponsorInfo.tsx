import { Card, CardContent } from "@/components/ui/card";
import { UserCheck, Archive, Clock } from "lucide-react";
import { useQuery } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/hooks/useAuth";
import { useProfile } from "@/hooks/useProfile";
import { Skeleton } from "@/components/ui/skeleton";

interface SponsorInfoResponse {
  sponsor: {
    id: string;
    full_name: string | null;
    is_active: boolean;
    is_archived: boolean | null;
  } | null;
  status: 'active' | 'inactive' | 'archived' | 'missing' | 'no_sponsor';
  error?: string;
}

export function SponsorInfo() {
  const { user } = useAuth();
  const { data: profile } = useProfile();

  // Fetch sponsor data using secure RPC function
  const { data: sponsorInfo, isLoading } = useQuery({
    queryKey: ['my-sponsor-info', user?.id],
    queryFn: async () => {
      const { data, error } = await supabase.rpc('get_my_sponsor_info');
      
      if (error) throw error;
      return data as unknown as SponsorInfoResponse;
    },
    enabled: !!user?.id && !!profile?.sponsor_id,
  });

  // Don't show if no sponsor
  if (!profile?.sponsor_id) {
    return null;
  }

  // Loading state
  if (isLoading) {
    return (
      <Card className="border-primary/20 bg-primary/5">
        <CardContent className="pt-6">
          <div className="flex items-start space-x-3">
            <Skeleton className="w-10 h-10 rounded-full" />
            <div className="flex-1">
              <Skeleton className="h-4 w-48" />
            </div>
          </div>
        </CardContent>
      </Card>
    );
  }

  const status = sponsorInfo?.status || 'active';
  const sponsorName = sponsorInfo?.sponsor?.full_name 
    || profile.referrer_snapshot?.full_name 
    || profile.referrer_snapshot?.email 
    || 'Неизвестный пользователь';

  const isArchived = status === 'archived';
  const isInactive = status === 'inactive';

  return (
    <Card className="border-primary/20 bg-primary/5">
      <CardContent className="pt-6">
        <div className="flex items-start space-x-3">
          <div className="flex-shrink-0">
            {isArchived ? (
              <div className="w-10 h-10 rounded-full bg-muted flex items-center justify-center">
                <Archive className="h-5 w-5 text-muted-foreground" />
              </div>
            ) : isInactive ? (
              <div className="w-10 h-10 rounded-full bg-yellow-500/10 flex items-center justify-center">
                <Clock className="h-5 w-5 text-yellow-600" />
              </div>
            ) : (
              <div className="w-10 h-10 rounded-full bg-primary/10 flex items-center justify-center">
                <UserCheck className="h-5 w-5 text-primary" />
              </div>
            )}
          </div>
          <div className="flex-1 min-w-0">
            <p className="text-sm font-medium text-base">
              Вы зарегистрированы по приглашению{' '}
              <span className="font-semibold">{sponsorName}</span>
            </p>
            {isArchived && (
              <p className="text-xs text-muted-foreground mt-1">
                (аккаунт архивирован)
              </p>
            )}
            {isInactive && (
              <p className="text-xs text-yellow-600 mt-1">
                (аккаунт не активирован)
              </p>
            )}
          </div>
        </div>
      </CardContent>
    </Card>
  );
}
