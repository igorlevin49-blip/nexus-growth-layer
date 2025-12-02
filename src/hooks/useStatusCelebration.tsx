import { useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "./useAuth";

interface StatusAchievement {
  id: string;
  user_id: string;
  level: number;
  status_name: string;
  achieved_at: string;
  shown: boolean;
}

export function useStatusCelebration() {
  const { user } = useAuth();
  const [celebration, setCelebration] = useState<{
    show: boolean;
    level: number;
    statusName: string;
  }>({ show: false, level: 0, statusName: '' });

  useEffect(() => {
    if (!user) return;

    const checkForNewAchievement = async () => {
      try {
        // Check for unshown achievements
        const { data, error } = await supabase
          .from('user_status_achievements')
          .select('*')
          .eq('user_id', user.id)
          .eq('shown', false)
          .order('achieved_at', { ascending: false })
          .limit(1)
          .single();

        if (error && error.code !== 'PGRST116') throw error;
        
        if (data) {
          // Show celebration
          setCelebration({
            show: true,
            level: data.level,
            statusName: data.status_name
          });

          // Mark as shown
          await supabase
            .from('user_status_achievements')
            .update({ shown: true })
            .eq('id', data.id);
        }
      } catch (error) {
        console.error('Error checking achievements:', error);
      }
    };

    checkForNewAchievement();

    // Subscribe to new achievements
    const channel = supabase
      .channel('status_achievements')
      .on(
        'postgres_changes',
        {
          event: 'INSERT',
          schema: 'public',
          table: 'user_status_achievements',
          filter: `user_id=eq.${user.id}`
        },
        (payload) => {
          const achievement = payload.new as StatusAchievement;
          setCelebration({
            show: true,
            level: achievement.level,
            statusName: achievement.status_name
          });
        }
      )
      .subscribe();

    return () => {
      supabase.removeChannel(channel);
    };
  }, [user]);

  const closeCelebration = () => {
    setCelebration({ show: false, level: 0, statusName: '' });
  };

  return {
    celebration,
    closeCelebration
  };
}
