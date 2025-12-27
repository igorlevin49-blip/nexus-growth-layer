-- Add maintenance_mode setting to mlm_settings
INSERT INTO public.mlm_settings (key, value, description)
VALUES (
  'maintenance_mode',
  '{"enabled": false, "title": "Технические работы", "message": "Мы проводим технические работы. Приносим извинения за неудобства."}'::jsonb,
  'Настройка режима технических работ - показывает всплывающее окно всем пользователям'
)
ON CONFLICT (key) DO NOTHING;