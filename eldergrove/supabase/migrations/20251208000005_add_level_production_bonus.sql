-- Add level-based production speed bonuses to factory system
-- Bonus: 1% per level, max 50% bonus at level 50
-- Formula: production_time = base_time / (1.0 + (level * 0.01))

-- Function to get production speed multiplier based on player level
CREATE OR REPLACE FUNCTION public.get_production_speed_multiplier(p_player_id uuid)
RETURNS numeric
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_level integer;
  v_level_multiplier numeric;
  v_max_multiplier numeric := 1.5; -- Max 50% bonus (1.5x speed)
BEGIN
  -- Get player level (default to 1 if not found)
  SELECT COALESCE(level, 1) INTO v_player_level
  FROM public.profiles
  WHERE id = p_player_id;
  
  -- Level multiplier: 1% per level, capped at 50% (level 50+)
  v_level_multiplier := 1.0 + (LEAST(v_player_level, 50) * 0.01);
  
  -- Cap at max multiplier
  v_level_multiplier := LEAST(v_level_multiplier, v_max_multiplier);
  
  RETURN v_level_multiplier;
END;
$$;

COMMENT ON FUNCTION public.get_production_speed_multiplier(uuid) IS 'Get production speed multiplier based on player level. 1% per level, max 50% bonus at level 50.';

-- Update start_factory_production to apply level-based speed bonus
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
  v_slot_count integer;
  v_next_slot integer;
  v_input_key text;
  v_input_qty_str text;
  v_input_qty integer;
  v_current_qty integer;
  v_item_id integer;
  v_base_minutes integer;
  v_speed_multiplier numeric;
  v_level_multiplier numeric;
  v_factory_multiplier numeric := 1.0;
  v_final_minutes numeric;
  v_finishes_at timestamptz;
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

  -- Get recipe details
  SELECT * INTO v_recipe 
  FROM public.recipes 
  WHERE name = p_recipe_name;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Recipe "%" does not exist', p_recipe_name;
  END IF;

  -- Check available slots
  SELECT count(*) INTO v_slot_count
  FROM public.factory_queue
  WHERE player_id = v_player_id
  AND factory_type = p_factory_type;

  -- Get max slots for this factory type (from factory upgrades)
  -- Default to 2 if no upgrade info found
  IF v_slot_count >= COALESCE(
    (SELECT max_slots FROM public.factory_types WHERE factory_type = p_factory_type),
    2
  ) THEN
    RAISE EXCEPTION 'Factory "%" queue is full', p_factory_type;
  END IF;

  v_next_slot := v_slot_count + 1;

  -- Validate and deduct input resources
  FOR v_input_key, v_input_qty_str IN
    SELECT key, value FROM jsonb_each_text(v_recipe.input)
  LOOP
    v_input_qty := v_input_qty_str::integer;

    -- Map input resource name to item_id
    CASE v_input_key
      WHEN 'wheat' THEN v_item_id := 1;
      WHEN 'carrot' THEN v_item_id := 2;
      WHEN 'potato' THEN v_item_id := 3;
      WHEN 'tomato' THEN v_item_id := 4;
      WHEN 'corn' THEN v_item_id := 5;
      WHEN 'pumpkin' THEN v_item_id := 6;
      WHEN 'bread' THEN v_item_id := 11;
      WHEN 'berry' THEN v_item_id := 7;
      WHEN 'herbs' THEN v_item_id := 8;
      WHEN 'magic_mushroom' THEN v_item_id := 9;
      WHEN 'enchanted_flower' THEN v_item_id := 10;
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
  
  -- Get level-based speed multiplier
  v_level_multiplier := public.get_production_speed_multiplier(v_player_id);
  
  -- Get factory level multiplier (if factory has upgrades)
  IF v_factory.level > 1 THEN
    SELECT COALESCE(production_speed_multiplier, 1.0) INTO v_factory_multiplier
    FROM public.building_upgrade_costs
    WHERE building_type = p_factory_type
      AND from_level = v_factory.level - 1
      AND to_level = v_factory.level
    LIMIT 1;
  END IF;
  
  -- Apply both multipliers (level and factory upgrade)
  -- Final time = base_time / (level_multiplier * factory_multiplier)
  v_final_minutes := v_base_minutes / (v_level_multiplier * v_factory_multiplier);
  
  -- Calculate finish time
  v_finishes_at := now() + (v_final_minutes || ' minutes')::interval;

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

COMMENT ON FUNCTION public.start_factory_production(text, text) IS 'Start factory production: deducts input resources from inventory, adds to queue. Applies level-based speed bonus (1% per level, max 50% at level 50).';

