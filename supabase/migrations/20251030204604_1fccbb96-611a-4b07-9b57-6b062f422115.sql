-- Добавляем финансовые настройки в mlm_settings если их нет
INSERT INTO mlm_settings (key, value, description)
VALUES 
  ('finance_subscription_usd', '100', 'Стоимость годовой подписки (USD)')
ON CONFLICT (key) DO NOTHING;

INSERT INTO mlm_settings (key, value, description)
VALUES 
  ('finance_activation_min_usd', '40', 'Минимальная сумма для месячной активации (USD)')
ON CONFLICT (key) DO NOTHING;

INSERT INTO mlm_settings (key, value, description)
VALUES 
  ('finance_usd_kzt_rate', '450', 'Курс обмена USD → KZT')
ON CONFLICT (key) DO NOTHING;

-- Добавляем комментарии для ясности
COMMENT ON TABLE mlm_settings IS 'Единый источник правды (SSOT) для всех MLM и финансовых настроек системы';