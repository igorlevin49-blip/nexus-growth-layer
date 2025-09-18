import { useState } from "react";
import { User, Bell, Shield, Globe, CreditCard, Eye, EyeOff, Save } from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Switch } from "@/components/ui/switch";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Badge } from "@/components/ui/badge";

export default function Settings() {
  const [showCurrentPassword, setShowCurrentPassword] = useState(false);
  const [showNewPassword, setShowNewPassword] = useState(false);
  const [language, setLanguage] = useState("ru");
  const [timezone, setTimezone] = useState("Europe/Moscow");

  const [notifications, setNotifications] = useState({
    newPartner: true,
    commissions: true,
    systemUpdates: false,
    newsletter: true,
    sms: false,
    telegram: true
  });

  const [privacy, setPrivacy] = useState({
    profileVisible: true,
    showStats: false,
    allowContact: true
  });

  return (
    <div className="p-6 space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-3xl font-bold">Настройки</h1>
          <p className="text-muted-foreground">
            Управление профилем, безопасностью и уведомлениями
          </p>
        </div>
        <Badge className="profit-indicator">
          Аккаунт подтверждён
        </Badge>
      </div>

      <Tabs defaultValue="profile" className="space-y-6">
        <TabsList className="grid w-full grid-cols-5">
          <TabsTrigger value="profile">Профиль</TabsTrigger>
          <TabsTrigger value="security">Безопасность</TabsTrigger>
          <TabsTrigger value="notifications">Уведомления</TabsTrigger>
          <TabsTrigger value="payments">Платежи</TabsTrigger>
          <TabsTrigger value="preferences">Предпочтения</TabsTrigger>
        </TabsList>

        <TabsContent value="profile" className="space-y-6">
          <Card className="financial-card">
            <CardHeader>
              <CardTitle className="flex items-center space-x-2">
                <User className="h-5 w-5" />
                <span>Информация профиля</span>
              </CardTitle>
            </CardHeader>
            <CardContent className="space-y-6">
              <div className="flex items-center space-x-6">
                <div className="w-20 h-20 bg-primary/10 rounded-full flex items-center justify-center">
                  <span className="text-primary font-bold text-2xl">ИИ</span>
                </div>
                <div className="space-y-2">
                  <Button variant="outline">Загрузить фото</Button>
                  <p className="text-xs text-muted-foreground">
                    JPG или PNG до 2MB
                  </p>
                </div>
              </div>

              <div className="grid gap-4 md:grid-cols-2">
                <div className="space-y-2">
                  <Label htmlFor="firstName">Имя</Label>
                  <Input id="firstName" defaultValue="Иван" />
                </div>
                <div className="space-y-2">
                  <Label htmlFor="lastName">Фамилия</Label>
                  <Input id="lastName" defaultValue="Иванов" />
                </div>
                <div className="space-y-2">
                  <Label htmlFor="email">Email</Label>
                  <Input id="email" type="email" defaultValue="ivan@example.com" />
                </div>
                <div className="space-y-2">
                  <Label htmlFor="phone">Телефон</Label>
                  <Input id="phone" type="tel" defaultValue="+7 (999) 123-45-67" />
                </div>
                <div className="space-y-2">
                  <Label htmlFor="telegram">Telegram</Label>
                  <Input id="telegram" defaultValue="@ivan_ivanov" />
                </div>
                <div className="space-y-2">
                  <Label htmlFor="partnerLevel">Уровень партнёра</Label>
                  <Input id="partnerLevel" defaultValue="Gold" disabled />
                </div>
              </div>

              <div className="space-y-2">
                <Label htmlFor="bio">О себе</Label>
                <textarea 
                  id="bio"
                  className="w-full min-h-[100px] px-3 py-2 border border-border rounded-md bg-background"
                  placeholder="Расскажите о себе и своих целях..."
                />
              </div>

              <Button className="hero-gradient border-0">
                <Save className="h-4 w-4 mr-2" />
                Сохранить изменения
              </Button>
            </CardContent>
          </Card>
        </TabsContent>

        <TabsContent value="security" className="space-y-6">
          <Card className="financial-card">
            <CardHeader>
              <CardTitle className="flex items-center space-x-2">
                <Shield className="h-5 w-5" />
                <span>Безопасность аккаунта</span>
              </CardTitle>
            </CardHeader>
            <CardContent className="space-y-6">
              <div className="space-y-4">
                <h3 className="font-semibold">Смена пароля</h3>
                <div className="space-y-4">
                  <div className="space-y-2">
                    <Label htmlFor="currentPassword">Текущий пароль</Label>
                    <div className="relative">
                      <Input
                        id="currentPassword"
                        type={showCurrentPassword ? "text" : "password"}
                        placeholder="Введите текущий пароль"
                      />
                      <Button
                        type="button"
                        variant="ghost"
                        size="sm"
                        className="absolute right-0 top-0 h-full px-3"
                        onClick={() => setShowCurrentPassword(!showCurrentPassword)}
                      >
                        {showCurrentPassword ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
                      </Button>
                    </div>
                  </div>
                  <div className="space-y-2">
                    <Label htmlFor="newPassword">Новый пароль</Label>
                    <div className="relative">
                      <Input
                        id="newPassword"
                        type={showNewPassword ? "text" : "password"}
                        placeholder="Введите новый пароль"
                      />
                      <Button
                        type="button"
                        variant="ghost"
                        size="sm"
                        className="absolute right-0 top-0 h-full px-3"
                        onClick={() => setShowNewPassword(!showNewPassword)}
                      >
                        {showNewPassword ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
                      </Button>
                    </div>
                  </div>
                  <div className="space-y-2">
                    <Label htmlFor="confirmPassword">Подтвердите пароль</Label>
                    <Input
                      id="confirmPassword"
                      type="password"
                      placeholder="Повторите новый пароль"
                    />
                  </div>
                </div>
                <Button variant="outline">Изменить пароль</Button>
              </div>

              <div className="border-t border-border pt-6">
                <h3 className="font-semibold mb-4">Двухфакторная аутентификация</h3>
                <div className="flex items-center justify-between">
                  <div>
                    <p className="font-medium">2FA через SMS</p>
                    <p className="text-sm text-muted-foreground">
                      Дополнительная защита через SMS-коды
                    </p>
                  </div>
                  <Switch />
                </div>
                <div className="flex items-center justify-between mt-4">
                  <div>
                    <p className="font-medium">2FA через Telegram</p>
                    <p className="text-sm text-muted-foreground">
                      Получение кодов в Telegram боте
                    </p>
                  </div>
                  <Switch defaultChecked />
                </div>
              </div>

              <div className="border-t border-border pt-6">
                <h3 className="font-semibold mb-4">Активные сессии</h3>
                <div className="space-y-3">
                  {[
                    { device: "Chrome на Windows", location: "Москва, Россия", current: true },
                    { device: "Safari на iPhone", location: "Москва, Россия", current: false },
                    { device: "Chrome на Android", location: "Санкт-Петербург, Россия", current: false }
                  ].map((session, index) => (
                    <div key={index} className="flex items-center justify-between p-3 border border-border rounded-lg">
                      <div>
                        <p className="font-medium">{session.device}</p>
                        <p className="text-sm text-muted-foreground">{session.location}</p>
                      </div>
                      <div className="flex items-center space-x-2">
                        {session.current && (
                          <Badge className="profit-indicator">Текущая</Badge>
                        )}
                        {!session.current && (
                          <Button variant="outline" size="sm">Завершить</Button>
                        )}
                      </div>
                    </div>
                  ))}
                </div>
              </div>
            </CardContent>
          </Card>
        </TabsContent>

        <TabsContent value="notifications" className="space-y-6">
          <Card className="financial-card">
            <CardHeader>
              <CardTitle className="flex items-center space-x-2">
                <Bell className="h-5 w-5" />
                <span>Настройки уведомлений</span>
              </CardTitle>
            </CardHeader>
            <CardContent className="space-y-6">
              <div className="space-y-4">
                <h3 className="font-semibold">Email уведомления</h3>
                {[
                  { key: "newPartner", label: "Новые партнёры", description: "Уведомления о регистрации новых партнёров" },
                  { key: "commissions", label: "Начисления", description: "Информация о комиссиях и бонусах" },
                  { key: "systemUpdates", label: "Обновления системы", description: "Технические уведомления и обновления" },
                  { key: "newsletter", label: "Новостная рассылка", description: "Еженедельная сводка и новости компании" }
                ].map((item) => (
                  <div key={item.key} className="flex items-center justify-between">
                    <div>
                      <p className="font-medium">{item.label}</p>
                      <p className="text-sm text-muted-foreground">{item.description}</p>
                    </div>
                    <Switch 
                      checked={notifications[item.key as keyof typeof notifications]}
                      onCheckedChange={(checked) => 
                        setNotifications(prev => ({ ...prev, [item.key]: checked }))
                      }
                    />
                  </div>
                ))}
              </div>

              <div className="border-t border-border pt-6">
                <h3 className="font-semibold mb-4">Дополнительные каналы</h3>
                <div className="space-y-4">
                  <div className="flex items-center justify-between">
                    <div>
                      <p className="font-medium">SMS уведомления</p>
                      <p className="text-sm text-muted-foreground">Важные уведомления через SMS</p>
                    </div>
                    <Switch 
                      checked={notifications.sms}
                      onCheckedChange={(checked) => 
                        setNotifications(prev => ({ ...prev, sms: checked }))
                      }
                    />
                  </div>
                  <div className="flex items-center justify-between">
                    <div>
                      <p className="font-medium">Telegram бот</p>
                      <p className="text-sm text-muted-foreground">Уведомления через Telegram бота</p>
                    </div>
                    <Switch 
                      checked={notifications.telegram}
                      onCheckedChange={(checked) => 
                        setNotifications(prev => ({ ...prev, telegram: checked }))
                      }
                    />
                  </div>
                </div>
              </div>
            </CardContent>
          </Card>
        </TabsContent>

        <TabsContent value="payments" className="space-y-6">
          <Card className="financial-card">
            <CardHeader>
              <CardTitle className="flex items-center space-x-2">
                <CreditCard className="h-5 w-5" />
                <span>Способы оплаты</span>
              </CardTitle>
            </CardHeader>
            <CardContent className="space-y-6">
              <div className="space-y-4">
                <h3 className="font-semibold">Банковские карты</h3>
                <div className="space-y-3">
                  <div className="flex items-center justify-between p-4 border border-border rounded-lg">
                    <div className="flex items-center space-x-3">
                      <div className="w-10 h-6 bg-gradient-to-r from-blue-600 to-blue-400 rounded"></div>
                      <div>
                        <p className="font-medium">**** **** **** 1234</p>
                        <p className="text-sm text-muted-foreground">Expires 12/26</p>
                      </div>
                      <Badge className="profit-indicator">Основная</Badge>
                    </div>
                    <Button variant="outline" size="sm">Удалить</Button>
                  </div>
                </div>
                <Button variant="outline">+ Добавить карту</Button>
              </div>

              <div className="border-t border-border pt-6">
                <h3 className="font-semibold mb-4">Настройки автовывода</h3>
                <div className="space-y-4">
                  <div className="flex items-center justify-between">
                    <div>
                      <p className="font-medium">Автоматический вывод</p>
                      <p className="text-sm text-muted-foreground">
                        Автоматически выводить средства при достижении лимита
                      </p>
                    </div>
                    <Switch />
                  </div>
                  <div className="grid gap-4 md:grid-cols-2">
                    <div className="space-y-2">
                      <Label htmlFor="autoWithdrawLimit">Сумма для автовывода</Label>
                      <Input id="autoWithdrawLimit" type="number" placeholder="1000" />
                    </div>
                    <div className="space-y-2">
                      <Label htmlFor="withdrawalCard">Карта для вывода</Label>
                      <Select>
                        <SelectTrigger>
                          <SelectValue placeholder="Выберите карту" />
                        </SelectTrigger>
                        <SelectContent>
                          <SelectItem value="card1">**** 1234 (Основная)</SelectItem>
                        </SelectContent>
                      </Select>
                    </div>
                  </div>
                </div>
              </div>
            </CardContent>
          </Card>
        </TabsContent>

        <TabsContent value="preferences" className="space-y-6">
          <Card className="financial-card">
            <CardHeader>
              <CardTitle className="flex items-center space-x-2">
                <Globe className="h-5 w-5" />
                <span>Предпочтения</span>
              </CardTitle>
            </CardHeader>
            <CardContent className="space-y-6">
              <div className="grid gap-4 md:grid-cols-2">
                <div className="space-y-2">
                  <Label htmlFor="language">Язык интерфейса</Label>
                  <Select value={language} onValueChange={setLanguage}>
                    <SelectTrigger>
                      <SelectValue />
                    </SelectTrigger>
                    <SelectContent>
                      <SelectItem value="ru">🇷🇺 Русский</SelectItem>
                      <SelectItem value="kz">🇰🇿 Қазақша</SelectItem>
                      <SelectItem value="en">🇺🇸 English</SelectItem>
                    </SelectContent>
                  </Select>
                </div>
                <div className="space-y-2">
                  <Label htmlFor="timezone">Часовой пояс</Label>
                  <Select value={timezone} onValueChange={setTimezone}>
                    <SelectTrigger>
                      <SelectValue />
                    </SelectTrigger>
                    <SelectContent>
                      <SelectItem value="Europe/Moscow">Москва (UTC+3)</SelectItem>
                      <SelectItem value="Asia/Almaty">Алматы (UTC+6)</SelectItem>
                      <SelectItem value="Europe/London">Лондон (UTC+0)</SelectItem>
                    </SelectContent>
                  </Select>
                </div>
              </div>

              <div className="border-t border-border pt-6">
                <h3 className="font-semibold mb-4">Приватность</h3>
                <div className="space-y-4">
                  {[
                    { key: "profileVisible", label: "Публичный профиль", description: "Другие пользователи могут видеть ваш профиль" },
                    { key: "showStats", label: "Показывать статистику", description: "Отображать ваши достижения в профиле" },
                    { key: "allowContact", label: "Разрешить контакты", description: "Другие партнёры могут связаться с вами" }
                  ].map((item) => (
                    <div key={item.key} className="flex items-center justify-between">
                      <div>
                        <p className="font-medium">{item.label}</p>
                        <p className="text-sm text-muted-foreground">{item.description}</p>
                      </div>
                      <Switch 
                        checked={privacy[item.key as keyof typeof privacy]}
                        onCheckedChange={(checked) => 
                          setPrivacy(prev => ({ ...prev, [item.key]: checked }))
                        }
                      />
                    </div>
                  ))}
                </div>
              </div>

              <Button className="hero-gradient border-0">
                <Save className="h-4 w-4 mr-2" />
                Сохранить настройки
              </Button>
            </CardContent>
          </Card>
        </TabsContent>
      </Tabs>
    </div>
  );
}