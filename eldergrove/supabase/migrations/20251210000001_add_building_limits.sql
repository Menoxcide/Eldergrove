-- Add building limits system
-- Limits how many of each building type a player can place

-- Add max_count column to building_types
ALTER TABLE public.building_types
ADD COLUMN IF NOT EXISTS max_count INTEGER DEFAULT NULL;

-- Set building limits based on category and type
-- Factories: 3-5 per type (more production capacity)
-- Community buildings: 1-2 per type (unique benefits)
-- Decorations: Unlimited (NULL means unlimited)
UPDATE public.building_types
SET max_count = CASE
  -- Factory buildings: 3-5 per type
  WHEN building_type = 'rune_bakery' THEN 5
  WHEN building_type = 'potion_workshop' THEN 4
  WHEN building_type = 'enchanting_lab' THEN 3
  WHEN building_type = 'kitchen' THEN 4
  -- Community buildings: 1-2 per type
  WHEN building_type = 'town_hall' THEN 1
  WHEN building_type = 'school' THEN 2
  WHEN building_type = 'hospital' THEN 2
  WHEN building_type = 'cinema' THEN 2
  -- Decorations: unlimited (NULL)
  WHEN building_type IN ('fountain', 'statue', 'tree') THEN NULL
  ELSE NULL
END
WHERE max_count IS NULL;

-- Update place_building function to check building limits
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
  v_current_count integer;
  v_max_count integer;
  v_discount_percent numeric;
  v_discount_amount integer;
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
  v_max_count := v_building_info.max_count;

  -- Get level discount
  SELECT COALESCE(population, 0), COALESCE(level, 1) 
  INTO v_current_population, v_current_level
  FROM public.profiles
  WHERE id = v_player_id;

  -- Check if building has a limit
  IF v_max_count IS NOT NULL THEN
    -- Count current buildings of this type
    SELECT COUNT(*) INTO v_current_count
    FROM public.buildings
    WHERE player_id = v_player_id
      AND building_type = p_building_type;

    -- Check if limit reached
    IF v_current_count >= v_max_count THEN
      RAISE EXCEPTION 'Building limit reached: You can only place % % buildings. Current: %', 
        v_max_count, v_building_info.name, v_current_count;
    END IF;
  END IF;

  -- Get level discount
  v_discount_percent := public.get_level_discount(v_player_id);
  v_discount_amount := FLOOR(v_cost * v_discount_percent);
  v_cost := v_cost - v_discount_amount;

  -- Check population requirement
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

  -- Deduct crystals (with discount applied)
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

COMMENT ON COLUMN public.building_types.max_count IS 'Maximum number of this building type a player can place. NULL means unlimited.';
COMMENT ON FUNCTION public.place_building(text, integer, integer) IS 'Place a building on the town grid. Checks population, level requirements, and building limits.';

