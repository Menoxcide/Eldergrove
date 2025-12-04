-- Update plant_crop function to consume seed items (100-110) from inventory
-- This matches the functionality of plant_plot but keeps the existing function name
-- that the frontend code is already using

CREATE OR REPLACE FUNCTION public.plant_crop(p_plot_index integer, p_crop_id integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_crop_item_id integer;
  v_seed_item_id integer;
  v_seed_quantity integer;
  v_grow_minutes integer;
BEGIN
  -- Get crop's item_id
  SELECT item_id INTO v_crop_item_id
  FROM public.crops
  WHERE id = p_crop_id;

  IF v_crop_item_id IS NULL THEN
    RAISE EXCEPTION 'Crop % does not have an item_id mapping', p_crop_id;
  END IF;

  -- Calculate seed item_id (100 + crop item_id)
  -- Crop item_id 1 (Wheat) -> Seed item_id 101
  v_seed_item_id := 100 + v_crop_item_id;

  -- Check if player has seed in inventory
  SELECT COALESCE(quantity, 0) INTO v_seed_quantity
  FROM public.inventory
  WHERE player_id = v_player_id AND item_id = v_seed_item_id;

  IF v_seed_quantity < 1 THEN
    RAISE EXCEPTION 'You do not have a seed for this crop. Seed item_id % required.', v_seed_item_id;
  END IF;

  -- Get grow time
  SELECT grow_minutes INTO v_grow_minutes
  FROM public.crops
  WHERE id = p_crop_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Crop with id % does not exist', p_crop_id;
  END IF;

  -- Deduct seed from inventory
  UPDATE public.inventory
  SET quantity = quantity - 1
  WHERE player_id = v_player_id AND item_id = v_seed_item_id;

  -- Plant the crop (only if plot is empty)
  UPDATE public.farm_plots 
  SET 
    crop_id = p_crop_id,
    planted_at = now(),
    ready_at = now() + (v_grow_minutes * interval '1 minute')
  WHERE player_id = v_player_id
    AND plot_index = p_plot_index
    AND crop_id is null;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Cannot plant on plot %: it is not empty or does not exist for this user', p_plot_index;
  END IF;

  -- Check achievements
  PERFORM public.check_achievements('plant_count', 1);
  
  -- Update quest progress
  PERFORM public.update_quest_progress('plant', NULL, 1);
  
  -- Auto-contribute to coven tasks
  PERFORM public.auto_contribute_coven_tasks('plant', 1);
END;
$$;

COMMENT ON FUNCTION public.plant_crop(integer, integer) IS 'Plant a crop on an empty farm plot. Consumes seed item (100-110) from inventory.';

