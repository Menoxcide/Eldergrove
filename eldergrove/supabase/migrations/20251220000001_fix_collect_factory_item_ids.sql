-- Fix collect_factory function to use correct item IDs for production items
-- The database was mapping berry/herbs/magic_mushroom/enchanted_flower to IDs 7-10
-- but the frontend expects them to be 11-14. This caused items to show as "Item X" instead of proper names.

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
  v_crystals_awarded integer := 0;
  v_new_crystal_balance bigint;
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
        v_crystals_awarded := v_qty; -- Track crystals awarded
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
          WHEN 'berry' THEN v_item_id := 11;        -- Fixed: was 7
          WHEN 'herbs' THEN v_item_id := 12;        -- Fixed: was 8
          WHEN 'magic_mushroom' THEN v_item_id := 13; -- Fixed: was 9
          WHEN 'enchanted_flower' THEN v_item_id := 14; -- Fixed: was 10
          WHEN 'bread' THEN v_item_id := 8;
          WHEN 'vegetable_stew' THEN v_item_id := 15;
          WHEN 'corn_bread' THEN v_item_id := 16;
          WHEN 'pumpkin_pie' THEN v_item_id := 17;
          WHEN 'herbal_tea' THEN v_item_id := 18;
          WHEN 'magic_potion' THEN v_item_id := 19;
          WHEN 'fruit_salad' THEN v_item_id := 20;
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

  -- Get the new crystal balance after all updates
  SELECT COALESCE(crystals, 0) INTO v_new_crystal_balance
  FROM public.profiles
  WHERE id = v_player_id;

  -- Check achievements
  PERFORM public.check_achievements('produce_count', 1);

  -- Update quest progress (FIXED: objective_type first, not NULL)
  PERFORM public.update_quest_progress('produce', NULL, 1);

  -- Auto-contribute to coven tasks
  PERFORM public.auto_contribute_coven_tasks('produce', 1);

  -- Return result with crystal balance and crystals awarded
  SELECT jsonb_build_object(
    'success', true,
    'output', v_output,
    'xp_gained', v_total_xp,
    'new_crystal_balance', v_new_crystal_balance,
    'crystals_awarded', v_crystals_awarded
  ) INTO v_result;

  RETURN v_result;
END;
$$;

COMMENT ON FUNCTION public.collect_factory(integer) IS 'Collect completed factory production: adds items to inventory, grants XP for crafted items, clears slot. Returns jsonb with success, output, xp_gained, new_crystal_balance, and crystals_awarded.';