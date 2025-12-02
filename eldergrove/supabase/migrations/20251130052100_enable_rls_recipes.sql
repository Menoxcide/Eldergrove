-- Enable RLS on recipes table (shared reference data)
ALTER TABLE public.recipes
  ENABLE ROW LEVEL SECURITY;

-- Policy: All authenticated users can read recipes
DROP POLICY IF EXISTS "Enable read access for authenticated users on recipes" ON public.recipes;
CREATE POLICY "Enable read access for authenticated users on recipes"
  ON public.recipes
  FOR SELECT
  TO authenticated
  USING (true);