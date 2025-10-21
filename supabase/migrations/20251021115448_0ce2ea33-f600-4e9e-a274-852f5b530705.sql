-- Create activity_log table for network activity tracking
CREATE TABLE IF NOT EXISTS public.activity_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  type TEXT NOT NULL CHECK (type IN ('invite', 'activation', 'freeze', 'unfreeze', 'purchase', 'registration')),
  payload JSONB,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Add avatar_url to profiles if it doesn't exist
DO $$ 
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'public' 
    AND table_name = 'profiles' 
    AND column_name = 'avatar_url'
  ) THEN
    ALTER TABLE public.profiles ADD COLUMN avatar_url TEXT;
  END IF;
END $$;

-- Enable RLS on activity_log
ALTER TABLE public.activity_log ENABLE ROW LEVEL SECURITY;

-- RLS policies for activity_log
CREATE POLICY "Users can view activity in their network"
ON public.activity_log
FOR SELECT
USING (
  user_id = auth.uid() OR
  EXISTS (
    WITH RECURSIVE network AS (
      SELECT id, sponsor_id FROM public.profiles WHERE id = auth.uid()
      UNION ALL
      SELECT p.id, p.sponsor_id 
      FROM public.profiles p
      INNER JOIN network n ON p.sponsor_id = n.id
    )
    SELECT 1 FROM network WHERE network.id = activity_log.user_id
  ) OR
  has_role(auth.uid(), 'admin'::app_role) OR
  has_role(auth.uid(), 'superadmin'::app_role)
);

CREATE POLICY "System can insert activity"
ON public.activity_log
FOR INSERT
WITH CHECK (true);

-- Create function to get network tree with levels
CREATE OR REPLACE FUNCTION public.get_network_tree(
  root_user_id UUID,
  max_level INTEGER DEFAULT 8
)
RETURNS TABLE (
  user_id UUID,
  partner_id UUID,
  level INTEGER,
  full_name TEXT,
  email TEXT,
  avatar_url TEXT,
  subscription_status TEXT,
  monthly_activation_met BOOLEAN,
  referral_code TEXT,
  created_at TIMESTAMP WITH TIME ZONE,
  direct_referrals INTEGER,
  total_team INTEGER,
  monthly_volume NUMERIC
) 
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  WITH RECURSIVE network AS (
    -- Root user
    SELECT 
      root_user_id as user_id,
      p.id as partner_id,
      0 as level,
      p.full_name,
      p.email,
      p.avatar_url,
      p.subscription_status,
      p.monthly_activation_met,
      p.referral_code,
      p.created_at
    FROM public.profiles p
    WHERE p.id = root_user_id
    
    UNION ALL
    
    -- Recursive: children
    SELECT
      root_user_id as user_id,
      p.id as partner_id,
      n.level + 1 as level,
      p.full_name,
      p.email,
      p.avatar_url,
      p.subscription_status,
      p.monthly_activation_met,
      p.referral_code,
      p.created_at
    FROM public.profiles p
    INNER JOIN network n ON p.sponsor_id = n.partner_id
    WHERE n.level < max_level
  ),
  stats AS (
    SELECT 
      n.partner_id,
      COUNT(DISTINCT CASE WHEN p.sponsor_id = n.partner_id THEN p.id END) as direct_refs,
      COUNT(DISTINCT p2.id) as total_team_count,
      COALESCE(SUM(CASE 
        WHEN o.status = 'paid' 
        AND DATE_TRUNC('month', o.created_at) = DATE_TRUNC('month', NOW())
        THEN oi.price_usd * oi.qty 
      END), 0) as monthly_vol
    FROM network n
    LEFT JOIN public.profiles p ON p.sponsor_id = n.partner_id
    LEFT JOIN LATERAL (
      WITH RECURSIVE sub_network AS (
        SELECT id FROM public.profiles WHERE sponsor_id = n.partner_id
        UNION ALL
        SELECT p.id FROM public.profiles p
        INNER JOIN sub_network sn ON p.sponsor_id = sn.id
      )
      SELECT id FROM sub_network
    ) p2 ON true
    LEFT JOIN public.orders o ON o.user_id = p2.id
    LEFT JOIN public.order_items oi ON oi.order_id = o.id
    GROUP BY n.partner_id
  )
  SELECT 
    n.user_id,
    n.partner_id,
    n.level,
    n.full_name,
    n.email,
    n.avatar_url,
    n.subscription_status,
    n.monthly_activation_met,
    n.referral_code,
    n.created_at,
    COALESCE(s.direct_refs, 0)::INTEGER as direct_referrals,
    COALESCE(s.total_team_count, 0)::INTEGER as total_team,
    COALESCE(s.monthly_vol, 0) as monthly_volume
  FROM network n
  LEFT JOIN stats s ON s.partner_id = n.partner_id
  WHERE n.level > 0
  ORDER BY n.level, n.created_at;
END;
$$;

-- Create function to get network statistics
CREATE OR REPLACE FUNCTION public.get_network_stats(user_id_param UUID)
RETURNS TABLE (
  total_partners INTEGER,
  active_partners INTEGER,
  frozen_partners INTEGER,
  max_level INTEGER,
  new_this_month INTEGER,
  activations_this_month INTEGER,
  volume_this_month NUMERIC,
  commissions_this_month NUMERIC
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  WITH network AS (
    SELECT * FROM public.get_network_tree(user_id_param, 8)
  ),
  month_start AS (
    SELECT DATE_TRUNC('month', NOW()) as start_date
  )
  SELECT 
    COUNT(DISTINCT n.partner_id)::INTEGER as total_partners,
    COUNT(DISTINCT CASE 
      WHEN n.subscription_status = 'active' OR n.monthly_activation_met = true 
      THEN n.partner_id 
    END)::INTEGER as active_partners,
    COUNT(DISTINCT CASE 
      WHEN n.subscription_status = 'frozen' 
      THEN n.partner_id 
    END)::INTEGER as frozen_partners,
    COALESCE(MAX(n.level), 0)::INTEGER as max_level,
    COUNT(DISTINCT CASE 
      WHEN n.created_at >= (SELECT start_date FROM month_start)
      THEN n.partner_id 
    END)::INTEGER as new_this_month,
    COALESCE(SUM(CASE 
      WHEN o.status = 'paid' 
      AND oi.is_activation_snapshot = true
      AND o.created_at >= (SELECT start_date FROM month_start)
      THEN oi.qty 
    END), 0)::INTEGER as activations_this_month,
    COALESCE(SUM(CASE 
      WHEN o.status = 'paid'
      AND o.created_at >= (SELECT start_date FROM month_start)
      THEN oi.price_usd * oi.qty 
    END), 0) as volume_this_month,
    0::NUMERIC as commissions_this_month
  FROM network n
  LEFT JOIN public.orders o ON o.user_id = n.partner_id
  LEFT JOIN public.order_items oi ON oi.order_id = o.id;
END;
$$;

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_activity_log_user_id ON public.activity_log(user_id);
CREATE INDEX IF NOT EXISTS idx_activity_log_type ON public.activity_log(type);
CREATE INDEX IF NOT EXISTS idx_activity_log_created_at ON public.activity_log(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_profiles_sponsor_id ON public.profiles(sponsor_id);
CREATE INDEX IF NOT EXISTS idx_profiles_subscription_status ON public.profiles(subscription_status);
CREATE INDEX IF NOT EXISTS idx_profiles_referral_code ON public.profiles(referral_code);

-- Trigger to log registration activity
CREATE OR REPLACE FUNCTION public.log_registration_activity()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.activity_log (user_id, type, payload)
  VALUES (
    NEW.id, 
    'registration',
    jsonb_build_object(
      'full_name', NEW.full_name,
      'email', NEW.email,
      'sponsor_id', NEW.sponsor_id
    )
  );
  RETURN NEW;
END;
$$;

CREATE TRIGGER on_profile_created
  AFTER INSERT ON public.profiles
  FOR EACH ROW
  EXECUTE FUNCTION public.log_registration_activity();

-- Trigger to log activation activity
CREATE OR REPLACE FUNCTION public.log_activation_activity()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  activation_amount NUMERIC;
BEGIN
  IF NEW.status = 'paid' AND OLD.status != 'paid' THEN
    SELECT COALESCE(SUM(oi.price_usd * oi.qty), 0) INTO activation_amount
    FROM order_items oi
    WHERE oi.order_id = NEW.id AND oi.is_activation_snapshot = true;
    
    IF activation_amount > 0 THEN
      INSERT INTO public.activity_log (user_id, type, payload)
      VALUES (
        NEW.user_id,
        'activation',
        jsonb_build_object('amount', activation_amount, 'order_id', NEW.id)
      );
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER on_order_paid
  AFTER UPDATE ON public.orders
  FOR EACH ROW
  WHEN (NEW.status = 'paid' AND OLD.status IS DISTINCT FROM 'paid')
  EXECUTE FUNCTION public.log_activation_activity();