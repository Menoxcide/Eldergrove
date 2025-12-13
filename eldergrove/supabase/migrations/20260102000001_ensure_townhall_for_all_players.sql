-- Ensure all existing players have a townhall at center (4,4)
-- This migration fixes players who were created before the seed function was in place
-- or whose townhall was removed

DO $$
DECLARE
  v_player_record record;
  v_town_hall_x integer := 4;
  v_town_hall_y integer := 4;
  v_building_id integer;
  v_has_townhall boolean;
BEGIN
  -- Loop through all players
  FOR v_player_record IN 
    SELECT id FROM public.profiles
  LOOP
    -- Check if player has a townhall
    SELECT EXISTS (
      SELECT 1 FROM public.buildings
      WHERE player_id = v_player_record.id
        AND building_type = 'town_hall'
    ) INTO v_has_townhall;
    
    -- If no townhall, place one at center (4,4)
    -- Townhall is 3x3, so it occupies (4,4) to (6,6)
    IF NOT v_has_townhall THEN
      -- Check if center cells are available
      IF NOT EXISTS (
        SELECT 1 FROM public.buildings
        WHERE player_id = v_player_record.id
          AND (
            (grid_x >= v_town_hall_x AND grid_x < v_town_hall_x + 3 AND
             grid_y >= v_town_hall_y AND grid_y < v_town_hall_y + 3)
          )
      ) THEN
        -- Place townhall at center
        INSERT INTO public.buildings (player_id, building_type, grid_x, grid_y, level)
        VALUES (v_player_record.id, 'town_hall', v_town_hall_x, v_town_hall_y, 1)
        RETURNING id INTO v_building_id;
        
        -- Recalculate population after placing townhall
        PERFORM public.calculate_population(v_player_record.id);
      END IF;
    END IF;
  END LOOP;
END;
$$;

COMMENT ON FUNCTION public.seed_initial_town_buildings() IS 'Seed initial town with only town hall at center. No roads or other buildings - players place them themselves.';

