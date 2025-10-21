-- Publish default documents
UPDATE public.legal_documents 
SET is_published = true 
WHERE slug IN ('offer-agreement', 'privacy-policy');