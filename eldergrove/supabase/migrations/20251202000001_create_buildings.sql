-- Create buildings table for city building placement system

CREATE TABLE IF NOT EXISTS public.buildings (
  id serial PRIMARY KEY,
  player_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  building_type text NOT NULL,
  grid_x integer NOT NULL CHECK (grid_x >= 0 AND grid_x < 20),
  grid_y integer NOT NULL CHECK (grid_y >= 0 AND grid_y < 20),
  level integer NOT NULL DEFAULT 1 CHECK (level >= 1 AND level <= 5),
  created_at timestamptz DEFAULT now(),
  UNIQUE(player_id, grid_x, grid_y) -- One building per grid cell
);

-- Enable RLS
ALTER TABLE public.buildings ENABLE ROW LEVEL SECURITY;

-- Policy: Players can view and manage their own buildings
CREATE POLICY "Players can view own buildings" ON public.buildings
  FOR SELECT TO authenticated
  USING (auth.uid() = player_id);

CREATE POLICY "Players can insert own buildings" ON public.buildings
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = player_id);

CREATE POLICY "Players can update own buildings" ON public.buildings
  FOR UPDATE TO authenticated
  USING (auth.uid() = player_id)
  WITH CHECK (auth.uid() = player_id);

CREATE POLICY "Players can delete own buildings" ON public.buildings
  FOR DELETE TO authenticated
  USING (auth.uid() = player_id);

-- Enable realtime
ALTER PUBLICATION supabase_realtime ADD TABLE public.buildings;

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_buildings_player ON public.buildings(player_id);
CREATE INDEX IF NOT EXISTS idx_buildings_position ON public.buildings(grid_x, grid_y);

-- Building types reference table (for validation and metadata)
CREATE TABLE IF NOT EXISTS public.building_types (
  building_type text PRIMARY KEY,
  name text NOT NULL,
  category text NOT NULL CHECK (category IN ('factory', 'community', 'decoration')),
  base_cost_crystals integer NOT NULL DEFAULT 100,
  size_x integer NOT NULL DEFAULT 1,
  size_y integer NOT NULL DEFAULT 1,
  provides_population integer DEFAULT 0,
  max_level integer DEFAULT 5
);

-- Seed building types
INSERT INTO public.building_types (building_type, name, category, base_cost_crystals, size_x, size_y, provides_population, max_level) VALUES
-- Factories
('rune_bakery', 'Rune Bakery', 'factory', 500, 2, 2, 0, 5),
('potion_workshop', 'Potion Workshop', 'factory', 1000, 2, 2, 0, 5),
('enchanting_lab', 'Enchanting Lab', 'factory', 1500, 2, 2, 0, 5),
('kitchen', 'Kitchen', 'factory', 800, 2, 2, 0, 5),
-- Community Buildings
('town_hall', 'Town Hall', 'community', 2000, 3, 3, 50, 1),
('school', 'School', 'community', 1500, 2, 2, 30, 1),
('hospital', 'Hospital', 'community', 1800, 2, 2, 25, 1),
('cinema', 'Cinema', 'community', 1200, 2, 2, 20, 1),
-- Decorations
('fountain', 'Fountain', 'decoration', 200, 1, 1, 0, 1),
('statue', 'Statue', 'decoration', 150, 1, 1, 0, 1),
('tree', 'Tree', 'decoration', 50, 1, 1, 0, 1)
ON CONFLICT (building_type) DO NOTHING;

-- RPC function to place a building
CREATE OR REPLACE FUNCTION public.place_building(
  p_building_type text,
  p_grid_x integer,
  p_grid_y integer
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_building_info record;
  v_cost integer;
  v_current_crystals bigint;
  v_building_id integer;
  v_size_x integer;
  v_size_y integer;
  v_check_x integer;
  v_check_y integer;
BEGIN
  -- Get building type info
  SELECT * INTO v_building_info
  FROM public.building_types
  WHERE building_type = p_building_type;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Building type "%" does not exist', p_building_type;
  END IF;

  v_cost := v_building_info.base_cost_crystals;
  v_size_x := v_building_info.size_x;
  v_size_y := v_building_info.size_y;

  -- Check if player has enough crystals
  SELECT crystals INTO v_current_crystals
  FROM public.profiles
  WHERE id = v_player_id;

  IF v_current_crystals < v_cost THEN
    RAISE EXCEPTION 'Insufficient crystals: required %, available %', v_cost, v_current_crystals;
  END IF;

  -- Check if grid cells are available (for multi-cell buildings)
  FOR v_check_x IN p_grid_x..(p_grid_x + v_size_x - 1) LOOP
    FOR v_check_y IN p_grid_y..(p_grid_y + v_size_y - 1) LOOP
      IF EXISTS (
        SELECT 1 FROM public.buildings
        WHERE player_id = v_player_id
        AND grid_x = v_check_x
        AND grid_y = v_check_y
      ) THEN
        RAISE EXCEPTION 'Grid cell (%,%) is already occupied', v_check_x, v_check_y;
      END IF;
    END LOOP;
  END LOOP;

  -- Deduct crystals
  UPDATE public.profiles
  SET crystals = crystals - v_cost
  WHERE id = v_player_id;

  -- Place building (only record top-left corner for multi-cell buildings)
  INSERT INTO public.buildings (player_id, building_type, grid_x, grid_y, level)
  VALUES (v_player_id, p_building_type, p_grid_x, p_grid_y, 1)
  RETURNING id INTO v_building_id;

  -- Update population if community building
  IF v_building_info.provides_population > 0 THEN
    UPDATE public.profiles
    SET population = COALESCE(population, 0) + v_building_info.provides_population
    WHERE id = v_player_id;
  END IF;

  RETURN v_building_id;
END;
$$;

COMMENT ON FUNCTION public.place_building(text, integer, integer) IS 'Place a building on the town grid. Returns building ID.';

-- RPC function to move a building
CREATE OR REPLACE FUNCTION public.move_building(
  p_building_id integer,
  p_new_x integer,
  p_new_y integer
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_building record;
  v_building_info record;
  v_size_x integer;
  v_size_y integer;
  v_check_x integer;
  v_check_y integer;
BEGIN
  -- Get building
  SELECT * INTO v_building
  FROM public.buildings
  WHERE id = p_building_id AND player_id = v_player_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Building % not found or does not belong to this player', p_building_id;
  END IF;

  -- Get building type info
  SELECT * INTO v_building_info
  FROM public.building_types
  WHERE building_type = v_building.building_type;

  v_size_x := v_building_info.size_x;
  v_size_y := v_building_info.size_y;

  -- Check if new location is available
  FOR v_check_x IN p_new_x..(p_new_x + v_size_x - 1) LOOP
    FOR v_check_y IN p_new_y..(p_new_y + v_size_y - 1) LOOP
      IF EXISTS (
        SELECT 1 FROM public.buildings
        WHERE player_id = v_player_id
        AND grid_x = v_check_x
        AND grid_y = v_check_y
        AND id != p_building_id
      ) THEN
        RAISE EXCEPTION 'Grid cell (%,%) is already occupied', v_check_x, v_check_y;
      END IF;
    END LOOP;
  END LOOP;

  -- Move building
  UPDATE public.buildings
  SET grid_x = p_new_x, grid_y = p_new_y
  WHERE id = p_building_id;
END;
$$;

COMMENT ON FUNCTION public.move_building(integer, integer, integer) IS 'Move a building to a new location on the grid.';

-- RPC function to remove a building
CREATE OR REPLACE FUNCTION public.remove_building(p_building_id integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_building record;
  v_building_info record;
BEGIN
  -- Get building
  SELECT * INTO v_building
  FROM public.buildings
  WHERE id = p_building_id AND player_id = v_player_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Building % not found or does not belong to this player', p_building_id;
  END IF;

  -- Get building type info
  SELECT * INTO v_building_info
  FROM public.building_types
  WHERE building_type = v_building.building_type;

  -- Remove building
  DELETE FROM public.buildings WHERE id = p_building_id;

  -- Remove population if community building
  IF v_building_info.provides_population > 0 THEN
    UPDATE public.profiles
    SET population = GREATEST(COALESCE(population, 0) - v_building_info.provides_population, 0)
    WHERE id = v_player_id;
  END IF;
END;
$$;

COMMENT ON FUNCTION public.remove_building(integer) IS 'Remove a building from the town grid.';

-- Add population column to profiles if it doesn't exist
DO $$ 
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'profiles' AND column_name = 'population'
  ) THEN
    ALTER TABLE public.profiles ADD COLUMN population integer DEFAULT 0;
  END IF;
END $$;

