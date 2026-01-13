import { useState } from "react";
import { Outlet, NavLink, useLocation } from "react-router-dom";
import {
  Home,
  ShoppingCart,
  Users,
  BarChart3,
  Settings,
  LogOut,
  Menu,
  X,
  Globe,
  Shield,
  ShieldAlert,
  Package,
  FileText,
  Trash2,
  DollarSign,
  Gift,
  Activity,
  AlertCircle,
  Bell,
  RefreshCw,
  ArrowUpCircle
} from "lucide-react";
import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";
import { useAuth } from "@/hooks/useAuth";
import { SubscriptionStatus } from "./SubscriptionStatus";
import { AdminNotificationsIndicator } from "./AdminNotificationsIndicator";
import { usePendingOrdersCount } from "@/hooks/usePendingOrdersCount";

const navigation = [
  { name: "Панель управления", href: "/dashboard", icon: Home },
  { name: "Магазин", href: "/shop", icon: ShoppingCart },
  { name: "Моя сеть", href: "/network", icon: Users },
  { name: "Финансы", href: "/finances", icon: BarChart3 },
  { name: "Настройки", href: "/settings", icon: Settings },
];

const languages = [
  { code: "ru", name: "Русский", flag: "🇷🇺" },
  { code: "kz", name: "Қазақша", flag: "🇰🇿" },
  { code: "en", name: "English", flag: "🇺🇸" },
];

export function AppLayout() {
  const [sidebarOpen, setSidebarOpen] = useState(false);
  const [currentLang, setCurrentLang] = useState("ru");
  const location = useLocation();
  const { userRole, signOut, user } = useAuth();
  const { data: pendingOrdersCount = 0 } = usePendingOrdersCount();

  const isActive = (path: string) => location.pathname === path;

  const adminNavigation = [
    { name: "Пользователи", href: "/admin/users", icon: Users },
    { name: "Товары", href: "/admin/products", icon: Package },
    { name: "Заказы", href: "/admin/orders", icon: ShoppingCart },
    { name: "Оплаты", href: "/admin/payments", icon: FileText },
    { name: "Выплаты", href: "/admin/payouts", icon: DollarSign },
    { name: "Активации", href: "/admin/monthly-activations", icon: Activity },
    { name: "Аудит комиссий", href: "/admin/commission-audit", icon: Shield },
    { name: "Диагностика", href: "/admin/payment-diagnostics", icon: AlertCircle },
    { name: "Отчеты", href: "/admin/reports", icon: BarChart3 },
    { name: "Документы", href: "/admin/documents", icon: FileText },
    { name: "Маркетинг доступ", href: "/admin/marketing-access", icon: Gift },
  ];

  const superAdminNavigation = [
    { name: "Управление лендингом", href: "/admin/landing-settings", icon: Globe },
    { name: "Уведомления", href: "/admin/notifications", icon: Bell },
    { name: "Логи безопасности", href: "/admin/security-logs", icon: ShieldAlert },
    { name: "Управление ролями", href: "/admin/roles", icon: Shield },
    { name: "Настройки магазина", href: "/admin/shop-settings", icon: Settings },
    { name: "MLM-настройки", href: "/admin/mlm-settings", icon: Settings },
    { name: "Пересчёт комиссий", href: "/admin/recalculate-commissions", icon: RefreshCw },
    { name: "Доначисление S1", href: "/admin/commission-backfill", icon: ArrowUpCircle },
    { name: "Очистка тестовых данных", href: "/admin/test-data-cleanup", icon: Trash2 },
  ];

  const getRoleLabel = (role: string | null) => {
    switch (role) {
      case 'superadmin':
        return 'Супер-админ';
      case 'admin':
        return 'Администратор';
      default:
        return 'Пользователь';
    }
  };

  return (
    <div className="min-h-screen bg-background">
      {/* Mobile sidebar overlay */}
      {sidebarOpen && (
        <div 
          className="fixed inset-0 z-40 lg:hidden bg-black/50"
          onClick={() => setSidebarOpen(false)}
        />
      )}

      {/* Sidebar */}
      <div className={cn(
        "fixed inset-y-0 left-0 z-50 w-64 bg-card border-r border-border transition-transform duration-300 ease-in-out lg:translate-x-0",
        sidebarOpen ? "translate-x-0" : "-translate-x-full lg:translate-x-0"
      )}>
        <div className="flex h-full flex-col">
          {/* Logo */}
          <div className="flex h-16 items-center justify-between px-6 border-b border-border">
            <div className="flex items-center space-x-2">
              <div className="w-8 h-8 rounded-lg hero-gradient flex items-center justify-center">
                <span className="text-white font-bold text-sm">MG</span>
              </div>
              <span className="font-semibold text-lg">MG-market</span>
            </div>
            <Button
              variant="ghost"
              size="sm"
              className="lg:hidden"
              onClick={() => setSidebarOpen(false)}
            >
              <X className="h-4 w-4" />
            </Button>
          </div>

          {/* Navigation */}
          <nav className="flex-1 space-y-1 px-3 py-4 overflow-y-auto">
            {navigation.map((item) => {
              const Icon = item.icon;
              return (
                <NavLink
                  key={item.name}
                  to={item.href}
                  className={cn(
                    "flex items-center space-x-3 rounded-lg px-3 py-2 text-sm font-medium transition-colors",
                    isActive(item.href)
                      ? "bg-primary/10 text-primary border border-primary/20"
                      : "text-muted-foreground hover:bg-accent hover:text-accent-foreground"
                  )}
                >
                  <Icon className="h-4 w-4" />
                  <span>{item.name}</span>
                </NavLink>
              );
            })}

            {(userRole === 'admin' || userRole === 'superadmin') && (
              <div className="pt-4 mt-4 border-t border-border">
                <div className="flex items-center space-x-2 px-3 py-2 text-xs font-semibold text-muted-foreground uppercase tracking-wider">
                  <Shield className="h-3 w-3" />
                  <span>Админ панель</span>
                </div>
                {adminNavigation.map((item) => {
                  const Icon = item.icon;
                  const showOrdersBadge = item.name === "Заказы" && pendingOrdersCount > 0;
                  return (
                    <NavLink
                      key={item.name}
                      to={item.href}
                      className={cn(
                        "flex items-center space-x-3 rounded-lg px-3 py-2 text-sm font-medium transition-colors",
                        isActive(item.href)
                          ? "bg-primary/10 text-primary border border-primary/20"
                          : "text-muted-foreground hover:bg-accent hover:text-accent-foreground"
                      )}
                    >
                      <div className="relative">
                        <Icon className="h-4 w-4" />
                        {showOrdersBadge && (
                          <span className="absolute -top-2 -right-2.5 flex h-4 min-w-4 items-center justify-center rounded-full bg-destructive text-[10px] font-bold text-destructive-foreground animate-pulse">
                            {pendingOrdersCount > 9 ? '9+' : pendingOrdersCount}
                          </span>
                        )}
                      </div>
                      <span>{item.name}</span>
                    </NavLink>
                  );
                })}
                {userRole === 'superadmin' && superAdminNavigation.map((item) => {
                  const Icon = item.icon;
                  return (
                    <NavLink
                      key={item.name}
                      to={item.href}
                      className={cn(
                        "flex items-center space-x-3 rounded-lg px-3 py-2 text-sm font-medium transition-colors",
                        isActive(item.href)
                          ? "bg-destructive/10 text-destructive border border-destructive/20"
                          : "text-muted-foreground hover:bg-accent hover:text-accent-foreground"
                      )}
                    >
                      <Icon className="h-4 w-4" />
                      <span>{item.name}</span>
                    </NavLink>
                  );
                })}
              </div>
            )}
          </nav>

          {/* Language Selector */}
          <div className="px-3 py-4 border-t border-border">
            <div className="flex items-center space-x-2 mb-2">
              <Globe className="h-4 w-4 text-muted-foreground" />
              <span className="text-sm font-medium">Язык</span>
            </div>
            <div className="grid grid-cols-3 gap-1">
              {languages.map((lang) => (
                <Button
                  key={lang.code}
                  variant={currentLang === lang.code ? "default" : "ghost"}
                  size="sm"
                  className="text-xs p-1 h-8"
                  onClick={() => setCurrentLang(lang.code)}
                >
                  <span className="mr-1">{lang.flag}</span>
                  {lang.code.toUpperCase()}
                </Button>
              ))}
            </div>
          </div>

          {/* Footer links */}
          <div className="px-3 py-3 border-t border-border">
            <div className="flex flex-wrap gap-2 text-xs text-muted-foreground">
              <NavLink to="/docs/offer-agreement" className="hover:text-primary">
                Договор оферты
              </NavLink>
              <span>·</span>
              <NavLink to="/docs/privacy-policy" className="hover:text-primary">
                Политика конфиденциальности
              </NavLink>
            </div>
          </div>

          {/* User menu */}
          <div className="p-3 border-t border-border">
            <div className="flex items-center space-x-3 mb-3">
              <div className="w-8 h-8 bg-primary/10 rounded-full flex items-center justify-center">
                <span className="text-primary font-medium text-sm">
                  {user?.email?.charAt(0).toUpperCase() || 'U'}
                </span>
              </div>
              <div className="flex-1 min-w-0">
                <p className="text-sm font-medium truncate">{user?.email || 'Пользователь'}</p>
                <p className="text-xs text-muted-foreground">{getRoleLabel(userRole)}</p>
              </div>
            </div>
            <Button 
              variant="ghost" 
              size="sm" 
              className="w-full justify-start text-muted-foreground"
              onClick={signOut}
            >
              <LogOut className="h-4 w-4 mr-2" />
              Выйти
            </Button>
          </div>
        </div>
      </div>

      {/* Main content */}
      <div className="lg:pl-64">
        {/* Top bar */}
        <header className="sticky top-0 z-30 flex h-16 items-center justify-between border-b border-border bg-card/95 backdrop-blur px-6">
          <Button
            variant="ghost"
            size="sm"
            className="lg:hidden"
            onClick={() => setSidebarOpen(true)}
          >
            <Menu className="h-4 w-4" />
          </Button>
          
          <div className="flex items-center gap-2">
            <AdminNotificationsIndicator />
            <SubscriptionStatus />
          </div>
        </header>

        {/* Page content */}
        <main className="flex-1">
          <Outlet />
        </main>
      </div>
    </div>
  );
}