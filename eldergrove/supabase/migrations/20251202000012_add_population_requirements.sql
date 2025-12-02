-- Add population requirements system for building unlocks

-- Add population_required column to building_types
ALTER TABLE public.building_types
ADD COLUMN IF NOT EXISTS population_required integer DEFAULT 0;

-- Update existing building types with population requirements
UPDATE public.building_types
SET population_required = CASE
  WHEN building_type = 'bakery' THEN 0
  WHEN building_type = 'mill' THEN 0
  WHEN building_type = 'dairy' THEN 10
  WHEN building_type = 'textile' THEN 20
  WHEN building_type = 'smithy' THEN 30
  WHEN building_type = 'library' THEN 50
  WHEN building_type = 'market' THEN 15
  WHEN building_type = 'town_hall' THEN 100
  WHEN building_type = 'park' THEN 0
  WHEN building_type = 'fountain' THEN 0
  ELSE 0
END
WHERE population_required IS NULL OR population_required = 0;

-- Function to calculate total population from buildings
CREATE OR REPLACE FUNCTION public.calculate_population(p_player_id uuid)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_total_population integer;
BEGIN
  SELECT COALESCE(SUM(bt.provides_population * b.level), 0) INTO v_total_population
  FROM public.buildings b
  JOIN public.building_types bt ON bt.building_type = b.building_type
  WHERE b.player_id = p_player_id
    AND bt.provides_population > 0;

  -- Update profiles table
  UPDATE public.profiles
  SET population = v_total_population
  WHERE id = p_player_id;

  RETURN v_total_population;
END;
$$;

COMMENT ON FUNCTION public.calculate_population(uuid) IS 'Calculate and update total population from buildings';

-- Update place_building to check population requirements
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
  v_size_x integer;
  v_size_y integer;
  v_current_crystals bigint;
  v_current_population integer;
  v_building_id integer;
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

  -- Check population requirement
  SELECT COALESCE(population, 0) INTO v_current_population
  FROM public.profiles
  WHERE id = v_player_id;

  IF v_current_population < v_building_info.population_required THEN
    RAISE EXCEPTION 'Insufficient population: required %, available %', 
      v_building_info.population_required, v_current_population;
  END IF;

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
        RAISE EXCEPTION 'Grid cell (%%) is already occupied', v_check_x, v_check_y;
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
    PERFORM public.calculate_population(v_player_id);
  END IF;

  -- Update quest progress
  PERFORM public.update_quest_progress(NULL, 'place_building', 1);

  RETURN v_building_id;
END;
$$;

COMMENT ON FUNCTION public.place_building(text, integer, integer) IS 'Place a building on the town grid. Checks population requirements.';

-- Update remove_building to recalculate population
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

  -- Recalculate population
  IF v_building_info.provides_population > 0 THEN
    PERFORM public.calculate_population(v_player_id);
  END IF;
END;
$$;

COMMENT ON FUNCTION public.remove_building(integer) IS 'Remove a building from the town grid and recalculate population.';

-- Function to get available buildings (filtered by population)
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
  RETURN QUERY
  SELECT 
    bt.building_type,
    bt.name,
    bt.category,
    bt.base_cost_crystals,
    bt.size_x,
    bt.size_y,
    bt.provides_population,
    bt.population_required,
    bt.max_level
  FROM public.building_types bt
  WHERE bt.population_required <= v_current_population
  ORDER BY bt.population_required, bt.name;
END;
$$;

COMMENT ON FUNCTION public.get_available_buildings() IS 'Get buildings available to the player based on population requirements';

