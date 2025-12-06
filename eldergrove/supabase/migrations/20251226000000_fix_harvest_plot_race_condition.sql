-- Fix harvest_plot race condition by adding row-level locking
-- This prevents concurrent harvest attempts from failing when multiple crops become ready simultaneously

CREATE OR REPLACE FUNCTION public.harvest_plot(p_plot_index integer)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_crop_id integer;
  v_ready_at timestamptz;
  v_yield_qty integer;
  v_item_id integer;
  v_new_item_qty bigint;
  v_xp_gained integer;
BEGIN
  -- Fetch current plot crop info WITH ROW-LEVEL LOCK to prevent concurrent harvests
  -- This ensures only one transaction can harvest a plot at a time
  SELECT crop_id, ready_at INTO v_crop_id, v_ready_at
  FROM public.farm_plots
  WHERE player_id = auth.uid()
    AND plot_index = p_plot_index
  FOR UPDATE;

  -- Check if plot exists (should always exist, but be safe)
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Plot % not found for this player', p_plot_index;
  END IF;

  -- Check if there's a crop to harvest (may have been harvested by another transaction)
  IF v_crop_id IS NULL THEN
    -- Return 0 instead of raising exception - plot was already harvested
    -- This allows graceful handling of race conditions
    RETURN 0;
  END IF;

  -- Check if crop is ready
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

  -- Grant XP for harvesting
  v_xp_gained := public.get_item_xp(v_item_id, v_yield_qty);
  PERFORM public.grant_xp(auth.uid(), v_xp_gained);

  -- Clear the plot (using the locked row ensures atomicity)
  UPDATE public.farm_plots
  SET crop_id = NULL,
      planted_at = NULL,
      ready_at = NULL
  WHERE player_id = auth.uid()
    AND plot_index = p_plot_index
    AND crop_id = v_crop_id; -- Only update if crop_id hasn't changed (double-check)

  -- Fetch and return updated item quantity
  SELECT COALESCE(quantity, 0) INTO v_new_item_qty
  FROM public.inventory
  WHERE player_id = auth.uid() AND item_id = v_item_id;

  -- Check achievements
  PERFORM public.check_achievements('harvest_count', 1);
  
  -- Update quest progress
  PERFORM public.update_quest_progress('harvest', NULL, 1);
  
  -- Auto-contribute to coven tasks
  PERFORM public.auto_contribute_coven_tasks('harvest', 1);

  RETURN v_new_item_qty;
END;
$$;

COMMENT ON FUNCTION public.harvest_plot(integer) IS 'Harvest ready crop from farm plot with row-level locking to prevent race conditions. Returns new item quantity, or 0 if plot was already harvested.';

