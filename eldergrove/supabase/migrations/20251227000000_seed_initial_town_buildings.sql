-- Seed initial town buildings and roads when a profile is created
-- Places one building of each type with roads connecting them all to the town hall

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
BEGIN
  -- Place Town Hall first at center (3,3) - occupies (3,3) to (5,5)
  INSERT INTO public.buildings (player_id, building_type, grid_x, grid_y, level)
  VALUES (v_player_id, 'town_hall', 3, 3, 1)
  RETURNING id INTO v_building_id;

  -- Place factory buildings
  INSERT INTO public.buildings (player_id, building_type, grid_x, grid_y, level) VALUES
    (v_player_id, 'rune_bakery', 0, 0, 1),
    (v_player_id, 'potion_workshop', 0, 3, 1),
    (v_player_id, 'enchanting_lab', 0, 6, 1),
    (v_player_id, 'kitchen', 7, 0, 1);

  -- Place community buildings
  INSERT INTO public.buildings (player_id, building_type, grid_x, grid_y, level) VALUES
    (v_player_id, 'school', 7, 3, 1),
    (v_player_id, 'hospital', 7, 6, 1),
    (v_player_id, 'cinema', 3, 7, 1);

  -- Recalculate population after placing all buildings
  PERFORM public.calculate_population(v_player_id);

  -- Create roads connecting all buildings to town hall
  -- Town Hall occupies (3,3) to (5,5), so roads must go around it
  -- Place all roads first with temporary types, then update them
  
  -- Main horizontal road above town hall (row 2)
  INSERT INTO public.roads (player_id, grid_x, grid_y, road_type) VALUES
    (v_player_id, 0, 2, 'straight_h'),
    (v_player_id, 1, 2, 'straight_h'),
    (v_player_id, 2, 2, 'straight_h'),
    (v_player_id, 3, 2, 'straight_h'),
    (v_player_id, 4, 2, 'straight_h'),
    (v_player_id, 5, 2, 'straight_h'),
    (v_player_id, 6, 2, 'straight_h'),
    (v_player_id, 7, 2, 'straight_h'),
    (v_player_id, 8, 2, 'straight_h')
  ON CONFLICT (player_id, grid_x, grid_y) DO NOTHING;

  -- Main horizontal road below town hall (row 6)
  INSERT INTO public.roads (player_id, grid_x, grid_y, road_type) VALUES
    (v_player_id, 0, 6, 'straight_h'),
    (v_player_id, 1, 6, 'straight_h'),
    (v_player_id, 2, 6, 'straight_h'),
    (v_player_id, 3, 6, 'straight_h'),
    (v_player_id, 4, 6, 'straight_h'),
    (v_player_id, 5, 6, 'straight_h'),
    (v_player_id, 6, 6, 'straight_h'),
    (v_player_id, 7, 6, 'straight_h'),
    (v_player_id, 8, 6, 'straight_h')
  ON CONFLICT (player_id, grid_x, grid_y) DO NOTHING;

  -- Vertical roads on left side (column 2) connecting row 2 to row 6
  INSERT INTO public.roads (player_id, grid_x, grid_y, road_type) VALUES
    (v_player_id, 2, 3, 'straight_v'),
    (v_player_id, 2, 4, 'straight_v'),
    (v_player_id, 2, 5, 'straight_v')
  ON CONFLICT (player_id, grid_x, grid_y) DO NOTHING;

  -- Vertical roads on right side (column 6) connecting row 2 to row 6
  INSERT INTO public.roads (player_id, grid_x, grid_y, road_type) VALUES
    (v_player_id, 6, 3, 'straight_v'),
    (v_player_id, 6, 4, 'straight_v'),
    (v_player_id, 6, 5, 'straight_v')
  ON CONFLICT (player_id, grid_x, grid_y) DO NOTHING;

  -- Roads connecting buildings to main roads
  -- Buildings are adjacent to roads, roads don't overlap buildings
  -- Road to Rune Bakery (0,0) - occupies (0,0) to (1,1), road at (0,2) connects above, (2,0) connects right
  INSERT INTO public.roads (player_id, grid_x, grid_y, road_type) VALUES
    (v_player_id, 2, 0, 'straight_h'),
    (v_player_id, 2, 1, 'straight_v')
  ON CONFLICT (player_id, grid_x, grid_y) DO NOTHING;

  -- Road to Potion Workshop (0,3) - occupies (0,3) to (1,4), road at (0,2) already connects above
  -- Road at (2,3) and (2,4) connects right
  INSERT INTO public.roads (player_id, grid_x, grid_y, road_type) VALUES
    (v_player_id, 2, 3, 'straight_v'),
    (v_player_id, 2, 4, 'straight_v')
  ON CONFLICT (player_id, grid_x, grid_y) DO NOTHING;

  -- Road to Enchanting Lab (0,6) - occupies (0,6) to (1,7), road at (0,6) already connects, (2,6) and (2,7) connect right
  INSERT INTO public.roads (player_id, grid_x, grid_y, road_type) VALUES
    (v_player_id, 2, 7, 'straight_v')
  ON CONFLICT (player_id, grid_x, grid_y) DO NOTHING;

  -- Road to Kitchen (7,0) - occupies (7,0) to (8,1), road at (6,0) and (6,1) connects left
  INSERT INTO public.roads (player_id, grid_x, grid_y, road_type) VALUES
    (v_player_id, 6, 0, 'straight_h'),
    (v_player_id, 6, 1, 'straight_v')
  ON CONFLICT (player_id, grid_x, grid_y) DO NOTHING;

  -- Road to School (7,3) - occupies (7,3) to (8,4), road at (6,3) and (6,4) connects left
  INSERT INTO public.roads (player_id, grid_x, grid_y, road_type) VALUES
    (v_player_id, 6, 3, 'straight_v'),
    (v_player_id, 6, 4, 'straight_v')
  ON CONFLICT (player_id, grid_x, grid_y) DO NOTHING;

  -- Road to Hospital (7,6) - occupies (7,6) to (8,7), road at (6,6) and (6,7) connects left
  INSERT INTO public.roads (player_id, grid_x, grid_y, road_type) VALUES
    (v_player_id, 6, 7, 'straight_v')
  ON CONFLICT (player_id, grid_x, grid_y) DO NOTHING;

  -- Road to Cinema (3,7) - occupies (3,7) to (4,8), road at (3,6) already connects above, (2,7) and (2,8) connect left
  INSERT INTO public.roads (player_id, grid_x, grid_y, road_type) VALUES
    (v_player_id, 2, 8, 'straight_h')
  ON CONFLICT (player_id, grid_x, grid_y) DO NOTHING;

  -- Update all road types based on adjacent roads
  -- Loop through all roads and update their types
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

-- Trigger to seed initial buildings when a profile is created
CREATE TRIGGER on_profile_created_seed_town
  AFTER INSERT ON public.profiles
  FOR EACH ROW
  EXECUTE FUNCTION public.seed_initial_town_buildings();

COMMENT ON FUNCTION public.seed_initial_town_buildings() IS 'Seed initial town buildings and roads when a profile is created. Places one building of each type with roads connecting them all to the town hall.';

