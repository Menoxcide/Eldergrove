-- Enable RLS on crops table (shared reference data)
ALTER TABLE public.crops
  ENABLE ROW LEVEL SECURITY;

-- Policy: All authenticated users can read crops
DROP POLICY IF EXISTS "Enable read access for authenticated users on crops" ON public.crops;
CREATE POLICY "Enable read access for authenticated users on crops"
  ON public.crops
  FOR SELECT
  TO authenticated
  USING (true);

-- Enable RLS on farm_plots table
ALTER TABLE public.farm_plots
  ENABLE ROW LEVEL SECURITY;

-- Policy: Users can view their own farm plots
DROP POLICY IF EXISTS "Users view own farm plots" ON public.farm_plots;
CREATE POLICY "Users view own farm plots"
  ON public.farm_plots
  FOR SELECT
  TO authenticated
  USING (player_id = auth.uid());

-- Policy: Users can insert their own farm plots
DROP POLICY IF EXISTS "Users insert own farm plots" ON public.farm_plots;
CREATE POLICY "Users insert own farm plots"
  ON public.farm_plots
  FOR INSERT
  TO authenticated
  WITH CHECK (player_id = auth.uid());

-- Policy: Users can update their own farm plots
DROP POLICY IF EXISTS "Users update own farm plots" ON public.farm_plots;
CREATE POLICY "Users update own farm plots"
  ON public.farm_plots
  FOR UPDATE
  TO authenticated
  USING (player_id = auth.uid())
  WITH CHECK (player_id = auth.uid());

-- Policy: Users can delete their own farm plots
DROP POLICY IF EXISTS "Users delete own farm plots" ON public.farm_plots;
CREATE POLICY "Users delete own farm plots"
  ON public.farm_plots
  FOR DELETE
  TO authenticated
  USING (player_id = auth.uid());