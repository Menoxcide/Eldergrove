-- Enable RLS on building_types table
-- This table contains reference data for building types

ALTER TABLE public.building_types ENABLE ROW LEVEL SECURITY;

-- Policy: Anyone can view building types (read-only reference data)
CREATE POLICY "Anyone can view building types" ON public.building_types
  FOR SELECT
  TO authenticated
  USING (true);

