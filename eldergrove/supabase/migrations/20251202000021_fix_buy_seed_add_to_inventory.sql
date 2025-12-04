-- Fix buy_seed function to actually add seeds to inventory

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

  -- Deduct crystals
  UPDATE public.profiles
  SET crystals = crystals - v_seed_price
  WHERE id = v_player_id;

  -- Add seed to inventory (using crop's item_id - seeds and crops use the same item_id)
  INSERT INTO public.inventory (player_id, item_id, quantity)
  VALUES (v_player_id, v_crop_item_id, 1)
  ON CONFLICT (player_id, item_id) DO UPDATE SET
    quantity = inventory.quantity + 1;

  -- Get updated crystals
  SELECT crystals INTO v_new_crystals
  FROM public.profiles
  WHERE id = v_player_id;

  RETURN v_new_crystals;
END;
$$;

COMMENT ON FUNCTION public.buy_seed(integer) IS 'Purchase seed for a crop using crystals. Adds 1 seed (using crop item_id) to inventory and returns new crystal balance.';

