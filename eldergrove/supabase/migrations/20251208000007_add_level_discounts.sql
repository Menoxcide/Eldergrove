-- Add level-based purchase discounts
-- Discount: 0.5% per level, max 25% discount at level 50

-- Function to get level-based discount percentage
CREATE OR REPLACE FUNCTION public.get_level_discount(p_player_id uuid)
RETURNS numeric
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_level integer;
  v_discount_percent numeric;
  v_max_discount numeric := 0.25; -- Max 25% discount
BEGIN
  -- Get player level (default to 1 if not found)
  SELECT COALESCE(level, 1) INTO v_player_level
  FROM public.profiles
  WHERE id = p_player_id;
  
  -- Discount: 0.5% per level, capped at 25% (level 50+)
  v_discount_percent := LEAST(v_player_level * 0.005, v_max_discount);
  
  RETURN v_discount_percent;
END;
$$;

COMMENT ON FUNCTION public.get_level_discount(uuid) IS 'Get level-based discount percentage. 0.5% per level, max 25% at level 50. Returns value between 0 and 0.25.';

-- Update place_building to apply level discount
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
  v_base_cost integer;
  v_discount_percent numeric;
  v_discount_amount integer;
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

  v_base_cost := v_building_info.base_cost_crystals;
  v_size_x := v_building_info.size_x;
  v_size_y := v_building_info.size_y;

  -- Get level discount
  v_discount_percent := public.get_level_discount(v_player_id);
  v_discount_amount := FLOOR(v_base_cost * v_discount_percent);
  v_cost := v_base_cost - v_discount_amount;

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

COMMENT ON FUNCTION public.place_building(text, integer, integer) IS 'Place a building on the town grid. Checks population and level requirements. Applies level-based discount (0.5% per level, max 25%).';

-- Update upgrade_factory to apply level discount
CREATE OR REPLACE FUNCTION public.upgrade_factory(p_factory_type text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_factory record;
  v_upgrade_cost record;
  v_current_level integer;
  v_new_level integer;
  v_base_cost_crystals integer;
  v_discount_percent numeric;
  v_discount_amount integer;
  v_cost_crystals integer;
  v_current_crystals bigint;
  v_result jsonb;
BEGIN
  -- Get factory
  SELECT * INTO v_factory
  FROM public.factories
  WHERE player_id = v_player_id AND factory_type = p_factory_type;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Factory "%" not found for this player', p_factory_type;
  END IF;

  v_current_level := v_factory.level;

  IF v_current_level >= 5 THEN
    RAISE EXCEPTION 'Factory "%" is already at maximum level (5)', p_factory_type;
  END IF;

  v_new_level := v_current_level + 1;

  -- Get upgrade cost
  SELECT * INTO v_upgrade_cost
  FROM public.building_upgrade_costs
  WHERE building_type = p_factory_type
    AND from_level = v_current_level
    AND to_level = v_new_level;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Upgrade cost not found for % level % to %', p_factory_type, v_current_level, v_new_level;
  END IF;

  v_base_cost_crystals := v_upgrade_cost.cost_crystals;

  -- Get level discount
  v_discount_percent := public.get_level_discount(v_player_id);
  v_discount_amount := FLOOR(v_base_cost_crystals * v_discount_percent);
  v_cost_crystals := v_base_cost_crystals - v_discount_amount;

  -- Check crystals
  SELECT crystals INTO v_current_crystals
  FROM public.profiles
  WHERE id = v_player_id;

  IF v_current_crystals < v_cost_crystals THEN
    RAISE EXCEPTION 'Insufficient crystals: required %, available %', v_cost_crystals, v_current_crystals;
  END IF;

  -- Deduct crystals (with discount applied)
  UPDATE public.profiles
  SET crystals = crystals - v_cost_crystals
  WHERE id = v_player_id;

  -- Upgrade factory
  UPDATE public.factories
  SET level = v_new_level
  WHERE player_id = v_player_id AND factory_type = p_factory_type;

  -- Return result
  SELECT jsonb_build_object(
    'success', true,
    'new_level', v_new_level,
    'cost_crystals', v_cost_crystals,
    'discount_applied', v_discount_amount,
    'unlocks_queue_slot', COALESCE(v_upgrade_cost.unlocks_queue_slot, false),
    'speed_multiplier', v_upgrade_cost.production_speed_multiplier
  ) INTO v_result;

  RETURN v_result;
END;
$$;

COMMENT ON FUNCTION public.upgrade_factory(text) IS 'Upgrade a factory: increases level, may unlock queue slots and improve production speed. Applies level-based discount (0.5% per level, max 25%).';

-- Update upgrade_warehouse to apply level discount
CREATE OR REPLACE FUNCTION public.upgrade_warehouse()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_current_level integer;
  v_new_level integer;
  v_base_upgrade_cost integer;
  v_discount_percent numeric;
  v_discount_amount integer;
  v_upgrade_cost integer;
  v_current_crystals bigint;
  v_new_capacity integer;
  v_result jsonb;
BEGIN
  -- Get current warehouse level
  SELECT COALESCE(level, 1) INTO v_current_level
  FROM public.warehouse_upgrades
  WHERE player_id = v_player_id;

  IF v_current_level >= 10 THEN
    RAISE EXCEPTION 'Warehouse is already at maximum level (10)';
  END IF;

  v_new_level := v_current_level + 1;
  
  -- Calculate base upgrade cost (exponential: 100 * level^2)
  v_base_upgrade_cost := 100 * v_new_level * v_new_level;

  -- Get level discount
  v_discount_percent := public.get_level_discount(v_player_id);
  v_discount_amount := FLOOR(v_base_upgrade_cost * v_discount_percent);
  v_upgrade_cost := v_base_upgrade_cost - v_discount_amount;

  -- Check crystals
  SELECT crystals INTO v_current_crystals
  FROM public.profiles
  WHERE id = v_player_id;

  IF v_current_crystals < v_upgrade_cost THEN
    RAISE EXCEPTION 'Insufficient crystals: required %, available %', v_upgrade_cost, v_current_crystals;
  END IF;

  -- Deduct crystals (with discount applied)
  UPDATE public.profiles
  SET crystals = crystals - v_upgrade_cost
  WHERE id = v_player_id;

  -- Update or insert warehouse upgrade
  INSERT INTO public.warehouse_upgrades (player_id, level)
  VALUES (v_player_id, v_new_level)
  ON CONFLICT (player_id) DO UPDATE SET
    level = v_new_level,
    upgraded_at = now();

  -- Update storage capacity using new function that includes player level bonus
  v_new_capacity := public.get_player_storage_capacity(v_player_id);
  UPDATE public.profiles
  SET storage_capacity = v_new_capacity
  WHERE id = v_player_id;

  -- Return result
  SELECT jsonb_build_object(
    'success', true,
    'new_level', v_new_level,
    'new_capacity', v_new_capacity,
    'cost', v_upgrade_cost,
    'discount_applied', v_discount_amount
  ) INTO v_result;

  RETURN v_result;
END;
$$;

COMMENT ON FUNCTION public.upgrade_warehouse() IS 'Upgrade warehouse: increases storage capacity, costs crystals based on level. Applies level-based discount (0.5% per level, max 25%). Capacity includes player level bonus.';

