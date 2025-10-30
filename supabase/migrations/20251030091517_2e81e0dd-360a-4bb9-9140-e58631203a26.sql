-- Create admin actions log table
CREATE TABLE IF NOT EXISTS admin_actions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  admin_id uuid NOT NULL REFERENCES auth.users(id),
  action_type text NOT NULL,
  target_id uuid,
  target_type text,
  comment text,
  metadata jsonb DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- Enable RLS
ALTER TABLE admin_actions ENABLE ROW LEVEL SECURITY;

-- Admins can view all actions
CREATE POLICY "Admins can view all actions"
  ON admin_actions FOR SELECT
  USING (has_role(auth.uid(), 'admin'::app_role) OR has_role(auth.uid(), 'superadmin'::app_role));

-- Admins can insert actions
CREATE POLICY "Admins can insert actions"
  ON admin_actions FOR INSERT
  WITH CHECK (has_role(auth.uid(), 'admin'::app_role) OR has_role(auth.uid(), 'superadmin'::app_role));

-- Add subscription table if not exists
CREATE TABLE IF NOT EXISTS subscriptions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'active', 'frozen', 'cancelled')),
  amount_usd numeric NOT NULL,
  amount_kzt numeric NOT NULL,
  payment_method text,
  payment_confirmed_by uuid REFERENCES auth.users(id),
  payment_confirmed_at timestamptz,
  admin_comment text,
  started_at timestamptz,
  expires_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(user_id)
);

-- Enable RLS on subscriptions
ALTER TABLE subscriptions ENABLE ROW LEVEL SECURITY;

-- Users can view their own subscription
CREATE POLICY "Users can view own subscription"
  ON subscriptions FOR SELECT
  USING (auth.uid() = user_id OR has_role(auth.uid(), 'admin'::app_role) OR has_role(auth.uid(), 'superadmin'::app_role));

-- Users can create their own subscription
CREATE POLICY "Users can create own subscription"
  ON subscriptions FOR INSERT
  WITH CHECK (auth.uid() = user_id);

-- Admins can update subscriptions
CREATE POLICY "Admins can update subscriptions"
  ON subscriptions FOR UPDATE
  USING (has_role(auth.uid(), 'admin'::app_role) OR has_role(auth.uid(), 'superadmin'::app_role));

-- Function to update profile when subscription is confirmed
CREATE OR REPLACE FUNCTION handle_subscription_confirmation()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- If subscription just became active
  IF NEW.status = 'active' AND (OLD.status IS NULL OR OLD.status != 'active') THEN
    -- Update profile
    UPDATE profiles
    SET 
      subscription_status = 'active',
      subscription_expires_at = NEW.expires_at,
      updated_at = NOW()
    WHERE id = NEW.user_id;
    
    -- Log activity
    INSERT INTO activity_log (user_id, type, payload)
    VALUES (
      NEW.user_id,
      'subscription_activated',
      jsonb_build_object(
        'subscription_id', NEW.id,
        'amount_usd', NEW.amount_usd,
        'confirmed_by', NEW.payment_confirmed_by,
        'expires_at', NEW.expires_at
      )
    );
  END IF;
  
  RETURN NEW;
END;
$$;

-- Create trigger for subscription confirmation
DROP TRIGGER IF EXISTS on_subscription_confirmation ON subscriptions;
CREATE TRIGGER on_subscription_confirmation
  AFTER INSERT OR UPDATE ON subscriptions
  FOR EACH ROW
  EXECUTE FUNCTION handle_subscription_confirmation();

-- Update timestamps trigger for subscriptions
DROP TRIGGER IF EXISTS update_subscriptions_updated_at ON subscriptions;
CREATE TRIGGER update_subscriptions_updated_at
  BEFORE UPDATE ON subscriptions
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();