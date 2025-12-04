-- Fix incorrect update_quest_progress function calls
-- The function signature is: update_quest_progress(p_objective_type text, p_quest_id integer DEFAULT NULL, p_increment integer DEFAULT 1)
-- Previous calls had parameters swapped (NULL as first parameter instead of objective_type)

-- Fix harvest_plot function
CREATE OR REPLACE FUNCTION public.harvest_plot(p_plot_index integer)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_crop_id integer;
  v_ready_at timestamptz;
  v_yield_qty integer;
  v_item_id integer;
  v_new_item_qty bigint;
  v_xp_gained integer;
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

  -- Fetch crop yield and item_id
  SELECT yield_crystals, item_id INTO v_yield_qty, v_item_id
  FROM public.crops
  WHERE id = v_crop_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Invalid crop_id % found on plot %', v_crop_id, p_plot_index;
  END IF;

  IF v_item_id IS NULL THEN
    RAISE EXCEPTION 'Crop % does not have an item_id mapping', v_crop_id;
  END IF;

  -- Award crop item to player inventory
  INSERT INTO public.inventory (player_id, item_id, quantity)
  VALUES (auth.uid(), v_item_id, v_yield_qty::bigint)
  ON CONFLICT (player_id, item_id) DO UPDATE SET
    quantity = inventory.quantity + excluded.quantity;

  -- Grant XP for harvesting
  v_xp_gained := public.get_item_xp(v_item_id, v_yield_qty);
  PERFORM public.grant_xp(auth.uid(), v_xp_gained);

  -- Clear the plot
  UPDATE public.farm_plots
  SET crop_id = NULL,
      planted_at = NULL,
      ready_at = NULL
  WHERE player_id = auth.uid()
    AND plot_index = p_plot_index;

  -- Fetch and return updated item quantity
  SELECT COALESCE(quantity, 0) INTO v_new_item_qty
  FROM public.inventory
  WHERE player_id = auth.uid() AND item_id = v_item_id;

  -- Check achievements
  PERFORM public.check_achievements('harvest_count', 1);
  
  -- Update quest progress (FIXED: objective_type first, not NULL)
  PERFORM public.update_quest_progress('harvest', NULL, 1);
  
  -- Auto-contribute to coven tasks
  PERFORM public.auto_contribute_coven_tasks('harvest', 1);

  RETURN v_new_item_qty;
END;
$$;

-- Fix collect_factory function
-- Drop the old function first since we're changing the return type from bigint to jsonb
DROP FUNCTION IF EXISTS public.collect_factory(integer);

CREATE OR REPLACE FUNCTION public.collect_factory(p_slot integer)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_factory_type text;
  v_queue record;
  v_output jsonb;
  v_key text;
  v_qty_str text;
  v_qty integer;
  v_item_id integer;
  v_total_xp integer := 0;
  v_crystal_multiplier numeric := 1.0;
  v_result jsonb;
BEGIN
  -- Fetch queue entry by slot
  SELECT * INTO v_queue
  FROM public.factory_queue
  WHERE player_id = v_player_id
    AND slot = p_slot;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'No production found in slot %', p_slot;
  END IF;

  v_factory_type := v_queue.factory_type;

  IF v_queue.finishes_at > now() THEN
    RAISE EXCEPTION 'Production in slot % not ready yet (finishes at %)', p_slot, v_queue.finishes_at;
  END IF;

  -- Get active crystal boost multiplier
  SELECT COALESCE(multiplier, 1.0) INTO v_crystal_multiplier
  FROM public.active_boosts
  WHERE player_id = v_player_id
    AND boost_type = 'crystal'
    AND expires_at > now()
  LIMIT 1;

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
      WHEN 'crystals' THEN
        -- Apply crystal boost and add to profile crystals
        v_qty := (v_qty * v_crystal_multiplier)::integer;
        UPDATE public.profiles
        SET crystals = crystals + v_qty
        WHERE id = v_player_id;
        -- Crystals don't grant XP (they're currency)
      ELSE
        -- Other items go to inventory
        CASE v_key
          WHEN 'wheat' THEN v_item_id := 1;
          WHEN 'carrot' THEN v_item_id := 2;
          WHEN 'potato' THEN v_item_id := 3;
          WHEN 'tomato' THEN v_item_id := 4;
          WHEN 'corn' THEN v_item_id := 5;
          WHEN 'pumpkin' THEN v_item_id := 6;
          WHEN 'berry' THEN v_item_id := 7;
          WHEN 'herbs' THEN v_item_id := 8;
          WHEN 'magic_mushroom' THEN v_item_id := 9;
          WHEN 'enchanted_flower' THEN v_item_id := 10;
          WHEN 'bread' THEN v_item_id := 11;
          WHEN 'vegetable_stew' THEN v_item_id := 12;
          WHEN 'corn_bread' THEN v_item_id := 13;
          WHEN 'pumpkin_pie' THEN v_item_id := 14;
          WHEN 'herbal_tea' THEN v_item_id := 15;
          WHEN 'magic_potion' THEN v_item_id := 16;
          WHEN 'fruit_salad' THEN v_item_id := 17;
          ELSE NULL;
        END CASE;

        IF v_item_id IS NOT NULL THEN
          INSERT INTO public.inventory (player_id, item_id, quantity)
          VALUES (v_player_id, v_item_id, v_qty::bigint)
          ON CONFLICT (player_id, item_id) DO UPDATE SET
            quantity = inventory.quantity + excluded.quantity;

          -- Calculate XP for this item
          v_total_xp := v_total_xp + public.get_item_xp(v_item_id, v_qty);
        END IF;
    END CASE;
  END LOOP;

  -- Grant XP
  IF v_total_xp > 0 THEN
    PERFORM public.grant_xp(v_player_id, v_total_xp);
  END IF;

  -- Remove queue entry
  DELETE FROM public.factory_queue
  WHERE player_id = v_player_id
    AND slot = p_slot;

  -- Check achievements
  PERFORM public.check_achievements('produce_count', 1);
  
  -- Update quest progress (FIXED: objective_type first, not NULL)
  PERFORM public.update_quest_progress('produce', NULL, 1);
  
  -- Auto-contribute to coven tasks
  PERFORM public.auto_contribute_coven_tasks('produce', 1);

  -- Return result
  SELECT jsonb_build_object(
    'success', true,
    'output', v_output,
    'xp_gained', v_total_xp
  ) INTO v_result;

  RETURN v_result;
END;
$$;

-- Fix sell_item function
-- Note: Keeping return type as jsonb to match frontend expectations
CREATE OR REPLACE FUNCTION public.sell_item(p_item_id integer, p_quantity integer)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_listing record;
  v_total_price bigint;
  v_current_qty bigint;
  v_xp_gained integer;
  v_new_crystals bigint;
  v_result jsonb;
BEGIN
  -- Validate quantity
  IF p_quantity <= 0 THEN
    RAISE EXCEPTION 'Quantity must be greater than 0';
  END IF;

  -- Get marketplace listing
  SELECT * INTO v_listing
  FROM public.marketplace
  WHERE item_id = p_item_id AND available = true;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Item % is not available for sale', p_item_id;
  END IF;

  -- Check inventory
  SELECT COALESCE(quantity, 0) INTO v_current_qty
  FROM public.inventory
  WHERE player_id = v_player_id AND item_id = p_item_id;

  IF v_current_qty < p_quantity THEN
    RAISE EXCEPTION 'Insufficient quantity: have %, trying to sell %', v_current_qty, p_quantity;
  END IF;

  -- Calculate total price
  v_total_price := v_listing.sell_price_crystals * p_quantity;

  -- Remove from inventory
  UPDATE public.inventory
  SET quantity = quantity - p_quantity
  WHERE player_id = v_player_id AND item_id = p_item_id;

  -- Add crystals
  UPDATE public.profiles
  SET crystals = crystals + v_total_price
  WHERE id = v_player_id;

  -- Grant XP (half of normal XP for selling)
  v_xp_gained := public.get_item_xp(p_item_id, p_quantity) / 2; -- Half XP for selling
  IF v_xp_gained > 0 THEN
    PERFORM public.grant_xp(v_player_id, v_xp_gained);
  END IF;

  -- Get updated crystals
  SELECT crystals INTO v_new_crystals
  FROM public.profiles
  WHERE id = v_player_id;

  -- Update quest progress (FIXED: objective_type first, not NULL)
  PERFORM public.update_quest_progress('sell', NULL, p_quantity);

  -- Return result as jsonb to match frontend expectations
  SELECT jsonb_build_object(
    'success', true,
    'crystals_awarded', v_total_price,
    'new_crystal_balance', v_new_crystals,
    'items_sold', p_quantity
  ) INTO v_result;

  RETURN v_result;
END;
$$;

-- Fix mine_ore function
CREATE OR REPLACE FUNCTION public.mine_ore(p_tool_type text DEFAULT 'basic_pickaxe')
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_mine_dig record;
  v_tool record;
  v_energy_cost integer;
  v_current_energy integer;
  v_max_energy integer := 100;
  v_ore_id integer;
  v_ore_type record;
  v_new_depth integer;
  v_result jsonb;
  v_xp_gained integer := 0;
BEGIN
  -- Get or create mine_digs entry
  SELECT * INTO v_mine_dig
  FROM public.mine_digs
  WHERE player_id = v_player_id;

  IF NOT FOUND THEN
    PERFORM public.initialize_mining(v_player_id);
    SELECT * INTO v_mine_dig
    FROM public.mine_digs
    WHERE player_id = v_player_id;
  END IF;

  -- Reset energy if needed
  IF v_mine_dig.last_energy_reset < now() - interval '24 hours' THEN
    UPDATE public.mine_digs
    SET energy_used_today = 0, last_energy_reset = now()
    WHERE player_id = v_player_id;
    v_mine_dig.energy_used_today := 0;
  END IF;

  -- Get tool
  SELECT * INTO v_tool
  FROM public.mining_tools
  WHERE player_id = v_player_id AND tool_type = p_tool_type;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Tool "%" not found. Please acquire a basic pickaxe first.', p_tool_type;
  END IF;

  IF v_tool.durability <= 0 THEN
    RAISE EXCEPTION 'Tool "%" is broken. Please repair it.', p_tool_type;
  END IF;

  -- Calculate energy cost
  v_energy_cost := public.get_dig_energy_cost(p_tool_type, v_mine_dig.depth);
  v_current_energy := v_max_energy - v_mine_dig.energy_used_today;

  IF v_current_energy < v_energy_cost THEN
    RAISE EXCEPTION 'Insufficient energy: required %, available %', v_energy_cost, v_current_energy;
  END IF;

  -- Determine ore drop
  v_ore_id := public.get_ore_drop(v_mine_dig.depth, p_tool_type);

  -- Update energy
  UPDATE public.mine_digs
  SET energy_used_today = energy_used_today + v_energy_cost,
      depth = depth + 1,
      last_dig_at = now()
  WHERE player_id = v_player_id;

  -- Reduce tool durability
  UPDATE public.mining_tools
  SET durability = GREATEST(durability - 1, 0)
  WHERE player_id = v_player_id AND tool_type = p_tool_type;

  -- Award ore if found and grant XP
  IF v_ore_id IS NOT NULL THEN
    SELECT * INTO v_ore_type FROM public.ore_types WHERE item_id = v_ore_id;
    
    INSERT INTO public.inventory (player_id, item_id, quantity)
    VALUES (v_player_id, v_ore_id, 1)
    ON CONFLICT (player_id, item_id) DO UPDATE SET
      quantity = inventory.quantity + 1;

    -- Grant XP for finding ore
    v_xp_gained := public.get_item_xp(v_ore_id, 1);
    PERFORM public.grant_xp(v_player_id, v_xp_gained);

    -- Update artifacts JSONB
    UPDATE public.mine_digs
    SET artifacts = artifacts || jsonb_build_array(jsonb_build_object(
      'item_id', v_ore_id,
      'name', v_ore_type.name,
      'found_at', now(),
      'depth', v_mine_dig.depth + 1
    ))
    WHERE player_id = v_player_id;
  ELSE
    -- Grant small XP for mining even if no ore found (5 XP per dig)
    PERFORM public.grant_xp(v_player_id, 5);
    v_xp_gained := 5;
  END IF;

  -- Check achievements
  PERFORM public.check_achievements('mine_count', 1);

  -- Update quest progress (FIXED: objective_type first, not NULL)
  PERFORM public.update_quest_progress('mine', NULL, 1);

  -- Return result
  SELECT jsonb_build_object(
    'success', true,
    'ore_found', v_ore_id IS NOT NULL,
    'ore_id', v_ore_id,
    'ore_name', CASE WHEN v_ore_id IS NOT NULL THEN v_ore_type.name ELSE NULL END,
    'new_depth', v_mine_dig.depth + 1,
    'energy_remaining', v_max_energy - (v_mine_dig.energy_used_today + v_energy_cost),
    'tool_durability', GREATEST(v_tool.durability - 1, 0),
    'xp_gained', v_xp_gained
  ) INTO v_result;

  RETURN v_result;
END;
$$;

COMMENT ON FUNCTION public.harvest_plot(integer) IS 'Harvest ready crop from farm plot, adds crop item to inventory, grants XP, clears plot. Returns new item quantity.';
COMMENT ON FUNCTION public.collect_factory(integer) IS 'Collect completed factory production, adds items to inventory, grants XP. Returns result with output and XP gained.';
COMMENT ON FUNCTION public.sell_item(integer, integer) IS 'Sell items to marketplace, grants crystals and XP. Returns new crystal balance.';
COMMENT ON FUNCTION public.mine_ore(text) IS 'Mine ore: consumes energy, reduces tool durability, may find ores based on depth and tool. Grants XP for mining and finding ores.';

