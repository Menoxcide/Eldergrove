-- Add XP gain system for all items in the game
-- This migration adds XP rewards for harvesting, crafting, selling, mining, and trading items

-- Helper function to calculate XP for an item based on its value
-- XP is calculated as: base XP * quantity, where base XP scales with item value
CREATE OR REPLACE FUNCTION public.get_item_xp(p_item_id integer, p_quantity integer DEFAULT 1)
RETURNS integer
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_base_xp integer;
  v_sell_price integer;
BEGIN
  -- Try to get sell price from marketplace to determine item value
  SELECT COALESCE(sell_price_crystals, 0) INTO v_sell_price
  FROM public.marketplace
  WHERE item_id = p_item_id;
  
  -- If not in marketplace, use default XP based on item_id ranges
  IF v_sell_price = 0 THEN
    -- Ores (20-29): Higher XP
    IF p_item_id >= 20 AND p_item_id <= 29 THEN
      v_base_xp := 15 + (p_item_id - 20) * 2; -- 15-33 XP per ore
    -- Crafted items (11-17): Medium-high XP
    ELSIF p_item_id >= 11 AND p_item_id <= 17 THEN
      v_base_xp := 10 + (p_item_id - 11) * 2; -- 10-22 XP per item
    -- Basic crops (1-10): Lower XP
    ELSE
      v_base_xp := 5 + (p_item_id - 1); -- 5-14 XP per crop
    END IF;
  ELSE
    -- Calculate XP based on sell price: 1 XP per 2 crystals value, minimum 5 XP
    v_base_xp := GREATEST(FLOOR(v_sell_price / 2.0), 5);
  END IF;
  
  RETURN v_base_xp * p_quantity;
END;
$$;

COMMENT ON FUNCTION public.get_item_xp(integer, integer) IS 'Calculate XP reward for an item based on its value. Returns XP amount for given quantity.';

-- Helper function to check and handle level-ups
-- Formula: XP needed for next level = current_level * 1000
CREATE OR REPLACE FUNCTION public.check_and_level_up(p_player_id uuid)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_current_level integer;
  v_current_xp bigint;
  v_xp_for_next_level integer;
  v_levels_gained integer := 0;
BEGIN
  -- Get current level and XP
  SELECT level, xp INTO v_current_level, v_current_xp
  FROM public.profiles
  WHERE id = p_player_id;
  
  -- Calculate XP needed for next level
  v_xp_for_next_level := v_current_level * 1000;
  
  -- Level up as many times as possible
  WHILE v_current_xp >= v_xp_for_next_level LOOP
    v_current_level := v_current_level + 1;
    v_current_xp := v_current_xp - v_xp_for_next_level;
    v_levels_gained := v_levels_gained + 1;
    v_xp_for_next_level := v_current_level * 1000;
  END LOOP;
  
  -- Update player level and remaining XP
  IF v_levels_gained > 0 THEN
    UPDATE public.profiles
    SET level = v_current_level,
        xp = v_current_xp
    WHERE id = p_player_id;
  END IF;
  
  RETURN v_levels_gained;
END;
$$;

COMMENT ON FUNCTION public.check_and_level_up(uuid) IS 'Check if player has enough XP to level up and update level accordingly. Returns number of levels gained.';

-- Helper function to grant XP to a player (with level-up check)
CREATE OR REPLACE FUNCTION public.grant_xp(p_player_id uuid, p_xp_amount integer)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_xp_multiplier numeric := 1.0;
  v_final_xp integer;
  v_levels_gained integer;
BEGIN
  -- Get active XP boost multiplier
  SELECT COALESCE(multiplier, 1.0) INTO v_xp_multiplier
  FROM public.active_boosts
  WHERE player_id = p_player_id
    AND boost_type = 'xp'
    AND expires_at > now()
  LIMIT 1;
  
  -- Calculate final XP with multiplier
  v_final_xp := (p_xp_amount * v_xp_multiplier)::integer;
  
  -- Grant XP
  UPDATE public.profiles
  SET xp = xp + v_final_xp
  WHERE id = p_player_id;
  
  -- Check for level-ups
  v_levels_gained := public.check_and_level_up(p_player_id);
  
  RETURN v_levels_gained;
END;
$$;

COMMENT ON FUNCTION public.grant_xp(uuid, integer) IS 'Grant XP to a player with boost multiplier support and automatic level-up handling. Returns number of levels gained.';

-- Update harvest_plot to grant XP when harvesting crops
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
  
  -- Update quest progress
  PERFORM public.update_quest_progress('harvest', NULL, 1);
  
  -- Auto-contribute to coven tasks
  PERFORM public.auto_contribute_coven_tasks('harvest', 1);

  RETURN v_new_item_qty;
END;
$$;

COMMENT ON FUNCTION public.harvest_plot(integer) IS 'Harvest ready crop from farm plot, adds crop item to inventory, grants XP, clears plot. Returns new item quantity.';

-- Update collect_factory to grant XP when collecting factory products
CREATE OR REPLACE FUNCTION public.collect_factory(p_slot integer)
RETURNS bigint
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
  v_new_crystals bigint;
  v_crystal_multiplier numeric := 1.0;
  v_total_xp integer := 0;
BEGIN
  -- Fetch queue entry
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

  -- Award output resources to inventory and calculate XP
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
        -- Map recipe output names to correct item_ids (matching itemUtils.ts)
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
          
          -- Add XP for crafted items
          v_total_xp := v_total_xp + public.get_item_xp(v_item_id, v_qty);
        END IF;
    END CASE;
  END LOOP;

  -- Grant XP for crafting
  IF v_total_xp > 0 THEN
    PERFORM public.grant_xp(v_player_id, v_total_xp);
  END IF;

  -- Remove queue entry
  DELETE FROM public.factory_queue
  WHERE player_id = v_player_id
    AND slot = p_slot;

  -- Return updated crystals quantity
  SELECT COALESCE(crystals, 0) INTO v_new_crystals
  FROM public.profiles
  WHERE id = v_player_id;

  -- Check achievements
  PERFORM public.check_achievements('produce_count', 1);
  
  -- Update quest progress
  PERFORM public.update_quest_progress('produce', NULL, 1);
  
  -- Auto-contribute to coven tasks
  PERFORM public.auto_contribute_coven_tasks('produce', 1);

  RETURN v_new_crystals;
END;
$$;

COMMENT ON FUNCTION public.collect_factory(integer) IS 'Collect completed factory production: adds items to inventory, grants XP for crafted items, clears slot. Returns new crystals balance.';

-- Update sell_item to grant XP when selling items
CREATE OR REPLACE FUNCTION public.sell_item(p_item_id integer, p_quantity integer)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_sell_price integer;
  v_current_qty bigint;
  v_total_crystals bigint;
  v_new_crystals bigint;
  v_xp_gained integer;
BEGIN
  -- Validate quantity
  IF p_quantity <= 0 THEN
    RAISE EXCEPTION 'Quantity must be greater than 0';
  END IF;

  -- Get sell price
  SELECT sell_price_crystals INTO v_sell_price
  FROM public.marketplace
  WHERE item_id = p_item_id AND available = true;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Item % is not available for sale in the marketplace', p_item_id;
  END IF;

  -- Get current inventory quantity
  SELECT COALESCE(quantity, 0) INTO v_current_qty
  FROM public.inventory
  WHERE player_id = v_player_id AND item_id = p_item_id;

  IF v_current_qty < p_quantity THEN
    RAISE EXCEPTION 'Insufficient quantity: required %, available %', p_quantity, v_current_qty;
  END IF;

  -- Calculate total crystals to award
  v_total_crystals := v_sell_price * p_quantity;

  -- Deduct items from inventory
  UPDATE public.inventory
  SET quantity = quantity - p_quantity
  WHERE player_id = v_player_id AND item_id = p_item_id;

  -- Award crystals to player
  UPDATE public.profiles
  SET crystals = crystals + v_total_crystals
  WHERE id = v_player_id;

  -- Grant XP for selling (reduced XP compared to harvesting/crafting)
  v_xp_gained := public.get_item_xp(p_item_id, p_quantity) / 2; -- Half XP for selling
  IF v_xp_gained > 0 THEN
    PERFORM public.grant_xp(v_player_id, v_xp_gained);
  END IF;

  -- Get updated crystals
  SELECT crystals INTO v_new_crystals
  FROM public.profiles
  WHERE id = v_player_id;

  -- Update quest progress
  PERFORM public.update_quest_progress('sell', NULL, p_quantity);

  -- Return result
  RETURN jsonb_build_object(
    'success', true,
    'crystals_awarded', v_total_crystals,
    'new_crystal_balance', v_new_crystals,
    'items_sold', p_quantity,
    'xp_gained', v_xp_gained
  );
END;
$$;

COMMENT ON FUNCTION public.sell_item(integer, integer) IS 'Sell items from inventory for crystals. Grants XP (half of harvest XP). Returns success status, crystals awarded, new balance, and XP gained.';

-- Update mine_ore to grant XP when mining (and when finding ores)
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
      total_digs = total_digs + 1,
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

  -- Update quest progress
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

COMMENT ON FUNCTION public.mine_ore(text) IS 'Mine ore: consumes energy, reduces tool durability, may find ores based on depth and tool. Grants XP for mining and finding ores.';

-- Update purchase_listing to grant XP when buying from market box
CREATE OR REPLACE FUNCTION public.purchase_listing(p_listing_id integer)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_buyer_id uuid := auth.uid();
  v_listing record;
  v_total_cost integer;
  v_buyer_crystals bigint;
  v_seller_crystals bigint;
  v_commission integer;
  v_seller_profit integer;
  v_result jsonb;
  v_xp_gained integer;
BEGIN
  -- Get listing
  SELECT * INTO v_listing
  FROM public.market_listings
  WHERE id = p_listing_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Listing % not found', p_listing_id;
  END IF;

  IF v_listing.purchased_at IS NOT NULL THEN
    RAISE EXCEPTION 'Listing % already purchased', p_listing_id;
  END IF;

  IF v_listing.expires_at < now() THEN
    RAISE EXCEPTION 'Listing % has expired', p_listing_id;
  END IF;

  IF v_listing.seller_id = v_buyer_id THEN
    RAISE EXCEPTION 'Cannot purchase your own listing';
  END IF;

  v_total_cost := v_listing.price_crystals;

  -- Check buyer crystals
  SELECT crystals INTO v_buyer_crystals
  FROM public.profiles
  WHERE id = v_buyer_id;

  IF v_buyer_crystals < v_total_cost THEN
    RAISE EXCEPTION 'Insufficient crystals: required %, available %', v_total_cost, v_buyer_crystals;
  END IF;

  -- Calculate commission (5%)
  v_commission := FLOOR(v_total_cost * 0.05);
  v_seller_profit := v_total_cost - v_commission;

  -- Deduct crystals from buyer
  UPDATE public.profiles
  SET crystals = crystals - v_total_cost
  WHERE id = v_buyer_id;

  -- Add profit to seller
  UPDATE public.profiles
  SET crystals = crystals + v_seller_profit
  WHERE id = v_listing.seller_id;

  -- Add items to buyer inventory
  INSERT INTO public.inventory (player_id, item_id, quantity)
  VALUES (v_buyer_id, v_listing.item_id, v_listing.quantity::bigint)
  ON CONFLICT (player_id, item_id) DO UPDATE SET
    quantity = inventory.quantity + excluded.quantity;

  -- Grant XP for purchasing items (reduced XP compared to harvesting)
  v_xp_gained := public.get_item_xp(v_listing.item_id, v_listing.quantity) / 3; -- One-third XP for buying
  IF v_xp_gained > 0 THEN
    PERFORM public.grant_xp(v_buyer_id, v_xp_gained);
  END IF;

  -- Mark listing as purchased
  UPDATE public.market_listings
  SET purchased_at = now(),
      buyer_id = v_buyer_id
  WHERE id = p_listing_id;

  -- Check achievements
  PERFORM public.check_achievements('trade_count', 1);

  -- Return result
  SELECT jsonb_build_object(
    'success', true,
    'item_id', v_listing.item_id,
    'quantity', v_listing.quantity,
    'cost', v_total_cost,
    'xp_gained', v_xp_gained
  ) INTO v_result;

  RETURN v_result;
END;
$$;

COMMENT ON FUNCTION public.purchase_listing(integer) IS 'Purchase a market listing: transfers items and crystals, grants XP to buyer (one-third of harvest XP). Returns success status, item details, cost, and XP gained.';

