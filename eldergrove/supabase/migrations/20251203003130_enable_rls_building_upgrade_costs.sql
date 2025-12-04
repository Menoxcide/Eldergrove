-- Enable RLS on building_upgrade_costs table
-- This table contains reference data for building upgrade costs

ALTER TABLE public.building_upgrade_costs ENABLE ROW LEVEL SECURITY;

-- Policy: Anyone can view building upgrade costs (read-only reference data)
CREATE POLICY "Anyone can view building upgrade costs" ON public.building_upgrade_costs
  FOR SELECT
  TO authenticated
  USING (true);

