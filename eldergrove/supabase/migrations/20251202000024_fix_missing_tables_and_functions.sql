-- Fix missing tables and functions
-- This migration ensures decorations tables and get_available_buildings function exist

-- Create decorations table if it doesn't exist
CREATE TABLE IF NOT EXISTS public.decorations (
  id serial PRIMARY KEY,
  player_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  decoration_type text NOT NULL,
  grid_x integer NOT NULL CHECK (grid_x >= 0),
  grid_y integer NOT NULL CHECK (grid_y >= 0),
  placed_at timestamptz DEFAULT now(),
  UNIQUE(player_id, grid_x, grid_y) -- One decoration per grid cell
);

-- Create decoration_types table if it doesn't exist
CREATE TABLE IF NOT EXISTS public.decoration_types (
  decoration_type text PRIMARY KEY,
  name text NOT NULL,
  icon text NOT NULL,
  cost_crystals integer NOT NULL DEFAULT 50,
  size_x integer NOT NULL DEFAULT 1,
  size_y integer NOT NULL DEFAULT 1,
  category text NOT NULL CHECK (category IN ('statue', 'tree', 'fountain', 'other'))
);

-- Insert decoration types (only if they don't exist)
INSERT INTO public.decoration_types (decoration_type, name, icon, cost_crystals, size_x, size_y, category) VALUES
  ('statue_warrior', 'Warrior Statue', '🗿', 200, 1, 1, 'statue'),
  ('statue_wizard', 'Wizard Statue', '🧙', 200, 1, 1, 'statue'),
  ('statue_dragon', 'Dragon Statue', '🐉', 500, 2, 2, 'statue'),
  ('tree_oak', 'Oak Tree', '🌳', 100, 1, 1, 'tree'),
  ('tree_pine', 'Pine Tree', '🌲', 100, 1, 1, 'tree'),
  ('tree_cherry', 'Cherry Blossom', '🌸', 150, 1, 1, 'tree'),
  ('tree_magic', 'Magic Tree', '✨', 300, 1, 1, 'tree'),
  ('fountain_small', 'Small Fountain', '⛲', 300, 1, 1, 'fountain'),
  ('fountain_grand', 'Grand Fountain', '🏛️', 1000, 2, 2, 'fountain'),
  ('bench', 'Park Bench', '🪑', 50, 1, 1, 'other'),
  ('lamp_post', 'Lamp Post', '🕯️', 75, 1, 1, 'other'),
  ('flower_bed', 'Flower Bed', '🌺', 80, 1, 1, 'other'),
  ('hedge', 'Hedge', '🌿', 60, 1, 1, 'other'),
  ('archway', 'Decorative Archway', '🚪', 400, 1, 2, 'other')
ON CONFLICT (decoration_type) DO NOTHING;

-- Enable RLS (idempotent)
ALTER TABLE public.decorations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.decoration_types ENABLE ROW LEVEL SECURITY;

-- Drop and recreate policies to ensure they exist (idempotent)
DROP POLICY IF EXISTS "Anyone can view decoration types" ON public.decoration_types;
CREATE POLICY "Anyone can view decoration types" ON public.decoration_types
  FOR SELECT TO authenticated
  USING (true);

DROP POLICY IF EXISTS "Anyone can view decorations" ON public.decorations;
CREATE POLICY "Anyone can view decorations" ON public.decorations
  FOR SELECT TO authenticated
  USING (true);

DROP POLICY IF EXISTS "Players can insert own decorations" ON public.decorations;
CREATE POLICY "Players can insert own decorations" ON public.decorations
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = player_id);

DROP POLICY IF EXISTS "Players can update own decorations" ON public.decorations;
CREATE POLICY "Players can update own decorations" ON public.decorations
  FOR UPDATE TO authenticated
  USING (auth.uid() = player_id)
  WITH CHECK (auth.uid() = player_id);

DROP POLICY IF EXISTS "Players can delete own decorations" ON public.decorations;
CREATE POLICY "Players can delete own decorations" ON public.decorations
  FOR DELETE TO authenticated
  USING (auth.uid() = player_id);

-- Enable realtime (handle gracefully if already added)
DO $$
BEGIN
  -- Try to add decorations table to publication
  IF EXISTS (
    SELECT 1 FROM pg_publication_tables 
    WHERE pubname = 'supabase_realtime' 
    AND tablename = 'decorations' 
    AND schemaname = 'public'
  ) THEN
    -- Already added, skip
    NULL;
  ELSE
    ALTER PUBLICATION supabase_realtime ADD TABLE public.decorations;
  END IF;
EXCEPTION WHEN OTHERS THEN
  -- Ignore errors (table might already be in publication or publication might not exist)
  NULL;
END $$;

DO $$
BEGIN
  -- Try to add decoration_types table to publication
  IF EXISTS (
    SELECT 1 FROM pg_publication_tables 
    WHERE pubname = 'supabase_realtime' 
    AND tablename = 'decoration_types' 
    AND schemaname = 'public'
  ) THEN
    -- Already added, skip
    NULL;
  ELSE
    ALTER PUBLICATION supabase_realtime ADD TABLE public.decoration_types;
  END IF;
EXCEPTION WHEN OTHERS THEN
  -- Ignore errors (table might already be in publication or publication might not exist)
  NULL;
END $$;

-- Create indexes (idempotent)
CREATE INDEX IF NOT EXISTS idx_decorations_player ON public.decorations(player_id);
CREATE INDEX IF NOT EXISTS idx_decorations_position ON public.decorations(grid_x, grid_y);

-- Function to place decoration
CREATE OR REPLACE FUNCTION public.place_decoration(
  p_decoration_type text,
  p_grid_x integer,
  p_grid_y integer
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_decoration_info record;
  v_cost integer;
  v_size_x integer;
  v_size_y integer;
  v_current_crystals bigint;
  v_decoration_id integer;
  v_check_x integer;
  v_check_y integer;
  v_town_size integer;
BEGIN
  -- Get decoration type info
  SELECT * INTO v_decoration_info
  FROM public.decoration_types
  WHERE decoration_type = p_decoration_type;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Decoration type "%" does not exist', p_decoration_type;
  END IF;

  v_cost := v_decoration_info.cost_crystals;
  v_size_x := v_decoration_info.size_x;
  v_size_y := v_decoration_info.size_y;

  -- Get town size
  SELECT COALESCE(town_size, 10) INTO v_town_size
  FROM public.profiles
  WHERE id = v_player_id;

  -- Check bounds
  IF p_grid_x + v_size_x > v_town_size OR p_grid_y + v_size_y > v_town_size THEN
    RAISE EXCEPTION 'Decoration would be placed outside town bounds';
  END IF;

  -- Check if player has enough crystals
  SELECT crystals INTO v_current_crystals
  FROM public.profiles
  WHERE id = v_player_id;

  IF v_current_crystals < v_cost THEN
    RAISE EXCEPTION 'Insufficient crystals: required %, available %', v_cost, v_current_crystals;
  END IF;

  -- Check if grid cells are available (for multi-cell decorations)
  FOR v_check_x IN p_grid_x..(p_grid_x + v_size_x - 1) LOOP
    FOR v_check_y IN p_grid_y..(p_grid_y + v_size_y - 1) LOOP
      -- Check for buildings
      IF EXISTS (
        SELECT 1 FROM public.buildings
        WHERE player_id = v_player_id
        AND grid_x = v_check_x
        AND grid_y = v_check_y
      ) THEN
        RAISE EXCEPTION 'Grid cell (%, %) is occupied by a building', v_check_x, v_check_y;
      END IF;
      
      -- Check for other decorations
      IF EXISTS (
        SELECT 1 FROM public.decorations
        WHERE player_id = v_player_id
        AND grid_x = v_check_x
        AND grid_y = v_check_y
      ) THEN
        RAISE EXCEPTION 'Grid cell (%, %) is already occupied by a decoration', v_check_x, v_check_y;
      END IF;
    END LOOP;
  END LOOP;

  -- Deduct crystals
  UPDATE public.profiles
  SET crystals = crystals - v_cost
  WHERE id = v_player_id;

  -- Place decoration (only record top-left corner for multi-cell decorations)
  INSERT INTO public.decorations (player_id, decoration_type, grid_x, grid_y)
  VALUES (v_player_id, p_decoration_type, p_grid_x, p_grid_y)
  RETURNING id INTO v_decoration_id;

  RETURN v_decoration_id;
END;
$$;

COMMENT ON FUNCTION public.place_decoration(text, integer, integer) IS 'Place a decoration on the town grid. Returns decoration ID.';

-- Function to remove decoration
CREATE OR REPLACE FUNCTION public.remove_decoration(p_decoration_id integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_decoration record;
BEGIN
  -- Get decoration
  SELECT * INTO v_decoration
  FROM public.decorations
  WHERE id = p_decoration_id AND player_id = v_player_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Decoration % not found or does not belong to this player', p_decoration_id;
  END IF;

  -- Remove decoration (no refund - purely cosmetic)
  DELETE FROM public.decorations WHERE id = p_decoration_id;
END;
$$;

COMMENT ON FUNCTION public.remove_decoration(integer) IS 'Remove a decoration from the town grid (no refund).';

-- Function to get available buildings (filtered by population)
-- This ensures the function exists even if the population_requirements migration hasn't run
CREATE OR REPLACE FUNCTION public.get_available_buildings()
RETURNS TABLE (
  building_type text,
  name text,
  category text,
  base_cost_crystals integer,
  size_x integer,
  size_y integer,
  provides_population integer,
  population_required integer,
  max_level integer
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_current_population integer;
BEGIN
  -- Get player's current population
  SELECT COALESCE(population, 0) INTO v_current_population
  FROM public.profiles
  WHERE id = v_player_id;

  -- Return buildings that player can afford (population-wise)
  -- Handle case where population_required column might not exist yet
  RETURN QUERY
  SELECT 
    bt.building_type,
    bt.name,
    bt.category,
    bt.base_cost_crystals,
    bt.size_x,
    bt.size_y,
    bt.provides_population,
    COALESCE(bt.population_required, 0) as population_required,
    bt.max_level
  FROM public.building_types bt
  WHERE COALESCE(bt.population_required, 0) <= v_current_population
  ORDER BY COALESCE(bt.population_required, 0), bt.name;
END;
$$;

COMMENT ON FUNCTION public.get_available_buildings() IS 'Get buildings available to the player based on population requirements';

