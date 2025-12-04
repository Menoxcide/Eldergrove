-- Integrate boost multipliers into reward systems

-- Update collect_factory to apply crystal boost multiplier
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
      ELSE
        -- Other items go to inventory
        CASE v_key
          WHEN 'wheat' THEN v_item_id := 1;
          WHEN 'bread' THEN v_item_id := 2;
          WHEN 'carrot' THEN v_item_id := 2;
          WHEN 'potato' THEN v_item_id := 3;
          WHEN 'tomato' THEN v_item_id := 4;
          WHEN 'corn' THEN v_item_id := 5;
          WHEN 'pumpkin' THEN v_item_id := 6;
          WHEN 'berry' THEN v_item_id := 7;
          WHEN 'herbs' THEN v_item_id := 8;
          WHEN 'magic_mushroom' THEN v_item_id := 9;
          WHEN 'enchanted_flower' THEN v_item_id := 10;
          ELSE NULL;
        END CASE;

        IF v_item_id IS NOT NULL THEN
          INSERT INTO public.inventory (player_id, item_id, quantity)
          VALUES (v_player_id, v_item_id, v_qty::bigint)
          ON CONFLICT (player_id, item_id) DO UPDATE SET
            quantity = inventory.quantity + excluded.quantity;
        END IF;
    END CASE;
  END LOOP;

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

-- Update fulfill_skyport_order to apply crystal boost
CREATE OR REPLACE FUNCTION public.fulfill_skyport_order(p_order_id integer)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_order record;
  v_requirements jsonb;
  v_rewards jsonb;
  v_item_id integer;
  v_required_qty integer;
  v_current_qty bigint;
  v_key text;
  v_value text;
  v_result jsonb;
  v_crystal_multiplier numeric := 1.0;
  v_xp_multiplier numeric := 1.0;
BEGIN
  -- Get order
  SELECT * INTO v_order
  FROM public.skyport_orders
  WHERE id = p_order_id AND player_id = v_player_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order % not found or does not belong to this player', p_order_id;
  END IF;

  IF v_order.completed_at IS NOT NULL THEN
    RAISE EXCEPTION 'Order % has already been completed', p_order_id;
  END IF;

  IF v_order.expires_at < now() THEN
    RAISE EXCEPTION 'Order % has expired', p_order_id;
  END IF;

  -- Get active boost multipliers
  SELECT COALESCE(multiplier, 1.0) INTO v_crystal_multiplier
  FROM public.active_boosts
  WHERE player_id = v_player_id
    AND boost_type = 'crystal'
    AND expires_at > now()
  LIMIT 1;

  SELECT COALESCE(multiplier, 1.0) INTO v_xp_multiplier
  FROM public.active_boosts
  WHERE player_id = v_player_id
    AND boost_type = 'xp'
    AND expires_at > now()
  LIMIT 1;

  v_requirements := v_order.requirements;
  v_rewards := v_order.rewards;

  -- Check and deduct required items
  FOR v_key, v_value IN SELECT key, value FROM jsonb_each_text(v_requirements) LOOP
    v_item_id := v_key::integer;
    v_required_qty := v_value::integer;

    SELECT COALESCE(quantity, 0) INTO v_current_qty
    FROM public.inventory
    WHERE player_id = v_player_id AND item_id = v_item_id;

    IF v_current_qty < v_required_qty THEN
      RAISE EXCEPTION 'Insufficient item %: required %, available %', v_item_id, v_required_qty, v_current_qty;
    END IF;

    -- Deduct from inventory
    UPDATE public.inventory
    SET quantity = quantity - v_required_qty
    WHERE player_id = v_player_id AND item_id = v_item_id;
  END LOOP;

  -- Award rewards (with boost multipliers)
  IF v_rewards ? 'crystals' THEN
    UPDATE public.profiles
    SET crystals = crystals + ((v_rewards->>'crystals')::integer * v_crystal_multiplier)::bigint,
        xp = xp + COALESCE(((v_rewards->>'xp')::integer * v_xp_multiplier)::bigint, 0)
    WHERE id = v_player_id;
  END IF;

  -- Items
  IF v_rewards ? 'items' THEN
    FOR v_key, v_value IN SELECT key, value FROM jsonb_each_text(v_rewards->'items') LOOP
      v_item_id := v_key::integer;
      v_required_qty := v_value::integer;

      INSERT INTO public.inventory (player_id, item_id, quantity)
      VALUES (v_player_id, v_item_id, v_required_qty::bigint)
      ON CONFLICT (player_id, item_id) DO UPDATE SET
        quantity = inventory.quantity + excluded.quantity;
    END LOOP;
  END IF;

  -- Mark order as completed
  UPDATE public.skyport_orders
  SET completed_at = now()
  WHERE id = p_order_id;

  -- Update quest progress for fulfilling orders
  PERFORM public.update_quest_progress('fulfill_order', NULL, 1);

  -- Return result
  SELECT jsonb_build_object(
    'success', true,
    'crystals_awarded', COALESCE(((v_rewards->>'crystals')::integer * v_crystal_multiplier)::integer, 0),
    'xp_awarded', COALESCE(((v_rewards->>'xp')::integer * v_xp_multiplier)::integer, 0)
  ) INTO v_result;

  RETURN v_result;
END;
$$;

-- Update check_achievements to apply XP boost
CREATE OR REPLACE FUNCTION public.check_achievements(
  p_condition_type text,
  p_increment_value integer DEFAULT 1,
  p_specific_value text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  r_achievement record;
  v_current_progress integer;
  v_new_progress integer;
  v_completed_achievements_count integer;
  v_player_level integer;
  v_player_crystals bigint;
  v_daily_streak integer;
  v_distinct_items_harvested integer;
  v_distinct_ores_mined integer;
  v_distinct_recipes_unlocked integer;
  v_distinct_animals_acquired integer;
  v_xp_multiplier numeric := 1.0;
BEGIN
  -- Get active XP boost multiplier
  SELECT COALESCE(multiplier, 1.0) INTO v_xp_multiplier
  FROM public.active_boosts
  WHERE player_id = v_player_id
    AND boost_type = 'xp'
    AND expires_at > now()
  LIMIT 1;

  -- Fetch player profile data for relevant conditions
  SELECT level, crystals, daily_streak INTO v_player_level, v_player_crystals, v_daily_streak
  FROM public.profiles
  WHERE id = v_player_id;

  -- Iterate through all achievements matching the condition type
  FOR r_achievement IN
    SELECT a.id, a.name, a.description, a.category, a.condition_type, a.condition_value,
           a.reward_crystals, a.reward_xp, a.reward_title, a.icon,
           pa.progress, pa.completed_at, pa.claimed_at
    FROM public.achievements a
    LEFT JOIN public.player_achievements pa ON a.id = pa.achievement_id AND pa.player_id = v_player_id
    WHERE a.condition_type = p_condition_type
  LOOP
    -- Skip if already completed and claimed
    IF r_achievement.completed_at IS NOT NULL AND r_achievement.claimed_at IS NOT NULL THEN
      CONTINUE;
    END IF;

    v_current_progress := COALESCE((r_achievement.progress->>'value')::integer, 0);
    v_new_progress := v_current_progress;

    -- Update progress based on condition type (same logic as before)
    IF r_achievement.condition_type = 'harvest_count' THEN
      v_new_progress := v_current_progress + p_increment_value;
    ELSIF r_achievement.condition_type = 'produce_count' THEN
      v_new_progress := v_current_progress + p_increment_value;
    ELSIF r_achievement.condition_type = 'build_count' THEN
      v_new_progress := v_current_progress + p_increment_value;
    ELSIF r_achievement.condition_type = 'mine_count' THEN
      v_new_progress := v_current_progress + p_increment_value;
    ELSIF r_achievement.condition_type = 'animal_product_count' THEN
      v_new_progress := v_current_progress + p_increment_value;
    ELSIF r_achievement.condition_type = 'breed_count' THEN
      v_new_progress := v_current_progress + p_increment_value;
    ELSIF r_achievement.condition_type = 'player_level' THEN
      v_new_progress := v_player_level;
    ELSIF r_achievement.condition_type = 'crystals_earned' THEN
      v_new_progress := v_player_crystals;
    ELSIF r_achievement.condition_type = 'daily_streak' THEN
      v_new_progress := v_daily_streak;
    ELSIF r_achievement.condition_type = 'upgrade_level' THEN
      v_new_progress := GREATEST(v_current_progress, p_increment_value);
    ELSIF r_achievement.condition_type = 'crop_variety' THEN
      SELECT COUNT(DISTINCT i.item_id) INTO v_distinct_items_harvested
      FROM public.inventory i
      JOIN public.crops c ON i.item_id = c.item_id
      WHERE i.player_id = v_player_id;
      v_new_progress := v_distinct_items_harvested;
    ELSIF r_achievement.condition_type = 'ore_variety' THEN
      SELECT COUNT(DISTINCT i.item_id) INTO v_distinct_ores_mined
      FROM public.inventory i
      JOIN public.ore_types ot ON i.item_id = ot.item_id
      WHERE i.player_id = v_player_id;
      v_new_progress := v_distinct_ores_mined;
    ELSIF r_achievement.condition_type = 'recipe_variety' THEN
      SELECT COUNT(DISTINCT fq.recipe_id) INTO v_distinct_recipes_unlocked
      FROM public.factory_queue fq
      WHERE fq.player_id = v_player_id;
      v_new_progress := v_distinct_recipes_unlocked;
    ELSIF r_achievement.condition_type = 'animal_count' THEN
      SELECT COUNT(DISTINCT animal_type_id) INTO v_distinct_animals_acquired
      FROM public.zoo_enclosures
      WHERE player_id = v_player_id;
      v_new_progress := v_distinct_animals_acquired;
    ELSE
      CONTINUE;
    END IF;

    -- Update or insert player achievement progress
    INSERT INTO public.player_achievements (player_id, achievement_id, progress, completed_at)
    VALUES (v_player_id, r_achievement.id, jsonb_build_object('value', v_new_progress), NULL)
    ON CONFLICT (player_id, achievement_id) DO UPDATE SET
      progress = jsonb_build_object('value', EXCLUDED.progress->>'value'),
      completed_at = CASE
                       WHEN r_achievement.completed_at IS NULL AND EXCLUDED.progress->>'value' >= r_achievement.condition_value::text THEN NOW()
                       ELSE r_achievement.completed_at
                     END;

    -- Check if achievement is newly completed
    IF r_achievement.completed_at IS NULL AND v_new_progress >= r_achievement.condition_value THEN
      -- Award rewards immediately (with boost multipliers)
      UPDATE public.profiles
      SET crystals = crystals + r_achievement.reward_crystals,
          xp = xp + (r_achievement.reward_xp * v_xp_multiplier)::bigint
      WHERE id = v_player_id;

      RAISE NOTICE 'Achievement "%" completed by player %!', r_achievement.name, v_player_id;
    END IF;
  END LOOP;
END;
$$;

