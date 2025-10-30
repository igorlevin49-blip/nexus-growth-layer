-- Бекфилл существующих товаров: заполняем NULL цены по курсу
DO $$
DECLARE
  current_rate NUMERIC;
BEGIN
  -- Получаем текущий курс
  SELECT rate_usd_kzt INTO current_rate FROM shop_settings WHERE id = 1;
  
  IF current_rate IS NULL OR current_rate <= 0 THEN
    current_rate := 450.00; -- Дефолтный курс если не настроен
  END IF;

  -- Заполняем price_usd если есть только price_kzt
  UPDATE products 
  SET price_usd = ROUND(price_kzt / current_rate, 2)
  WHERE price_kzt IS NOT NULL 
    AND price_usd IS NULL;

  -- Заполняем price_kzt если есть только price_usd
  UPDATE products 
  SET price_kzt = ROUND(price_usd * current_rate)
  WHERE price_usd IS NOT NULL 
    AND price_kzt IS NULL;

  -- Удаляем товары где обе цены NULL (если такие есть)
  DELETE FROM products 
  WHERE price_usd IS NULL AND price_kzt IS NULL;
END $$;

-- Функция для автозаполнения цен при INSERT/UPDATE
CREATE OR REPLACE FUNCTION public.autofill_product_prices()
RETURNS TRIGGER AS $$
DECLARE
  current_rate NUMERIC;
BEGIN
  -- Получаем текущий курс
  SELECT rate_usd_kzt INTO current_rate FROM shop_settings WHERE id = 1;
  
  IF current_rate IS NULL OR current_rate <= 0 THEN
    current_rate := 450.00;
  END IF;

  -- Если обе цены NULL - ошибка
  IF NEW.price_usd IS NULL AND NEW.price_kzt IS NULL THEN
    RAISE EXCEPTION 'Необходимо указать хотя бы одну цену (USD или KZT)';
  END IF;

  -- Если есть только KZT, рассчитываем USD
  IF NEW.price_kzt IS NOT NULL AND NEW.price_usd IS NULL THEN
    NEW.price_usd := ROUND(NEW.price_kzt / current_rate, 2);
  END IF;

  -- Если есть только USD, рассчитываем KZT
  IF NEW.price_usd IS NOT NULL AND NEW.price_kzt IS NULL THEN
    NEW.price_kzt := ROUND(NEW.price_usd * current_rate);
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- Создаём триггер для автозаполнения
DROP TRIGGER IF EXISTS autofill_product_prices_trigger ON products;
CREATE TRIGGER autofill_product_prices_trigger
  BEFORE INSERT OR UPDATE ON products
  FOR EACH ROW
  EXECUTE FUNCTION public.autofill_product_prices();

-- Делаем колонки NOT NULL после бекфилла
ALTER TABLE products 
  ALTER COLUMN price_usd SET NOT NULL,
  ALTER COLUMN price_kzt SET NOT NULL;