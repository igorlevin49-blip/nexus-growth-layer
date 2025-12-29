-- Удалить неправильную политику (с ролью public вместо authenticated)
DROP POLICY IF EXISTS "Superadmins can manage all orders" ON public.orders;

-- Создать правильную политику для authenticated пользователей
CREATE POLICY "Superadmins can manage all orders" 
ON public.orders 
FOR ALL 
TO authenticated
USING (has_role(auth.uid(), 'superadmin'::app_role))
WITH CHECK (has_role(auth.uid(), 'superadmin'::app_role));