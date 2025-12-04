-- Fix check_achievements function overload ambiguity
-- Drop the old function signature and keep only the newer one with boost multipliers
-- Also fix the progress field usage (it's integer, not JSONB)

-- Drop the old check_achievements function signature
DROP FUNCTION IF EXISTS public.check_achievements(text, integer);

-- Ensure the newer function exists (with boost multipliers support)
-- Fix: progress is integer, not JSONB
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

COMMENT ON FUNCTION public.check_achievements(text, integer, text) IS 'Check and update achievement progress for a condition type with XP boost multiplier support';

