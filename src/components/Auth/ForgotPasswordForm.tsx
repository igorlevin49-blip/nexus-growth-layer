import { useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { toast } from "sonner";
import { ArrowLeft, Mail } from "lucide-react";
import { Link } from "react-router-dom";
import { APP_CONFIG } from "@/config/constants";

export function ForgotPasswordForm() {
  const [email, setEmail] = useState("");
  const [loading, setLoading] = useState(false);
  const [sent, setSent] = useState(false);

  const handleResetPassword = async (e: React.FormEvent) => {
    e.preventDefault();
    setLoading(true);

    try {
      const { error } = await supabase.auth.resetPasswordForEmail(email, {
        redirectTo: `${APP_CONFIG.DOMAIN}/reset-password`,
      });

      if (error) throw error;

      setSent(true);
      toast.success("Письмо отправлено", {
        description: "Проверьте почту для восстановления пароля",
      });
    } catch (error: any) {
      toast.error("Ошибка", {
        description: error.message || "Не удалось отправить письмо",
      });
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="min-h-screen flex items-center justify-center p-4 bg-gradient-to-br from-background via-background to-muted">
      <Card className="w-full max-w-md">
        <CardHeader className="space-y-1">
          <CardTitle className="text-2xl font-bold">Забыли пароль?</CardTitle>
          <CardDescription>
            Введите email для восстановления доступа
          </CardDescription>
        </CardHeader>
        <CardContent>
          {!sent ? (
            <form onSubmit={handleResetPassword} className="space-y-4">
              <div className="space-y-2">
                <label htmlFor="email" className="text-sm font-medium">
                  Email
                </label>
                <div className="relative">
                  <Mail className="absolute left-3 top-3 h-4 w-4 text-muted-foreground" />
                  <Input
                    id="email"
                    type="email"
                    placeholder="your@email.com"
                    value={email}
                    onChange={(e) => setEmail(e.target.value)}
                    required
                    disabled={loading}
                    className="pl-10"
                  />
                </div>
              </div>

              <Button type="submit" className="w-full" disabled={loading}>
                {loading ? "Отправка..." : "Отправить письмо"}
              </Button>

              <Link to="/login">
                <Button variant="ghost" className="w-full" type="button">
                  <ArrowLeft className="mr-2 h-4 w-4" />
                  Вернуться к входу
                </Button>
              </Link>
            </form>
          ) : (
            <div className="space-y-4 text-center">
              <div className="p-4 bg-primary/10 rounded-lg">
                <Mail className="h-12 w-12 mx-auto mb-3 text-primary" />
                <p className="text-sm text-muted-foreground">
                  Письмо с инструкцией отправлено на <strong>{email}</strong>
                </p>
              </div>
              
              <Link to="/login">
                <Button variant="outline" className="w-full">
                  <ArrowLeft className="mr-2 h-4 w-4" />
                  Вернуться к входу
                </Button>
              </Link>
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
