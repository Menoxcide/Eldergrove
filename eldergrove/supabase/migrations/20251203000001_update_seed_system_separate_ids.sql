-- Update seed system to use separate item IDs (100-110 for seeds, 1-10 for crops)

-- Update buy_seed function to add seed items (100-110) instead of crop items (1-10)
CREATE OR REPLACE FUNCTION public.buy_seed(p_crop_id integer)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_seed_price integer;
  v_current_crystals bigint;
  v_new_crystals bigint;
  v_crop_item_id integer;
  v_seed_item_id integer;
BEGIN
  -- Get seed price
  SELECT price_crystals INTO v_seed_price
  FROM public.seed_shop
  WHERE crop_id = p_crop_id AND available = true;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Seed for crop_id % is not available in the shop', p_crop_id;
  END IF;

  -- Get current crystals
  SELECT crystals INTO v_current_crystals
  FROM public.profiles
  WHERE id = v_player_id;

  IF v_current_crystals < v_seed_price THEN
    RAISE EXCEPTION 'Insufficient crystals: required %, available %', v_seed_price, v_current_crystals;
  END IF;

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

  -- Deduct crystals
  UPDATE public.profiles
  SET crystals = crystals - v_seed_price
  WHERE id = v_player_id;

  -- Add seed to inventory (using seed item_id 100-110)
  INSERT INTO public.inventory (player_id, item_id, quantity)
  VALUES (v_player_id, v_seed_item_id, 1)
  ON CONFLICT (player_id, item_id) DO UPDATE SET
    quantity = inventory.quantity + 1;

  -- Get updated crystals
  SELECT crystals INTO v_new_crystals
  FROM public.profiles
  WHERE id = v_player_id;

  RETURN v_new_crystals;
END;
$$;

COMMENT ON FUNCTION public.buy_seed(integer) IS 'Purchase seed for a crop using crystals. Adds 1 seed (using seed item_id 100-110) to inventory and returns new crystal balance.';

-- Update plant_plot function to consume seed items (100-110) instead of crop items (1-10)
CREATE OR REPLACE FUNCTION public.plant_plot(p_plot_index integer, p_crop_id integer)
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

  -- Deduct seed from inventory
  UPDATE public.inventory
  SET quantity = quantity - 1
  WHERE player_id = v_player_id AND item_id = v_seed_item_id;

  -- Plant the crop
  UPDATE public.farm_plots
  SET crop_id = p_crop_id,
      planted_at = now(),
      ready_at = now() + (v_grow_minutes * interval '1 minute')
  WHERE player_id = v_player_id
    AND plot_index = p_plot_index;

  -- Check achievements
  PERFORM public.check_achievements('plant_count', 1);
  
  -- Update quest progress
  PERFORM public.update_quest_progress('plant', NULL, 1);
  
  -- Auto-contribute to coven tasks
  PERFORM public.auto_contribute_coven_tasks('plant', 1);
END;
$$;

COMMENT ON FUNCTION public.plant_plot(integer, integer) IS 'Plant a seed on a farm plot. Consumes seed item (100-110) from inventory.';

