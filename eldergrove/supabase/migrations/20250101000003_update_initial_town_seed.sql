-- Update initial town seed to only place town hall (no other buildings or roads)

CREATE OR REPLACE FUNCTION public.seed_initial_town_buildings()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_player_id uuid := new.id;
  v_building_id integer;
  v_town_hall_x integer := 4;
  v_town_hall_y integer := 4;
BEGIN
  -- Only place Town Hall at center (4,4) - occupies (4,4) to (6,6) for 3x3 building
  -- No roads, no other buildings - just town hall surrounded by grass
  INSERT INTO public.buildings (player_id, building_type, grid_x, grid_y, level)
  VALUES (v_player_id, 'town_hall', v_town_hall_x, v_town_hall_y, 1)
  RETURNING id INTO v_building_id;

  -- Recalculate population after placing town hall
  PERFORM public.calculate_population(v_player_id);

  RETURN new;
END;
$$;

COMMENT ON FUNCTION public.seed_initial_town_buildings() IS 'Seed initial town with only town hall at center. No roads or other buildings - players place them themselves.';

