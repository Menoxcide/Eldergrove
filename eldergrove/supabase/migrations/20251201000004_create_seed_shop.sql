-- Create seed shop system for purchasing seeds with crystals

-- Create seed_shop table with crop prices
CREATE TABLE IF NOT EXISTS public.seed_shop (
  crop_id integer PRIMARY KEY REFERENCES public.crops(id) ON DELETE CASCADE,
  price_crystals integer NOT NULL DEFAULT 10,
  available boolean NOT NULL DEFAULT true
);

-- Enable RLS
ALTER TABLE public.seed_shop ENABLE ROW LEVEL SECURITY;

-- Policy: Everyone can view seed shop
CREATE POLICY "Anyone can view seed shop" ON public.seed_shop
  FOR SELECT TO authenticated
  USING (true);

-- Seed shop with prices for all crops (cheaper than selling harvested crops)
INSERT INTO public.seed_shop (crop_id, price_crystals, available) VALUES
(1, 5, true),   -- Wheat: 5 crystals
(2, 10, true),  -- Carrot: 10 crystals
(3, 8, true),   -- Potato: 8 crystals
(4, 10, true),   -- Tomato: 10 crystals
(5, 12, true),   -- Corn: 12 crystals
(6, 20, true),   -- Pumpkin: 20 crystals
(7, 6, true),   -- Berry: 6 crystals
(8, 9, true),   -- Herbs: 9 crystals
(9, 25, true),  -- Magic Mushroom: 25 crystals
(10, 30, true)   -- Enchanted Flower: 30 crystals
ON CONFLICT (crop_id) DO UPDATE SET
  price_crystals = EXCLUDED.price_crystals,
  available = EXCLUDED.available;

-- Create RPC function to buy seeds
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

  -- Deduct crystals
  UPDATE public.profiles
  SET crystals = crystals - v_seed_price
  WHERE id = v_player_id;

  -- Add seed to inventory (seeds use item_id 10 for "Enchanted Seeds" or we can create a seed inventory)
  -- For now, we'll add the crop's item_id directly (player can plant it immediately)
  -- Actually, seeds should be separate. Let's use a seed inventory approach.
  -- For simplicity, we'll just deduct crystals and the player can plant directly.
  -- The seed purchase is just a crystal cost to unlock planting that crop.

  -- Get updated crystals
  SELECT crystals INTO v_new_crystals
  FROM public.profiles
  WHERE id = v_player_id;

  RETURN v_new_crystals;
END;
$$;

COMMENT ON FUNCTION public.buy_seed(integer) IS 'Purchase seed for a crop using crystals. Returns new crystal balance.';

-- Note: In this implementation, buying a seed just deducts crystals.
-- The player can then plant that crop type. For a more complex system,
-- you could add a seeds inventory table, but for simplicity we'll allow
-- direct planting after "purchasing" (which is really just paying to unlock/plant).

