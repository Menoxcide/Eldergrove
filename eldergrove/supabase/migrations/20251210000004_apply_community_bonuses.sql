-- Apply community building bonuses to game systems
-- Schools: XP multiplier (1% per school, max 10%)
-- Hospitals: Energy regeneration (5 per hour per hospital, max 20)
-- Cinemas: Crystal generation (1% per cinema, max 5%)

-- Update grant_xp to include school bonus
CREATE OR REPLACE FUNCTION public.grant_xp(p_player_id uuid, p_xp_amount integer)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_xp_multiplier numeric := 1.0;
  v_building_bonus numeric := 0;
  v_final_xp integer;
  v_levels_gained integer;
  v_bonuses jsonb;
BEGIN
  -- Get active XP boost multiplier
  SELECT COALESCE(multiplier, 1.0) INTO v_xp_multiplier
  FROM public.active_boosts
  WHERE player_id = p_player_id
    AND boost_type = 'xp'
    AND expires_at > now()
  LIMIT 1;
  
  -- Get building bonuses (schools provide XP multiplier)
  SELECT public.get_building_bonuses(p_player_id) INTO v_bonuses;
  v_building_bonus := COALESCE((v_bonuses->>'xp_multiplier')::numeric, 0);
  
  -- Calculate final XP with both boost and building multiplier
  v_final_xp := (p_xp_amount * (1.0 + v_building_bonus) * v_xp_multiplier)::integer;
  
  -- Grant XP
  UPDATE public.profiles
  SET xp = xp + v_final_xp
  WHERE id = p_player_id;
  
  -- Check for level-ups
  v_levels_gained := public.check_and_level_up(p_player_id);
  
  RETURN v_levels_gained;
END;
$$;

-- Update claim_daily_reward to include cinema bonus
CREATE OR REPLACE FUNCTION public.claim_daily_reward()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_user_id uuid;
  v_today date;
  v_last_claimed date;
  v_current_crystals integer;
  v_reward_crystals integer := 500;
  v_cinema_bonus numeric := 0;
  v_bonuses jsonb;
  v_new_crystals integer;
  v_current_streak integer;
  v_new_streak integer;
BEGIN
  -- Get current user ID
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'message', 'No authenticated user'
    );
  END IF;

  v_today := CURRENT_DATE;

  -- Get current profile data
  SELECT last_claimed_date, crystals, COALESCE(daily_streak, 0)
  INTO v_last_claimed, v_current_crystals, v_current_streak
  FROM public.profiles
  WHERE id = v_user_id;

  -- Check if already claimed today
  IF v_last_claimed = v_today THEN
    RETURN jsonb_build_object(
      'success', true,
      'message', 'Daily reward already claimed today',
      'alreadyClaimed', true,
      'streak', v_current_streak
    );
  END IF;

  -- Calculate new streak
  IF v_last_claimed IS NULL THEN
    -- First time claiming
    v_new_streak := 1;
  ELSIF v_last_claimed = v_today - INTERVAL '1 day' THEN
    -- Consecutive day
    v_new_streak := v_current_streak + 1;
  ELSE
    -- Streak broken, reset to 1
    v_new_streak := 1;
  END IF;

  -- Get cinema bonus (crystal generation multiplier)
  SELECT public.get_building_bonuses(v_user_id) INTO v_bonuses;
  v_cinema_bonus := COALESCE((v_bonuses->>'crystal_generation')::numeric, 0);
  
  -- Apply cinema bonus to daily reward
  v_reward_crystals := (v_reward_crystals * (1.0 + v_cinema_bonus))::integer;

  -- Calculate new crystal total
  v_new_crystals := v_current_crystals + v_reward_crystals;

  -- Update profile
  UPDATE public.profiles
  SET
    crystals = v_new_crystals,
    last_claimed_date = v_today,
    daily_streak = v_new_streak
  WHERE id = v_user_id;

  -- Check achievements for daily_streak
  PERFORM public.check_achievements('daily_streak', v_new_streak);

  RETURN jsonb_build_object(
    'success', true,
    'message', format('Successfully claimed %s crystals!', v_reward_crystals),
    'crystalsAwarded', v_reward_crystals,
    'alreadyClaimed', false,
    'streak', v_new_streak,
    'cinema_bonus', v_cinema_bonus
  );
END;
$$;

-- Function to get energy regeneration rate (includes hospital bonus)
CREATE OR REPLACE FUNCTION public.get_energy_regeneration_rate(p_player_id uuid)
RETURNS numeric
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_base_rate numeric := 0; -- Base regeneration (0 = no passive regen, only manual restore)
  v_hospital_bonus numeric := 0;
  v_bonuses jsonb;
BEGIN
  -- Get building bonuses (hospitals provide energy regeneration)
  SELECT public.get_building_bonuses(p_player_id) INTO v_bonuses;
  v_hospital_bonus := COALESCE((v_bonuses->>'energy_regen')::numeric, 0);
  
  -- Total regeneration rate per hour
  RETURN v_base_rate + v_hospital_bonus;
END;
$$;

COMMENT ON FUNCTION public.grant_xp(uuid, integer) IS 'Grant XP to a player with boost multiplier and school building bonus support. Schools provide 1% XP multiplier per building (max 10%).';
COMMENT ON FUNCTION public.claim_daily_reward() IS 'Claim daily reward with cinema bonus. Cinemas provide 1% crystal generation bonus per building (max 5%).';
COMMENT ON FUNCTION public.get_energy_regeneration_rate(uuid) IS 'Get energy regeneration rate per hour including hospital bonus. Hospitals provide 5 energy per hour per building (max 20).';

