import { useState } from "react";
import { Eye, EyeOff, UserPlus, Phone, Mail, MessageCircle } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Checkbox } from "@/components/ui/checkbox";

export function RegisterForm() {
  const [showPassword, setShowPassword] = useState(false);
  const [showConfirmPassword, setShowConfirmPassword] = useState(false);
  const [registrationType, setRegistrationType] = useState("phone");
  const [acceptTerms, setAcceptTerms] = useState(false);

  return (
    <div className="min-h-screen flex items-center justify-center bg-background p-4">
      <div className="w-full max-w-lg">
        <Card className="shadow-[var(--shadow-elevated)]">
          <CardHeader className="text-center space-y-2">
            <div className="mx-auto w-12 h-12 rounded-xl hero-gradient flex items-center justify-center mb-4">
              <UserPlus className="text-white h-6 w-6" />
            </div>
            <CardTitle className="text-2xl font-bold">Регистрация</CardTitle>
            <CardDescription>
              Создайте аккаунт в MLM Platform и начните зарабатывать
            </CardDescription>
          </CardHeader>
          
          <CardContent className="space-y-6">
            {/* Personal Information */}
            <div className="space-y-4">
              <h3 className="font-semibold text-lg">Личные данные</h3>
              <div className="grid gap-4 md:grid-cols-2">
                <div className="space-y-2">
                  <Label htmlFor="firstName">Имя *</Label>
                  <Input
                    id="firstName"
                    placeholder="Иван"
                    required
                  />
                </div>
                <div className="space-y-2">
                  <Label htmlFor="lastName">Фамилия *</Label>
                  <Input
                    id="lastName"
                    placeholder="Иванов"
                    required
                  />
                </div>
              </div>
            </div>

            {/* Contact Method Selection */}
            <div className="space-y-4">
              <h3 className="font-semibold text-lg">Способ регистрации</h3>
              <Tabs value={registrationType} onValueChange={setRegistrationType} className="w-full">
                <TabsList className="grid w-full grid-cols-3">
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

                <TabsContent value="phone" className="space-y-4 mt-4">
                  <div className="space-y-2">
                    <Label htmlFor="phone">Номер телефона *</Label>
                    <Input
                      id="phone"
                      type="tel"
                      placeholder="+7 (___) ___-__-__"
                      required
                    />
                    <p className="text-xs text-muted-foreground">
                      На этот номер будет отправлен код подтверждения
                    </p>
                  </div>
                </TabsContent>

                <TabsContent value="email" className="space-y-4 mt-4">
                  <div className="space-y-2">
                    <Label htmlFor="email">Email адрес *</Label>
                    <Input
                      id="email"
                      type="email"
                      placeholder="example@domain.com"
                      required
                    />
                    <p className="text-xs text-muted-foreground">
                      На этот email будет отправлена ссылка для подтверждения
                    </p>
                  </div>
                </TabsContent>

                <TabsContent value="telegram" className="space-y-4 mt-4">
                  <div className="space-y-2">
                    <Label htmlFor="telegram">Логин Telegram *</Label>
                    <Input
                      id="telegram"
                      placeholder="@username"
                      required
                    />
                    <p className="text-xs text-muted-foreground">
                      Подтверждение будет отправлено через Telegram бота
                    </p>
                  </div>
                </TabsContent>
              </Tabs>
            </div>

            {/* Password Section */}
            <div className="space-y-4">
              <h3 className="font-semibold text-lg">Пароль</h3>
              <div className="space-y-4">
                <div className="space-y-2">
                  <Label htmlFor="password">Пароль *</Label>
                  <div className="relative">
                    <Input
                      id="password"
                      type={showPassword ? "text" : "password"}
                      placeholder="Минимум 8 символов"
                      required
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

                <div className="space-y-2">
                  <Label htmlFor="confirmPassword">Подтвердите пароль *</Label>
                  <div className="relative">
                    <Input
                      id="confirmPassword"
                      type={showConfirmPassword ? "text" : "password"}
                      placeholder="Повторите пароль"
                      required
                    />
                    <Button
                      type="button"
                      variant="ghost"
                      size="sm"
                      className="absolute right-0 top-0 h-full px-3 py-2 hover:bg-transparent"
                      onClick={() => setShowConfirmPassword(!showConfirmPassword)}
                    >
                      {showConfirmPassword ? (
                        <EyeOff className="h-4 w-4 text-muted-foreground" />
                      ) : (
                        <Eye className="h-4 w-4 text-muted-foreground" />
                      )}
                    </Button>
                  </div>
                </div>
              </div>
            </div>

            {/* Referral Code */}
            <div className="space-y-2">
              <Label htmlFor="referralCode">Код приглашения (опционально)</Label>
              <Input
                id="referralCode"
                placeholder="Введите код, если вас пригласили"
              />
              <p className="text-xs text-muted-foreground">
                Если у вас есть код приглашения от партнёра, введите его здесь
              </p>
            </div>

            {/* Payment Information */}
            <div className="space-y-4">
              <h3 className="font-semibold text-lg">Платёжные данные</h3>
              <div className="space-y-4">
                <div className="space-y-2">
                  <Label htmlFor="cardNumber">Номер карты (для выплат)</Label>
                  <Input
                    id="cardNumber"
                    placeholder="**** **** **** ****"
                  />
                </div>
                <p className="text-xs text-muted-foreground">
                  Эти данные можно добавить позже в настройках профиля
                </p>
              </div>
            </div>

            {/* Terms and Conditions */}
            <div className="space-y-4">
              <div className="flex items-start space-x-2">
                <Checkbox 
                  id="terms" 
                  checked={acceptTerms}
                  onCheckedChange={(checked) => setAcceptTerms(checked as boolean)}
                />
                <div className="space-y-1">
                  <Label htmlFor="terms" className="text-sm leading-none peer-disabled:cursor-not-allowed peer-disabled:opacity-70">
                    Я принимаю{" "}
                    <Button variant="link" className="p-0 h-auto text-primary">
                      Пользовательское соглашение
                    </Button>{" "}
                    и{" "}
                    <Button variant="link" className="p-0 h-auto text-primary">
                      Политику конфиденциальности
                    </Button>
                  </Label>
                  <p className="text-xs text-muted-foreground">
                    Также я согласен(на) получать уведомления о работе платформы
                  </p>
                </div>
              </div>
            </div>

            {/* Submit Button */}
            <Button 
              className="w-full hero-gradient border-0" 
              size="lg"
              disabled={!acceptTerms}
            >
              Создать аккаунт
            </Button>

            {/* Login Link */}
            <div className="text-center">
              <div className="text-sm text-muted-foreground">
                Уже есть аккаунт?{" "}
                <a href="/login" className="text-primary hover:underline font-medium">
                  Войти
                </a>
              </div>
            </div>
          </CardContent>
        </Card>
      </div>
    </div>
  );
}