-- Update harvest_plot RPC to handle all crop types and yield appropriate items based on crop.item_id

CREATE OR REPLACE FUNCTION public.harvest_plot(p_plot_index integer)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_crop_id integer;
  v_ready_at timestamptz;
  v_yield_qty integer;
  v_item_id integer;
  v_new_item_qty bigint;
BEGIN
  -- Fetch current plot crop info
  SELECT crop_id, ready_at INTO v_crop_id, v_ready_at
  FROM public.farm_plots
  WHERE player_id = auth.uid()
    AND plot_index = p_plot_index;

  IF v_crop_id IS NULL THEN
    RAISE EXCEPTION 'No crop to harvest on plot % for this player', p_plot_index;
  END IF;

  IF v_ready_at > now() THEN
    RAISE EXCEPTION 'Crop on plot % is not ready yet (ready at %)', p_plot_index, v_ready_at;
  END IF;

  -- Fetch crop yield and item_id
  SELECT yield_crystals, item_id INTO v_yield_qty, v_item_id
  FROM public.crops
  WHERE id = v_crop_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Invalid crop_id % found on plot %', v_crop_id, p_plot_index;
  END IF;

  IF v_item_id IS NULL THEN
    RAISE EXCEPTION 'Crop % does not have an item_id mapping', v_crop_id;
  END IF;

  -- Award crop item to player inventory
  INSERT INTO public.inventory (player_id, item_id, quantity)
  VALUES (auth.uid(), v_item_id, v_yield_qty::bigint)
  ON CONFLICT (player_id, item_id) DO UPDATE SET
    quantity = inventory.quantity + excluded.quantity;

  -- Clear the plot
  UPDATE public.farm_plots
  SET crop_id = NULL,
      planted_at = NULL,
      ready_at = NULL
  WHERE player_id = auth.uid()
    AND plot_index = p_plot_index;

  -- Fetch and return updated item quantity
  SELECT COALESCE(quantity, 0) INTO v_new_item_qty
  FROM public.inventory
  WHERE player_id = auth.uid() AND item_id = v_item_id;

  -- Check achievements
  PERFORM public.check_achievements('harvest_count', 1);
  
  -- Update quest progress
  PERFORM public.update_quest_progress(NULL, 'harvest', 1);
  
  -- Auto-contribute to coven tasks
  PERFORM public.auto_contribute_coven_tasks('harvest', 1);

  RETURN v_new_item_qty;
END;
$$;

COMMENT ON FUNCTION public.harvest_plot(integer) IS 'Harvest ready crop from farm plot, adds crop item (based on crop.item_id) yield to inventory, clears plot. Returns new item quantity.';

