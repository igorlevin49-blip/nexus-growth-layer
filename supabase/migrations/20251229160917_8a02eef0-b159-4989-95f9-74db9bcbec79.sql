
-- Удалить старую политику для админов на обновление
DROP POLICY IF EXISTS "Admins update orders" ON orders;

-- Создать новую политику, разрешающую обновление и админам и суперадминам
CREATE POLICY "Admins and superadmins update orders"
ON orders
FOR UPDATE
USING (has_role(auth.uid(), 'admin'::app_role) OR has_role(auth.uid(), 'superadmin'::app_role))
WITH CHECK (has_role(auth.uid(), 'admin'::app_role) OR has_role(auth.uid(), 'superadmin'::app_role));
