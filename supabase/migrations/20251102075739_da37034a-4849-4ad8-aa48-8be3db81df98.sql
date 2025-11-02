-- Delete all orphaned users from auth.users (except egor.smart@mail.ru)
DELETE FROM auth.users 
WHERE email != 'egor.smart@mail.ru' 
AND NOT EXISTS (
  SELECT 1 FROM public.profiles WHERE profiles.id = auth.users.id
);