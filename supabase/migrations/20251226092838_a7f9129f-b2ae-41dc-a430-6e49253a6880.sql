-- Fix search_path for audit_commission_structure_integrity function
CREATE OR REPLACE FUNCTION public.audit_commission_structure_integrity()
RETURNS TABLE (
  transaction_id uuid,
  source_ref text,
  current_structure_type text,
  expected_structure_type text,
  issue text
)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  -- Find S1 commissions with wrong structure_type
  SELECT 
    t.id as transaction_id,
    t.source_ref,
    t.structure_type::text as current_structure_type,
    'primary' as expected_structure_type,
    'S1 commission marked as secondary' as issue
  FROM public.transactions t
  WHERE t.type = 'commission'
    AND t.source_ref LIKE '%_s1_level_%'
    AND t.structure_type = 'secondary'
  
  UNION ALL
  
  -- Find S2 commissions with wrong structure_type  
  SELECT 
    t.id as transaction_id,
    t.source_ref,
    t.structure_type::text as current_structure_type,
    'secondary' as expected_structure_type,
    'S2 commission marked as primary' as issue
  FROM public.transactions t
  WHERE t.type = 'commission'
    AND t.source_ref LIKE '%_s2_level_%'
    AND t.structure_type = 'primary';
$$;