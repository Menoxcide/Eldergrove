-- Add required building types (farm, factory, mine, armory, zoo, coven)
-- Add prerequisite system for building unlocks

-- Add prerequisite_building_type column to building_types
ALTER TABLE public.building_types
ADD COLUMN IF NOT EXISTS prerequisite_building_type TEXT REFERENCES public.building_types(building_type);

-- Add required buildings to building_types table
INSERT INTO public.building_types (
  building_type, 
  name, 
  category, 
  base_cost_crystals, 
  size_x, 
  size_y, 
  provides_population, 
  max_level,
  max_count,
  level_required,
  prerequisite_building_type
) VALUES
  -- Farm: Level 1, no prerequisite, first is free
  ('farm', 'Farm', 'factory', 500, 2, 2, 0, 5, NULL, 1, NULL),
  -- Factory: Level 2, requires farm
  ('factory', 'Factory', 'factory', 1000, 2, 2, 0, 5, NULL, 2, 'farm'),
  -- Mine: Level 3, requires factory
  ('mine', 'Mine', 'factory', 1500, 2, 2, 0, 5, NULL, 3, 'factory'),
  -- Armory: Level 4, requires mine
  ('armory', 'Armory', 'factory', 2000, 2, 2, 0, 5, NULL, 4, 'mine'),
  -- Zoo: Level 5, requires armory, provides population
  ('zoo', 'Zoo', 'community', 2500, 2, 2, 30, 5, NULL, 5, 'armory'),
  -- Coven: Level 6, requires zoo, provides population
  ('coven', 'Coven', 'community', 3000, 2, 2, 50, 5, NULL, 6, 'zoo')
ON CONFLICT (building_type) DO UPDATE SET
  prerequisite_building_type = EXCLUDED.prerequisite_building_type,
  level_required = EXCLUDED.level_required;

COMMENT ON COLUMN public.building_types.prerequisite_building_type IS 'Building type that must be built before this building can be placed. NULL means no prerequisite.';

