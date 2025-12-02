-- Phase 6.5: Integrate farm/factory RPCs with inventory table (item_id 1=wheat, 2=bread, 3=crystals)

-- Update bread recipe to produce bread and crystals
UPDATE public.recipes
SET output = '{"bread": 1, "crystals": 10}'::jsonb
WHERE name = 'Bread';

-- 1. Updated harvest_plot RPC: harvest adds wheat (item_id=1) to inventory instead of profiles.crystals
CREATE OR REPLACE FUNCTION public.harvest_plot(p_plot_index integer)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_crop_id integer;
  v_ready_at timestamptz;
  v_yield_wheat integer;
  v_new_wheat bigint;
BEGIN
  -- Fetch current plot crop info
  SELECT crop_id, ready_at INTO v_crop_id, v_ready_at
  FROM public.farm_plots
  WHERE player_id = auth.uid()
    AND plot_index = p_plot_index;

  IF v_crop_id IS NULL THEN
    RAISE EXCEPTION 'No crop to harvest on plot % for this player', p_plot_index;
  END IF;

  IF v_ready_at > now() THEN
    RAISE EXCEPTION 'Crop on plot % is not ready yet (ready at %)', p_plot_index, v_ready_at;
  END IF;

  -- Fetch crop yield (repurposed yield_crystals as wheat yield)
  SELECT yield_crystals INTO v_yield_wheat
  FROM public.crops
  WHERE id = v_crop_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Invalid crop_id % found on plot %', v_crop_id, p_plot_index;
  END IF;

  -- Award wheat to player inventory
  INSERT INTO public.inventory (player_id, item_id, quantity)
  VALUES (auth.uid(), 1, v_yield_wheat::bigint)
  ON CONFLICT (player_id, item_id) DO UPDATE SET
    quantity = inventory.quantity + excluded.quantity;

  -- Clear the plot
  UPDATE public.farm_plots
  SET crop_id = NULL,
      planted_at = NULL,
      ready_at = NULL
  WHERE player_id = auth.uid()
    AND plot_index = p_plot_index;

  -- Fetch and return updated wheat quantity
  SELECT COALESCE(quantity, 0) INTO v_new_wheat
  FROM public.inventory
  WHERE player_id = auth.uid() AND item_id = 1;

  RETURN v_new_wheat;
END;
$$;

COMMENT ON FUNCTION public.harvest_plot(integer) IS 'Harvest ready crop from farm plot, adds wheat (item_id=1) yield to inventory, clears plot. Returns new wheat balance.';

-- 2. Updated start_factory_production RPC: deduct input (wheat item_id=1) from inventory instead of profiles.resources
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
  v_slot_count integer;
  v_next_slot integer;
  v_input_key text;
  v_input_qty_str text;
  v_input_qty integer;
  v_current_qty integer;
  v_item_id integer;
BEGIN
  -- Validate factory exists
  IF NOT EXISTS (
    SELECT 1 FROM public.factories 
    WHERE player_id = v_player_id 
    AND factory_type = p_factory_type
  ) THEN
    RAISE EXCEPTION 'Factory "%" does not exist for this player', p_factory_type;
  END IF;

  -- Get recipe details
  SELECT * INTO v_recipe 
  FROM public.recipes 
  WHERE name = p_recipe_name;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Recipe "%" does not exist', p_recipe_name;
  END IF;

  -- Check available slots (max 2)
  SELECT count(*) INTO v_slot_count
  FROM public.factory_queue
  WHERE player_id = v_player_id
  AND factory_type = p_factory_type;

  IF v_slot_count >= 2 THEN
    RAISE EXCEPTION 'Factory "%" queue is full (max 2 slots)', p_factory_type;
  END IF;

  v_next_slot := v_slot_count + 1;

  -- Validate and deduct input resources from inventory
  FOR v_input_key, v_input_qty_str IN
    SELECT key, value FROM jsonb_each_text(v_recipe.input)
  LOOP
    v_input_qty := v_input_qty_str::integer;

    -- Map input resource name to item_id
    CASE v_input_key
      WHEN 'wheat' THEN v_item_id := 1;
      WHEN 'bread' THEN v_item_id := 2;
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
    now() + (v_recipe.minutes * interval '1 minute')
  );
END;
$$;

COMMENT ON FUNCTION public.start_factory_production(text, text) IS 'Start factory production: deducts input resources (wheat/bread item_ids 1/2) from inventory, adds to queue (max 2 slots).';

-- 3. Updated collect_factory RPC: add recipe output (bread/crystals item_ids 2/3) to inventory instead of profiles.crystals
CREATE OR REPLACE FUNCTION public.collect_factory(p_slot integer)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_factory_type text := 'Rune Bakery';
  v_queue record;
  v_output jsonb;
  v_key text;
  v_qty_str text;
  v_qty integer;
  v_item_id integer;
  v_new_crystals bigint;
BEGIN
  -- Fetch queue entry
  SELECT * INTO v_queue
  FROM public.factory_queue
  WHERE player_id = v_player_id
    AND factory_type = v_factory_type
    AND slot = p_slot;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'No production found in slot % of %', p_slot, v_factory_type;
  END IF;

  IF v_queue.finishes_at > now() THEN
    RAISE EXCEPTION 'Production in slot % of % not ready yet (finishes at %)', p_slot, v_factory_type, v_queue.finishes_at;
  END IF;

  -- Get recipe output
  SELECT output INTO v_output
  FROM public.recipes
  WHERE id = v_queue.recipe_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Recipe with id % not found', v_queue.recipe_id;
  END IF;

  -- Award output resources to inventory
  FOR v_key, v_qty_str IN SELECT key, value FROM jsonb_each_text(v_output) LOOP
    v_qty := v_qty_str::integer;

    -- Map output resource name to item_id
    CASE v_key
      WHEN 'wheat' THEN v_item_id := 1;
      WHEN 'bread' THEN v_item_id := 2;
      WHEN 'crystals' THEN v_item_id := 3;
      ELSE RAISE EXCEPTION 'Unsupported output resource "%"', v_key;
    END CASE;

    INSERT INTO public.inventory (player_id, item_id, quantity)
    VALUES (v_player_id, v_item_id, v_qty::bigint)
    ON CONFLICT (player_id, item_id) DO UPDATE SET
      quantity = inventory.quantity + excluded.quantity;
  END LOOP;

  -- Remove queue entry
  DELETE FROM public.factory_queue
  WHERE player_id = v_player_id
    AND factory_type = v_factory_type
    AND slot = p_slot;

  -- Return updated crystals quantity (for frontend compatibility)
  SELECT COALESCE(quantity, 0) INTO v_new_crystals
  FROM public.inventory
  WHERE player_id = v_player_id AND item_id = 3;

  -- Check achievements
  PERFORM public.check_achievements('produce_count', 1);
  
  -- Update quest progress
  PERFORM public.update_quest_progress(NULL, 'produce', 1);
  
  -- Auto-contribute to coven tasks
  PERFORM public.auto_contribute_coven_tasks('produce', 1);

  RETURN v_new_crystals;
END;
$$;

COMMENT ON FUNCTION public.collect_factory(integer) IS 'Collect completed Rune Bakery production: adds recipe output (bread/crystals item_ids 2/3) to inventory, clears slot. Returns new crystals quantity.';