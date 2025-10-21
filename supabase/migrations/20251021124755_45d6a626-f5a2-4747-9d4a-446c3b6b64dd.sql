-- Finance tables with IF NOT EXISTS checks

-- Create enums if they don't exist
DO $$ BEGIN
  CREATE TYPE transaction_type AS ENUM ('commission', 'bonus', 'withdrawal', 'adjustment', 'purchase');
EXCEPTION
  WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
  CREATE TYPE transaction_status AS ENUM ('pending', 'processing', 'completed', 'failed', 'frozen');
EXCEPTION
  WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
  CREATE TYPE withdrawal_status AS ENUM ('pending', 'processing', 'completed', 'failed', 'cancelled');
EXCEPTION
  WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
  CREATE TYPE payment_method_type AS ENUM ('card', 'bank', 'crypto', 'other');
EXCEPTION
  WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
  CREATE TYPE structure_type AS ENUM ('primary', 'secondary');
EXCEPTION
  WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
  CREATE TYPE auto_withdraw_schedule AS ENUM ('daily', 'weekly', 'monthly');
EXCEPTION
  WHEN duplicate_object THEN null;
END $$;

-- Transactions table
CREATE TABLE IF NOT EXISTS public.transactions (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL,
  type transaction_type NOT NULL,
  amount_cents BIGINT NOT NULL,
  currency TEXT NOT NULL DEFAULT 'USD',
  status transaction_status NOT NULL DEFAULT 'pending',
  source_id UUID,
  source_ref TEXT,
  level INTEGER,
  structure_type structure_type DEFAULT 'primary',
  payload JSONB DEFAULT '{}'::jsonb,
  frozen_until TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  CONSTRAINT unique_source_ref UNIQUE (source_ref)
);

CREATE INDEX IF NOT EXISTS idx_transactions_user_id ON public.transactions(user_id);
CREATE INDEX IF NOT EXISTS idx_transactions_status ON public.transactions(status);
CREATE INDEX IF NOT EXISTS idx_transactions_type ON public.transactions(type);
CREATE INDEX IF NOT EXISTS idx_transactions_created_at ON public.transactions(created_at);
CREATE INDEX IF NOT EXISTS idx_transactions_frozen_until ON public.transactions(frozen_until);

-- Withdrawals table
CREATE TABLE IF NOT EXISTS public.withdrawals (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL,
  method_id UUID,
  amount_cents BIGINT NOT NULL,
  fee_cents BIGINT NOT NULL DEFAULT 0,
  status withdrawal_status NOT NULL DEFAULT 'pending',
  transaction_id UUID REFERENCES public.transactions(id),
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  processed_at TIMESTAMP WITH TIME ZONE
);

CREATE INDEX IF NOT EXISTS idx_withdrawals_user_id ON public.withdrawals(user_id);
CREATE INDEX IF NOT EXISTS idx_withdrawals_status ON public.withdrawals(status);

-- Payment methods table
CREATE TABLE IF NOT EXISTS public.payment_methods (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL,
  type payment_method_type NOT NULL,
  masked TEXT NOT NULL,
  meta JSONB DEFAULT '{}'::jsonb,
  is_default BOOLEAN DEFAULT false,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_payment_methods_user_id ON public.payment_methods(user_id);

-- Auto-withdraw rules table
CREATE TABLE IF NOT EXISTS public.auto_withdraw_rules (
  user_id UUID NOT NULL PRIMARY KEY,
  enabled BOOLEAN DEFAULT false,
  threshold_cents BIGINT NOT NULL DEFAULT 10000,
  schedule auto_withdraw_schedule NOT NULL DEFAULT 'weekly',
  min_amount_cents BIGINT NOT NULL DEFAULT 5000,
  method_id UUID REFERENCES public.payment_methods(id),
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Commission plan levels table
CREATE TABLE IF NOT EXISTS public.commission_plan_levels (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  plan_id TEXT NOT NULL DEFAULT 'default',
  structure_type structure_type NOT NULL DEFAULT 'primary',
  level INTEGER NOT NULL CHECK (level >= 1 AND level <= 10),
  percent NUMERIC NOT NULL CHECK (percent >= 0 AND percent <= 100),
  description TEXT,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  CONSTRAINT unique_plan_structure_level UNIQUE (plan_id, structure_type, level)
);

-- Insert default commission structures only if table is empty
INSERT INTO public.commission_plan_levels (plan_id, structure_type, level, percent, description)
SELECT 'default', 'primary', 1, 25, 'Прямые рефералы'
WHERE NOT EXISTS (SELECT 1 FROM public.commission_plan_levels WHERE plan_id = 'default' AND structure_type = 'primary' AND level = 1);

INSERT INTO public.commission_plan_levels (plan_id, structure_type, level, percent, description)
SELECT 'default', 'primary', n, 
  CASE 
    WHEN n = 2 THEN 15
    WHEN n = 3 THEN 10
    WHEN n = 4 THEN 8
    WHEN n = 5 THEN 5
    WHEN n = 6 THEN 4
    WHEN n = 7 THEN 3
    WHEN n = 8 THEN 2
    WHEN n = 9 THEN 1.5
    WHEN n = 10 THEN 1
  END,
  CASE 
    WHEN n = 2 THEN 'Второй уровень'
    WHEN n = 3 THEN 'Третий уровень'
    WHEN n = 4 THEN 'Четвёртый уровень'
    WHEN n = 5 THEN 'Пятый уровень'
    WHEN n = 6 THEN 'Шестой уровень'
    WHEN n = 7 THEN 'Седьмой уровень'
    WHEN n = 8 THEN 'Восьмой уровень'
    WHEN n = 9 THEN 'Девятый уровень'
    WHEN n = 10 THEN 'Десятый уровень'
  END
FROM generate_series(2, 10) AS n
WHERE NOT EXISTS (SELECT 1 FROM public.commission_plan_levels WHERE plan_id = 'default' AND structure_type = 'primary' AND level = n);

-- Insert secondary structure levels
INSERT INTO public.commission_plan_levels (plan_id, structure_type, level, percent, description)
SELECT 'default', 'secondary', n, 
  CASE 
    WHEN n = 1 THEN 20
    WHEN n = 2 THEN 12
    WHEN n = 3 THEN 8
    WHEN n = 4 THEN 6
    WHEN n = 5 THEN 4
    WHEN n = 6 THEN 3
    WHEN n = 7 THEN 2
    WHEN n = 8 THEN 1.5
    WHEN n = 9 THEN 1
    WHEN n = 10 THEN 0.5
  END,
  CASE 
    WHEN n = 1 THEN 'Прямые рефералы (2-я структура)'
    WHEN n = 2 THEN 'Второй уровень (2-я структура)'
    WHEN n = 3 THEN 'Третий уровень (2-я структура)'
    WHEN n = 4 THEN 'Четвёртый уровень (2-я структура)'
    WHEN n = 5 THEN 'Пятый уровень (2-я структура)'
    WHEN n = 6 THEN 'Шестой уровень (2-я структура)'
    WHEN n = 7 THEN 'Седьмой уровень (2-я структура)'
    WHEN n = 8 THEN 'Восьмой уровень (2-я структура)'
    WHEN n = 9 THEN 'Девятый уровень (2-я структура)'
    WHEN n = 10 THEN 'Десятый уровень (2-я структура)'
  END
FROM generate_series(1, 10) AS n
WHERE NOT EXISTS (SELECT 1 FROM public.commission_plan_levels WHERE plan_id = 'default' AND structure_type = 'secondary' AND level = n);

-- Balance view
CREATE OR REPLACE VIEW public.user_balances AS
SELECT 
  p.id as user_id,
  COALESCE(SUM(CASE 
    WHEN t.type IN ('commission', 'bonus') AND t.status = 'completed' AND (t.frozen_until IS NULL OR t.frozen_until <= NOW())
    THEN t.amount_cents 
    WHEN t.type IN ('withdrawal', 'purchase', 'adjustment') AND t.status = 'completed'
    THEN -t.amount_cents
    ELSE 0 
  END), 0) as available_cents,
  COALESCE(SUM(CASE 
    WHEN t.type IN ('commission', 'bonus') AND t.status = 'completed' AND t.frozen_until > NOW()
    THEN t.amount_cents 
    ELSE 0 
  END), 0) as frozen_cents,
  COALESCE(SUM(CASE 
    WHEN t.type IN ('commission', 'bonus') AND t.status IN ('pending', 'processing')
    THEN t.amount_cents 
    ELSE 0 
  END), 0) as pending_cents,
  COALESCE(SUM(CASE 
    WHEN t.type = 'withdrawal' AND t.status = 'completed'
    THEN t.amount_cents 
    ELSE 0 
  END), 0) as withdrawn_cents,
  NOW() as updated_at
FROM public.profiles p
LEFT JOIN public.transactions t ON t.user_id = p.id
GROUP BY p.id;

-- Enable RLS
ALTER TABLE public.transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.withdrawals ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payment_methods ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.auto_withdraw_rules ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.commission_plan_levels ENABLE ROW LEVEL SECURITY;

-- RLS Policies
DROP POLICY IF EXISTS "Users can view their own transactions" ON public.transactions;
CREATE POLICY "Users can view their own transactions"
  ON public.transactions FOR SELECT
  USING (auth.uid() = user_id OR has_role(auth.uid(), 'admin'::app_role) OR has_role(auth.uid(), 'superadmin'::app_role));

DROP POLICY IF EXISTS "System can insert transactions" ON public.transactions;
CREATE POLICY "System can insert transactions"
  ON public.transactions FOR INSERT
  WITH CHECK (true);

DROP POLICY IF EXISTS "System can update transactions" ON public.transactions;
CREATE POLICY "System can update transactions"
  ON public.transactions FOR UPDATE
  USING (true);

DROP POLICY IF EXISTS "Users can view their own withdrawals" ON public.withdrawals;
CREATE POLICY "Users can view their own withdrawals"
  ON public.withdrawals FOR SELECT
  USING (auth.uid() = user_id OR has_role(auth.uid(), 'admin'::app_role) OR has_role(auth.uid(), 'superadmin'::app_role));

DROP POLICY IF EXISTS "Users can create their own withdrawals" ON public.withdrawals;
CREATE POLICY "Users can create their own withdrawals"
  ON public.withdrawals FOR INSERT
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Admins can update withdrawals" ON public.withdrawals;
CREATE POLICY "Admins can update withdrawals"
  ON public.withdrawals FOR UPDATE
  USING (has_role(auth.uid(), 'admin'::app_role) OR has_role(auth.uid(), 'superadmin'::app_role));

DROP POLICY IF EXISTS "Users can manage their own payment methods" ON public.payment_methods;
CREATE POLICY "Users can manage their own payment methods"
  ON public.payment_methods FOR ALL
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can manage their own auto-withdraw rules" ON public.auto_withdraw_rules;
CREATE POLICY "Users can manage their own auto-withdraw rules"
  ON public.auto_withdraw_rules FOR ALL
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Anyone can view commission plans" ON public.commission_plan_levels;
CREATE POLICY "Anyone can view commission plans"
  ON public.commission_plan_levels FOR SELECT
  USING (true);

DROP POLICY IF EXISTS "Admins can manage commission plans" ON public.commission_plan_levels;
CREATE POLICY "Admins can manage commission plans"
  ON public.commission_plan_levels FOR ALL
  USING (has_role(auth.uid(), 'admin'::app_role) OR has_role(auth.uid(), 'superadmin'::app_role));

-- Triggers
DROP TRIGGER IF EXISTS update_transactions_updated_at ON public.transactions;
CREATE TRIGGER update_transactions_updated_at
  BEFORE UPDATE ON public.transactions
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

DROP TRIGGER IF EXISTS update_payment_methods_updated_at ON public.payment_methods;
CREATE TRIGGER update_payment_methods_updated_at
  BEFORE UPDATE ON public.payment_methods
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

DROP TRIGGER IF EXISTS update_auto_withdraw_rules_updated_at ON public.auto_withdraw_rules;
CREATE TRIGGER update_auto_withdraw_rules_updated_at
  BEFORE UPDATE ON public.auto_withdraw_rules
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

-- Commission creation function
CREATE OR REPLACE FUNCTION public.create_commission_transactions()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  order_total_cents BIGINT;
  current_level INTEGER := 1;
  current_user_id UUID;
  commission_percent NUMERIC;
  commission_amount_cents BIGINT;
  hold_days INTEGER := 7;
BEGIN
  IF NEW.status = 'paid' AND (OLD.status IS NULL OR OLD.status != 'paid') THEN
    SELECT (total_usd * 100)::BIGINT INTO order_total_cents FROM orders WHERE id = NEW.id;
    current_user_id := NEW.user_id;
    
    WHILE current_level <= 10 AND current_user_id IS NOT NULL LOOP
      SELECT sponsor_id INTO current_user_id FROM profiles WHERE id = current_user_id;
      
      IF current_user_id IS NOT NULL THEN
        SELECT percent INTO commission_percent 
        FROM commission_plan_levels 
        WHERE plan_id = 'default' 
          AND structure_type = 'primary' 
          AND level = current_level;
        
        IF commission_percent IS NOT NULL AND commission_percent > 0 THEN
          commission_amount_cents := (order_total_cents * commission_percent / 100)::BIGINT;
          
          INSERT INTO transactions (
            user_id, type, amount_cents, status, source_id, source_ref,
            level, structure_type, frozen_until, payload
          ) VALUES (
            current_user_id, 'commission', commission_amount_cents, 'completed',
            NEW.id, 'order_' || NEW.id || '_level_' || current_level || '_primary',
            current_level, 'primary', NOW() + (hold_days || ' days')::INTERVAL,
            jsonb_build_object('order_id', NEW.id, 'buyer_id', NEW.user_id, 'level', current_level, 'structure', 'primary', 'percent', commission_percent)
          ) ON CONFLICT (source_ref) DO NOTHING;
        END IF;
        
        current_level := current_level + 1;
      END IF;
    END LOOP;
  END IF;
  
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS create_commissions_on_payment ON public.orders;
CREATE TRIGGER create_commissions_on_payment
  AFTER UPDATE ON public.orders
  FOR EACH ROW
  EXECUTE FUNCTION public.create_commission_transactions();