-- Finance tables for transaction tracking, balances, withdrawals, and commissions

-- Transaction types enum
CREATE TYPE transaction_type AS ENUM ('commission', 'bonus', 'withdrawal', 'adjustment', 'purchase');

-- Transaction status enum
CREATE TYPE transaction_status AS ENUM ('pending', 'processing', 'completed', 'failed', 'frozen');

-- Withdrawal status enum
CREATE TYPE withdrawal_status AS ENUM ('pending', 'processing', 'completed', 'failed', 'cancelled');

-- Payment method types
CREATE TYPE payment_method_type AS ENUM ('card', 'bank', 'crypto', 'other');

-- Structure types for dual structure support
CREATE TYPE structure_type AS ENUM ('primary', 'secondary');

-- Auto-withdraw schedule
CREATE TYPE auto_withdraw_schedule AS ENUM ('daily', 'weekly', 'monthly');

-- Transactions table
CREATE TABLE public.transactions (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
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

CREATE INDEX idx_transactions_user_id ON public.transactions(user_id);
CREATE INDEX idx_transactions_status ON public.transactions(status);
CREATE INDEX idx_transactions_type ON public.transactions(type);
CREATE INDEX idx_transactions_created_at ON public.transactions(created_at);
CREATE INDEX idx_transactions_frozen_until ON public.transactions(frozen_until);

-- Withdrawals table
CREATE TABLE public.withdrawals (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  method_id UUID,
  amount_cents BIGINT NOT NULL,
  fee_cents BIGINT NOT NULL DEFAULT 0,
  status withdrawal_status NOT NULL DEFAULT 'pending',
  transaction_id UUID REFERENCES public.transactions(id),
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  processed_at TIMESTAMP WITH TIME ZONE
);

CREATE INDEX idx_withdrawals_user_id ON public.withdrawals(user_id);
CREATE INDEX idx_withdrawals_status ON public.withdrawals(status);

-- Payment methods table
CREATE TABLE public.payment_methods (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  type payment_method_type NOT NULL,
  masked TEXT NOT NULL,
  meta JSONB DEFAULT '{}'::jsonb,
  is_default BOOLEAN DEFAULT false,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

CREATE INDEX idx_payment_methods_user_id ON public.payment_methods(user_id);

-- Auto-withdraw rules table
CREATE TABLE public.auto_withdraw_rules (
  user_id UUID NOT NULL PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  enabled BOOLEAN DEFAULT false,
  threshold_cents BIGINT NOT NULL DEFAULT 10000,
  schedule auto_withdraw_schedule NOT NULL DEFAULT 'weekly',
  min_amount_cents BIGINT NOT NULL DEFAULT 5000,
  method_id UUID REFERENCES public.payment_methods(id),
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Commission plan levels table (supports both primary and secondary structures)
CREATE TABLE public.commission_plan_levels (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  plan_id TEXT NOT NULL DEFAULT 'default',
  structure_type structure_type NOT NULL DEFAULT 'primary',
  level INTEGER NOT NULL CHECK (level >= 1 AND level <= 10),
  percent NUMERIC NOT NULL CHECK (percent >= 0 AND percent <= 100),
  description TEXT,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  CONSTRAINT unique_plan_structure_level UNIQUE (plan_id, structure_type, level)
);

-- Insert default commission structure for primary structure (levels 1-10)
INSERT INTO public.commission_plan_levels (plan_id, structure_type, level, percent, description) VALUES
('default', 'primary', 1, 25, 'Прямые рефералы'),
('default', 'primary', 2, 15, 'Второй уровень'),
('default', 'primary', 3, 10, 'Третий уровень'),
('default', 'primary', 4, 8, 'Четвёртый уровень'),
('default', 'primary', 5, 5, 'Пятый уровень'),
('default', 'primary', 6, 4, 'Шестой уровень'),
('default', 'primary', 7, 3, 'Седьмой уровень'),
('default', 'primary', 8, 2, 'Восьмой уровень'),
('default', 'primary', 9, 1.5, 'Девятый уровень'),
('default', 'primary', 10, 1, 'Десятый уровень');

-- Insert default commission structure for secondary structure (levels 1-10)
INSERT INTO public.commission_plan_levels (plan_id, structure_type, level, percent, description) VALUES
('default', 'secondary', 1, 20, 'Прямые рефералы (2-я структура)'),
('default', 'secondary', 2, 12, 'Второй уровень (2-я структура)'),
('default', 'secondary', 3, 8, 'Третий уровень (2-я структура)'),
('default', 'secondary', 4, 6, 'Четвёртый уровень (2-я структура)'),
('default', 'secondary', 5, 4, 'Пятый уровень (2-я структура)'),
('default', 'secondary', 6, 3, 'Шестой уровень (2-я структура)'),
('default', 'secondary', 7, 2, 'Седьмой уровень (2-я структура)'),
('default', 'secondary', 8, 1.5, 'Восьмой уровень (2-я структура)'),
('default', 'secondary', 9, 1, 'Девятый уровень (2-я структура)'),
('default', 'secondary', 10, 0.5, 'Десятый уровень (2-я структура)');

-- Balance calculation view
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

-- RLS Policies for transactions
CREATE POLICY "Users can view their own transactions"
  ON public.transactions FOR SELECT
  USING (auth.uid() = user_id OR has_role(auth.uid(), 'admin') OR has_role(auth.uid(), 'superadmin'));

CREATE POLICY "System can insert transactions"
  ON public.transactions FOR INSERT
  WITH CHECK (true);

CREATE POLICY "System can update transactions"
  ON public.transactions FOR UPDATE
  USING (true);

-- RLS Policies for withdrawals
CREATE POLICY "Users can view their own withdrawals"
  ON public.withdrawals FOR SELECT
  USING (auth.uid() = user_id OR has_role(auth.uid(), 'admin') OR has_role(auth.uid(), 'superadmin'));

CREATE POLICY "Users can create their own withdrawals"
  ON public.withdrawals FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Admins can update withdrawals"
  ON public.withdrawals FOR UPDATE
  USING (has_role(auth.uid(), 'admin') OR has_role(auth.uid(), 'superadmin'));

-- RLS Policies for payment_methods
CREATE POLICY "Users can manage their own payment methods"
  ON public.payment_methods FOR ALL
  USING (auth.uid() = user_id);

-- RLS Policies for auto_withdraw_rules
CREATE POLICY "Users can manage their own auto-withdraw rules"
  ON public.auto_withdraw_rules FOR ALL
  USING (auth.uid() = user_id);

-- RLS Policies for commission_plan_levels
CREATE POLICY "Anyone can view commission plans"
  ON public.commission_plan_levels FOR SELECT
  USING (true);

CREATE POLICY "Admins can manage commission plans"
  ON public.commission_plan_levels FOR ALL
  USING (has_role(auth.uid(), 'admin') OR has_role(auth.uid(), 'superadmin'));

-- Triggers for updated_at
CREATE TRIGGER update_transactions_updated_at
  BEFORE UPDATE ON public.transactions
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER update_payment_methods_updated_at
  BEFORE UPDATE ON public.payment_methods
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER update_auto_withdraw_rules_updated_at
  BEFORE UPDATE ON public.auto_withdraw_rules
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

-- Function to create commission transaction when order is paid
CREATE OR REPLACE FUNCTION public.create_commission_transactions()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  order_total_cents BIGINT;
  sponsor_record RECORD;
  current_level INTEGER := 1;
  current_user_id UUID;
  commission_percent NUMERIC;
  commission_amount_cents BIGINT;
  hold_days INTEGER := 7;
BEGIN
  -- Only process when order status changes to 'paid'
  IF NEW.status = 'paid' AND OLD.status != 'paid' THEN
    -- Get order total in cents
    SELECT (total_usd * 100)::BIGINT INTO order_total_cents FROM orders WHERE id = NEW.id;
    
    -- Get the buyer's sponsor chain
    current_user_id := NEW.user_id;
    
    -- Traverse up to 10 levels for primary structure
    WHILE current_level <= 10 AND current_user_id IS NOT NULL LOOP
      -- Get sponsor
      SELECT sponsor_id INTO current_user_id FROM profiles WHERE id = current_user_id;
      
      IF current_user_id IS NOT NULL THEN
        -- Get commission percentage for this level (primary structure)
        SELECT percent INTO commission_percent 
        FROM commission_plan_levels 
        WHERE plan_id = 'default' 
          AND structure_type = 'primary' 
          AND level = current_level;
        
        IF commission_percent IS NOT NULL AND commission_percent > 0 THEN
          -- Calculate commission
          commission_amount_cents := (order_total_cents * commission_percent / 100)::BIGINT;
          
          -- Create transaction with freeze
          INSERT INTO transactions (
            user_id, 
            type, 
            amount_cents, 
            status, 
            source_id, 
            source_ref,
            level,
            structure_type,
            frozen_until,
            payload
          ) VALUES (
            current_user_id,
            'commission',
            commission_amount_cents,
            'completed',
            NEW.id,
            'order_' || NEW.id || '_level_' || current_level || '_primary',
            current_level,
            'primary',
            NOW() + (hold_days || ' days')::INTERVAL,
            jsonb_build_object(
              'order_id', NEW.id,
              'buyer_id', NEW.user_id,
              'level', current_level,
              'structure', 'primary',
              'percent', commission_percent
            )
          );
        END IF;
        
        current_level := current_level + 1;
      END IF;
    END LOOP;
  END IF;
  
  RETURN NEW;
END;
$$;

-- Trigger to create commissions on order payment
CREATE TRIGGER create_commissions_on_payment
  AFTER UPDATE ON public.orders
  FOR EACH ROW
  EXECUTE FUNCTION public.create_commission_transactions();