import { useState } from "react";
import { Eye, EyeOff, Phone, Mail, MessageCircle } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";

export function LoginForm() {
  const [showPassword, setShowPassword] = useState(false);
  const [loginType, setLoginType] = useState("phone");

  return (
    <div className="min-h-screen flex items-center justify-center bg-background p-4">
      <div className="w-full max-w-md">
        <Card className="shadow-[var(--shadow-elevated)]">
          <CardHeader className="text-center space-y-2">
            <div className="mx-auto w-12 h-12 rounded-xl hero-gradient flex items-center justify-center mb-4">
              <span className="text-white font-bold text-lg">MLM</span>
            </div>
            <CardTitle className="text-2xl font-bold">Добро пожаловать</CardTitle>
            <CardDescription>
              Войдите в вашу учётную запись MLM Platform
            </CardDescription>
          </CardHeader>
          
          <CardContent>
            <Tabs value={loginType} onValueChange={setLoginType} className="w-full">
              <TabsList className="grid w-full grid-cols-3 mb-6">
                <TabsTrigger value="phone" className="flex items-center space-x-1">
                  <Phone className="h-3 w-3" />
                  <span className="hidden sm:inline">Телефон</span>
                </TabsTrigger>
                <TabsTrigger value="email" className="flex items-center space-x-1">
                  <Mail className="h-3 w-3" />
                  <span className="hidden sm:inline">Email</span>
                </TabsTrigger>
                <TabsTrigger value="telegram" className="flex items-center space-x-1">
                  <MessageCircle className="h-3 w-3" />
                  <span className="hidden sm:inline">Telegram</span>
                </TabsTrigger>
              </TabsList>

              <TabsContent value="phone" className="space-y-4">
                <div className="space-y-2">
                  <Label htmlFor="phone">Номер телефона</Label>
                  <Input
                    id="phone"
                    type="tel"
                    placeholder="+7 (___) ___-__-__"
                    className="text-base"
                  />
                </div>
              </TabsContent>

              <TabsContent value="email" className="space-y-4">
                <div className="space-y-2">
                  <Label htmlFor="email">Email</Label>
                  <Input
                    id="email"
                    type="email"
                    placeholder="example@domain.com"
                    className="text-base"
                  />
                </div>
              </TabsContent>

              <TabsContent value="telegram" className="space-y-4">
                <div className="space-y-2">
                  <Label htmlFor="telegram">Логин Telegram</Label>
                  <Input
                    id="telegram"
                    type="text"
                    placeholder="@username"
                    className="text-base"
                  />
                </div>
              </TabsContent>

              <div className="space-y-2">
                <Label htmlFor="password">Пароль</Label>
                <div className="relative">
                  <Input
                    id="password"
                    type={showPassword ? "text" : "password"}
                    placeholder="Введите пароль"
                    className="text-base pr-10"
                  />
                  <Button
                    type="button"
                    variant="ghost"
                    size="sm"
                    className="absolute right-0 top-0 h-full px-3 py-2 hover:bg-transparent"
                    onClick={() => setShowPassword(!showPassword)}
                  >
                    {showPassword ? (
                      <EyeOff className="h-4 w-4 text-muted-foreground" />
                    ) : (
                      <Eye className="h-4 w-4 text-muted-foreground" />
                    )}
                  </Button>
                </div>
              </div>

              <Button className="w-full hero-gradient border-0" size="lg">
                Войти
              </Button>

              <div className="text-center space-y-2">
                <Button variant="link" size="sm" className="text-muted-foreground">
                  Забыли пароль?
                </Button>
                <div className="text-sm text-muted-foreground">
                  Нет аккаунта?{" "}
                  <a href="/register" className="text-primary hover:underline font-medium">
                    Зарегистрироваться
                  </a>
                </div>
              </div>
            </Tabs>
          </CardContent>
        </Card>
      </div>
    </div>
  );
}