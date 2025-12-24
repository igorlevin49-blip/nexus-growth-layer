import { useState, useEffect } from "react";
import { Eye, EyeOff, UserPlus } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Checkbox } from "@/components/ui/checkbox";
import { useNavigate, useSearchParams, Link } from "react-router-dom";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "sonner";
import { useAuth } from "@/hooks/useAuth";
import { APP_CONFIG } from "@/config/constants";
import { setCookie, getCookie, deleteCookie } from "@/utils/cookies";
import { Loader } from "@/components/ui/loader";

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
  const { user, loading: authLoading } = useAuth();
  const [searchParams] = useSearchParams();

  // Get referral code from URL or cookie (REQUIRED)
  useEffect(() => {
    const refFromUrl = searchParams.get('ref');
    const refFromCookie = getCookie(APP_CONFIG.REFERRAL_COOKIE_KEY);
    
    if (refFromUrl) {
      setReferralCode(refFromUrl);
      setCookie(APP_CONFIG.REFERRAL_COOKIE_KEY, refFromUrl, APP_CONFIG.REFERRAL_COOKIE_EXPIRY_DAYS);
    } else if (refFromCookie) {
      setReferralCode(refFromCookie);
    }
  }, [searchParams]);

  // Show loader while checking auth state
  if (authLoading) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-background">
        <Loader />
      </div>
    );
  }

  // Redirect if already logged in
  if (user) {
    navigate('/dashboard');
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
    if (!phone) return true; // Optional field
    // Remove all non-digit characters
    const cleaned = phone.replace(/\D/g, '');
    // E.164 format: 7-15 digits (without +)
    return cleaned.length >= 7 && cleaned.length <= 15;
  };

  const normalizePhone = (phone: string): string => {
    // Remove all non-digit characters
    const cleaned = phone.replace(/\D/g, '');
    return '+' + cleaned;
  };

  const handleRegister = async (e: React.FormEvent) => {
    e.preventDefault();

    // CRITICAL: Validate referral code is present
    if (!referralCode || !referralCode.trim()) {
      toast.error("Регистрация возможна только по приглашению партнёра", {
        description: "Попросите вашего партнёра прислать вам реферальную ссылку",
      });
      return;
    }

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
      toast.error("Введите номер телефона в международном формате (например, +7XXXXXXXXXX или +996XXXXXXXXX)");
      return;
    }

    // Validate full name
    if (fullName.length < 2 || fullName.length > 128) {
      toast.error("Имя должно быть от 2 до 128 символов");
      return;
    }

    setLoading(true);

    try {
      // SINGLE SOURCE OF TRUTH: Validate referral code first
      console.log('[REGISTER] Validating referral code:', referralCode.trim());
      
      const { data: validationData, error: validationError } = await (supabase.rpc as any)('validate_referral_code', {
        p_ref_code: referralCode.trim()
      });

      if (validationError) {
        console.error('[REGISTER] Validation error:', validationError);
        throw new Error("Ошибка проверки кода приглашения");
      }

      const validation = validationData as { valid?: boolean; error?: string; sponsor_name?: string } | null;
      
      if (!validation?.valid) {
        console.error('[REGISTER] Invalid referral code:', validation?.error);
        const errorMessages: Record<string, string> = {
          'EMPTY_CODE': 'Код приглашения не может быть пустым',
          'INVALID_CODE': 'Код приглашения не найден или недействителен',
        };
        throw new Error(errorMessages[validation?.error || ''] || 'Регистрация возможна только по приглашению партнёра');
      }

      console.log('[REGISTER] Referral code validated. Sponsor:', validation.sponsor_name);

      // Create account with inviter_ref_code in metadata for backend trigger
      const redirectUrl = `${APP_CONFIG.DOMAIN}/login?ref=${encodeURIComponent(referralCode.trim())}`;
      const trimmedReferralCode = referralCode.trim();

      console.log('[REGISTER] Creating user account...');
      
      const { data: authData, error: signUpError } = await supabase.auth.signUp({
        email,
        password,
        options: {
          emailRedirectTo: redirectUrl,
          data: {
            full_name: fullName,
            inviter_ref_code: trimmedReferralCode, // CRITICAL: Backend trigger uses this
          },
        },
      });

      if (signUpError) {
        console.error('[REGISTER] SignUp error:', signUpError);
        throw signUpError;
      }

      console.log('[REGISTER] User created:', authData.user?.id);

      // Update profile with additional data
      if (authData.user) {
        const updateData: any = {
          full_name: fullName,
        };
        
        if (phone) {
          updateData.phone = normalizePhone(phone);
        }

        console.log('[REGISTER] Updating profile data...');
        
        await supabase
          .from('profiles')
          .update(updateData)
          .eq('id', authData.user.id);

        // CRITICAL: Explicit bind_referral call (backup if trigger fails)
        console.log('[REGISTER] Binding referral explicitly...');
        
        const { data: bindResult, error: bindError } = await supabase.rpc('bind_referral', {
          p_ref_code: trimmedReferralCode
        });

        if (bindError) {
          console.error('[REGISTER] Bind referral error:', bindError);
          // Don't block registration - trigger should have handled it
          toast.warning("Предупреждение", {
            description: "Регистрация завершена, но проверьте привязку спонсора в личном кабинете",
          });
        } else {
          const result = bindResult as { success?: boolean; error?: string; sponsor_name?: string } | null;
          console.log('[REGISTER] Bind result:', result);
          
          if (result?.success) {
            deleteCookie(APP_CONFIG.REFERRAL_COOKIE_KEY);
            
            toast.success("Регистрация успешна!", {
              description: `Пригласивший: ${result.sponsor_name || validation.sponsor_name}`,
            });
          }
        }
      }

      console.log('[REGISTER] Registration complete. Redirecting to dashboard...');
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
              Создайте аккаунт в MG-market и начните зарабатывать
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
                  value={phone}
                  onChange={(e) => setPhone(e.target.value)}
                  placeholder="Введите номер в международном формате +XXX..."
                />
                <p className="text-xs text-muted-foreground">
                  Например: +77001234567, +996555123456
                </p>
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

              {/* Referral Code - REQUIRED */}
              <div className="space-y-2">
                <Label htmlFor="referralCode">Код приглашения *</Label>
                <Input
                  id="referralCode"
                  placeholder="Обязательно: код приглашения от партнёра"
                  value={referralCode}
                  onChange={(e) => setReferralCode(e.target.value)}
                  required
                />
                {referralCode ? (
                  <p className="text-xs text-primary">
                    ✓ Код приглашения введён
                  </p>
                ) : (
                  <p className="text-xs text-destructive">
                    Регистрация возможна только по приглашению партнёра
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
                <Link to="/login" className="text-primary hover:underline font-medium">
                  Войти
                </Link>
              </div>
            </div>
          </CardContent>
        </Card>
      </div>
    </div>
  );
}