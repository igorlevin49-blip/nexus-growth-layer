-- Create legal documents tables
CREATE TABLE public.legal_documents (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  slug TEXT NOT NULL UNIQUE,
  title TEXT NOT NULL,
  summary TEXT,
  language TEXT NOT NULL DEFAULT 'ru',
  is_published BOOLEAN NOT NULL DEFAULT false,
  effective_at TIMESTAMPTZ,
  current_version_id UUID,
  meta_title TEXT,
  meta_description TEXT,
  og_image_url TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE public.legal_document_versions (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  document_id UUID NOT NULL REFERENCES public.legal_documents(id) ON DELETE CASCADE,
  version INTEGER NOT NULL,
  content_md TEXT NOT NULL,
  changelog TEXT,
  created_by UUID REFERENCES public.profiles(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(document_id, version)
);

CREATE INDEX idx_legal_document_versions_document_version 
ON public.legal_document_versions(document_id, version DESC);

CREATE TABLE public.user_consents (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  document_id UUID NOT NULL REFERENCES public.legal_documents(id) ON DELETE CASCADE,
  document_version INTEGER NOT NULL,
  accepted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  ip TEXT,
  user_agent TEXT
);

-- Enable RLS
ALTER TABLE public.legal_documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.legal_document_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_consents ENABLE ROW LEVEL SECURITY;

-- RLS Policies for legal_documents
CREATE POLICY "Anyone can view published documents"
ON public.legal_documents FOR SELECT
USING (is_published = true OR has_role(auth.uid(), 'admin') OR has_role(auth.uid(), 'superadmin'));

CREATE POLICY "Admins can manage documents"
ON public.legal_documents FOR ALL
USING (has_role(auth.uid(), 'admin') OR has_role(auth.uid(), 'superadmin'));

-- RLS Policies for legal_document_versions
CREATE POLICY "Anyone can view versions of published documents"
ON public.legal_document_versions FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM public.legal_documents 
    WHERE id = legal_document_versions.document_id 
    AND (is_published = true OR has_role(auth.uid(), 'admin') OR has_role(auth.uid(), 'superadmin'))
  )
);

CREATE POLICY "Admins can manage versions"
ON public.legal_document_versions FOR ALL
USING (has_role(auth.uid(), 'admin') OR has_role(auth.uid(), 'superadmin'));

-- RLS Policies for user_consents
CREATE POLICY "Users can view their own consents"
ON public.user_consents FOR SELECT
USING (auth.uid() = user_id OR has_role(auth.uid(), 'admin') OR has_role(auth.uid(), 'superadmin'));

CREATE POLICY "System can insert consents"
ON public.user_consents FOR INSERT
WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Admins can view all consents"
ON public.user_consents FOR SELECT
USING (has_role(auth.uid(), 'admin') OR has_role(auth.uid(), 'superadmin'));

-- Trigger for updated_at
CREATE TRIGGER update_legal_documents_updated_at
BEFORE UPDATE ON public.legal_documents
FOR EACH ROW
EXECUTE FUNCTION public.update_updated_at_column();

-- Insert default documents
INSERT INTO public.legal_documents (slug, title, summary, language, effective_at)
VALUES 
  ('offer-agreement', 'Договор оферты', 'Условия использования платформы и совершения покупок', 'ru', now()),
  ('privacy-policy', 'Политика конфиденциальности', 'Правила обработки и защиты персональных данных', 'ru', now());

-- Insert default versions
WITH doc_ids AS (
  SELECT id, slug FROM public.legal_documents WHERE slug IN ('offer-agreement', 'privacy-policy')
)
INSERT INTO public.legal_document_versions (document_id, version, content_md, changelog)
SELECT 
  id, 
  1,
  CASE 
    WHEN slug = 'offer-agreement' THEN '# Договор оферты

## 1. Общие положения
Настоящий документ определяет условия использования платформы.

## 2. Предмет договора
Платформа предоставляет услуги электронной коммерции.

## 3. Права и обязанности сторон
Пользователь обязуется соблюдать правила платформы.'
    ELSE '# Политика конфиденциальности

## 1. Сбор данных
Мы собираем только необходимые данные для работы платформы.

## 2. Использование данных
Данные используются для предоставления услуг.

## 3. Защита данных
Мы обеспечиваем защиту ваших персональных данных.'
  END,
  'Первоначальная версия'
FROM doc_ids;

-- Update current_version_id
UPDATE public.legal_documents ld
SET current_version_id = ldv.id
FROM public.legal_document_versions ldv
WHERE ld.id = ldv.document_id AND ldv.version = 1;