-- Create referrals table to track referral relationships
CREATE TABLE IF NOT EXISTS public.referrals (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  referrer_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  referred_user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  structure_type INTEGER NOT NULL DEFAULT 1, -- 1 = primary MLM, 2 = secondary (activation)
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  utm_source TEXT,
  utm_campaign TEXT,
  utm_medium TEXT,
  UNIQUE(referred_user_id, structure_type),
  CHECK (referrer_id != referred_user_id)
);

-- Create index for fast lookups
CREATE INDEX IF NOT EXISTS idx_referrals_referrer ON public.referrals(referrer_id, structure_type);
CREATE INDEX IF NOT EXISTS idx_referrals_referred ON public.referrals(referred_user_id);
CREATE INDEX IF NOT EXISTS idx_referrals_created ON public.referrals(created_at);

-- Enable RLS
ALTER TABLE public.referrals ENABLE ROW LEVEL SECURITY;

-- RLS Policies for referrals
CREATE POLICY "Users can view their own referral network"
ON public.referrals FOR SELECT
USING (
  auth.uid() = referrer_id OR 
  auth.uid() = referred_user_id OR
  has_role(auth.uid(), 'admin'::app_role) OR 
  has_role(auth.uid(), 'superadmin'::app_role)
);

CREATE POLICY "System can insert referrals"
ON public.referrals FOR INSERT
WITH CHECK (true);

-- Create function to handle referral registration
CREATE OR REPLACE FUNCTION public.handle_referral_registration()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  ref_user_id UUID;
BEGIN
  -- Get referrer from sponsor_id if set
  IF NEW.sponsor_id IS NOT NULL THEN
    -- Insert primary structure referral
    INSERT INTO public.referrals (
      referrer_id,
      referred_user_id,
      structure_type
    ) VALUES (
      NEW.sponsor_id,
      NEW.id,
      1 -- Primary structure
    ) ON CONFLICT (referred_user_id, structure_type) DO NOTHING;
  END IF;
  
  RETURN NEW;
END;
$$;

-- Trigger to automatically create referral record on profile creation
DROP TRIGGER IF EXISTS on_profile_referral_registration ON public.profiles;
CREATE TRIGGER on_profile_referral_registration
  AFTER INSERT ON public.profiles
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_referral_registration();

-- Function to add user to secondary structure when they make activation purchase
CREATE OR REPLACE FUNCTION public.handle_activation_structure()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  user_sponsor_id UUID;
  has_activation BOOLEAN;
BEGIN
  -- Only process paid orders with activation products
  IF NEW.status = 'paid' THEN
    -- Check if order has activation products
    SELECT EXISTS(
      SELECT 1 FROM order_items oi
      WHERE oi.order_id = NEW.id AND oi.is_activation_snapshot = true
    ) INTO has_activation;
    
    IF has_activation THEN
      -- Get user's sponsor
      SELECT sponsor_id INTO user_sponsor_id
      FROM profiles
      WHERE id = NEW.user_id;
      
      -- If user has sponsor, add to secondary structure
      IF user_sponsor_id IS NOT NULL THEN
        INSERT INTO public.referrals (
          referrer_id,
          referred_user_id,
          structure_type
        ) VALUES (
          user_sponsor_id,
          NEW.user_id,
          2 -- Secondary structure
        ) ON CONFLICT (referred_user_id, structure_type) DO NOTHING;
      END IF;
    END IF;
  END IF;
  
  RETURN NEW;
END;
$$;

-- Trigger for secondary structure on activation purchase
DROP TRIGGER IF EXISTS on_activation_purchase ON public.orders;
CREATE TRIGGER on_activation_purchase
  AFTER INSERT OR UPDATE ON public.orders
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_activation_structure();

-- Function to get referral network tree
CREATE OR REPLACE FUNCTION public.get_referral_network(
  root_user_id UUID,
  structure_type_param INTEGER DEFAULT 1,
  max_levels INTEGER DEFAULT 10
)
RETURNS TABLE(
  user_id UUID,
  partner_id UUID,
  level INTEGER,
  full_name TEXT,
  email TEXT,
  referral_code TEXT,
  subscription_status TEXT,
  monthly_activation_met BOOLEAN,
  created_at TIMESTAMP WITH TIME ZONE,
  structure_type INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  is_admin_user BOOLEAN;
BEGIN
  -- Check if requesting user is admin
  is_admin_user := has_role(auth.uid(), 'admin'::app_role) OR 
                   has_role(auth.uid(), 'superadmin'::app_role);
  
  RETURN QUERY
  WITH RECURSIVE network AS (
    -- Root user
    SELECT 
      root_user_id as user_id,
      p.id as partner_id,
      0 as level,
      p.full_name,
      CASE 
        WHEN is_admin_user OR p.id = auth.uid() THEN p.email
        ELSE NULL
      END as email,
      p.referral_code,
      p.subscription_status,
      p.monthly_activation_met,
      p.created_at,
      structure_type_param as structure_type
    FROM public.profiles p
    WHERE p.id = root_user_id
    
    UNION ALL
    
    -- Recursive: get children through referrals table
    SELECT
      root_user_id as user_id,
      p.id as partner_id,
      n.level + 1 as level,
      p.full_name,
      CASE 
        WHEN is_admin_user OR p.id = auth.uid() THEN p.email
        ELSE NULL
      END as email,
      p.referral_code,
      p.subscription_status,
      p.monthly_activation_met,
      p.created_at,
      structure_type_param as structure_type
    FROM public.profiles p
    INNER JOIN public.referrals r ON r.referred_user_id = p.id
    INNER JOIN network n ON n.partner_id = r.referrer_id
    WHERE n.level < max_levels 
      AND r.structure_type = structure_type_param
  )
  SELECT 
    n.user_id,
    n.partner_id,
    n.level,
    n.full_name,
    n.email,
    n.referral_code,
    n.subscription_status,
    n.monthly_activation_met,
    n.created_at,
    n.structure_type
  FROM network n
  WHERE n.level > 0
  ORDER BY n.level, n.created_at;
END;
$$;