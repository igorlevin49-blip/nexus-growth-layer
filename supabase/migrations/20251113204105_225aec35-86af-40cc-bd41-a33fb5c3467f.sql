-- Create team_members table for landing page management
CREATE TABLE public.team_members (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  name TEXT NOT NULL,
  position TEXT NOT NULL,
  description TEXT NOT NULL,
  photo_url TEXT,
  display_order INTEGER NOT NULL DEFAULT 0,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.team_members ENABLE ROW LEVEL SECURITY;

-- Public can view active team members
CREATE POLICY "Team members are viewable by everyone" 
ON public.team_members 
FOR SELECT 
USING (is_active = true);

-- Only admins can manage team members
CREATE POLICY "Admins can insert team members" 
ON public.team_members 
FOR INSERT 
WITH CHECK (
  EXISTS (
    SELECT 1 FROM public.user_roles 
    WHERE user_id = auth.uid() AND role = 'admin'
  )
);

CREATE POLICY "Admins can update team members" 
ON public.team_members 
FOR UPDATE 
USING (
  EXISTS (
    SELECT 1 FROM public.user_roles 
    WHERE user_id = auth.uid() AND role = 'admin'
  )
);

CREATE POLICY "Admins can delete team members" 
ON public.team_members 
FOR DELETE 
USING (
  EXISTS (
    SELECT 1 FROM public.user_roles 
    WHERE user_id = auth.uid() AND role = 'admin'
  )
);

-- Create storage bucket for team photos
INSERT INTO storage.buckets (id, name, public) 
VALUES ('team-photos', 'team-photos', true)
ON CONFLICT (id) DO NOTHING;

-- Storage policies for team photos
CREATE POLICY "Team photos are publicly accessible" 
ON storage.objects 
FOR SELECT 
USING (bucket_id = 'team-photos');

CREATE POLICY "Admins can upload team photos" 
ON storage.objects 
FOR INSERT 
WITH CHECK (
  bucket_id = 'team-photos' AND 
  EXISTS (
    SELECT 1 FROM public.user_roles 
    WHERE user_id = auth.uid() AND role = 'admin'
  )
);

CREATE POLICY "Admins can update team photos" 
ON storage.objects 
FOR UPDATE 
USING (
  bucket_id = 'team-photos' AND 
  EXISTS (
    SELECT 1 FROM public.user_roles 
    WHERE user_id = auth.uid() AND role = 'admin'
  )
);

CREATE POLICY "Admins can delete team photos" 
ON storage.objects 
FOR DELETE 
USING (
  bucket_id = 'team-photos' AND 
  EXISTS (
    SELECT 1 FROM public.user_roles 
    WHERE user_id = auth.uid() AND role = 'admin'
  )
);

-- Trigger for updated_at
CREATE TRIGGER update_team_members_updated_at
BEFORE UPDATE ON public.team_members
FOR EACH ROW
EXECUTE FUNCTION public.update_updated_at_column();

-- Insert initial team data
INSERT INTO public.team_members (name, position, description, display_order) VALUES
('Ибраев Марсбек', 'Учредитель MG Market', 'Долларовый мультимиллионер с многолетним опытом построения успешных бизнесов', 1),
('Камалов Эрбол', 'Президент компании', 'Опытный профессионал с 20 лет опыта в прямых продажах, превративший амбициозную идею в успешный бизнес', 2),
('Банников Олег', 'CEO, Коммерческий директор', 'Более 20 лет опыта в продажах, управлении командами и построении эффективных коммерческих стратегий', 3);