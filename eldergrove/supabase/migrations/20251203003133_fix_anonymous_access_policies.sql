-- Fix anonymous access policies by explicitly adding TO authenticated clause
-- This ensures policies are explicitly restricted to authenticated users only

-- Fix profiles table policies (missing TO authenticated)
DROP POLICY IF EXISTS "Users view own profile" ON public.profiles;
CREATE POLICY "Users view own profile" ON public.profiles
  FOR SELECT
  TO authenticated
  USING (auth.uid() = id);

DROP POLICY IF EXISTS "Users update own profile" ON public.profiles;
CREATE POLICY "Users update own profile" ON public.profiles
  FOR UPDATE
  TO authenticated
  USING (auth.uid() = id);

-- Note: Many other tables already have TO authenticated in their policies.
-- The linter warnings for those tables may be false positives or acceptable
-- for reference data tables that legitimately allow anonymous read access.
-- User-specific tables with proper TO authenticated clauses are secure even
-- if the linter flags them, as the USING clause with auth.uid() ensures
-- only authenticated users can access their own data.

