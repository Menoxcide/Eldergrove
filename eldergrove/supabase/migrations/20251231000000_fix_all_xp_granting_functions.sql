-- Fix all XP granting functions to use grant_xp() instead of direct updates
-- This ensures XP multipliers, building bonuses, and level-ups work correctly

-- Fix fulfill_skyport_order: Replace direct XP update with grant_xp()
CREATE OR REPLACE FUNCTION public.fulfill_skyport_order(p_order_id integer)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
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
  v_xp_amount integer;
  v_new_crystals bigint;
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

  -- Get active crystal boost multiplier
  SELECT COALESCE(multiplier, 1.0) INTO v_crystal_multiplier
  FROM public.active_boosts
  WHERE player_id = v_player_id
    AND boost_type = 'crystal'
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
    SET crystals = crystals + ((v_rewards->>'crystals')::integer * v_crystal_multiplier)::bigint
    WHERE id = v_player_id;
  END IF;

  -- Grant XP using grant_xp() function (handles multipliers and level-ups)
  IF v_rewards ? 'xp' THEN
    v_xp_amount := (v_rewards->>'xp')::integer;
    IF v_xp_amount > 0 THEN
      PERFORM public.grant_xp(v_player_id, v_xp_amount);
    END IF;
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

  -- Get updated crystal balance
  SELECT COALESCE(crystals, 0) INTO v_new_crystals
  FROM public.profiles
  WHERE id = v_player_id;

  -- Return result with new crystal balance
  SELECT jsonb_build_object(
    'success', true,
    'crystals_awarded', COALESCE(((v_rewards->>'crystals')::integer * v_crystal_multiplier)::integer, 0),
    'xp_awarded', COALESCE((v_rewards->>'xp')::integer, 0),
    'new_crystal_balance', v_new_crystals
  ) INTO v_result;

  RETURN v_result;
END;
$$;

COMMENT ON FUNCTION public.fulfill_skyport_order(integer) IS 'Fulfill a skyport order: deduct requirements from inventory, award rewards, grant XP using grant_xp(). Returns new crystal balance.';

-- Fix claim_quest_reward: Replace direct XP update with grant_xp()
CREATE OR REPLACE FUNCTION public.claim_quest_reward(p_quest_id integer)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_quest record;
  v_progress record;
  v_rewards jsonb;
  v_key text;
  v_value text;
  v_item_id integer;
  v_qty integer;
  v_result jsonb;
  v_new_crystals bigint;
  v_xp_amount integer;
BEGIN
  -- Get quest
  SELECT * INTO v_quest
  FROM public.quests
  WHERE id = p_quest_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Quest % not found', p_quest_id;
  END IF;

  -- Get progress
  SELECT * INTO v_progress
  FROM public.quest_progress
  WHERE player_id = v_player_id AND quest_id = p_quest_id;

  IF NOT FOUND OR NOT v_progress.completed THEN
    RAISE EXCEPTION 'Quest % is not completed', p_quest_id;
  END IF;

  IF v_progress.claimed THEN
    RAISE EXCEPTION 'Quest % reward already claimed', p_quest_id;
  END IF;

  v_rewards := v_quest.rewards;

  -- Award crystals
  IF v_rewards ? 'crystals' THEN
    UPDATE public.profiles
    SET crystals = crystals + (v_rewards->>'crystals')::integer
    WHERE id = v_player_id;
  END IF;

  -- Grant XP using grant_xp() function (handles multipliers and level-ups)
  IF v_rewards ? 'xp' THEN
    v_xp_amount := (v_rewards->>'xp')::integer;
    IF v_xp_amount > 0 THEN
      PERFORM public.grant_xp(v_player_id, v_xp_amount);
    END IF;
  END IF;

  -- Award items
  IF v_rewards ? 'items' THEN
    FOR v_key, v_value IN SELECT key, value FROM jsonb_each_text(v_rewards->'items') LOOP
      v_item_id := v_key::integer;
      v_qty := v_value::integer;

      INSERT INTO public.inventory (player_id, item_id, quantity)
      VALUES (v_player_id, v_item_id, v_qty::bigint)
      ON CONFLICT (player_id, item_id) DO UPDATE SET
        quantity = inventory.quantity + excluded.quantity;
    END LOOP;
  END IF;

  -- Mark as claimed
  UPDATE public.quest_progress
  SET claimed = true, claimed_at = now()
  WHERE player_id = v_player_id AND quest_id = p_quest_id;

  -- Get updated crystal balance
  SELECT COALESCE(crystals, 0) INTO v_new_crystals
  FROM public.profiles
  WHERE id = v_player_id;

  -- Return result with new crystal balance
  SELECT jsonb_build_object(
    'success', true,
    'crystals_awarded', COALESCE((v_rewards->>'crystals')::integer, 0),
    'xp_awarded', COALESCE((v_rewards->>'xp')::integer, 0),
    'new_crystal_balance', v_new_crystals
  ) INTO v_result;

  RETURN v_result;
END;
$$;

COMMENT ON FUNCTION public.claim_quest_reward(integer) IS 'Claim quest reward: awards crystals, grants XP using grant_xp(). Returns new crystal balance.';

-- Fix claim_achievement: Replace direct XP update with grant_xp()
CREATE OR REPLACE FUNCTION public.claim_achievement(p_achievement_id integer)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_achievement record;
  v_player_achievement record;
  v_result jsonb;
  v_new_crystals bigint;
BEGIN
  -- Get achievement
  SELECT * INTO v_achievement
  FROM public.achievements
  WHERE id = p_achievement_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Achievement % not found', p_achievement_id;
  END IF;

  -- Get player achievement
  SELECT * INTO v_player_achievement
  FROM public.player_achievements
  WHERE player_id = v_player_id AND achievement_id = p_achievement_id;

  IF NOT FOUND OR NOT v_player_achievement.completed THEN
    RAISE EXCEPTION 'Achievement % is not completed', p_achievement_id;
  END IF;

  IF v_player_achievement.claimed THEN
    RAISE EXCEPTION 'Achievement % reward already claimed', p_achievement_id;
  END IF;

  -- Award crystals
  IF v_achievement.reward_crystals > 0 THEN
    UPDATE public.profiles
    SET crystals = crystals + v_achievement.reward_crystals
    WHERE id = v_player_id;
  END IF;

  -- Grant XP using grant_xp() function (handles multipliers and level-ups)
  IF v_achievement.reward_xp > 0 THEN
    PERFORM public.grant_xp(v_player_id, v_achievement.reward_xp);
  END IF;

  -- Mark as claimed
  UPDATE public.player_achievements
  SET claimed = true, claimed_at = now()
  WHERE player_id = v_player_id AND achievement_id = p_achievement_id;

  -- Get updated crystal balance
  SELECT COALESCE(crystals, 0) INTO v_new_crystals
  FROM public.profiles
  WHERE id = v_player_id;

  -- Return result with new crystal balance
  SELECT jsonb_build_object(
    'success', true,
    'crystals_awarded', v_achievement.reward_crystals,
    'xp_awarded', v_achievement.reward_xp,
    'title', v_achievement.reward_title,
    'new_crystal_balance', v_new_crystals
  ) INTO v_result;

  RETURN v_result;
END;
$$;

COMMENT ON FUNCTION public.claim_achievement(integer) IS 'Claim achievement reward. Grants XP using grant_xp(). Returns new crystal balance.';

-- Fix check_achievements: Replace direct XP update with grant_xp()
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
BEGIN
  -- Fetch player profile data for relevant conditions
  SELECT level, crystals, daily_streak INTO v_player_level, v_player_crystals, v_daily_streak
  FROM public.profiles
  WHERE id = v_player_id;

  -- Iterate through all achievements matching the condition type
  FOR r_achievement IN
    SELECT a.id, a.name, a.description, a.category, a.condition_type, a.condition_value,
           a.reward_crystals, a.reward_xp, a.reward_title, a.icon,
           COALESCE(pa.progress, 0) as progress, pa.completed_at, pa.claimed_at
    FROM public.achievements a
    LEFT JOIN public.player_achievements pa ON a.id = pa.achievement_id AND pa.player_id = v_player_id
    WHERE a.condition_type = p_condition_type
  LOOP
    -- Skip if already completed and claimed
    IF r_achievement.completed_at IS NOT NULL AND r_achievement.claimed_at IS NOT NULL THEN
      CONTINUE;
    END IF;

    v_current_progress := COALESCE(r_achievement.progress, 0);
    v_new_progress := v_current_progress;

    -- Update progress based on condition type
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

    -- Update or insert player achievement progress (progress is integer, not JSONB)
    INSERT INTO public.player_achievements (player_id, achievement_id, progress, completed_at)
    VALUES (v_player_id, r_achievement.id, v_new_progress, NULL)
    ON CONFLICT (player_id, achievement_id) DO UPDATE SET
      progress = EXCLUDED.progress,
      completed_at = CASE
                       WHEN r_achievement.completed_at IS NULL AND EXCLUDED.progress >= r_achievement.condition_value THEN NOW()
                       ELSE r_achievement.completed_at
                     END;

    -- Check if achievement is newly completed
    IF r_achievement.completed_at IS NULL AND v_new_progress >= r_achievement.condition_value THEN
      -- Award crystals
      IF r_achievement.reward_crystals > 0 THEN
        UPDATE public.profiles
        SET crystals = crystals + r_achievement.reward_crystals
        WHERE id = v_player_id;
      END IF;

      -- Grant XP using grant_xp() function (handles multipliers and level-ups)
      IF r_achievement.reward_xp > 0 THEN
        PERFORM public.grant_xp(v_player_id, r_achievement.reward_xp);
      END IF;

      RAISE NOTICE 'Achievement "%" completed by player %!', r_achievement.name, v_player_id;
    END IF;
  END LOOP;
END;
$$;

COMMENT ON FUNCTION public.check_achievements(text, integer, text) IS 'Check and update achievement progress for a condition type. Grants XP using grant_xp() when achievements are completed.';

-- Fix help_friend_fill_order: Replace direct XP update with grant_xp()
CREATE OR REPLACE FUNCTION public.help_friend_fill_order(
  p_friend_id uuid,
  p_order_id integer
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_order record;
  v_requirements jsonb;
  v_key text;
  v_value text;
  v_item_id integer;
  v_required_qty integer;
  v_current_qty bigint;
  v_xp_amount integer;
BEGIN
  -- Check if friends
  IF NOT EXISTS (
    SELECT 1 FROM public.friends
    WHERE ((player_id = v_player_id AND friend_id = p_friend_id)
        OR (player_id = p_friend_id AND friend_id = v_player_id))
      AND status = 'accepted'
  ) THEN
    RAISE EXCEPTION 'You are not friends with this player';
  END IF;

  -- Get order
  SELECT * INTO v_order
  FROM public.skyport_orders
  WHERE id = p_order_id AND player_id = p_friend_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found';
  END IF;

  IF v_order.completed_at IS NOT NULL THEN
    RAISE EXCEPTION 'Order already completed';
  END IF;

  v_requirements := v_order.requirements;

  -- Check and deduct items from helper's inventory
  FOR v_key, v_value IN SELECT key, value FROM jsonb_each_text(v_requirements) LOOP
    v_item_id := v_key::integer;
    v_required_qty := v_value::integer;

    SELECT COALESCE(quantity, 0) INTO v_current_qty
    FROM public.inventory
    WHERE player_id = v_player_id AND item_id = v_item_id;

    IF v_current_qty < v_required_qty THEN
      RAISE EXCEPTION 'Insufficient item %: required %, available %', v_item_id, v_required_qty, v_current_qty;
    END IF;

    -- Deduct from helper's inventory
    UPDATE public.inventory
    SET quantity = quantity - v_required_qty
    WHERE player_id = v_player_id AND item_id = v_item_id;
  END LOOP;

  -- Mark order as completed (friend gets rewards)
  UPDATE public.skyport_orders
  SET completed_at = now()
  WHERE id = p_order_id;

  -- Award crystals to friend
  IF v_order.rewards ? 'crystals' THEN
    UPDATE public.profiles
    SET crystals = crystals + (v_order.rewards->>'crystals')::integer
    WHERE id = p_friend_id;
  END IF;

  -- Grant XP to friend using grant_xp() function (handles multipliers and level-ups)
  IF v_order.rewards ? 'xp' THEN
    v_xp_amount := COALESCE((v_order.rewards->>'xp')::integer, 0);
    IF v_xp_amount > 0 THEN
      PERFORM public.grant_xp(p_friend_id, v_xp_amount);
    END IF;
  END IF;

  -- Record help
  INSERT INTO public.friend_help (helper_id, helped_id, help_type, target_id)
  VALUES (v_player_id, p_friend_id, 'fill_order', p_order_id);

  -- Check achievements
  PERFORM public.check_achievements('help_count', 1);
END;
$$;

COMMENT ON FUNCTION public.help_friend_fill_order(uuid, integer) IS 'Help a friend by filling their skyport order. Grants XP to friend using grant_xp().';

-- Add XP to collect_animal_production: Grant XP when collecting items from animals
CREATE OR REPLACE FUNCTION public.collect_animal_production(
  p_enclosure_id integer,
  p_slot integer
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_enclosure record;
  v_animal_type record;
  v_animal_id integer;
  v_animal_level integer;
  v_produced_at timestamptz;
  v_item_id integer;
  v_base_quantity integer;
  v_quantity integer;
  v_interval_minutes integer;
  v_result jsonb;
  v_xp_gained integer;
BEGIN
  -- Validate slot
  IF p_slot NOT IN (1, 2) THEN
    RAISE EXCEPTION 'Invalid slot: % (must be 1 or 2)', p_slot;
  END IF;
  
  -- Get enclosure
  SELECT * INTO v_enclosure
  FROM public.zoo_enclosures
  WHERE id = p_enclosure_id AND player_id = v_player_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Enclosure % not found or does not belong to this player', p_enclosure_id;
  END IF;

  -- Get animal info based on slot
  IF p_slot = 1 THEN
    v_animal_id := v_enclosure.animal1_id;
    v_animal_level := COALESCE(v_enclosure.animal1_level, 0);
    v_produced_at := v_enclosure.animal1_produced_at;
  ELSE
    v_animal_id := v_enclosure.animal2_id;
    v_animal_level := COALESCE(v_enclosure.animal2_level, 0);
    v_produced_at := v_enclosure.animal2_produced_at;
  END IF;

  IF v_animal_id IS NULL THEN
    RAISE EXCEPTION 'No animal in slot %', p_slot;
  END IF;

  -- Get animal type
  SELECT * INTO v_animal_type
  FROM public.animal_types
  WHERE id = v_animal_id;

  v_item_id := v_animal_type.produces_item_id;
  v_base_quantity := v_animal_type.produces_quantity;
  v_interval_minutes := v_animal_type.produces_interval_minutes;

  -- Check if production is ready
  IF v_produced_at IS NULL OR v_produced_at + (v_interval_minutes || ' minutes')::interval > now() THEN
    RAISE EXCEPTION 'Animal production not ready yet';
  END IF;

  -- Calculate quantity with level scaling: base_quantity * (1 + level * 0.1)
  v_quantity := ROUND(v_base_quantity * (1.0 + (v_animal_level * 0.1)));

  -- Award items
  IF v_item_id IS NOT NULL THEN
    INSERT INTO public.inventory (player_id, item_id, quantity)
    VALUES (v_player_id, v_item_id, v_quantity::bigint)
    ON CONFLICT (player_id, item_id) DO UPDATE SET
      quantity = inventory.quantity + excluded.quantity;
    
    -- Grant XP for collecting animal production (similar to harvesting)
    v_xp_gained := public.get_item_xp(v_item_id, v_quantity);
    IF v_xp_gained > 0 THEN
      PERFORM public.grant_xp(v_player_id, v_xp_gained);
    END IF;
  END IF;

  -- Update production time
  IF p_slot = 1 THEN
    UPDATE public.zoo_enclosures
    SET animal1_produced_at = now()
    WHERE id = p_enclosure_id;
  ELSE
    UPDATE public.zoo_enclosures
    SET animal2_produced_at = now()
    WHERE id = p_enclosure_id;
  END IF;

  -- Return result
  SELECT jsonb_build_object(
    'success', true,
    'item_id', v_item_id,
    'quantity', v_quantity,
    'xp_gained', COALESCE(v_xp_gained, 0)
  ) INTO v_result;

  RETURN v_result;
END;
$$;

COMMENT ON FUNCTION public.collect_animal_production(integer, integer) IS 'Collect production from an animal in an enclosure. Production quantity scales with animal level (1 + level * 0.1). Grants XP using grant_xp() based on items collected.';

-- Add XP to collect_bred_animal: Grant XP when breeding completes
CREATE OR REPLACE FUNCTION public.collect_bred_animal(p_enclosure_id integer)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_enclosure record;
  v_animal1_type record;
  v_animal2_type record;
  v_result_animal_id integer;
  v_result_animal_type record;
  v_xp_gained integer;
BEGIN
  -- Get enclosure
  SELECT * INTO v_enclosure
  FROM public.zoo_enclosures
  WHERE id = p_enclosure_id AND player_id = v_player_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Enclosure % not found or does not belong to this player', p_enclosure_id;
  END IF;

  IF v_enclosure.breeding_completes_at IS NULL OR v_enclosure.breeding_completes_at > now() THEN
    RAISE EXCEPTION 'Breeding not complete yet';
  END IF;

  -- Get animal types
  SELECT * INTO v_animal1_type FROM public.animal_types WHERE id = v_enclosure.animal1_id;
  SELECT * INTO v_animal2_type FROM public.animal_types WHERE id = v_enclosure.animal2_id;

  -- Determine result animal (higher rarity, or random if same)
  IF v_animal1_type.rarity = 'legendary' OR v_animal2_type.rarity = 'legendary' THEN
    -- At least one legendary parent = chance for legendary
    IF random() < 0.3 THEN
      SELECT id INTO v_result_animal_id FROM public.animal_types WHERE rarity = 'legendary' ORDER BY random() LIMIT 1;
    ELSIF random() < 0.6 THEN
      SELECT id INTO v_result_animal_id FROM public.animal_types WHERE rarity = 'rare' ORDER BY random() LIMIT 1;
    ELSE
      SELECT id INTO v_result_animal_id FROM public.animal_types WHERE rarity = 'common' ORDER BY random() LIMIT 1;
    END IF;
  ELSIF v_animal1_type.rarity = 'rare' OR v_animal2_type.rarity = 'rare' THEN
    -- At least one rare parent
    IF random() < 0.2 THEN
      SELECT id INTO v_result_animal_id FROM public.animal_types WHERE rarity = 'rare' ORDER BY random() LIMIT 1;
    ELSE
      SELECT id INTO v_result_animal_id FROM public.animal_types WHERE rarity = 'common' ORDER BY random() LIMIT 1;
    END IF;
  ELSE
    -- Both common = common result
    SELECT id INTO v_result_animal_id FROM public.animal_types WHERE rarity = 'common' ORDER BY random() LIMIT 1;
  END IF;

  SELECT * INTO v_result_animal_type FROM public.animal_types WHERE id = v_result_animal_id;

  -- Add to inventory as item (using animal_type id as item_id, or create special item_ids 30+)
  -- For now, we'll add the animal type ID as a special item
  INSERT INTO public.inventory (player_id, item_id, quantity)
  VALUES (v_player_id, 30 + v_result_animal_id, 1) -- Use item_ids 30+ for animals
  ON CONFLICT (player_id, item_id) DO UPDATE SET
    quantity = inventory.quantity + 1;

  -- Grant XP for breeding (base XP for breeding action, scales with rarity)
  -- Common: 50 XP, Rare: 100 XP, Legendary: 200 XP
  CASE v_result_animal_type.rarity
    WHEN 'legendary' THEN v_xp_gained := 200;
    WHEN 'rare' THEN v_xp_gained := 100;
    ELSE v_xp_gained := 50;
  END CASE;
  
  PERFORM public.grant_xp(v_player_id, v_xp_gained);

  -- Reset breeding
  UPDATE public.zoo_enclosures
  SET breeding_started_at = NULL,
      breeding_completes_at = NULL
  WHERE id = p_enclosure_id;

  -- Check achievements
  PERFORM public.check_achievements('breed_count', 1);

  -- Return result
  RETURN jsonb_build_object(
    'success', true,
    'animal_id', v_result_animal_id,
    'animal_name', v_result_animal_type.name,
    'animal_icon', v_result_animal_type.icon,
    'xp_gained', v_xp_gained
  );
END;
$$;

COMMENT ON FUNCTION public.collect_bred_animal(integer) IS 'Collect a bred animal from an enclosure. Grants XP using grant_xp() based on animal rarity (Common: 50, Rare: 100, Legendary: 200 XP).';

