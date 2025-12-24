-- Create a secure function to get sponsor info for the current user
-- This bypasses RLS safely by only returning limited, non-sensitive data about the sponsor

CREATE OR REPLACE FUNCTION public.get_my_sponsor_info()
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_sponsor_id UUID;
  v_sponsor RECORD;
  v_result JSON;
BEGIN
  -- Get current authenticated user
  v_user_id := auth.uid();
  
  IF v_user_id IS NULL THEN
    RETURN json_build_object('error', 'Not authenticated');
  END IF;
  
  -- Get sponsor_id from current user's profile
  SELECT sponsor_id INTO v_sponsor_id
  FROM profiles
  WHERE id = v_user_id;
  
  -- If no sponsor, return null
  IF v_sponsor_id IS NULL THEN
    RETURN json_build_object('sponsor', NULL, 'status', 'no_sponsor');
  END IF;
  
  -- Get sponsor's profile with limited fields (no email for privacy)
  SELECT 
    id,
    full_name,
    is_active,
    is_archived,
    deleted_at
  INTO v_sponsor
  FROM profiles
  WHERE id = v_sponsor_id;
  
  -- If sponsor profile not found
  IF v_sponsor.id IS NULL THEN
    RETURN json_build_object('sponsor', NULL, 'status', 'missing');
  END IF;
  
  -- Determine status
  IF v_sponsor.deleted_at IS NOT NULL OR v_sponsor.is_archived = true THEN
    v_result := json_build_object(
      'sponsor', json_build_object(
        'id', v_sponsor.id,
        'full_name', v_sponsor.full_name,
        'is_active', v_sponsor.is_active,
        'is_archived', v_sponsor.is_archived
      ),
      'status', 'archived'
    );
  ELSIF v_sponsor.is_active = false THEN
    v_result := json_build_object(
      'sponsor', json_build_object(
        'id', v_sponsor.id,
        'full_name', v_sponsor.full_name,
        'is_active', v_sponsor.is_active,
        'is_archived', v_sponsor.is_archived
      ),
      'status', 'inactive'
    );
  ELSE
    v_result := json_build_object(
      'sponsor', json_build_object(
        'id', v_sponsor.id,
        'full_name', v_sponsor.full_name,
        'is_active', v_sponsor.is_active,
        'is_archived', v_sponsor.is_archived
      ),
      'status', 'active'
    );
  END IF;
  
  RETURN v_result;
END;
$$;