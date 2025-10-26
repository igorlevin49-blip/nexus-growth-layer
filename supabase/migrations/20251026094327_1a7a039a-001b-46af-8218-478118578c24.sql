-- Создание таблицы конфигурации комиссий MLM
CREATE TABLE IF NOT EXISTS public.mlm_commission_rules (
  id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  structure_type integer NOT NULL CHECK (structure_type IN (1, 2)),
  level integer NOT NULL CHECK (level >= 1 AND level <= 10),
  percent numeric(6,3) NOT NULL CHECK (percent >= 0 AND percent <= 100),
  plan_id text NOT NULL DEFAULT 'default',
  effective_from timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (structure_type, plan_id, level, effective_from)
);

-- Enable RLS
ALTER TABLE public.mlm_commission_rules ENABLE ROW LEVEL SECURITY;

-- Политики RLS для mlm_commission_rules
CREATE POLICY "Anyone can view commission rules"
  ON public.mlm_commission_rules
  FOR SELECT
  USING (true);

CREATE POLICY "Superadmins can manage commission rules"
  ON public.mlm_commission_rules
  FOR ALL
  USING (has_role(auth.uid(), 'superadmin'::app_role));

-- Заполнение начальных данных для Структуры 1 (Абонентская - 5 уровней)
INSERT INTO public.mlm_commission_rules (structure_type, level, percent, plan_id) VALUES
  (1, 1, 20.000, 'default'),  -- L1: 20%
  (1, 2, 15.000, 'default'),  -- L2: 15%
  (1, 3, 10.000, 'default'),  -- L3: 10%
  (1, 4, 7.000, 'default'),   -- L4: 7%
  (1, 5, 5.000, 'default')    -- L5: 5%
ON CONFLICT (structure_type, plan_id, level, effective_from) DO NOTHING;

-- Заполнение начальных данных для Структуры 2 (Товарная - 10 уровней)
INSERT INTO public.mlm_commission_rules (structure_type, level, percent, plan_id) VALUES
  (2, 1, 10.000, 'default'),  -- L1: 10%
  (2, 2, 5.000, 'default'),   -- L2: 5%
  (2, 3, 5.000, 'default'),   -- L3: 5%
  (2, 4, 5.000, 'default'),   -- L4: 5%
  (2, 5, 5.000, 'default'),   -- L5: 5%
  (2, 6, 5.000, 'default'),   -- L6: 5%
  (2, 7, 5.000, 'default'),   -- L7: 5%
  (2, 8, 5.000, 'default'),   -- L8: 5%
  (2, 9, 5.000, 'default'),   -- L9: 5%
  (2, 10, 10.000, 'default')  -- L10: 10%
ON CONFLICT (structure_type, plan_id, level, effective_from) DO NOTHING;

-- Добавление полей подписки в profiles (если их еще нет)
DO $$ 
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='profiles' AND column_name='subscription_active') THEN
    ALTER TABLE public.profiles ADD COLUMN subscription_active boolean DEFAULT false;
  END IF;
  
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='profiles' AND column_name='subscription_expires_at') THEN
    ALTER TABLE public.profiles ALTER COLUMN subscription_expires_at TYPE timestamptz;
  END IF;
  
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='profiles' AND column_name='direct_referrals_count') THEN
    ALTER TABLE public.profiles ADD COLUMN direct_referrals_count integer DEFAULT 0;
  END IF;
END $$;

-- Функция для подсчета прямых рефералов
CREATE OR REPLACE FUNCTION update_direct_referrals_count()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.sponsor_id IS NOT NULL THEN
    UPDATE profiles 
    SET direct_referrals_count = (
      SELECT COUNT(*) FROM profiles WHERE sponsor_id = NEW.sponsor_id
    )
    WHERE id = NEW.sponsor_id;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- Триггер для автоматического подсчета прямых рефералов
DROP TRIGGER IF EXISTS trigger_update_direct_referrals ON public.profiles;
CREATE TRIGGER trigger_update_direct_referrals
  AFTER INSERT OR UPDATE OF sponsor_id ON public.profiles
  FOR EACH ROW
  EXECUTE FUNCTION update_direct_referrals_count();