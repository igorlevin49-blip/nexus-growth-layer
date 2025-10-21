-- Create enum for order status
CREATE TYPE public.order_status AS ENUM ('draft', 'pending', 'paid', 'cancelled');

-- Create enum for currency
CREATE TYPE public.currency_type AS ENUM ('USD', 'KZT');

-- Create products table
CREATE TABLE public.products (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title TEXT NOT NULL,
  slug TEXT UNIQUE NOT NULL,
  description TEXT,
  price_usd NUMERIC(10, 2) NOT NULL,
  price_kzt NUMERIC(10, 2) NOT NULL,
  is_activation BOOLEAN DEFAULT FALSE,
  is_popular BOOLEAN DEFAULT FALSE,
  is_new BOOLEAN DEFAULT FALSE,
  image_url TEXT,
  stock INTEGER,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create indexes for products
CREATE INDEX idx_products_is_activation ON public.products(is_activation);
CREATE INDEX idx_products_is_popular ON public.products(is_popular);
CREATE INDEX idx_products_is_new ON public.products(is_new);
CREATE INDEX idx_products_slug ON public.products(slug);

-- Create orders table
CREATE TABLE public.orders (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  total_usd NUMERIC(10, 2) NOT NULL DEFAULT 0,
  total_kzt NUMERIC(10, 2) NOT NULL DEFAULT 0,
  status public.order_status DEFAULT 'draft',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create index for orders
CREATE INDEX idx_orders_user_id ON public.orders(user_id);
CREATE INDEX idx_orders_status ON public.orders(status);
CREATE INDEX idx_orders_created_at ON public.orders(created_at);

-- Create order_items table
CREATE TABLE public.order_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID REFERENCES public.orders(id) ON DELETE CASCADE NOT NULL,
  product_id UUID REFERENCES public.products(id) ON DELETE SET NULL,
  qty INTEGER NOT NULL DEFAULT 1,
  price_usd NUMERIC(10, 2) NOT NULL,
  price_kzt NUMERIC(10, 2) NOT NULL,
  is_activation_snapshot BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create index for order_items
CREATE INDEX idx_order_items_order_id ON public.order_items(order_id);
CREATE INDEX idx_order_items_product_id ON public.order_items(product_id);

-- Create shop_settings table
CREATE TABLE public.shop_settings (
  id INTEGER PRIMARY KEY DEFAULT 1,
  monthly_activation_required_usd NUMERIC(10, 2) DEFAULT 40,
  currency public.currency_type DEFAULT 'USD',
  rate_usd_kzt NUMERIC(10, 4) DEFAULT 450.00,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  CONSTRAINT single_row CHECK (id = 1)
);

-- Insert default settings
INSERT INTO public.shop_settings (id) VALUES (1);

-- Enable RLS
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.shop_settings ENABLE ROW LEVEL SECURITY;

-- RLS Policies for products
CREATE POLICY "Anyone can view products"
  ON public.products FOR SELECT
  USING (TRUE);

CREATE POLICY "Admins can manage products"
  ON public.products FOR ALL
  USING (has_role(auth.uid(), 'admin'::app_role) OR has_role(auth.uid(), 'superadmin'::app_role));

-- RLS Policies for orders
CREATE POLICY "Users can view their own orders"
  ON public.orders FOR SELECT
  USING (auth.uid() = user_id OR has_role(auth.uid(), 'admin'::app_role) OR has_role(auth.uid(), 'superadmin'::app_role));

CREATE POLICY "Users can create their own orders"
  ON public.orders FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own draft orders"
  ON public.orders FOR UPDATE
  USING (auth.uid() = user_id AND status = 'draft');

CREATE POLICY "Superadmins can manage all orders"
  ON public.orders FOR ALL
  USING (has_role(auth.uid(), 'superadmin'::app_role));

-- RLS Policies for order_items
CREATE POLICY "Users can view their order items"
  ON public.order_items FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.orders
      WHERE orders.id = order_items.order_id
        AND (orders.user_id = auth.uid() OR has_role(auth.uid(), 'admin'::app_role) OR has_role(auth.uid(), 'superadmin'::app_role))
    )
  );

CREATE POLICY "Users can manage items in their draft orders"
  ON public.order_items FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM public.orders
      WHERE orders.id = order_items.order_id
        AND orders.user_id = auth.uid()
        AND orders.status = 'draft'
    )
  );

CREATE POLICY "Superadmins can manage all order items"
  ON public.order_items FOR ALL
  USING (has_role(auth.uid(), 'superadmin'::app_role));

-- RLS Policies for shop_settings
CREATE POLICY "Anyone can view shop settings"
  ON public.shop_settings FOR SELECT
  USING (TRUE);

CREATE POLICY "Superadmins can update shop settings"
  ON public.shop_settings FOR UPDATE
  USING (has_role(auth.uid(), 'superadmin'::app_role));

-- Trigger for products updated_at
CREATE TRIGGER update_products_updated_at
  BEFORE UPDATE ON public.products
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

-- Trigger for orders updated_at
CREATE TRIGGER update_orders_updated_at
  BEFORE UPDATE ON public.orders
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

-- Trigger for shop_settings updated_at
CREATE TRIGGER update_shop_settings_updated_at
  BEFORE UPDATE ON public.shop_settings
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

-- Function to update profile activation status
CREATE OR REPLACE FUNCTION public.check_activation_status()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  activation_sum NUMERIC;
  required_sum NUMERIC;
  target_user_id UUID;
BEGIN
  -- Only process paid orders
  IF NEW.status = 'paid' THEN
    target_user_id := NEW.user_id;
    
    -- Get required activation sum
    SELECT monthly_activation_required_usd INTO required_sum
    FROM shop_settings WHERE id = 1;
    
    -- Calculate activation sum for current month
    SELECT COALESCE(SUM(oi.price_usd * oi.qty), 0) INTO activation_sum
    FROM order_items oi
    JOIN orders o ON o.id = oi.order_id
    WHERE o.user_id = target_user_id
      AND o.status = 'paid'
      AND oi.is_activation_snapshot = TRUE
      AND DATE_TRUNC('month', o.created_at) = DATE_TRUNC('month', NOW());
    
    -- Update profile if activation requirement is met
    IF activation_sum >= required_sum THEN
      UPDATE profiles
      SET 
        subscription_status = 'active',
        monthly_activation_completed = TRUE,
        next_activation_date = (DATE_TRUNC('month', NOW()) + INTERVAL '1 month')::DATE,
        updated_at = NOW()
      WHERE id = target_user_id;
    END IF;
  END IF;
  
  RETURN NEW;
END;
$$;

-- Trigger to check activation after order is paid
CREATE TRIGGER trigger_check_activation
  AFTER UPDATE ON public.orders
  FOR EACH ROW
  WHEN (OLD.status IS DISTINCT FROM NEW.status AND NEW.status = 'paid')
  EXECUTE FUNCTION public.check_activation_status();