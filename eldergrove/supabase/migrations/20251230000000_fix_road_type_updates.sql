-- Fix road type updates to ensure all roads are updated correctly
-- This migration improves the road type calculation to handle chains of roads properly

-- Improved function to update adjacent roads
-- Updates roads in a 2-cell radius to catch chains and ensure proper connections
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
  v_road_record RECORD;
BEGIN
  -- Update all roads within 2 cells to ensure chains are properly updated
  -- This includes immediate neighbors and second-level neighbors in the same direction
  FOR v_road_record IN
    SELECT DISTINCT grid_x, grid_y
    FROM public.roads
    WHERE player_id = p_player_id
    AND (
      -- Immediate neighbors (north, south, east, west)
      (grid_x = p_grid_x AND grid_y = p_grid_y - 1) OR
      (grid_x = p_grid_x AND grid_y = p_grid_y + 1) OR
      (grid_x = p_grid_x + 1 AND grid_y = p_grid_y) OR
      (grid_x = p_grid_x - 1 AND grid_y = p_grid_y) OR
      -- Second-level neighbors in same direction (for straight road chains)
      (grid_x = p_grid_x AND grid_y = p_grid_y - 2) OR
      (grid_x = p_grid_x AND grid_y = p_grid_y + 2) OR
      (grid_x = p_grid_x + 2 AND grid_y = p_grid_y) OR
      (grid_x = p_grid_x - 2 AND grid_y = p_grid_y) OR
      -- Diagonal neighbors (for corner connections)
      (ABS(grid_x - p_grid_x) = 1 AND ABS(grid_y - p_grid_y) = 1)
    )
  LOOP
    v_road_type := public.determine_road_type(p_player_id, v_road_record.grid_x, v_road_record.grid_y);
    UPDATE public.roads
    SET road_type = v_road_type
    WHERE player_id = p_player_id
      AND grid_x = v_road_record.grid_x
      AND grid_y = v_road_record.grid_y;
  END LOOP;
END;
$$;

-- Function to recalculate all road types for a player (useful for fixing stale data)
CREATE OR REPLACE FUNCTION public.recalculate_all_road_types()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_player_id UUID := auth.uid();
  v_road_record RECORD;
  v_new_road_type TEXT;
BEGIN
  IF v_player_id IS NULL THEN
    RAISE EXCEPTION 'User must be authenticated';
  END IF;

  -- Recalculate all road types for the current player
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
END;
$$;

COMMENT ON FUNCTION public.recalculate_all_road_types() IS 'Recalculate all road types for the current player. Useful for fixing stale road type data.';

