-- Fix crystal update race condition by returning new crystal balance from RPC functions
-- This ensures the frontend always uses the authoritative database value

-- Update fulfill_skyport_order to return new crystal balance
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
  v_xp_multiplier numeric := 1.0;
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

  -- Get updated crystal balance
  SELECT COALESCE(crystals, 0) INTO v_new_crystals
  FROM public.profiles
  WHERE id = v_player_id;

  -- Return result with new crystal balance
  SELECT jsonb_build_object(
    'success', true,
    'crystals_awarded', COALESCE(((v_rewards->>'crystals')::integer * v_crystal_multiplier)::integer, 0),
    'xp_awarded', COALESCE(((v_rewards->>'xp')::integer * v_xp_multiplier)::integer, 0),
    'new_crystal_balance', v_new_crystals
  ) INTO v_result;

  RETURN v_result;
END;
$$;

-- Update claim_achievement to return new crystal balance
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

  -- Award rewards
  IF v_achievement.reward_crystals > 0 THEN
    UPDATE public.profiles
    SET crystals = crystals + v_achievement.reward_crystals
    WHERE id = v_player_id;
  END IF;

  IF v_achievement.reward_xp > 0 THEN
    UPDATE public.profiles
    SET xp = xp + v_achievement.reward_xp
    WHERE id = v_player_id;
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

-- Update claim_quest_reward to return new crystal balance
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

  -- Award XP
  IF v_rewards ? 'xp' THEN
    UPDATE public.profiles
    SET xp = xp + (v_rewards->>'xp')::integer
    WHERE id = v_player_id;
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

-- Update claim_regatta_rewards to return new crystal balance
CREATE OR REPLACE FUNCTION public.claim_regatta_rewards(p_regatta_id integer)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_regatta record;
  v_participant record;
  v_total_participants integer;
  v_player_rank integer;
  v_reward jsonb;
  v_crystals integer;
  v_new_crystals bigint;
BEGIN
  -- Get regatta
  SELECT * INTO v_regatta
  FROM public.regatta_events
  WHERE id = p_regatta_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Regatta % not found', p_regatta_id;
  END IF;

  IF v_regatta.status != 'completed' THEN
    RAISE EXCEPTION 'Regatta % is not completed yet', p_regatta_id;
  END IF;

  -- Get participant
  SELECT * INTO v_participant
  FROM public.regatta_participants
  WHERE regatta_id = p_regatta_id AND player_id = v_player_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'You did not participate in regatta %', p_regatta_id;
  END IF;

  -- Calculate rank
  SELECT count(*) INTO v_total_participants
  FROM public.regatta_participants
  WHERE regatta_id = p_regatta_id;

  SELECT count(*) + 1 INTO v_player_rank
  FROM public.regatta_participants
  WHERE regatta_id = p_regatta_id
    AND points > v_participant.points;

  -- Determine reward tier
  IF v_player_rank <= v_total_participants * 0.1 THEN
    -- Top 10%
    v_reward := v_regatta.rewards->'top_10';
  ELSIF v_player_rank <= v_total_participants * 0.25 THEN
    -- Top 25%
    v_reward := v_regatta.rewards->'top_25';
  ELSE
    -- Participation
    v_reward := v_regatta.rewards->'participation';
  END IF;

  -- Award crystals
  IF v_reward ? 'crystals' THEN
    v_crystals := (v_reward->>'crystals')::integer;
    UPDATE public.profiles
    SET crystals = crystals + v_crystals
    WHERE id = v_player_id;
  ELSE
    v_crystals := 0;
  END IF;

  -- Get updated crystal balance
  SELECT COALESCE(crystals, 0) INTO v_new_crystals
  FROM public.profiles
  WHERE id = v_player_id;

  -- Return result with new crystal balance
  RETURN jsonb_build_object(
    'success', true,
    'rank', v_player_rank,
    'total_participants', v_total_participants,
    'crystals_awarded', v_crystals,
    'new_crystal_balance', v_new_crystals
  );
END;
$$;

COMMENT ON FUNCTION public.fulfill_skyport_order(integer) IS 'Fulfill a skyport order: deduct requirements from inventory, award rewards, mark complete. Returns new crystal balance.';
COMMENT ON FUNCTION public.claim_achievement(integer) IS 'Claim achievement reward. Returns new crystal balance.';
COMMENT ON FUNCTION public.claim_quest_reward(integer) IS 'Claim quest reward. Returns new crystal balance.';
COMMENT ON FUNCTION public.claim_regatta_rewards(integer) IS 'Claim regatta rewards based on final rank. Returns new crystal balance.';

