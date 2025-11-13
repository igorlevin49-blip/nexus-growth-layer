import { useNavigate } from "react-router-dom";
import { useEffect } from "react";
import { useAuth } from "@/hooks/useAuth";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
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
  Globe
} from "lucide-react";

const Index = () => {
  const navigate = useNavigate();
  const { user } = useAuth();

  useEffect(() => {
    if (user) {
      navigate('/dashboard');
    }
  }, [user, navigate]);

  if (user) return null;

  return (
    <div className="min-h-screen bg-background">
      {/* Header */}
      <header className="sticky top-0 z-50 w-full border-b bg-background/95 backdrop-blur supports-[backdrop-filter]:bg-background/60">
        <div className="container mx-auto px-4 h-16 flex items-center justify-between">
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
          <div className="flex items-center gap-3">
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
      <section className="py-20 px-4">
        <div className="container mx-auto max-w-6xl text-center">
          <h2 className="text-5xl md:text-6xl font-bold mb-6">
            MG MARKET — платформа{" "}
            <span className="bg-gradient-to-r from-primary to-purple-600 bg-clip-text text-transparent">
              честных прямых продаж
            </span>
          </h2>
          <p className="text-xl text-muted-foreground mb-8 max-w-3xl mx-auto">
            Мы создаём сообщество людей, которые развиваются, заботятся о своём здоровье и доме, 
            и при этом имеют надёжную возможность зарабатывать честно и прозрачно
          </p>
          <div className="flex flex-col sm:flex-row items-center justify-center gap-4 mb-4">
            <Button 
              size="lg" 
              onClick={() => navigate('/register')}
              className="bg-gradient-to-r from-primary to-purple-600 text-lg px-8 py-6 h-auto"
            >
              <Rocket className="mr-2" />
              Стать партнёром
            </Button>
          </div>
          <a 
            href="/login" 
            className="text-sm text-muted-foreground hover:text-primary transition-colors"
          >
            У меня уже есть аккаунт → Войти
          </a>
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

          <div className="grid md:grid-cols-3 gap-6 mb-16">
            <Card className="p-6 text-center">
              <Target className="w-12 h-12 mx-auto mb-4 text-primary" />
              <h4 className="font-semibold mb-2">Наша миссия</h4>
              <p className="text-sm text-muted-foreground">
                Создавать сообщество людей, которые развиваются и имеют надёжную возможность зарабатывать
              </p>
            </Card>
            <Card className="p-6 text-center">
              <Award className="w-12 h-12 mx-auto mb-4 text-primary" />
              <h4 className="font-semibold mb-2">Качество и польза</h4>
              <p className="text-sm text-muted-foreground">
                Доход рождается из сотрудничества, честности и реального качества продукта
              </p>
            </Card>
            <Card className="p-6 text-center">
              <Users className="w-12 h-12 mx-auto mb-4 text-primary" />
              <h4 className="font-semibold mb-2">Поддержка</h4>
              <p className="text-sm text-muted-foreground">
                Поддержка и обучение на каждом этапе в сообществе единомышленников
              </p>
            </Card>
          </div>

          {/* Team */}
          <div className="text-center mb-12">
            <h4 className="text-3xl font-bold mb-8">Наша команда</h4>
          </div>
          <div className="grid md:grid-cols-3 gap-8">
            <Card className="p-6">
              <Briefcase className="w-10 h-10 mb-4 text-primary" />
              <h5 className="font-bold text-lg mb-2">Ибраев Марсбек</h5>
              <p className="text-sm font-medium text-primary mb-2">Учредитель MG Market</p>
              <p className="text-sm text-muted-foreground">
                Долларовый мультимиллионер с многолетним опытом построения успешных бизнесов
              </p>
            </Card>
            <Card className="p-6">
              <Award className="w-10 h-10 mb-4 text-primary" />
              <h5 className="font-bold text-lg mb-2">Камалов Эрбол</h5>
              <p className="text-sm font-medium text-primary mb-2">Президент компании</p>
              <p className="text-sm text-muted-foreground">
                Опытный профессионал с 20 лет опыта в прямых продажах, превративший амбициозную идею в успешный бизнес
              </p>
            </Card>
            <Card className="p-6">
              <TrendingUp className="w-10 h-10 mb-4 text-primary" />
              <h5 className="font-bold text-lg mb-2">Банников Олег</h5>
              <p className="text-sm font-medium text-primary mb-2">CEO, Коммерческий директор</p>
              <p className="text-sm text-muted-foreground">
                Более 20 лет опыта в продажах, управлении командами и построении эффективных коммерческих стратегий
              </p>
            </Card>
          </div>
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

          <div className="grid md:grid-cols-2 lg:grid-cols-3 gap-6">
            <Card className="p-6 hover:shadow-lg transition-shadow">
              <DollarSign className="w-10 h-10 mb-4 text-primary" />
              <h4 className="font-semibold mb-2">Доход от продаж и команды</h4>
              <p className="text-sm text-muted-foreground">
                Система вознаграждения формирует устойчивый и растущий доход. Два вида дохода
              </p>
            </Card>
            <Card className="p-6 hover:shadow-lg transition-shadow">
              <TrendingUp className="w-10 h-10 mb-4 text-primary" />
              <h4 className="font-semibold mb-2">5 карьерных уровней</h4>
              <p className="text-sm text-muted-foreground">
                Каждый уровень открывает новые преимущества, инструменты и возможности для заработка
              </p>
            </Card>
            <Card className="p-6 hover:shadow-lg transition-shadow">
              <Rocket className="w-10 h-10 mb-4 text-primary" />
              <h4 className="font-semibold mb-2">Автоматизация до 90%</h4>
              <p className="text-sm text-muted-foreground">
                Личный кабинет, маркетплейс, CRM сокращают рутину и экономят время
              </p>
            </Card>
            <Card className="p-6 hover:shadow-lg transition-shadow">
              <GraduationCap className="w-10 h-10 mb-4 text-primary" />
              <h4 className="font-semibold mb-2">Наставничество и обучение</h4>
              <p className="text-sm text-muted-foreground">
                Поддержка опытных лидеров, регулярные программы и чёткий путь развития
              </p>
            </Card>
            <Card className="p-6 hover:shadow-lg transition-shadow">
              <CheckCircle2 className="w-10 h-10 mb-4 text-primary" />
              <h4 className="font-semibold mb-2">Проверенные товары</h4>
              <p className="text-sm text-muted-foreground">
                Ассортимент товаров для здоровья и дома. Только проверенные бренды
              </p>
            </Card>
            <Card className="p-6 hover:shadow-lg transition-shadow">
              <Users className="w-10 h-10 mb-4 text-primary" />
              <h4 className="font-semibold mb-2">Личный бренд и лидерство</h4>
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
            <h3 className="text-4xl font-bold mb-4">Лидерская программа</h3>
            <div className="w-20 h-1 bg-gradient-to-r from-primary to-purple-600 mx-auto mb-6"></div>
          </div>
          <Card className="p-8 max-w-3xl mx-auto">
            <h4 className="text-2xl font-semibold mb-6 text-center">Торговый Клуб</h4>
            <div className="space-y-4">
              <div className="flex items-start gap-3">
                <CheckCircle2 className="w-6 h-6 text-primary flex-shrink-0 mt-1" />
                <p>Единоразовый взнос <strong className="text-primary">$100</strong></p>
              </div>
              <div className="flex items-start gap-3">
                <CheckCircle2 className="w-6 h-6 text-primary flex-shrink-0 mt-1" />
                <p>Кофемашина в подарок</p>
              </div>
              <div className="flex items-start gap-3">
                <CheckCircle2 className="w-6 h-6 text-primary flex-shrink-0 mt-1" />
                <p>Ежемесячная покупка капсул на <strong className="text-primary">20 000 ₸</strong></p>
              </div>
            </div>
          </Card>
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
