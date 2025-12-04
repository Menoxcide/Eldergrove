-- Fix magic_mushroom and enchanted_flower item_id mapping in start_factory_production
-- The crops table maps these to item_ids 13 and 14, but the frontend/itemUtils uses 9 and 10
-- This migration ensures the function uses the correct item_ids that match the frontend

CREATE OR REPLACE FUNCTION public.start_factory_production(
  p_factory_type text,
  p_recipe_name text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_recipe record;
  v_slot_count integer;
  v_next_slot integer;
  v_input_key text;
  v_input_qty_str text;
  v_input_qty integer;
  v_current_qty integer;
  v_item_id integer;
BEGIN
  -- Validate factory exists
  IF NOT EXISTS (
    SELECT 1 FROM public.factories 
    WHERE player_id = v_player_id 
    AND factory_type = p_factory_type
  ) THEN
    RAISE EXCEPTION 'Factory "%" does not exist for this player', p_factory_type;
  END IF;

  -- Get recipe details
  SELECT * INTO v_recipe 
  FROM public.recipes 
  WHERE name = p_recipe_name;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Recipe "%" does not exist', p_recipe_name;
  END IF;

  -- Check available slots (max 2)
  SELECT count(*) INTO v_slot_count
  FROM public.factory_queue
  WHERE player_id = v_player_id
  AND factory_type = p_factory_type;

  IF v_slot_count >= 2 THEN
    RAISE EXCEPTION 'Factory "%" queue is full (max 2 slots)', p_factory_type;
  END IF;

  v_next_slot := v_slot_count + 1;

  -- Validate and deduct input resources from inventory
  -- Map resource names to item_ids matching crops table (harvested items use these IDs)
  FOR v_input_key, v_input_qty_str IN
    SELECT key, value FROM jsonb_each_text(v_recipe.input)
  LOOP
    v_input_qty := v_input_qty_str::integer;

    -- Map input resource name to item_id
    -- These match the item_ids in the crops table (harvested crops use these IDs)
    CASE v_input_key
      WHEN 'wheat' THEN v_item_id := 1;
      WHEN 'carrot' THEN v_item_id := 2;
      WHEN 'potato' THEN v_item_id := 3;
      WHEN 'tomato' THEN v_item_id := 4;
      WHEN 'corn' THEN v_item_id := 5;
      WHEN 'pumpkin' THEN v_item_id := 6;
      WHEN 'berry' THEN v_item_id := 11;
      WHEN 'herbs' THEN v_item_id := 12;
      WHEN 'magic_mushroom' THEN v_item_id := 13;
      WHEN 'enchanted_flower' THEN v_item_id := 14;
      WHEN 'bread' THEN v_item_id := 8;
      ELSE RAISE EXCEPTION 'Unsupported input resource "%"', v_input_key;
    END CASE;

    v_current_qty := COALESCE(
      (SELECT quantity FROM public.inventory WHERE player_id = v_player_id AND item_id = v_item_id),
      0
    );

    IF v_current_qty < v_input_qty THEN
      RAISE EXCEPTION 'Insufficient "%": required %, available %', v_input_key, v_input_qty, v_current_qty;
    END IF;

    -- Deduct from inventory
    UPDATE public.inventory SET
      quantity = quantity - v_input_qty
    WHERE player_id = v_player_id AND item_id = v_item_id;
  END LOOP;

  -- Insert into queue
  INSERT INTO public.factory_queue (
    player_id,
    factory_type,
    recipe_id,
    slot,
    started_at,
    finishes_at
  ) VALUES (
    v_player_id,
    p_factory_type,
    v_recipe.id,
    v_next_slot,
    now(),
    now() + (v_recipe.minutes * interval '1 minute')
  );
END;
$$;

COMMENT ON FUNCTION public.start_factory_production(text, text) IS 'Start factory production: deducts input resources from inventory, adds to queue (max 2 slots). Uses item_ids matching crops table (berry=11, herbs=12, magic_mushroom=13, enchanted_flower=14).';

