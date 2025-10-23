-- Fix activity log payload exposure by removing sensitive financial data
-- Replace log_activation_activity trigger to exclude transaction amounts

-- Drop trigger first
DROP TRIGGER IF EXISTS log_activation_activity_trigger ON orders;
DROP TRIGGER IF EXISTS on_order_paid ON orders;

-- Drop function with CASCADE to remove dependent triggers
DROP FUNCTION IF EXISTS public.log_activation_activity() CASCADE;

-- Recreate function without sensitive amount data
CREATE OR REPLACE FUNCTION public.log_activation_activity()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
DECLARE
  has_activation_products BOOLEAN;
BEGIN
  IF NEW.status = 'paid' AND (OLD.status IS NULL OR OLD.status != 'paid') THEN
    -- Check if order contains activation products
    SELECT EXISTS(
      SELECT 1 FROM order_items oi
      WHERE oi.order_id = NEW.id AND oi.is_activation_snapshot = true
    ) INTO has_activation_products;
    
    IF has_activation_products THEN
      -- Log activation event WITHOUT financial amounts (privacy protection)
      INSERT INTO public.activity_log (user_id, type, payload)
      VALUES (
        NEW.user_id,
        'activation',
        jsonb_build_object(
          'order_id', NEW.id,
          'status', 'completed'
          -- Note: amount removed to protect financial privacy from network sponsors
        )
      );
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;

-- Recreate trigger
CREATE TRIGGER on_order_paid
  AFTER UPDATE ON public.orders
  FOR EACH ROW
  EXECUTE FUNCTION public.log_activation_activity();

-- Add security comment to activity_log.payload
COMMENT ON COLUMN public.activity_log.payload IS 'SECURITY: Contains only non-sensitive event metadata (order_id, status). Financial amounts and PII excluded to protect user privacy in network visibility.';