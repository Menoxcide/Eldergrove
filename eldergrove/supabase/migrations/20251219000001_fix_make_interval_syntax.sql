-- Fix start_factory_production RPC to use correct interval syntax
-- The make_interval function with named parameters doesn't work in all PostgreSQL versions
-- Reverting to interval string casting which is more compatible

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
  v_recipe record;
  v_factory record;
  v_current_slot_count integer;
  v_base_max_slots integer;
  v_building_slots integer;
  v_total_max_slots integer;
  v_input_key text;
  v_input_qty_str text;
  v_input_qty integer;
  v_item_id integer;
  v_current_qty bigint;
  v_base_minutes integer;
  v_speed_multiplier numeric;
  v_level_multiplier numeric;
  v_factory_multiplier numeric := 1.0;
  v_final_minutes numeric;
  v_finishes_at timestamptz;
  v_next_slot integer;
BEGIN
  -- Validate factory exists
  IF NOT EXISTS (
    SELECT 1 FROM public.factories
    WHERE player_id = v_player_id
    AND factory_type = p_factory_type
  ) THEN
    RAISE EXCEPTION 'Factory "%" does not exist for this player', p_factory_type;
  END IF;

  -- Get factory info (for factory level multiplier)
  SELECT * INTO v_factory
  FROM public.factories
  WHERE player_id = v_player_id AND factory_type = p_factory_type;

  -- Get recipe details (using correct column names: input, output, minutes)
  SELECT * INTO v_recipe
  FROM public.recipes
  WHERE name = p_recipe_name;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Recipe "%" does not exist', p_recipe_name;
  END IF;

  -- Validate recipe minutes is not NULL
  IF v_recipe.minutes IS NULL THEN
    RAISE EXCEPTION 'Recipe "%" has NULL minutes value', p_recipe_name;
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

  -- Get current slot count (across all factories)
  SELECT COUNT(*) INTO v_current_slot_count
  FROM public.factory_queue
  WHERE player_id = v_player_id;

  -- Check if at limit
  IF v_current_slot_count >= v_total_max_slots THEN
    RAISE EXCEPTION 'Factory slot limit reached: %/% slots used. Build more factory buildings or purchase slots.',
      v_current_slot_count, v_total_max_slots;
  END IF;

  v_next_slot := v_current_slot_count + 1;

  -- Validate and deduct input resources from inventory
  -- Recipe input uses item names as keys (e.g., 'wheat', 'carrot') that need to be mapped to item_ids
  FOR v_input_key, v_input_qty_str IN
    SELECT key, value FROM jsonb_each_text(v_recipe.input)
  LOOP
    v_input_qty := v_input_qty_str::integer;

    -- Map input resource name to item_id
    CASE LOWER(v_input_key)
      WHEN 'wheat' THEN v_item_id := 1;
      WHEN 'carrot' THEN v_item_id := 2;
      WHEN 'potato' THEN v_item_id := 3;
      WHEN 'tomato' THEN v_item_id := 4;
      WHEN 'corn' THEN v_item_id := 5;
      WHEN 'pumpkin' THEN v_item_id := 6;
      WHEN 'bread' THEN v_item_id := 8;
      WHEN 'berry' THEN v_item_id := 11;
      WHEN 'herbs' THEN v_item_id := 12;
      WHEN 'magic_mushroom' THEN v_item_id := 13;
      WHEN 'enchanted_flower' THEN v_item_id := 14;
      ELSE RAISE EXCEPTION 'Unsupported input resource "%"', v_input_key;
    END CASE;

    v_current_qty := COALESCE(
      (SELECT quantity FROM public.inventory WHERE player_id = v_player_id AND item_id = v_item_id),
      0
    );

    IF v_current_qty < v_input_qty THEN
      RAISE EXCEPTION 'Insufficient "%": required %, available %', v_input_key, v_input_qty, v_current_qty;
    END IF;

    -- Deduct from inventory
    UPDATE public.inventory SET
      quantity = quantity - v_input_qty
    WHERE player_id = v_player_id AND item_id = v_item_id;
  END LOOP;

  -- Calculate production time with level-based speed bonus
  v_base_minutes := v_recipe.minutes;

  -- Get level-based speed multiplier (with NULL handling)
  v_level_multiplier := COALESCE(public.get_production_speed_multiplier(v_player_id), 1.0);

  -- Get factory level multiplier (if factory has upgrades)
  -- Ensure v_factory_multiplier is never NULL with COALESCE
  IF v_factory.level > 1 THEN
    SELECT COALESCE(production_speed_multiplier, 1.0) INTO v_factory_multiplier
    FROM public.building_upgrade_costs
    WHERE building_type = p_factory_type
      AND from_level = v_factory.level - 1
      AND to_level = v_factory.level
    LIMIT 1;
  END IF;

  -- Ensure v_factory_multiplier is never NULL (safeguard)
  v_factory_multiplier := COALESCE(v_factory_multiplier, 1.0);

  -- Apply both multipliers (level and factory upgrade)
  -- Final time = base_time / (level_multiplier * factory_multiplier)
  -- Ensure all values are not NULL before calculation
  v_final_minutes := COALESCE(v_base_minutes, 0) / (COALESCE(v_level_multiplier, 1.0) * COALESCE(v_factory_multiplier, 1.0));

  -- Validate that v_final_minutes is not NULL before calculating finish time
  IF v_final_minutes IS NULL OR v_final_minutes <= 0 THEN
    RAISE EXCEPTION 'Invalid production time calculation: base_minutes=%, level_multiplier=%, factory_multiplier=%',
      v_base_minutes, v_level_multiplier, v_factory_multiplier;
  END IF;

  -- Calculate finish time using interval casting (compatible with numeric type)
  -- This approach works with numeric values and is compatible across PostgreSQL versions
  v_finishes_at := now() + (v_final_minutes::text || ' minutes')::interval;

  -- Final validation that finishes_at is not NULL before insert
  IF v_finishes_at IS NULL THEN
    RAISE EXCEPTION 'Failed to calculate finish time for production';
  END IF;

  -- Insert into queue
  INSERT INTO public.factory_queue (
    player_id,
    factory_type,
    recipe_id,
    slot,
    started_at,
    finishes_at
  ) VALUES (
    v_player_id,
    p_factory_type,
    v_recipe.id,
    v_next_slot,
    now(),
    v_finishes_at
  );
END;
$$;

COMMENT ON FUNCTION public.start_factory_production(text, text) IS 'Start factory production: deducts input resources from inventory, adds to queue. Uses total slots (base + building slots). Applies level-based speed bonus and factory level multiplier. Recipe input uses item names (e.g., wheat, carrot) that are mapped to item_ids. Includes comprehensive NULL validation to ensure finishes_at is never NULL. Fixed interval calculation syntax for compatibility.';

