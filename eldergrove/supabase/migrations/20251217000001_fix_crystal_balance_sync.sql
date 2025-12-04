-- Fix crystal balance synchronization by returning new_crystal_balance from functions that modify crystals
-- Drop the existing function first to allow changing return type
DROP FUNCTION IF EXISTS public.add_animal_to_enclosure(integer, integer, integer);
-- Update add_animal_to_enclosure to return new_crystal_balance
CREATE OR REPLACE FUNCTION public.add_animal_to_enclosure(
  p_enclosure_id integer,
  p_animal_type_id integer,
  p_slot integer
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_enclosure record;
  v_animal_type record;
  v_current_crystals bigint;
  v_new_crystals bigint;
  v_rows_affected integer;
BEGIN
  -- Validate slot
  IF p_slot NOT IN (1, 2) THEN
    RAISE EXCEPTION 'Invalid slot: % (must be 1 or 2)', p_slot;
  END IF;
  
  -- Get enclosure
  SELECT * INTO v_enclosure
  FROM public.zoo_enclosures
  WHERE id = p_enclosure_id AND player_id = v_player_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Enclosure % not found or does not belong to this player', p_enclosure_id;
  END IF;

  -- Get animal type
  SELECT * INTO v_animal_type
  FROM public.animal_types
  WHERE id = p_animal_type_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Animal type % not found', p_animal_type_id;
  END IF;

  -- Check if slot is already occupied
  IF p_slot = 1 AND v_enclosure.animal1_id IS NOT NULL THEN
    RAISE EXCEPTION 'Slot 1 is already occupied';
  END IF;

  IF p_slot = 2 AND v_enclosure.animal2_id IS NOT NULL THEN
    RAISE EXCEPTION 'Slot 2 is already occupied';
  END IF;

  -- Check crystals
  SELECT crystals INTO v_current_crystals
  FROM public.profiles
  WHERE id = v_player_id;

  IF v_current_crystals < v_animal_type.base_cost_crystals THEN
    RAISE EXCEPTION 'Insufficient crystals: required %, available %', v_animal_type.base_cost_crystals, v_current_crystals;
  END IF;

  -- Deduct crystals
  UPDATE public.profiles
  SET crystals = crystals - v_animal_type.base_cost_crystals
  WHERE id = v_player_id;

  -- Get new crystal balance
  SELECT crystals INTO v_new_crystals
  FROM public.profiles
  WHERE id = v_player_id;

  -- Add animal to enclosure with verification
  IF p_slot = 1 THEN
    UPDATE public.zoo_enclosures
    SET animal1_id = p_animal_type_id,
        animal1_level = 0,
        animal1_produced_at = now()
    WHERE id = p_enclosure_id AND player_id = v_player_id;
    GET DIAGNOSTICS v_rows_affected = ROW_COUNT;
    IF v_rows_affected = 0 THEN
      RAISE EXCEPTION 'Failed to update enclosure slot 1';
    END IF;
  ELSE
    UPDATE public.zoo_enclosures
    SET animal2_id = p_animal_type_id,
        animal2_level = 0,
        animal2_produced_at = now()
    WHERE id = p_enclosure_id AND player_id = v_player_id;
    GET DIAGNOSTICS v_rows_affected = ROW_COUNT;
    IF v_rows_affected = 0 THEN
      RAISE EXCEPTION 'Failed to update enclosure slot 2';
    END IF;
  END IF;

  -- Return result with new crystal balance
  RETURN jsonb_build_object(
    'success', true,
    'new_crystal_balance', v_new_crystals
  );
END;
$$;

COMMENT ON FUNCTION public.add_animal_to_enclosure(integer, integer, integer) IS 'Add an animal to an enclosure slot. Returns success status and new crystal balance.';

-- Update create_enclosure to return new_crystal_balance
CREATE OR REPLACE FUNCTION public.create_enclosure(p_enclosure_name text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_enclosure_id integer;
  v_current_max integer;
  v_current_count integer;
  v_cost integer;
  v_current_crystals bigint;
  v_new_crystals bigint;
BEGIN
  -- Get current max_enclosures (defaults to 3 if null)
  SELECT COALESCE(max_enclosures, 3) INTO v_current_max
  FROM public.profiles
  WHERE id = v_player_id;

  -- Get current enclosure count
  SELECT COUNT(*) INTO v_current_count
  FROM public.zoo_enclosures
  WHERE player_id = v_player_id;

  -- Check if at limit
  IF v_current_count >= v_current_max THEN
    -- Calculate cost for next slot
    v_cost := public.get_enclosure_cost(v_current_max);
    
    -- Get current crystals
    SELECT crystals INTO v_current_crystals
    FROM public.profiles
    WHERE id = v_player_id;

    IF v_current_crystals < v_cost THEN
      RAISE EXCEPTION 'Insufficient crystals: required % for next enclosure slot, available %', v_cost, v_current_crystals;
    END IF;

    -- Deduct crystals and increase max_enclosures
    UPDATE public.profiles
    SET crystals = crystals - v_cost,
        max_enclosures = max_enclosures + 1
    WHERE id = v_player_id;

    -- Get new crystal balance
    SELECT crystals INTO v_new_crystals
    FROM public.profiles
    WHERE id = v_player_id;
  ELSE
    -- No cost, crystals unchanged
    SELECT crystals INTO v_new_crystals
    FROM public.profiles
    WHERE id = v_player_id;
  END IF;

  -- Create the enclosure
  INSERT INTO public.zoo_enclosures (player_id, enclosure_name)
  VALUES (v_player_id, p_enclosure_name)
  RETURNING id INTO v_enclosure_id;

  -- Return result with cost info and new crystal balance
  RETURN jsonb_build_object(
    'success', true,
    'enclosure_id', v_enclosure_id,
    'cost_paid', CASE WHEN v_current_count >= v_current_max THEN v_cost ELSE 0 END,
    'new_max_enclosures', CASE WHEN v_current_count >= v_current_max THEN v_current_max + 1 ELSE v_current_max END,
    'new_crystal_balance', v_new_crystals
  );
END;
$$;

COMMENT ON FUNCTION public.create_enclosure(text) IS 'Create a new enclosure. Automatically purchases slot expansion if at limit. Returns cost information and new crystal balance.';

-- Update place_decoration to return new_crystal_balance
DROP FUNCTION IF EXISTS public.place_decoration(text,integer,integer);
CREATE OR REPLACE FUNCTION public.place_decoration(
  p_decoration_type text,
  p_grid_x integer,
  p_grid_y integer
)
RETURNS jsonb
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
  v_new_crystals bigint;
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

  -- Get new crystal balance
  SELECT crystals INTO v_new_crystals
  FROM public.profiles
  WHERE id = v_player_id;

  -- Place decoration (only record top-left corner for multi-cell decorations)
  INSERT INTO public.decorations (player_id, decoration_type, grid_x, grid_y)
  VALUES (v_player_id, p_decoration_type, p_grid_x, p_grid_y)
  RETURNING id INTO v_decoration_id;

  -- Return result with decoration ID and new crystal balance
  RETURN jsonb_build_object(
    'success', true,
    'decoration_id', v_decoration_id,
    'new_crystal_balance', v_new_crystals
  );
END;
$$;

COMMENT ON FUNCTION public.place_decoration(text, integer, integer) IS 'Place a decoration on the town grid. Returns decoration ID and new crystal balance.';

-- Update upgrade_building to return new_crystal_balance
CREATE OR REPLACE FUNCTION public.upgrade_building(p_building_id integer)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_building record;
  v_building_type_info record;
  v_current_level integer;
  v_new_level integer;
  v_cost_crystals integer;
  v_current_crystals bigint;
  v_new_crystals bigint;
  v_result jsonb;
BEGIN
  -- Get building
  SELECT * INTO v_building
  FROM public.buildings
  WHERE id = p_building_id AND player_id = v_player_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Building % not found or does not belong to this player', p_building_id;
  END IF;

  v_current_level := v_building.level;

  -- Get building type info
  SELECT * INTO v_building_type_info
  FROM public.building_types
  WHERE building_type = v_building.building_type;

  IF v_current_level >= v_building_type_info.max_level THEN
    RAISE EXCEPTION 'Building is already at maximum level (%)', v_building_type_info.max_level;
  END IF;

  v_new_level := v_current_level + 1;
  
  -- Calculate upgrade cost (base_cost * level)
  v_cost_crystals := v_building_type_info.base_cost_crystals * v_new_level;

  -- Check crystals
  SELECT crystals INTO v_current_crystals
  FROM public.profiles
  WHERE id = v_player_id;

  IF v_current_crystals < v_cost_crystals THEN
    RAISE EXCEPTION 'Insufficient crystals: required %, available %', v_cost_crystals, v_current_crystals;
  END IF;

  -- Deduct crystals
  UPDATE public.profiles
  SET crystals = crystals - v_cost_crystals
  WHERE id = v_player_id;

  -- Get new crystal balance
  SELECT crystals INTO v_new_crystals
  FROM public.profiles
  WHERE id = v_player_id;

  -- Upgrade building
  UPDATE public.buildings
  SET level = v_new_level
  WHERE id = p_building_id;

  -- Update population if community building
  IF v_building_type_info.provides_population > 0 THEN
    UPDATE public.profiles
    SET population = COALESCE(population, 0) + v_building_type_info.provides_population
    WHERE id = v_player_id;
  END IF;

  -- Return result with new crystal balance
  SELECT jsonb_build_object(
    'success', true,
    'new_level', v_new_level,
    'cost_crystals', v_cost_crystals,
    'new_crystal_balance', v_new_crystals
  ) INTO v_result;

  RETURN v_result;
END;
$$;

COMMENT ON FUNCTION public.upgrade_building(integer) IS 'Upgrade a building: increases level, may provide additional population. Returns new level, cost, and new crystal balance.';

