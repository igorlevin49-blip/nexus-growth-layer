-- Fix security warnings: set search_path for new functions

ALTER FUNCTION public.create_commission_transactions(uuid, text, uuid, numeric, integer) 
SET search_path = public;

ALTER FUNCTION public.release_expired_frozen_transactions() 
SET search_path = public;