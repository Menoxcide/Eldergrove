-- Fix mine_ore function: v_ore_type may be unassigned when accessing v_ore_type.name
-- The issue occurs when v_ore_id IS NOT NULL but the SELECT INTO doesn't find a matching ore_type
-- or when accessing v_ore_type.name in the return statement without proper initialization

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
  v_ore_name text := NULL;
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
    
    -- Check if ore_type was found, if not raise an error
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Ore type not found for item_id: %', v_ore_id;
    END IF;
    
    -- Store ore name in a separate variable for safe access
    v_ore_name := v_ore_type.name;
    
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
      'name', v_ore_name,
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

  -- Return result - use v_ore_name which is safely initialized
  SELECT jsonb_build_object(
    'success', true,
    'ore_found', v_ore_id IS NOT NULL,
    'ore_id', v_ore_id,
    'ore_name', v_ore_name,
    'new_depth', v_mine_dig.depth + 1,
    'energy_remaining', v_max_energy - (v_mine_dig.energy_used_today + v_energy_cost),
    'tool_durability', GREATEST(v_tool.durability - 1, 0),
    'xp_gained', v_xp_gained
  ) INTO v_result;

  RETURN v_result;
END;
$$;

COMMENT ON FUNCTION public.mine_ore(text) IS 'Mine ore: consumes energy, reduces tool durability, may find ores based on depth and tool. Grants XP for mining and finding ores. Fixed: v_ore_type unassigned error.';

