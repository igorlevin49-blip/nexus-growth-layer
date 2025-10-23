import { useState, useEffect } from "react";
import { Eye, EyeOff, UserPlus } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Checkbox } from "@/components/ui/checkbox";
import { useNavigate, useSearchParams } from "react-router-dom";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "sonner";
import { useAuth } from "@/hooks/useAuth";
import { APP_CONFIG } from "@/config/constants";

export function RegisterForm() {
  const [showPassword, setShowPassword] = useState(false);
  const [showConfirmPassword, setShowConfirmPassword] = useState(false);
  const [fullName, setFullName] = useState("");
  const [email, setEmail] = useState("");
  const [phone, setPhone] = useState("");
  const [password, setPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [referralCode, setReferralCode] = useState("");
  const [acceptTerms, setAcceptTerms] = useState(false);
  const [loading, setLoading] = useState(false);
  const navigate = useNavigate();
  const { user } = useAuth();
  const [searchParams] = useSearchParams();

  // Get referral code from URL or cookie
  useEffect(() => {
    const refFromUrl = searchParams.get('ref');
    const refFromCookie = localStorage.getItem(APP_CONFIG.REFERRAL_COOKIE_KEY);
    
    if (refFromUrl) {
      setReferralCode(refFromUrl);
      // Save to cookie for 30 days
      localStorage.setItem(APP_CONFIG.REFERRAL_COOKIE_KEY, refFromUrl);
    } else if (refFromCookie) {
      setReferralCode(refFromCookie);
    }
  }, [searchParams]);

  // Redirect if already logged in
  if (user) {
    navigate('/');
    return null;
  }

  const validatePassword = (pwd: string): string | null => {
    if (pwd.length < 8) {
      return "Пароль должен быть не менее 8 символов";
    }
    if (!/[a-zA-Z]/.test(pwd)) {
      return "Пароль должен содержать минимум 1 букву";
    }
    if (!/[0-9]/.test(pwd)) {
      return "Пароль должен содержать минимум 1 цифру";
    }
    return null;
  };

  const validatePhone = (phone: string): boolean => {
    // Remove all non-digit characters
    const cleaned = phone.replace(/\D/g, '');
    // Check if it's a valid Kazakhstan phone number (starts with 7 and has 11 digits)
    return cleaned.length >= 10 && cleaned.length <= 15;
  };

  const normalizePhone = (phone: string): string => {
    // Remove all non-digit characters and ensure it starts with country code
    const cleaned = phone.replace(/\D/g, '');
    if (cleaned.startsWith('8')) {
      return '+7' + cleaned.substring(1);
    }
    if (!cleaned.startsWith('7') && !cleaned.startsWith('+')) {
      return '+7' + cleaned;
    }
    if (!cleaned.startsWith('+')) {
      return '+' + cleaned;
    }
    return cleaned;
  };

  const handleRegister = async (e: React.FormEvent) => {
    e.preventDefault();

    // Validate passwords match
    if (password !== confirmPassword) {
      toast.error("Пароли не совпадают");
      return;
    }

    // Validate password strength
    const passwordError = validatePassword(password);
    if (passwordError) {
      toast.error(passwordError);
      return;
    }

    // Validate phone if provided
    if (phone && !validatePhone(phone)) {
      toast.error("Неверный формат телефона");
      return;
    }

    // Validate full name
    if (fullName.length < 2 || fullName.length > 128) {
      toast.error("Имя должно быть от 2 до 128 символов");
      return;
    }

    setLoading(true);

    try {
      // Find sponsor by referral code if provided
      let sponsorId: string | null = null;
      if (referralCode) {
        const { data: sponsorProfile, error: sponsorError } = await supabase
          .from('profiles')
          .select('id')
          .eq('referral_code', referralCode.trim())
          .maybeSingle();
        
        if (sponsorProfile) {
          sponsorId = sponsorProfile.id;
        } else if (!sponsorError) {
          toast.warning("Код приглашения не найден", {
            description: "Регистрация продолжается без реферера",
          });
        }
      }

      const redirectUrl = `${APP_CONFIG.DOMAIN}/`;
      
      const { data: authData, error: signUpError } = await supabase.auth.signUp({
        email,
        password,
        options: {
          emailRedirectTo: redirectUrl,
          data: {
            full_name: fullName,
          },
        },
      });

      if (signUpError) throw signUpError;

      // Update profile with additional data
      if (authData.user) {
        const updateData: any = {
          full_name: fullName,
        };
        
        if (phone) {
          updateData.phone = normalizePhone(phone);
        }
        
        if (sponsorId) {
          updateData.sponsor_id = sponsorId;
        }

        await supabase
          .from('profiles')
          .update(updateData)
          .eq('id', authData.user.id);

        // Clear referral cookie after successful registration
        localStorage.removeItem(APP_CONFIG.REFERRAL_COOKIE_KEY);
      }

      toast.success("Регистрация успешна", {
        description: "Добро пожаловать в систему!",
      });

      navigate('/dashboard');
    } catch (error: any) {
      toast.error("Ошибка регистрации", {
        description: error.message || "Не удалось зарегистрироваться",
      });
    } finally {
      setLoading(false);
    }
  };

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
            <form onSubmit={handleRegister} className="space-y-6">
              {/* Full Name */}
              <div className="space-y-2">
                <Label htmlFor="fullName">Полное имя *</Label>
                <Input
                  id="fullName"
                  placeholder="Иван Иванов"
                  value={fullName}
                  onChange={(e) => setFullName(e.target.value)}
                  required
                  minLength={2}
                  maxLength={128}
                />
              </div>

              {/* Email */}
              <div className="space-y-2">
                <Label htmlFor="email">Email *</Label>
                <Input
                  id="email"
                  type="email"
                  placeholder="email@example.com"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  required
                />
              </div>

              {/* Phone (optional) */}
              <div className="space-y-2">
                <Label htmlFor="phone">Телефон (опционально)</Label>
                <Input
                  id="phone"
                  type="tel"
                  placeholder="+7 (___) ___-__-__"
                  value={phone}
                  onChange={(e) => setPhone(e.target.value)}
                />
              </div>

              {/* Password */}
              <div className="space-y-2">
                <Label htmlFor="password">Пароль *</Label>
                <div className="relative">
                  <Input
                    id="password"
                    type={showPassword ? "text" : "password"}
                    placeholder="Минимум 8 символов"
                    value={password}
                    onChange={(e) => setPassword(e.target.value)}
                    required
                    minLength={8}
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
                <p className="text-xs text-muted-foreground">
                  Минимум 8 символов, 1 буква и 1 цифра
                </p>
              </div>

              {/* Confirm Password */}
              <div className="space-y-2">
                <Label htmlFor="confirmPassword">Подтвердите пароль *</Label>
                <div className="relative">
                  <Input
                    id="confirmPassword"
                    type={showConfirmPassword ? "text" : "password"}
                    placeholder="Повторите пароль"
                    value={confirmPassword}
                    onChange={(e) => setConfirmPassword(e.target.value)}
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

              {/* Referral Code */}
              <div className="space-y-2">
                <Label htmlFor="referralCode">Код приглашения</Label>
                <Input
                  id="referralCode"
                  placeholder="Введите код, если вас пригласили"
                  value={referralCode}
                  onChange={(e) => setReferralCode(e.target.value)}
                />
                {referralCode && (
                  <p className="text-xs text-primary">
                    ✓ Вы регистрируетесь по реферальной ссылке
                  </p>
                )}
              </div>

              {/* Terms and Conditions */}
              <div className="flex items-start space-x-2">
                <Checkbox 
                  id="terms" 
                  checked={acceptTerms}
                  onCheckedChange={(checked) => setAcceptTerms(checked as boolean)}
                />
                <div className="space-y-1">
                  <Label htmlFor="terms" className="text-sm leading-none">
                    Я принимаю{" "}
                    <a href="/docs/offer-agreement" target="_blank" rel="noopener noreferrer" className="text-primary hover:underline">
                      Договор оферты
                    </a>{" "}
                    и{" "}
                    <a href="/docs/privacy-policy" target="_blank" rel="noopener noreferrer" className="text-primary hover:underline">
                      Политику конфиденциальности
                    </a>
                  </Label>
                </div>
              </div>

              {/* Submit Button */}
              <Button 
                type="submit"
                className="w-full hero-gradient border-0" 
                size="lg"
                disabled={!acceptTerms || loading}
              >
                {loading ? "Регистрация..." : "Создать аккаунт"}
              </Button>
            </form>

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