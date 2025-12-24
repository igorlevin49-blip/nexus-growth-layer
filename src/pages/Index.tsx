import { useNavigate } from "react-router-dom";
import { useEffect } from "react";
import { useAuth } from "@/hooks/useAuth";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Avatar, AvatarImage, AvatarFallback } from "@/components/ui/avatar";
import { useTeamMembers } from "@/hooks/useTeamMembers";
import { 
  TrendingUp, 
  Users, 
  Target, 
  Award, 
  DollarSign, 
  Rocket,
  CheckCircle2,
  Briefcase,
  GraduationCap,
  Globe,
  Coffee,
  ShoppingCart,
  Calendar,
  Shield
} from "lucide-react";

const Index = () => {
  const navigate = useNavigate();
  const { user, loading: authLoading } = useAuth();
  const { data: teamMembers, isLoading: teamLoading } = useTeamMembers();

  useEffect(() => {
    if (user) {
      navigate('/dashboard');
    }
  }, [user, navigate]);

  // Show loader while checking auth state
  if (authLoading) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-background">
        <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-primary"></div>
      </div>
    );
  }

  if (user) return null;

  return (
    <div className="min-h-screen bg-background">
      {/* Header */}
      <header className="sticky top-0 z-50 w-full border-b bg-background/95 backdrop-blur supports-[backdrop-filter]:bg-background/60">
        <div className="container mx-auto px-4 h-14 md:h-16 flex items-center justify-between">
          <h1 className="text-2xl font-bold bg-gradient-to-r from-primary to-purple-600 bg-clip-text text-transparent">
            MG MARKET
          </h1>
          <nav className="hidden md:flex items-center gap-6">
            <a href="#about" className="text-sm font-medium hover:text-primary transition-colors">О компании</a>
            <a href="#opportunities" className="text-sm font-medium hover:text-primary transition-colors">Возможности</a>
            <a href="#income" className="text-sm font-medium hover:text-primary transition-colors">Доход</a>
            <a href="#product" className="text-sm font-medium hover:text-primary transition-colors">Продукт</a>
            <a href="#roadmap" className="text-sm font-medium hover:text-primary transition-colors">Дорожная карта</a>
          </nav>
          <div className="flex items-center gap-2 sm:gap-3">
            <Button variant="ghost" onClick={() => navigate('/login')}>
              Войти
            </Button>
            <Button onClick={() => navigate('/register')} className="bg-gradient-to-r from-primary to-purple-600">
              Регистрация
            </Button>
          </div>
        </div>
      </header>

      {/* Hero Section */}
      <section className="relative py-20 md:py-28 px-4 overflow-hidden">
        {/* Анимированный фон */}
        <div className="absolute inset-0 bg-gradient-to-br from-primary/10 via-purple-500/10 to-background animate-gradient bg-[length:200%_200%]" />
        
        <div className="container mx-auto max-w-6xl relative z-10">
          {/* Бейдж "Новая эра MLM" */}
          <div className="flex justify-center mb-6">
            <span className="inline-flex items-center gap-2 px-4 py-2 rounded-full bg-primary/10 border border-primary/20 text-sm font-medium">
              <TrendingUp className="w-4 h-4" />
              Новая эра прямых продаж
            </span>
          </div>
          
          {/* Основной заголовок */}
          <h2 className="text-4xl sm:text-5xl md:text-6xl lg:text-7xl font-bold mb-6 text-center leading-tight break-words">
            MG MARKET — платформа{" "}
            <span className="bg-gradient-to-r from-primary via-purple-600 to-primary bg-clip-text text-transparent">
              честных прямых продаж
            </span>
          </h2>
          
          {/* Подзаголовок */}
          <p className="text-base sm:text-lg md:text-2xl text-muted-foreground mb-10 max-w-4xl mx-auto text-center leading-relaxed">
            Мы создаём сообщество людей, которые развиваются, заботятся о своём здоровье и доме, 
            и при этом имеют надёжную возможность зарабатывать честно и прозрачно
          </p>
          
          {/* CTA кнопки */}
          <div className="flex flex-col sm:flex-row items-center justify-center gap-4 mb-10 md:mb-16">
            <Button 
              size="lg" 
              onClick={() => navigate('/register')} 
              className="bg-gradient-to-r from-primary to-purple-600 text-base md:text-lg px-6 md:px-10 py-4 md:py-7 h-auto hover:shadow-xl hover:scale-105 transition-all"
            >
              <Rocket className="mr-2 w-5 h-5" />
              Стать партнёром
            </Button>
            <Button 
              size="lg" 
              variant="outline"
              onClick={() => navigate('/login')}
              className="text-base md:text-lg px-6 md:px-10 py-4 md:py-7 h-auto"
            >
              Войти в систему
            </Button>
          </div>
          
          {/* Статистика компании */}
          <div className="grid grid-cols-2 md:grid-cols-4 gap-4 sm:gap-6 max-w-5xl mx-auto">
            <Card className="p-4 sm:p-6 text-center border-primary/20 hover:border-primary/40 transition-colors">
              <Calendar className="w-6 h-6 md:w-8 md:h-8 mx-auto mb-3 text-primary" />
              <div className="text-2xl md:text-3xl font-bold mb-1">18+</div>
              <div className="text-xs sm:text-sm text-muted-foreground">лет на рынке</div>
            </Card>
            <Card className="p-4 sm:p-6 text-center border-primary/20 hover:border-primary/40 transition-colors">
              <Users className="w-6 h-6 md:w-8 md:h-8 mx-auto mb-3 text-primary" />
              <div className="text-2xl md:text-3xl font-bold mb-1">10,000+</div>
              <div className="text-xs sm:text-sm text-muted-foreground">партнёров</div>
            </Card>
            <Card className="p-4 sm:p-6 text-center border-primary/20 hover:border-primary/40 transition-colors">
              <Globe className="w-6 h-6 md:w-8 md:h-8 mx-auto mb-3 text-primary" />
              <div className="text-2xl md:text-3xl font-bold mb-1">50+</div>
              <div className="text-xs sm:text-sm text-muted-foreground">стран</div>
            </Card>
            <Card className="p-4 sm:p-6 text-center border-primary/20 hover:border-primary/40 transition-colors">
              <Shield className="w-6 h-6 md:w-8 md:h-8 mx-auto mb-3 text-primary" />
              <div className="text-2xl md:text-3xl font-bold mb-1">100%</div>
              <div className="text-xs sm:text-sm text-muted-foreground">прозрачность</div>
            </Card>
          </div>
        </div>
      </section>

      {/* About Section */}
      <section id="about" className="py-20 px-4 bg-muted/30">
        <div className="container mx-auto max-w-6xl">
          <div className="text-center mb-16">
            <h3 className="text-4xl font-bold mb-4">О компании</h3>
            <div className="w-20 h-1 bg-gradient-to-r from-primary to-purple-600 mx-auto mb-6"></div>
          </div>
          <Card className="p-8 mb-8">
            <p className="text-lg leading-relaxed mb-6">
              MG MARKET — платформа для людей, которые ценят качество и возможности. 
              Мы в прямых продажах с 2006 года и развиваем партнёрскую модель, где каждый может покупать, 
              рекомендовать и зарабатывать.
            </p>
            <blockquote className="border-l-4 border-primary pl-4 italic text-muted-foreground">
              "Это наше уверенное движение в будущее продаж — честных, прозрачных и выгодных для всех."
            </blockquote>
          </Card>

          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-5 sm:gap-6 mb-16">
            <Card className="p-5 sm:p-6 text-center">
              <Target className="w-8 h-8 sm:w-10 sm:h-10 md:w-12 md:h-12 mx-auto mb-3 sm:mb-4 text-primary" />
              <h4 className="text-base sm:text-lg md:text-xl font-semibold mb-2">Наша миссия</h4>
              <p className="text-sm text-muted-foreground">
                Создавать сообщество людей, которые развиваются и имеют надёжную возможность зарабатывать
              </p>
            </Card>
            <Card className="p-5 sm:p-6 text-center">
              <Award className="w-8 h-8 sm:w-10 sm:h-10 md:w-12 md:h-12 mx-auto mb-3 sm:mb-4 text-primary" />
              <h4 className="text-base sm:text-lg md:text-xl font-semibold mb-2">Качество и польза</h4>
              <p className="text-sm text-muted-foreground">
                Доход рождается из сотрудничества, честности и реального качества продукта
              </p>
            </Card>
            <Card className="p-5 sm:p-6 text-center">
              <Users className="w-8 h-8 sm:w-10 sm:h-10 md:w-12 md:h-12 mx-auto mb-3 sm:mb-4 text-primary" />
              <h4 className="text-base sm:text-lg md:text-xl font-semibold mb-2">Поддержка</h4>
              <p className="text-sm text-muted-foreground">
                Поддержка и обучение на каждом этапе в сообществе единомышленников
              </p>
            </Card>
          </div>

          {/* Team */}
          <div className="text-center mb-12">
            <h4 className="text-3xl font-bold mb-8">Наша команда</h4>
          </div>
          {teamLoading ? null : (
            <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 gap-6">
              {teamMembers?.map((member) => (
                <Card key={member.id} className="p-6 md:p-8 text-center hover:shadow-lg transition-shadow">
                  <div className="flex justify-center mb-4 md:mb-6">
                    <Avatar className="w-28 h-28 sm:w-32 sm:h-32 md:w-40 md:h-40 rounded-2xl">
                      <AvatarImage 
                        src={member.photo_url || undefined} 
                        alt={member.name}
                        className="rounded-2xl object-cover"
                      />
                      <AvatarFallback className="bg-primary/10 text-primary text-2xl sm:text-3xl font-semibold rounded-2xl">
                        {member.name.split(' ').map(n => n[0]).join('').slice(0, 2)}
                      </AvatarFallback>
                    </Avatar>
                  </div>
                  <h5 className="font-bold text-lg md:text-xl mb-1 md:mb-2">{member.name}</h5>
                  <p className="text-xs sm:text-sm font-medium text-primary mb-2 md:mb-3">{member.position}</p>
                  <p className="text-xs sm:text-sm text-muted-foreground">{member.description}</p>
                </Card>
              ))}
            </div>
          )}
        </div>
      </section>

      {/* Opportunities Section */}
      <section id="opportunities" className="py-20 px-4">
        <div className="container mx-auto max-w-6xl">
          <div className="text-center mb-16">
            <h3 className="text-4xl font-bold mb-4">Возможности для партнёров</h3>
            <div className="w-20 h-1 bg-gradient-to-r from-primary to-purple-600 mx-auto mb-6"></div>
            <p className="text-lg text-muted-foreground max-w-3xl mx-auto">
              MG MARKET открывает пространство для развития, дохода и роста в команде. 
              В основе — прозрачная система, качественный продукт и поддержка на каждом этапе.
            </p>
          </div>

          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-5 sm:gap-6">
            <Card className="p-5 sm:p-6 hover:shadow-lg transition-shadow">
              <DollarSign className="w-8 h-8 sm:w-10 sm:h-10 mb-3 sm:mb-4 text-primary" />
              <h4 className="text-lg md:text-xl font-semibold mb-2">Доход от продаж и команды</h4>
              <p className="text-sm text-muted-foreground">
                Система вознаграждения формирует устойчивый и растущий доход. Два вида дохода
              </p>
            </Card>
            <Card className="p-5 sm:p-6 hover:shadow-lg transition-shadow">
              <TrendingUp className="w-8 h-8 sm:w-10 sm:h-10 mb-3 sm:mb-4 text-primary" />
              <h4 className="text-lg md:text-xl font-semibold mb-2">5 карьерных уровней</h4>
              <p className="text-sm text-muted-foreground">
                Каждый уровень открывает новые преимущества, инструменты и возможности для заработка
              </p>
            </Card>
            <Card className="p-5 sm:p-6 hover:shadow-lg transition-shadow">
              <Rocket className="w-8 h-8 sm:w-10 sm:h-10 mb-3 sm:mb-4 text-primary" />
              <h4 className="text-lg md:text-xl font-semibold mb-2">Автоматизация до 90%</h4>
              <p className="text-sm text-muted-foreground">
                Личный кабинет, маркетплейс, CRM сокращают рутину и экономят время
              </p>
            </Card>
            <Card className="p-5 sm:p-6 hover:shadow-lg transition-shadow">
              <GraduationCap className="w-8 h-8 sm:w-10 sm:h-10 mb-3 sm:mb-4 text-primary" />
              <h4 className="text-lg md:text-xl font-semibold mb-2">Наставничество и обучение</h4>
              <p className="text-sm text-muted-foreground">
                Поддержка опытных лидеров, регулярные программы и чёткий путь развития
              </p>
            </Card>
            <Card className="p-5 sm:p-6 hover:shadow-lg transition-shadow">
              <CheckCircle2 className="w-8 h-8 sm:w-10 sm:h-10 mb-3 sm:mb-4 text-primary" />
              <h4 className="text-lg md:text-xl font-semibold mb-2">Проверенные товары</h4>
              <p className="text-sm text-muted-foreground">
                Ассортимент товаров для здоровья и дома. Только проверенные бренды
              </p>
            </Card>
            <Card className="p-5 sm:p-6 hover:shadow-lg transition-shadow">
              <Users className="w-8 h-8 sm:w-10 sm:h-10 mb-3 sm:mb-4 text-primary" />
              <h4 className="text-lg md:text-xl font-semibold mb-2">Личный бренд и лидерство</h4>
              <p className="text-sm text-muted-foreground">
                Развивайте навыки влияния, коммуникации и управления командой
              </p>
            </Card>
          </div>
        </div>
      </section>

      {/* Leader Program Section */}
      <section id="product" className="py-20 px-4 bg-muted/30">
        <div className="container mx-auto max-w-6xl">
          <div className="text-center mb-12">
            <h3 className="text-4xl md:text-5xl font-bold mb-4">Лидерская программа</h3>
            <div className="w-20 h-1 bg-gradient-to-r from-primary to-purple-600 mx-auto mb-6"></div>
            <p className="text-lg text-muted-foreground max-w-2xl mx-auto">
              Начните свой путь к финансовой независимости с программой Торговый Клуб
            </p>
          </div>
          
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-6 md:gap-8 mb-12">
            {/* Карточка 1: Единоразовый взнос */}
            <Card className="relative overflow-hidden group hover:shadow-2xl transition-all duration-300 hover:-translate-y-2">
              <div className="absolute inset-0 bg-gradient-to-br from-primary/5 to-primary/10 opacity-0 group-hover:opacity-100 transition-opacity" />
              <CardContent className="p-6 md:p-8 relative z-10">
                <div className="w-12 h-12 md:w-16 md:h-16 rounded-2xl bg-gradient-to-br from-primary to-purple-600 flex items-center justify-center mb-4 md:mb-6 group-hover:scale-110 transition-transform">
                  <DollarSign className="w-6 h-6 md:w-8 md:h-8 text-white" />
                </div>
                <h4 className="text-xl md:text-2xl font-bold mb-2 md:mb-3">Единоразовый взнос</h4>
                <div className="text-3xl sm:text-4xl md:text-5xl font-bold text-primary mb-3 md:mb-4">$100</div>
                <p className="text-sm md:text-base text-muted-foreground">
                  Стартовая точка для входа в торговый клуб MG MARKET. Полная прозрачность использования средств
                </p>
              </CardContent>
            </Card>
            
            {/* Карточка 2: Кофемашина в подарок */}
            <Card className="relative overflow-hidden group hover:shadow-2xl transition-all duration-300 hover:-translate-y-2">
              <div className="absolute inset-0 bg-gradient-to-br from-success/5 to-success/10 opacity-0 group-hover:opacity-100 transition-opacity" />
              <CardContent className="p-6 md:p-8 relative z-10">
                <div className="w-12 h-12 md:w-16 md:h-16 rounded-2xl bg-gradient-to-br from-success to-green-600 flex items-center justify-center mb-4 md:mb-6 group-hover:scale-110 transition-transform">
                  <Coffee className="w-6 h-6 md:w-8 md:h-8 text-white" />
                </div>
                <h4 className="text-xl md:text-2xl font-bold mb-2 md:mb-3">Кофемашина в подарок</h4>
                <div className="text-3xl sm:text-4xl md:text-5xl font-bold text-success mb-3 md:mb-4">БЕСПЛАТНО</div>
                <p className="text-sm md:text-base text-muted-foreground">
                  Профессиональная кофемашина + полное обучение работе с продуктом и построению бизнеса
                </p>
              </CardContent>
            </Card>
            
            {/* Карточка 3: Стартовый пакет продуктов */}
            <Card className="relative overflow-hidden group hover:shadow-2xl transition-all duration-300 hover:-translate-y-2">
              <div className="absolute inset-0 bg-gradient-to-br from-purple-500/5 to-purple-600/10 opacity-0 group-hover:opacity-100 transition-opacity" />
              <CardContent className="p-6 md:p-8 relative z-10">
                <div className="w-12 h-12 md:w-16 md:h-16 rounded-2xl bg-gradient-to-br from-purple-500 to-purple-700 flex items-center justify-center mb-4 md:mb-6 group-hover:scale-110 transition-transform">
                  <ShoppingCart className="w-6 h-6 md:w-8 md:h-8 text-white" />
                </div>
                <h4 className="text-xl md:text-2xl font-bold mb-2 md:mb-3">Стартовый пакет</h4>
                <div className="text-3xl sm:text-4xl md:text-5xl font-bold text-purple-600 mb-3 md:mb-4">20,000 ₸</div>
                <p className="text-sm md:text-base text-muted-foreground">
                  Качественный набор продуктов для старта: кофе, чай, товары для дома и здоровья
                </p>
              </CardContent>
            </Card>
          </div>
          
          {/* CTA кнопка */}
          <div className="text-center">
            <Button 
              size="lg" 
              onClick={() => navigate('/register')}
              className="bg-gradient-to-r from-primary to-purple-600 text-lg px-10 py-7 h-auto shadow-xl hover:shadow-2xl transition-all"
            >
              <Rocket className="mr-2" />
              Начать сейчас
            </Button>
            <p className="text-sm text-muted-foreground mt-4">
              Присоединитесь к тысячам успешных партнёров
            </p>
          </div>
        </div>
      </section>

      {/* Income Section */}
      <section id="income" className="py-20 px-4">
        <div className="container mx-auto max-w-6xl">
          <div className="text-center mb-16">
            <h3 className="text-4xl font-bold mb-4">На чём вы зарабатываете</h3>
            <div className="w-20 h-1 bg-gradient-to-r from-primary to-purple-600 mx-auto mb-6"></div>
          </div>

          <div className="grid md:grid-cols-3 gap-8 mb-16">
            <Card className="p-6">
              <div className="w-12 h-12 rounded-full bg-primary/10 flex items-center justify-center mb-4">
                <span className="text-2xl font-bold text-primary">1</span>
              </div>
              <h4 className="font-semibold mb-3">Реферальный и лидерский бонус</h4>
              <p className="text-sm text-muted-foreground mb-2">До <strong>10%</strong> с команды</p>
              <p className="text-sm text-muted-foreground">
                Доход от привлечения новых партнёров и развития структуры
              </p>
            </Card>
            <Card className="p-6">
              <div className="w-12 h-12 rounded-full bg-primary/10 flex items-center justify-center mb-4">
                <span className="text-2xl font-bold text-primary">2</span>
              </div>
              <h4 className="font-semibold mb-3">Доход от повторных покупок</h4>
              <p className="text-sm text-muted-foreground mb-2">До <strong>60%</strong> с команды</p>
              <p className="text-sm text-muted-foreground">
                Регулярный доход с покупок капсул кофе и чая на всех уровнях структуры
              </p>
            </Card>
            <Card className="p-6">
              <div className="w-12 h-12 rounded-full bg-primary/10 flex items-center justify-center mb-4">
                <span className="text-2xl font-bold text-primary">3</span>
              </div>
              <h4 className="font-semibold mb-3">Личные продажи</h4>
              <p className="text-sm text-muted-foreground mb-2"><strong>10%</strong> + командный процент</p>
              <p className="text-sm text-muted-foreground">
                Доход от собственных рекомендаций и продаж вашей команды
              </p>
            </Card>
          </div>

          {/* Marketing Plan */}
          <Card className="p-8 mb-12">
            <h4 className="text-2xl font-bold mb-6 text-center">Маркетинг-план</h4>
            <div className="overflow-x-auto">
              <table className="w-full">
                <thead>
                  <tr className="border-b">
                    <th className="text-left py-3 px-4">Уровень</th>
                    <th className="text-right py-3 px-4">Процент</th>
                  </tr>
                </thead>
                <tbody>
                  {[
                    { level: '1 уровень', percent: '10%' },
                    { level: '2 уровень', percent: '5%' },
                    { level: '3 уровень', percent: '5%' },
                    { level: '4 уровень', percent: '5%' },
                    { level: '5 уровень', percent: '5%' },
                    { level: '6 уровень', percent: '5%' },
                    { level: '7 уровень', percent: '5%' },
                    { level: '8 уровень', percent: '5%' },
                    { level: '9 уровень', percent: '5%' },
                    { level: '10 уровень', percent: '10%' },
                  ].map((row) => (
                    <tr key={row.level} className="border-b">
                      <td className="py-3 px-4">{row.level}</td>
                      <td className="text-right py-3 px-4 font-semibold text-primary">{row.percent}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </Card>

          {/* Income Potential */}
          <div className="text-center mb-8">
            <h4 className="text-2xl font-bold mb-4">Потенциал дохода</h4>
            <p className="text-muted-foreground mb-8">
              Примеры расчётов при разных сценариях активности структуры
            </p>
          </div>
          <div className="grid md:grid-cols-4 gap-6">
            {[
              { activity: '100%', income: '~15,000,000 ₸', description: 'Максимальная активность' },
              { activity: '50%', income: '~7,500,000 ₸', description: 'Высокая активность' },
              { activity: '10%', income: '~1,500,000 ₸', description: 'Средняя активность' },
              { activity: '1%', income: '~150,000 ₸', description: 'Базовая активность' },
            ].map((scenario) => (
              <Card key={scenario.activity} className="p-6 text-center">
                <p className="text-3xl font-bold text-primary mb-2">{scenario.activity}</p>
                <p className="text-sm text-muted-foreground mb-3">{scenario.description}</p>
                <p className="text-xl font-semibold">{scenario.income}</p>
              </Card>
            ))}
          </div>
          <p className="text-sm text-center text-muted-foreground mt-6 italic">
            * Результаты зависят от личной активности и развития команды. Не является гарантией дохода.
          </p>
        </div>
      </section>

      {/* Roadmap Section */}
      <section id="roadmap" className="py-20 px-4 bg-muted/30">
        <div className="container mx-auto max-w-6xl">
          <div className="text-center mb-16">
            <h3 className="text-4xl font-bold mb-4">Дорожная карта</h3>
            <div className="w-20 h-1 bg-gradient-to-r from-primary to-purple-600 mx-auto mb-6"></div>
            <p className="text-lg text-muted-foreground">Развитие, масштабирование, цели</p>
          </div>

          <div className="grid md:grid-cols-3 gap-8">
            <Card className="p-8">
              <div className="text-3xl font-bold text-primary mb-6">2025</div>
              <div className="space-y-4">
                <div>
                  <h5 className="font-semibold mb-2 flex items-center gap-2">
                    <Rocket className="w-5 h-5" />
                    Пред старт проекта
                  </h5>
                  <p className="text-sm text-muted-foreground">
                    Запуск платформы MG MARKET, формирование первых команд партнёрства, обучение лидеров (11.10.2025)
                  </p>
                </div>
                <div>
                  <h5 className="font-semibold mb-2">Официальное открытие</h5>
                  <p className="text-sm text-muted-foreground">
                    Презентация как полноформатной платформы с масштабной партнёрской программой
                  </p>
                </div>
              </div>
            </Card>

            <Card className="p-8">
              <div className="text-3xl font-bold text-primary mb-6">2026</div>
              <div className="space-y-4">
                <div>
                  <h5 className="font-semibold mb-2 flex items-center gap-2">
                    <Globe className="w-5 h-5" />
                    Региональные представительства
                  </h5>
                  <p className="text-sm text-muted-foreground mb-2">Открытие офисов:</p>
                  <ul className="text-sm text-muted-foreground list-disc list-inside">
                    <li>Астана (офис)</li>
                    <li>Бишкек</li>
                    <li>Шымкент</li>
                    <li>Актау, Атырау, Актобе</li>
                  </ul>
                </div>
                <div>
                  <h5 className="font-semibold mb-2">Новогодняя встреча</h5>
                  <p className="text-sm text-muted-foreground">
                    Подведение результатов, награждение активных партнёров
                  </p>
                </div>
              </div>
            </Card>

            <Card className="p-8">
              <div className="text-3xl font-bold text-primary mb-6">2027</div>
              <div className="space-y-4">
                <div>
                  <h5 className="font-semibold mb-2 flex items-center gap-2">
                    <Globe className="w-5 h-5" />
                    Международный семинар
                  </h5>
                  <p className="text-sm text-muted-foreground">
                    Объединение партнёров из разных стран. Обмен опытом, запуск новых рынков
                  </p>
                </div>
                <div>
                  <h5 className="font-semibold mb-2">Глобальное развитие</h5>
                  <p className="text-sm text-muted-foreground">
                    Развитие международного сообщества MG MARKET
                  </p>
                </div>
              </div>
            </Card>
          </div>
        </div>
      </section>

      {/* Final CTA Section */}
      <section className="py-20 px-4">
        <div className="container mx-auto max-w-4xl text-center">
          <blockquote className="text-3xl md:text-4xl font-bold mb-8">
            "Лучшее время начать — сейчас.{" "}
            <span className="bg-gradient-to-r from-primary to-purple-600 bg-clip-text text-transparent">
              Завтра твои мечты могут стать реальностью
            </span>"
          </blockquote>
          <div className="flex flex-col sm:flex-row items-center justify-center gap-4">
            <Button 
              size="lg" 
              onClick={() => navigate('/register')}
              className="bg-gradient-to-r from-primary to-purple-600 text-lg px-8 py-6 h-auto"
            >
              Зарегистрироваться
            </Button>
            <Button 
              size="lg" 
              variant="outline"
              onClick={() => navigate('/login')}
              className="text-lg px-8 py-6 h-auto"
            >
              Войти
            </Button>
          </div>
        </div>
      </section>

      {/* Footer */}
      <footer className="border-t py-8 px-4 bg-muted/30">
        <div className="container mx-auto max-w-6xl text-center text-sm text-muted-foreground">
          <p>© 2025 MG MARKET. Платформа честных прямых продаж.</p>
        </div>
      </footer>
    </div>
  );
};

export default Index;
