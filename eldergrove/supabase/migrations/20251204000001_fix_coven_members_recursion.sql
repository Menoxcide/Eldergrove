-- Fix infinite recursion in coven_members RLS policy
-- The policy was querying coven_members within itself, causing recursion

-- Create helper function to check coven membership (bypasses RLS)
CREATE OR REPLACE FUNCTION public.is_coven_member(p_coven_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_is_member boolean;
BEGIN
  -- Check if user is a member of this coven
  -- SECURITY DEFINER allows this to bypass RLS
  SELECT EXISTS (
    SELECT 1 FROM public.coven_members
    WHERE coven_id = p_coven_id AND player_id = v_player_id
  ) INTO v_is_member;
  
  RETURN COALESCE(v_is_member, false);
END;
$$;

COMMENT ON FUNCTION public.is_coven_member(uuid) IS 'Check if current user is a member of a coven (bypasses RLS to prevent recursion)';

-- Replace the recursive policy with one that uses the helper function
DROP POLICY IF EXISTS "Members can view coven members" ON public.coven_members;
CREATE POLICY "Members can view coven members"
  ON public.coven_members
  FOR SELECT
  TO authenticated
  USING (
    -- Use helper function to avoid recursion
    public.is_coven_member(coven_id)
  );

