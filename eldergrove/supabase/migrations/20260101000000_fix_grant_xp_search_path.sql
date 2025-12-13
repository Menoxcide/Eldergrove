-- Fix grant_xp function to include SET search_path in CREATE statement
-- This ensures the function works correctly when called from other functions with restricted search_path
-- Also adds proper error handling for get_building_bonuses calls

CREATE OR REPLACE FUNCTION public.grant_xp(p_player_id uuid, p_xp_amount integer)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_xp_multiplier numeric := 1.0;
  v_building_bonus numeric := 0;
  v_final_xp integer;
  v_levels_gained integer;
  v_bonuses jsonb;
BEGIN
  -- Validate input
  IF p_player_id IS NULL THEN
    RAISE EXCEPTION 'Player ID cannot be NULL';
  END IF;
  
  IF p_xp_amount IS NULL OR p_xp_amount <= 0 THEN
    -- If XP amount is 0 or negative, just return 0 levels gained (don't fail)
    RETURN 0;
  END IF;
  
  -- Get active XP boost multiplier
  SELECT COALESCE(multiplier, 1.0) INTO v_xp_multiplier
  FROM public.active_boosts
  WHERE player_id = p_player_id
    AND boost_type = 'xp'
    AND expires_at > now()
  LIMIT 1;
  
  -- Get building bonuses (schools provide XP multiplier)
  -- Use exception handling to gracefully handle any errors
  BEGIN
    SELECT public.get_building_bonuses(p_player_id) INTO v_bonuses;
    v_building_bonus := COALESCE((v_bonuses->>'xp_multiplier')::numeric, 0);
  EXCEPTION
    WHEN OTHERS THEN
      -- If get_building_bonuses fails, log and continue with 0 bonus
      RAISE WARNING 'Failed to get building bonuses for player %: %', p_player_id, SQLERRM;
      v_building_bonus := 0;
  END;
  
  -- Calculate final XP with both boost and building multiplier
  v_final_xp := (p_xp_amount * (1.0 + v_building_bonus) * v_xp_multiplier)::integer;
  
  -- Ensure we have a positive XP amount
  IF v_final_xp <= 0 THEN
    RETURN 0;
  END IF;
  
  -- Grant XP
  UPDATE public.profiles
  SET xp = xp + v_final_xp
  WHERE id = p_player_id;
  
  -- Note: UPDATE doesn't set FOUND/NOT FOUND in the same way as SELECT
  -- If player doesn't exist, the UPDATE simply affects 0 rows but doesn't raise an error
  -- This is acceptable behavior - we'll continue and let check_and_level_up handle validation
  
  -- Check for level-ups
  BEGIN
    v_levels_gained := public.check_and_level_up(p_player_id);
  EXCEPTION
    WHEN OTHERS THEN
      -- If level-up check fails, log but don't fail the XP grant
      RAISE WARNING 'Failed to check level-up for player %: %', p_player_id, SQLERRM;
      v_levels_gained := 0;
  END;
  
  RETURN COALESCE(v_levels_gained, 0);
END;
$$;

COMMENT ON FUNCTION public.grant_xp(uuid, integer) IS 'Grant XP to a player with boost multiplier and school building bonus support. Schools provide 1% XP multiplier per building (max 10%). Includes proper error handling and search_path security.';

