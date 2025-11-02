-- Delete user completely from auth.users if they don't exist in profiles
DELETE FROM auth.users 
WHERE email = 'igor.levin.1983@mail.ru' 
AND NOT EXISTS (
  SELECT 1 FROM public.profiles WHERE profiles.id = auth.users.id
);