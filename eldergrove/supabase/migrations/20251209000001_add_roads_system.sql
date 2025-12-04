-- Roads system for town map
-- Allows players to place roads to connect buildings

-- Roads table
CREATE TABLE IF NOT EXISTS public.roads (
  id SERIAL PRIMARY KEY,
  player_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  grid_x INTEGER NOT NULL,
  grid_y INTEGER NOT NULL,
  road_type TEXT NOT NULL DEFAULT 'straight' CHECK (road_type IN ('straight_h', 'straight_v', 'corner_ne', 'corner_nw', 'corner_se', 'corner_sw', 'intersection', 't_n', 't_s', 't_e', 't_w')),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(player_id, grid_x, grid_y)
);

-- Enable RLS
ALTER TABLE public.roads ENABLE ROW LEVEL SECURITY;

-- RLS Policies
CREATE POLICY "Users can view their own roads"
  ON public.roads FOR SELECT
  USING (auth.uid() = player_id);

CREATE POLICY "Users can insert their own roads"
  ON public.roads FOR INSERT
  WITH CHECK (auth.uid() = player_id);

CREATE POLICY "Users can update their own roads"
  ON public.roads FOR UPDATE
  USING (auth.uid() = player_id);

CREATE POLICY "Users can delete their own roads"
  ON public.roads FOR DELETE
  USING (auth.uid() = player_id);

-- Index for faster queries
CREATE INDEX IF NOT EXISTS idx_roads_player_grid ON public.roads(player_id, grid_x, grid_y);

-- Function to determine road type based on adjacent roads
CREATE OR REPLACE FUNCTION public.determine_road_type(
  p_player_id UUID,
  p_grid_x INTEGER,
  p_grid_y INTEGER
)
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
  v_has_north BOOLEAN := FALSE;
  v_has_south BOOLEAN := FALSE;
  v_has_east BOOLEAN := FALSE;
  v_has_west BOOLEAN := FALSE;
  v_count INTEGER;
BEGIN
  -- Check adjacent roads
  SELECT EXISTS(
    SELECT 1 FROM public.roads 
    WHERE player_id = p_player_id 
    AND grid_x = p_grid_x 
    AND grid_y = p_grid_y - 1
  ) INTO v_has_north;
  
  SELECT EXISTS(
    SELECT 1 FROM public.roads 
    WHERE player_id = p_player_id 
    AND grid_x = p_grid_x 
    AND grid_y = p_grid_y + 1
  ) INTO v_has_south;
  
  SELECT EXISTS(
    SELECT 1 FROM public.roads 
    WHERE player_id = p_player_id 
    AND grid_x = p_grid_x + 1 
    AND grid_y = p_grid_y
  ) INTO v_has_east;
  
  SELECT EXISTS(
    SELECT 1 FROM public.roads 
    WHERE player_id = p_player_id 
    AND grid_x = p_grid_x - 1 
    AND grid_y = p_grid_y
  ) INTO v_has_west;
  
  -- Count connections
  v_count := (CASE WHEN v_has_north THEN 1 ELSE 0 END) +
             (CASE WHEN v_has_south THEN 1 ELSE 0 END) +
             (CASE WHEN v_has_east THEN 1 ELSE 0 END) +
             (CASE WHEN v_has_west THEN 1 ELSE 0 END);
  
  -- Determine road type
  IF v_count = 0 THEN
    RETURN 'straight_h'; -- Default to horizontal
  ELSIF v_count = 1 THEN
    IF v_has_north OR v_has_south THEN
      RETURN 'straight_v';
    ELSE
      RETURN 'straight_h';
    END IF;
  ELSIF v_count = 2 THEN
    IF (v_has_north AND v_has_south) THEN
      RETURN 'straight_v';
    ELSIF (v_has_east AND v_has_west) THEN
      RETURN 'straight_h';
    ELSIF (v_has_north AND v_has_east) THEN
      RETURN 'corner_ne';
    ELSIF (v_has_north AND v_has_west) THEN
      RETURN 'corner_nw';
    ELSIF (v_has_south AND v_has_east) THEN
      RETURN 'corner_se';
    ELSIF (v_has_south AND v_has_west) THEN
      RETURN 'corner_sw';
    END IF;
  ELSIF v_count = 3 THEN
    IF NOT v_has_north THEN
      RETURN 't_s';
    ELSIF NOT v_has_south THEN
      RETURN 't_n';
    ELSIF NOT v_has_east THEN
      RETURN 't_w';
    ELSIF NOT v_has_west THEN
      RETURN 't_e';
    END IF;
  ELSE
    RETURN 'intersection';
  END IF;
  
  RETURN 'straight_h';
END;
$$;

-- Function to place a road
CREATE OR REPLACE FUNCTION public.place_road(
  p_grid_x INTEGER,
  p_grid_y INTEGER
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id UUID := auth.uid();
  v_road_id INTEGER;
  v_road_type TEXT;
BEGIN
  IF v_player_id IS NULL THEN
    RAISE EXCEPTION 'User must be authenticated';
  END IF;

  -- Check if cell is already occupied by a building or decoration
  IF EXISTS (
    SELECT 1 FROM public.buildings
    WHERE player_id = v_player_id
    AND grid_x = p_grid_x
    AND grid_y = p_grid_y
  ) OR EXISTS (
    SELECT 1 FROM public.decorations
    WHERE player_id = v_player_id
    AND grid_x = p_grid_x
    AND grid_y = p_grid_y
  ) THEN
    RAISE EXCEPTION 'Cell is occupied by a building or decoration';
  END IF;

  -- Determine road type based on adjacent roads
  v_road_type := public.determine_road_type(v_player_id, p_grid_x, p_grid_y);

  -- Insert or update road
  INSERT INTO public.roads (player_id, grid_x, grid_y, road_type)
  VALUES (v_player_id, p_grid_x, p_grid_y, v_road_type)
  ON CONFLICT (player_id, grid_x, grid_y) 
  DO UPDATE SET road_type = v_road_type
  RETURNING id INTO v_road_id;

  -- Update adjacent roads to recalculate their types
  PERFORM public.update_adjacent_roads(v_player_id, p_grid_x, p_grid_y);

  RETURN v_road_id;
END;
$$;

-- Function to update adjacent roads
CREATE OR REPLACE FUNCTION public.update_adjacent_roads(
  p_player_id UUID,
  p_grid_x INTEGER,
  p_grid_y INTEGER
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  v_road_type TEXT;
BEGIN
  -- Update north road
  IF EXISTS (SELECT 1 FROM public.roads WHERE player_id = p_player_id AND grid_x = p_grid_x AND grid_y = p_grid_y - 1) THEN
    v_road_type := public.determine_road_type(p_player_id, p_grid_x, p_grid_y - 1);
    UPDATE public.roads SET road_type = v_road_type 
    WHERE player_id = p_player_id AND grid_x = p_grid_x AND grid_y = p_grid_y - 1;
  END IF;

  -- Update south road
  IF EXISTS (SELECT 1 FROM public.roads WHERE player_id = p_player_id AND grid_x = p_grid_x AND grid_y = p_grid_y + 1) THEN
    v_road_type := public.determine_road_type(p_player_id, p_grid_x, p_grid_y + 1);
    UPDATE public.roads SET road_type = v_road_type 
    WHERE player_id = p_player_id AND grid_x = p_grid_x AND grid_y = p_grid_y + 1;
  END IF;

  -- Update east road
  IF EXISTS (SELECT 1 FROM public.roads WHERE player_id = p_player_id AND grid_x = p_grid_x + 1 AND grid_y = p_grid_y) THEN
    v_road_type := public.determine_road_type(p_player_id, p_grid_x + 1, p_grid_y);
    UPDATE public.roads SET road_type = v_road_type 
    WHERE player_id = p_player_id AND grid_x = p_grid_x + 1 AND grid_y = p_grid_y;
  END IF;

  -- Update west road
  IF EXISTS (SELECT 1 FROM public.roads WHERE player_id = p_player_id AND grid_x = p_grid_x - 1 AND grid_y = p_grid_y) THEN
    v_road_type := public.determine_road_type(p_player_id, p_grid_x - 1, p_grid_y);
    UPDATE public.roads SET road_type = v_road_type 
    WHERE player_id = p_player_id AND grid_x = p_grid_x - 1 AND grid_y = p_grid_y;
  END IF;
END;
$$;

-- Function to remove a road
CREATE OR REPLACE FUNCTION public.remove_road(
  p_grid_x INTEGER,
  p_grid_y INTEGER
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id UUID := auth.uid();
  v_adjacent_x INTEGER;
  v_adjacent_y INTEGER;
BEGIN
  IF v_player_id IS NULL THEN
    RAISE EXCEPTION 'User must be authenticated';
  END IF;

  -- Store adjacent coordinates before deletion
  SELECT grid_x, grid_y INTO v_adjacent_x, v_adjacent_y
  FROM public.roads
  WHERE player_id = v_player_id 
  AND grid_x = p_grid_x 
  AND grid_y = p_grid_y;

  -- Delete the road
  DELETE FROM public.roads
  WHERE player_id = v_player_id
  AND grid_x = p_grid_x
  AND grid_y = p_grid_y;

  -- Update adjacent roads
  IF v_adjacent_x IS NOT NULL THEN
    PERFORM public.update_adjacent_roads(v_player_id, p_grid_x, p_grid_y);
  END IF;
END;
$$;

COMMENT ON TABLE public.roads IS 'Roads placed by players on the town map';
COMMENT ON FUNCTION public.place_road(INTEGER, INTEGER) IS 'Place a road at the specified grid coordinates';
COMMENT ON FUNCTION public.remove_road(INTEGER, INTEGER) IS 'Remove a road from the specified grid coordinates';
COMMENT ON FUNCTION public.determine_road_type(UUID, INTEGER, INTEGER) IS 'Determine the appropriate road type based on adjacent roads';

