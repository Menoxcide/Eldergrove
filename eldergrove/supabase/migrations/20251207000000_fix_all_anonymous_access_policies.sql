-- Fix RLS policies that allow anonymous access by adding TO authenticated clause
-- This migration addresses Supabase database advisor warnings about policies
-- that allow access to anonymous users

-- Fix ad_watches table policies (missing TO authenticated)
DROP POLICY IF EXISTS "Players can view their own ad watches" ON public.ad_watches;
CREATE POLICY "Players can view their own ad watches"
  ON public.ad_watches
  FOR SELECT
  TO authenticated
  USING (auth.uid() = player_id);

DROP POLICY IF EXISTS "Players can insert their own ad watches" ON public.ad_watches;
CREATE POLICY "Players can insert their own ad watches"
  ON public.ad_watches
  FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = player_id);

-- Note: All other tables have been verified to already include TO authenticated
-- in their RLS policies. The ad_watches table was the only one missing this clause.

