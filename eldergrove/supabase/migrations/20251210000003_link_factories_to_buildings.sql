-- Link factory system to buildings on town map
-- Each factory building provides 2 production slots

-- Update get_factory_slot_info to include building slots
CREATE OR REPLACE FUNCTION public.get_factory_slot_info()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_base_max integer;
  v_building_slots integer := 0;
  v_total_max integer;
  v_current_count integer;
  v_cost integer;
  v_factory_type text;
BEGIN
  -- Get base max_factory_slots from profile (defaults to 2 if null)
  SELECT COALESCE(max_factory_slots, 2) INTO v_base_max
  FROM public.profiles
  WHERE id = v_player_id;

  -- Calculate slots from factory buildings on town map
  -- Each factory building provides 2 slots
  SELECT COALESCE(SUM(2), 0) INTO v_building_slots
  FROM public.buildings
  WHERE player_id = v_player_id
    AND building_type IN ('rune_bakery', 'potion_workshop', 'enchanting_lab', 'kitchen');

  -- Total max slots = base slots + building slots
  v_total_max := v_base_max + v_building_slots;

  -- Get current active slot count (across all factories)
  SELECT COUNT(*) INTO v_current_count
  FROM public.factory_queue
  WHERE player_id = v_player_id;

  -- Calculate cost for next slot (only for base slots, building slots are free)
  v_cost := public.get_factory_slot_cost(v_base_max);

  RETURN jsonb_build_object(
    'current_slots_used', v_current_count,
    'max_slots', v_total_max,
    'base_slots', v_base_max,
    'building_slots', v_building_slots,
    'next_cost', v_cost,
    'can_add_more', v_current_count < v_total_max
  );
END;
$$;

-- Update start_factory_production to use total slots (base + building)
CREATE OR REPLACE FUNCTION public.start_factory_production(
  p_factory_type text,
  p_recipe_name text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_recipe_id integer;
  v_factory record;
  v_input_items jsonb;
  v_output_items jsonb;
  v_duration_minutes integer;
  v_current_slot_count integer;
  v_base_max_slots integer;
  v_building_slots integer;
  v_total_max_slots integer;
  v_key text;
  v_item_id integer;
  v_quantity integer;
  v_current_qty bigint;
BEGIN
  -- Get recipe info
  SELECT id, input_items, output_items, duration_minutes
  INTO v_recipe_id, v_input_items, v_output_items, v_duration_minutes
  FROM public.recipes
  WHERE name = p_recipe_name;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Recipe "%" not found', p_recipe_name;
  END IF;

  -- Get factory info
  SELECT * INTO v_factory
  FROM public.factories
  WHERE player_id = v_player_id AND factory_type = p_factory_type;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Factory "%" not found for this player', p_factory_type;
  END IF;

  -- Get base max slots from profile
  SELECT COALESCE(max_factory_slots, 2) INTO v_base_max_slots
  FROM public.profiles
  WHERE id = v_player_id;

  -- Get building slots from town map
  SELECT COALESCE(SUM(2), 0) INTO v_building_slots
  FROM public.buildings
  WHERE player_id = v_player_id
    AND building_type IN ('rune_bakery', 'potion_workshop', 'enchanting_lab', 'kitchen');

  -- Total max slots = base + building
  v_total_max_slots := v_base_max_slots + v_building_slots;

  -- Get current slot count
  SELECT COUNT(*) INTO v_current_slot_count
  FROM public.factory_queue
  WHERE player_id = v_player_id;

  -- Check if at limit
  IF v_current_slot_count >= v_total_max_slots THEN
    RAISE EXCEPTION 'Factory slot limit reached: %/% slots used. Build more factory buildings or purchase slots.', 
      v_current_slot_count, v_total_max_slots;
  END IF;

  -- Check inventory for input items
  FOR v_key, v_quantity IN SELECT * FROM jsonb_each_text(v_input_items) LOOP
    v_item_id := v_key::integer;
    SELECT COALESCE(quantity, 0) INTO v_current_qty
    FROM public.inventory
    WHERE player_id = v_player_id AND item_id = v_item_id;

    IF v_current_qty < v_quantity THEN
      RAISE EXCEPTION 'Insufficient %: required %, available %', 
        (SELECT name FROM public.items WHERE id = v_item_id), v_quantity, v_current_qty;
    END IF;
  END LOOP;

  -- Deduct input items
  FOR v_key, v_quantity IN SELECT * FROM jsonb_each_text(v_input_items) LOOP
    v_item_id := v_key::integer;
    UPDATE public.inventory
    SET quantity = quantity - v_quantity
    WHERE player_id = v_player_id AND item_id = v_item_id;
  END LOOP;

  -- Add to factory queue
  INSERT INTO public.factory_queue (
    player_id,
    factory_type,
    recipe_id,
    slot,
    started_at,
    finishes_at
  )
  VALUES (
    v_player_id,
    p_factory_type,
    v_recipe_id,
    v_current_slot_count + 1,
    NOW(),
    NOW() + (v_duration_minutes || ' minutes')::interval
  );
END;
$$;

COMMENT ON FUNCTION public.get_factory_slot_info() IS 'Get factory slot info including slots from buildings on town map. Each factory building provides 2 slots.';
COMMENT ON FUNCTION public.start_factory_production(text, text) IS 'Start factory production. Uses total slots (base + building slots). Each factory building on town map provides 2 slots.';

