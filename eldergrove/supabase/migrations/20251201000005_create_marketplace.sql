-- Create marketplace system for selling items for crystals

-- Create marketplace table with sell prices
CREATE TABLE IF NOT EXISTS public.marketplace (
  item_id integer PRIMARY KEY,
  sell_price_crystals integer NOT NULL DEFAULT 1,
  available boolean NOT NULL DEFAULT true
);

-- Enable RLS
ALTER TABLE public.marketplace ENABLE ROW LEVEL SECURITY;

-- Policy: Everyone can view marketplace prices
CREATE POLICY "Anyone can view marketplace" ON public.marketplace
  FOR SELECT TO authenticated
  USING (true);

-- Seed marketplace with sell prices for all items
-- Prices are typically lower than seed costs to create economy
INSERT INTO public.marketplace (item_id, sell_price_crystals, available) VALUES
(1, 3, true),   -- Wheat: 3 crystals per unit
(2, 8, true),  -- Carrot: 8 crystals per unit
(3, 5, true),   -- Potato: 5 crystals per unit
(4, 7, true),   -- Tomato: 7 crystals per unit
(5, 10, true),  -- Corn: 10 crystals per unit
(6, 18, true),  -- Pumpkin: 18 crystals per unit
(8, 12, true),  -- Bread: 12 crystals per unit
(11, 4, true),  -- Berry: 4 crystals per unit
(12, 6, true),  -- Herbs: 6 crystals per unit
(13, 20, true), -- Magic Mushroom: 20 crystals per unit
(14, 25, true)  -- Enchanted Flower: 25 crystals per unit
ON CONFLICT (item_id) DO UPDATE SET
  sell_price_crystals = EXCLUDED.sell_price_crystals,
  available = EXCLUDED.available;

-- Create RPC function to sell items
CREATE OR REPLACE FUNCTION public.sell_item(p_item_id integer, p_quantity integer)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_sell_price integer;
  v_current_qty bigint;
  v_total_crystals bigint;
  v_new_crystals bigint;
BEGIN
  -- Validate quantity
  IF p_quantity <= 0 THEN
    RAISE EXCEPTION 'Quantity must be greater than 0';
  END IF;

  -- Get sell price
  SELECT sell_price_crystals INTO v_sell_price
  FROM public.marketplace
  WHERE item_id = p_item_id AND available = true;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Item % is not available for sale in the marketplace', p_item_id;
  END IF;

  -- Get current inventory quantity
  SELECT COALESCE(quantity, 0) INTO v_current_qty
  FROM public.inventory
  WHERE player_id = v_player_id AND item_id = p_item_id;

  IF v_current_qty < p_quantity THEN
    RAISE EXCEPTION 'Insufficient quantity: required %, available %', p_quantity, v_current_qty;
  END IF;

  -- Calculate total crystals to award
  v_total_crystals := v_sell_price * p_quantity;

  -- Deduct items from inventory
  UPDATE public.inventory
  SET quantity = quantity - p_quantity
  WHERE player_id = v_player_id AND item_id = p_item_id;

  -- Award crystals to player
  UPDATE public.profiles
  SET crystals = crystals + v_total_crystals
  WHERE id = v_player_id;

  -- Get updated crystals
  SELECT crystals INTO v_new_crystals
  FROM public.profiles
  WHERE id = v_player_id;

  -- Update quest progress
  PERFORM public.update_quest_progress(NULL, 'sell', p_quantity);

  -- Return result
  RETURN jsonb_build_object(
    'success', true,
    'crystals_awarded', v_total_crystals,
    'new_crystal_balance', v_new_crystals,
    'items_sold', p_quantity
  );
END;
$$;

COMMENT ON FUNCTION public.sell_item(integer, integer) IS 'Sell items from inventory for crystals. Returns success status, crystals awarded, and new balance.';

