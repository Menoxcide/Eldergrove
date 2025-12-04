-- Fix and verify level calculation formula
-- Current formula: XP needed = current_level * 1000
-- This ensures proper level progression

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
  
  -- Ensure level is at least 1
  IF v_current_level IS NULL OR v_current_level < 1 THEN
    v_current_level := 1;
  END IF;
  
  -- Ensure XP is non-negative
  IF v_current_xp IS NULL OR v_current_xp < 0 THEN
    v_current_xp := 0;
  END IF;
  
  -- Calculate XP needed for next level
  -- Formula: XP needed = current_level * 1000
  -- Level 1 -> 2: 1000 XP
  -- Level 2 -> 3: 2000 XP
  -- Level 3 -> 4: 3000 XP
  -- etc.
  v_xp_for_next_level := v_current_level * 1000;
  
  -- Level up as many times as possible
  WHILE v_current_xp >= v_xp_for_next_level LOOP
    v_current_level := v_current_level + 1;
    v_current_xp := v_current_xp - v_xp_for_next_level;
    v_levels_gained := v_levels_gained + 1;
    
    -- Recalculate XP needed for next level
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

COMMENT ON FUNCTION public.check_and_level_up(uuid) IS 'Check if player has enough XP to level up and update level accordingly. Formula: XP needed = current_level * 1000. Returns number of levels gained.';

-- Helper function to get XP needed for next level (for UI display)
CREATE OR REPLACE FUNCTION public.get_xp_for_next_level(p_player_id uuid)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_current_level integer;
BEGIN
  SELECT COALESCE(level, 1) INTO v_current_level
  FROM public.profiles
  WHERE id = p_player_id;
  
  -- XP needed = current_level * 1000
  RETURN v_current_level * 1000;
END;
$$;

COMMENT ON FUNCTION public.get_xp_for_next_level(uuid) IS 'Get XP needed for next level. Formula: current_level * 1000.';

