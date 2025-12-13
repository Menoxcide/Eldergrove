-- Fix place_building function: correct update_quest_progress parameter order
-- The function signature is: update_quest_progress(p_objective_type text, p_quest_id integer DEFAULT NULL, p_increment integer DEFAULT 1)
-- Previous call had parameters in wrong order: (NULL, 'place_building', 1) instead of ('build', NULL, 1)

CREATE OR REPLACE FUNCTION public.place_building(
  p_building_type text,
  p_grid_x integer,
  p_grid_y integer
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
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
  v_prerequisite_exists boolean;
  v_is_first_building boolean;
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

  -- Get player stats
  SELECT COALESCE(population, 0), COALESCE(level, 1), crystals
  INTO v_current_population, v_current_level, v_current_crystals
  FROM public.profiles
  WHERE id = v_player_id;

  -- Check if this is the first building of this type (for free logic)
  SELECT COUNT(*) INTO v_current_count
  FROM public.buildings
  WHERE player_id = v_player_id
    AND building_type = p_building_type;

  v_is_first_building := (v_current_count = 0);

  -- Check if building has a limit
  IF v_max_count IS NOT NULL THEN
    -- Check if limit reached
    IF v_current_count >= v_max_count THEN
      RAISE EXCEPTION 'Building limit reached: You can only place % % buildings. Current: %', 
        v_max_count, v_building_info.name, v_current_count;
    END IF;
  END IF;

  -- Check prerequisite building exists (if required)
  IF v_building_info.prerequisite_building_type IS NOT NULL THEN
    SELECT EXISTS (
      SELECT 1 FROM public.buildings
      WHERE player_id = v_player_id
        AND building_type = v_building_info.prerequisite_building_type
    ) INTO v_prerequisite_exists;

    IF NOT v_prerequisite_exists THEN
      RAISE EXCEPTION 'Prerequisite not met: You must build a % before placing a %', 
        (SELECT name FROM public.building_types WHERE building_type = v_building_info.prerequisite_building_type),
        v_building_info.name;
    END IF;
  END IF;

  -- Check level requirement
  IF v_current_level < v_building_info.level_required THEN
    RAISE EXCEPTION 'Insufficient level: required level %, you are level %', 
      v_building_info.level_required, v_current_level;
  END IF;

  -- Check population requirement
  IF v_current_population < v_building_info.population_required THEN
    RAISE EXCEPTION 'Insufficient population: required %, available %', 
      v_building_info.population_required, v_current_population;
  END IF;

  -- Calculate cost: first building is free, others get level discount
  IF v_is_first_building THEN
    v_cost := 0;
  ELSE
    -- Get level discount for subsequent buildings
    v_discount_percent := public.get_level_discount(v_player_id);
    v_discount_amount := FLOOR(v_cost * v_discount_percent);
    v_cost := v_cost - v_discount_amount;
  END IF;

  -- Check if player has enough crystals (only if not free)
  IF v_cost > 0 AND v_current_crystals < v_cost THEN
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

  -- Deduct crystals (only if cost > 0)
  IF v_cost > 0 THEN
    UPDATE public.profiles
    SET crystals = crystals - v_cost
    WHERE id = v_player_id;
  END IF;

  -- Place building (only record top-left corner for multi-cell buildings)
  INSERT INTO public.buildings (player_id, building_type, grid_x, grid_y, level)
  VALUES (v_player_id, p_building_type, p_grid_x, p_grid_y, 1)
  RETURNING id INTO v_building_id;

  -- Update population if community building
  IF v_building_info.provides_population > 0 THEN
    PERFORM public.calculate_population(v_player_id);
  END IF;

  -- Update quest progress (FIXED: objective_type first, not NULL)
  PERFORM public.update_quest_progress('build', NULL, 1);

  RETURN v_building_id;
END;
$$;

COMMENT ON FUNCTION public.place_building(text, integer, integer) IS 'Place a building on the town grid. Checks prerequisites, level requirements, building limits. First building of each type is free.';

