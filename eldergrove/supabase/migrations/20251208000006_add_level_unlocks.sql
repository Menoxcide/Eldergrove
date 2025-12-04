-- Add level-based building/feature unlocks
-- Add level_required column to building_types table

-- Add level_required column to building_types
ALTER TABLE public.building_types
ADD COLUMN IF NOT EXISTS level_required integer DEFAULT 1;

-- Set level requirements for buildings
-- Level 1: Basic buildings (bakery, mill, park, fountain)
-- Level 5: Advanced factories (dairy, textile, smithy)
-- Level 10: Special buildings (library, market)
-- Level 15: Premium buildings (town_hall)
-- Level 20+: End-game content (future buildings)
UPDATE public.building_types
SET level_required = CASE
  WHEN building_type IN ('bakery', 'mill', 'park', 'fountain') THEN 1
  WHEN building_type IN ('dairy', 'textile', 'smithy') THEN 5
  WHEN building_type IN ('library', 'market') THEN 10
  WHEN building_type = 'town_hall' THEN 15
  ELSE 1
END
WHERE level_required IS NULL OR level_required = 1;

-- Update get_available_buildings to check both population AND level requirements
-- Drop the function first since we're changing the return type (adding level_required column)
DROP FUNCTION IF EXISTS public.get_available_buildings();

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
  level_required integer,
  max_level integer
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_current_population integer;
  v_current_level integer;
BEGIN
  -- Get player's current population and level
  SELECT COALESCE(population, 0), COALESCE(level, 1) 
  INTO v_current_population, v_current_level
  FROM public.profiles
  WHERE id = v_player_id;

  -- Return buildings that player can afford (population and level-wise)
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
    bt.level_required,
    bt.max_level
  FROM public.building_types bt
  WHERE bt.population_required <= v_current_population
    AND bt.level_required <= v_current_level
  ORDER BY bt.level_required, bt.population_required, bt.name;
END;
$$;

COMMENT ON FUNCTION public.get_available_buildings() IS 'Get buildings available to the player based on population and level requirements';

-- Update place_building to check level requirements
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
  v_current_level integer;
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
  SELECT COALESCE(population, 0), COALESCE(level, 1) 
  INTO v_current_population, v_current_level
  FROM public.profiles
  WHERE id = v_player_id;

  IF v_current_population < v_building_info.population_required THEN
    RAISE EXCEPTION 'Insufficient population: required %, available %', 
      v_building_info.population_required, v_current_population;
  END IF;

  -- Check level requirement
  IF v_current_level < v_building_info.level_required THEN
    RAISE EXCEPTION 'Insufficient level: required level %, you are level %', 
      v_building_info.level_required, v_current_level;
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
        RAISE EXCEPTION 'Grid cell (%, %) is already occupied', v_check_x, v_check_y;
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

COMMENT ON FUNCTION public.place_building(text, integer, integer) IS 'Place a building on the town grid. Checks population and level requirements.';

