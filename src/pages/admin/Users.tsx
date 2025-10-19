import { useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { toast } from "@/hooks/use-toast";
import { Ban, CheckCircle, XCircle } from "lucide-react";

interface Profile {
  id: string;
  full_name: string | null;
  email: string | null;
  subscription_status: string;
  balance: number;
  created_at: string;
}

export default function AdminUsers() {
  const [profiles, setProfiles] = useState<Profile[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    fetchProfiles();
  }, []);

  const fetchProfiles = async () => {
    try {
      const { data, error } = await supabase
        .from('profiles')
        .select('*')
        .order('created_at', { ascending: false });

      if (error) throw error;
      setProfiles(data || []);
    } catch (error) {
      console.error('Error fetching profiles:', error);
      toast({
        title: "Ошибка",
        description: "Не удалось загрузить пользователей",
        variant: "destructive",
      });
    } finally {
      setLoading(false);
    }
  };

  const toggleUserStatus = async (userId: string, currentStatus: string) => {
    const newStatus = currentStatus === 'active' ? 'frozen' : 'active';
    
    try {
      const { error } = await supabase
        .from('profiles')
        .update({ subscription_status: newStatus })
        .eq('id', userId);

      if (error) throw error;

      toast({
        title: "Успешно",
        description: `Статус пользователя изменен на ${newStatus}`,
      });

      fetchProfiles();
    } catch (error) {
      console.error('Error updating user status:', error);
      toast({
        title: "Ошибка",
        description: "Не удалось обновить статус пользователя",
        variant: "destructive",
      });
    }
  };

  if (loading) {
    return <div className="flex items-center justify-center h-96">Загрузка...</div>;
  }

  return (
    <div className="p-8">
      <Card>
        <CardHeader>
          <CardTitle>Управление пользователями</CardTitle>
        </CardHeader>
        <CardContent>
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Имя</TableHead>
                <TableHead>Email</TableHead>
                <TableHead>Статус</TableHead>
                <TableHead>Баланс</TableHead>
                <TableHead>Дата регистрации</TableHead>
                <TableHead>Действия</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {profiles.map((profile) => (
                <TableRow key={profile.id}>
                  <TableCell>{profile.full_name || 'Не указано'}</TableCell>
                  <TableCell>{profile.email}</TableCell>
                  <TableCell>
                    <Badge 
                      variant={
                        profile.subscription_status === 'active' 
                          ? 'default' 
                          : profile.subscription_status === 'frozen'
                          ? 'secondary'
                          : 'destructive'
                      }
                    >
                      {profile.subscription_status === 'active' ? (
                        <><CheckCircle className="w-3 h-3 mr-1" /> Активен</>
                      ) : profile.subscription_status === 'frozen' ? (
                        <><XCircle className="w-3 h-3 mr-1" /> Заморожен</>
                      ) : (
                        'Неактивен'
                      )}
                    </Badge>
                  </TableCell>
                  <TableCell>${profile.balance?.toFixed(2) || '0.00'}</TableCell>
                  <TableCell>{new Date(profile.created_at).toLocaleDateString('ru-RU')}</TableCell>
                  <TableCell>
                    <Button
                      variant="outline"
                      size="sm"
                      onClick={() => toggleUserStatus(profile.id, profile.subscription_status)}
                    >
                      <Ban className="w-4 h-4 mr-1" />
                      {profile.subscription_status === 'active' ? 'Заблокировать' : 'Разблокировать'}
                    </Button>
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </CardContent>
      </Card>
    </div>
  );
}
