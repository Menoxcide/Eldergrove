-- Seed initial town buildings and roads when a profile is created
-- Places one building of each type with organic roads connecting them all to the town hall

-- Helper function to check if a cell is occupied by a building
CREATE OR REPLACE FUNCTION public.is_cell_occupied(
  p_player_id uuid,
  p_x integer,
  p_y integer
)
RETURNS boolean
LANGUAGE plpgsql
AS $$
DECLARE
  v_building record;
  v_size_x integer;
  v_size_y integer;
BEGIN
  FOR v_building IN 
    SELECT b.grid_x, b.grid_y, bt.size_x, bt.size_y
    FROM public.buildings b
    JOIN public.building_types bt ON b.building_type = bt.building_type
    WHERE b.player_id = p_player_id
  LOOP
    IF p_x >= v_building.grid_x AND p_x < v_building.grid_x + v_building.size_x AND
       p_y >= v_building.grid_y AND p_y < v_building.grid_y + v_building.size_y THEN
      RETURN true;
    END IF;
  END LOOP;
  RETURN false;
END;
$$;

-- Helper function to find path from building to town hall using simple pathfinding
CREATE OR REPLACE FUNCTION public.find_road_path(
  p_player_id uuid,
  p_start_x integer,
  p_start_y integer,
  p_end_x integer,
  p_end_y integer
)
RETURNS TABLE(path_x integer, path_y integer)
LANGUAGE plpgsql
AS $$
DECLARE
  v_current_x integer;
  v_current_y integer;
  v_delta_x integer;
  v_delta_y integer;
  v_step_x integer;
  v_step_y integer;
  v_path_x integer;
  v_path_y integer;
  v_iteration integer := 0;
  v_alternate boolean := false;
BEGIN
  -- Simple pathfinding: move towards target, avoiding buildings
  -- Use L-shaped paths (move in one direction, then the other) for organic feel
  
  v_current_x := p_start_x;
  v_current_y := p_start_y;
  
  v_delta_x := p_end_x - p_start_x;
  v_delta_y := p_end_y - p_start_y;
  
  -- Determine step direction
  v_step_x := CASE WHEN v_delta_x > 0 THEN 1 WHEN v_delta_x < 0 THEN -1 ELSE 0 END;
  v_step_y := CASE WHEN v_delta_y > 0 THEN 1 WHEN v_delta_y < 0 THEN -1 ELSE 0 END;
  
  -- Create L-shaped path: move in dominant direction first, then the other
  -- This creates more organic paths than straight lines
  -- If a cell is occupied, we skip it but continue - roads will go around buildings
  
  -- Move in X direction first if X distance is larger, otherwise Y
  IF ABS(v_delta_x) >= ABS(v_delta_y) THEN
    -- Move horizontally first
    WHILE v_current_x != p_end_x LOOP
      IF NOT public.is_cell_occupied(p_player_id, v_current_x, v_current_y) THEN
        path_x := v_current_x;
        path_y := v_current_y;
        RETURN NEXT;
      END IF;
      -- Move to next cell even if occupied (will skip it)
      v_current_x := v_current_x + v_step_x;
      v_delta_x := p_end_x - v_current_x;
      v_iteration := v_iteration + 1;
      IF v_iteration > 50 THEN EXIT; END IF;
    END LOOP;
    
    -- Then move vertically
    WHILE v_current_y != p_end_y LOOP
      IF NOT public.is_cell_occupied(p_player_id, v_current_x, v_current_y) THEN
        path_x := v_current_x;
        path_y := v_current_y;
        RETURN NEXT;
      END IF;
      -- Move to next cell even if occupied (will skip it)
      v_current_y := v_current_y + v_step_y;
      v_delta_y := p_end_y - v_current_y;
      v_iteration := v_iteration + 1;
      IF v_iteration > 50 THEN EXIT; END IF;
    END LOOP;
  ELSE
    -- Move vertically first
    WHILE v_current_y != p_end_y LOOP
      IF NOT public.is_cell_occupied(p_player_id, v_current_x, v_current_y) THEN
        path_x := v_current_x;
        path_y := v_current_y;
        RETURN NEXT;
      END IF;
      -- Move to next cell even if occupied (will skip it)
      v_current_y := v_current_y + v_step_y;
      v_delta_y := p_end_y - v_current_y;
      v_iteration := v_iteration + 1;
      IF v_iteration > 50 THEN EXIT; END IF;
    END LOOP;
    
    -- Then move horizontally
    WHILE v_current_x != p_end_x LOOP
      IF NOT public.is_cell_occupied(p_player_id, v_current_x, v_current_y) THEN
        path_x := v_current_x;
        path_y := v_current_y;
        RETURN NEXT;
      END IF;
      -- Move to next cell even if occupied (will skip it)
      v_current_x := v_current_x + v_step_x;
      v_delta_x := p_end_x - v_current_x;
      v_iteration := v_iteration + 1;
      IF v_iteration > 50 THEN EXIT; END IF;
    END LOOP;
  END IF;
  
  RETURN;
END;
$$;

-- Function to seed initial buildings and roads (bypasses normal checks for initial setup)
CREATE OR REPLACE FUNCTION public.seed_initial_town_buildings()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_player_id uuid := new.id;
  v_building_info record;
  v_size_x integer;
  v_size_y integer;
  v_building_id integer;
  v_road_record record;
  v_new_road_type text;
  v_town_hall_x integer := 4;
  v_town_hall_y integer := 4;
  v_path_point record;
  v_building_x integer;
  v_building_y integer;
  v_building_center_x integer;
  v_building_center_y integer;
  v_town_hall_center_x integer := 5; -- Town hall is 3x3, center is at (4,4) + 1 = (5,5) but we use entrance
  v_town_hall_center_y integer := 5;
BEGIN
  -- Place Town Hall at center (4,4) - occupies (4,4) to (6,6) for 3x3 building
  -- Town hall entrance is typically at the front, so we'll connect roads to (5,3) - north side
  INSERT INTO public.buildings (player_id, building_type, grid_x, grid_y, level)
  VALUES (v_player_id, 'town_hall', v_town_hall_x, v_town_hall_y, 1)
  RETURNING id INTO v_building_id;

  -- Place buildings in a more organic layout around the town hall
  -- Space them out better and consider building sizes (2x2 for most, 3x3 for town hall)
  -- Factory buildings - spread them out in a circle around town hall
  INSERT INTO public.buildings (player_id, building_type, grid_x, grid_y, level) VALUES
    (v_player_id, 'rune_bakery', 1, 1, 1),      -- Top-left area (2x2, occupies 1,1 to 2,2)
    (v_player_id, 'potion_workshop', 0, 4, 1),  -- Left side (2x2, occupies 0,4 to 1,5)
    (v_player_id, 'enchanting_lab', 1, 7, 1),   -- Bottom-left (2x2, occupies 1,7 to 2,8)
    (v_player_id, 'kitchen', 7, 1, 1);          -- Top-right (2x2, occupies 7,1 to 8,2)

  -- Community buildings - spread them out
  INSERT INTO public.buildings (player_id, building_type, grid_x, grid_y, level) VALUES
    (v_player_id, 'school', 7, 4, 1),           -- Right side (2x2, occupies 7,4 to 8,5)
    (v_player_id, 'hospital', 7, 7, 1),        -- Bottom-right (2x2, occupies 7,7 to 8,8)
    (v_player_id, 'cinema', 4, 7, 1);          -- Bottom center (2x2, occupies 4,7 to 5,8)

  -- Recalculate population after placing all buildings
  PERFORM public.calculate_population(v_player_id);

  -- Create organic roads connecting each building to town hall
  -- Town hall is at (4,4) to (6,6), so we'll connect roads to the north side at (5,3)
  -- For each building, find a path to the town hall entrance
  
  -- Connect Rune Bakery (1,1) - 2x2 building, entrance at south/east side (2,2)
  FOR v_path_point IN 
    SELECT * FROM public.find_road_path(v_player_id, 2, 2, 5, 3)
  LOOP
    INSERT INTO public.roads (player_id, grid_x, grid_y, road_type)
    VALUES (v_player_id, v_path_point.path_x, v_path_point.path_y, 'straight_h')
    ON CONFLICT (player_id, grid_x, grid_y) DO NOTHING;
  END LOOP;
  
  -- Connect Potion Workshop (0,4) - 2x2 building, entrance at east side (1,5)
  FOR v_path_point IN 
    SELECT * FROM public.find_road_path(v_player_id, 1, 5, 5, 3)
  LOOP
    INSERT INTO public.roads (player_id, grid_x, grid_y, road_type)
    VALUES (v_player_id, v_path_point.path_x, v_path_point.path_y, 'straight_h')
    ON CONFLICT (player_id, grid_x, grid_y) DO NOTHING;
  END LOOP;
  
  -- Connect Enchanting Lab (1,7) - 2x2 building, entrance at north/east side (2,7)
  FOR v_path_point IN 
    SELECT * FROM public.find_road_path(v_player_id, 2, 7, 5, 3)
  LOOP
    INSERT INTO public.roads (player_id, grid_x, grid_y, road_type)
    VALUES (v_player_id, v_path_point.path_x, v_path_point.path_y, 'straight_h')
    ON CONFLICT (player_id, grid_x, grid_y) DO NOTHING;
  END LOOP;
  
  -- Connect Kitchen (7,1) - 2x2 building, entrance at south/west side (7,2)
  FOR v_path_point IN 
    SELECT * FROM public.find_road_path(v_player_id, 7, 2, 5, 3)
  LOOP
    INSERT INTO public.roads (player_id, grid_x, grid_y, road_type)
    VALUES (v_player_id, v_path_point.path_x, v_path_point.path_y, 'straight_h')
    ON CONFLICT (player_id, grid_x, grid_y) DO NOTHING;
  END LOOP;
  
  -- Connect School (7,4) - 2x2 building, entrance at west side (7,5)
  FOR v_path_point IN 
    SELECT * FROM public.find_road_path(v_player_id, 7, 5, 5, 3)
  LOOP
    INSERT INTO public.roads (player_id, grid_x, grid_y, road_type)
    VALUES (v_player_id, v_path_point.path_x, v_path_point.path_y, 'straight_h')
    ON CONFLICT (player_id, grid_x, grid_y) DO NOTHING;
  END LOOP;
  
  -- Connect Hospital (7,7) - 2x2 building, entrance at north/west side (7,7)
  FOR v_path_point IN 
    SELECT * FROM public.find_road_path(v_player_id, 7, 7, 5, 3)
  LOOP
    INSERT INTO public.roads (player_id, grid_x, grid_y, road_type)
    VALUES (v_player_id, v_path_point.path_x, v_path_point.path_y, 'straight_h')
    ON CONFLICT (player_id, grid_x, grid_y) DO NOTHING;
  END LOOP;
  
  -- Connect Cinema (4,7) - 2x2 building, entrance at north side (5,7)
  FOR v_path_point IN 
    SELECT * FROM public.find_road_path(v_player_id, 5, 7, 5, 3)
  LOOP
    INSERT INTO public.roads (player_id, grid_x, grid_y, road_type)
    VALUES (v_player_id, v_path_point.path_x, v_path_point.path_y, 'straight_h')
    ON CONFLICT (player_id, grid_x, grid_y) DO NOTHING;
  END LOOP;

  -- Update all road types based on adjacent roads
  FOR v_road_record IN 
    SELECT grid_x, grid_y FROM public.roads WHERE player_id = v_player_id
  LOOP
    v_new_road_type := public.determine_road_type(v_player_id, v_road_record.grid_x, v_road_record.grid_y);
    UPDATE public.roads 
    SET road_type = v_new_road_type
    WHERE player_id = v_player_id 
      AND grid_x = v_road_record.grid_x 
      AND grid_y = v_road_record.grid_y;
  END LOOP;

  RETURN new;
END;
$$;

-- Drop existing trigger if it exists (for migration re-runs)
DROP TRIGGER IF EXISTS on_profile_created_seed_town ON public.profiles;

-- Trigger to seed initial buildings when a profile is created
CREATE TRIGGER on_profile_created_seed_town
  AFTER INSERT ON public.profiles
  FOR EACH ROW
  EXECUTE FUNCTION public.seed_initial_town_buildings();

COMMENT ON FUNCTION public.seed_initial_town_buildings() IS 'Seed initial town buildings and roads when a profile is created. Places one building of each type with roads connecting them all to the town hall.';

