-- Add back the missing INSERT policy for coven table
-- This policy was accidentally removed in the anonymous access policy fix migration
-- Authenticated users need to be able to create covens where they become the leader

DROP POLICY IF EXISTS "Users can create coven" ON public.coven;
CREATE POLICY "Users can create coven"
  ON public.coven
  FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() IS NOT NULL AND leader_id = auth.uid());
