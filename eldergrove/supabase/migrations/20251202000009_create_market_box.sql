-- Create market box (player trading) system

-- Create market_listings table
CREATE TABLE IF NOT EXISTS public.market_listings (
  id serial PRIMARY KEY,
  seller_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  item_id integer NOT NULL,
  quantity integer NOT NULL CHECK (quantity > 0),
  price_crystals integer NOT NULL CHECK (price_crystals > 0),
  created_at timestamptz DEFAULT now(),
  expires_at timestamptz NOT NULL,
  purchased_at timestamptz,
  buyer_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL
);

-- Enable RLS
ALTER TABLE public.market_listings ENABLE ROW LEVEL SECURITY;

-- Policy: Anyone can view active listings
CREATE POLICY "Anyone can view active listings" ON public.market_listings
  FOR SELECT TO authenticated
  USING (purchased_at IS NULL AND expires_at > now());

-- Policy: Players can view their own listings
CREATE POLICY "Players can view own listings" ON public.market_listings
  FOR SELECT TO authenticated
  USING (auth.uid() = seller_id);

-- Policy: Players can create listings
CREATE POLICY "Players can create listings" ON public.market_listings
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = seller_id);

-- Policy: Players can update own listings
CREATE POLICY "Players can update own listings" ON public.market_listings
  FOR UPDATE TO authenticated
  USING (auth.uid() = seller_id)
  WITH CHECK (auth.uid() = seller_id);

-- Policy: Players can delete own listings
CREATE POLICY "Players can delete own listings" ON public.market_listings
  FOR DELETE TO authenticated
  USING (auth.uid() = seller_id);

-- Enable realtime
ALTER PUBLICATION supabase_realtime ADD TABLE public.market_listings;

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_market_listings_seller ON public.market_listings(seller_id);
CREATE INDEX IF NOT EXISTS idx_market_listings_active ON public.market_listings(purchased_at, expires_at) WHERE purchased_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_market_listings_item ON public.market_listings(item_id);

-- Function to create a listing
CREATE OR REPLACE FUNCTION public.create_listing(
  p_item_id integer,
  p_quantity integer,
  p_price_crystals integer,
  p_expires_hours integer DEFAULT 24
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_current_qty bigint;
  v_listing_id integer;
BEGIN
  IF p_quantity <= 0 THEN
    RAISE EXCEPTION 'Quantity must be positive';
  END IF;

  IF p_price_crystals <= 0 THEN
    RAISE EXCEPTION 'Price must be positive';
  END IF;

  -- Check inventory
  SELECT COALESCE(quantity, 0) INTO v_current_qty
  FROM public.inventory
  WHERE player_id = v_player_id AND item_id = p_item_id;

  IF v_current_qty < p_quantity THEN
    RAISE EXCEPTION 'Insufficient item %: required %, available %', p_item_id, p_quantity, v_current_qty;
  END IF;

  -- Deduct from inventory
  UPDATE public.inventory
  SET quantity = quantity - p_quantity
  WHERE player_id = v_player_id AND item_id = p_item_id;

  -- Create listing
  INSERT INTO public.market_listings (
    seller_id,
    item_id,
    quantity,
    price_crystals,
    expires_at
  )
  VALUES (
    v_player_id,
    p_item_id,
    p_quantity,
    p_price_crystals,
    now() + (p_expires_hours || ' hours')::interval
  )
  RETURNING id INTO v_listing_id;

  RETURN v_listing_id;
END;
$$;

COMMENT ON FUNCTION public.create_listing(integer, integer, integer, integer) IS 'Create a market listing: deducts items from inventory, creates listing';

-- Function to purchase a listing
CREATE OR REPLACE FUNCTION public.purchase_listing(p_listing_id integer)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_buyer_id uuid := auth.uid();
  v_listing record;
  v_total_cost integer;
  v_buyer_crystals bigint;
  v_seller_crystals bigint;
  v_commission integer;
  v_seller_profit integer;
  v_result jsonb;
BEGIN
  -- Get listing
  SELECT * INTO v_listing
  FROM public.market_listings
  WHERE id = p_listing_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Listing % not found', p_listing_id;
  END IF;

  IF v_listing.purchased_at IS NOT NULL THEN
    RAISE EXCEPTION 'Listing % already purchased', p_listing_id;
  END IF;

  IF v_listing.expires_at < now() THEN
    RAISE EXCEPTION 'Listing % has expired', p_listing_id;
  END IF;

  IF v_listing.seller_id = v_buyer_id THEN
    RAISE EXCEPTION 'Cannot purchase your own listing';
  END IF;

  v_total_cost := v_listing.price_crystals;

  -- Check buyer crystals
  SELECT crystals INTO v_buyer_crystals
  FROM public.profiles
  WHERE id = v_buyer_id;

  IF v_buyer_crystals < v_total_cost THEN
    RAISE EXCEPTION 'Insufficient crystals: required %, available %', v_total_cost, v_buyer_crystals;
  END IF;

  -- Calculate commission (5%)
  v_commission := FLOOR(v_total_cost * 0.05);
  v_seller_profit := v_total_cost - v_commission;

  -- Deduct crystals from buyer
  UPDATE public.profiles
  SET crystals = crystals - v_total_cost
  WHERE id = v_buyer_id;

  -- Add profit to seller
  UPDATE public.profiles
  SET crystals = crystals + v_seller_profit
  WHERE id = v_listing.seller_id;

  -- Add items to buyer inventory
  INSERT INTO public.inventory (player_id, item_id, quantity)
  VALUES (v_buyer_id, v_listing.item_id, v_listing.quantity::bigint)
  ON CONFLICT (player_id, item_id) DO UPDATE SET
    quantity = inventory.quantity + excluded.quantity;

  -- Mark listing as purchased
  UPDATE public.market_listings
  SET purchased_at = now(),
      buyer_id = v_buyer_id
  WHERE id = p_listing_id;

  -- Check achievements
  PERFORM public.check_achievements('trade_count', 1);

  -- Return result
  SELECT jsonb_build_object(
    'success', true,
    'item_id', v_listing.item_id,
    'quantity', v_listing.quantity,
    'cost', v_total_cost
  ) INTO v_result;

  RETURN v_result;
END;
$$;

COMMENT ON FUNCTION public.purchase_listing(integer) IS 'Purchase a market listing: transfers crystals and items, applies 5% commission';

-- Function to cancel a listing
CREATE OR REPLACE FUNCTION public.cancel_listing(p_listing_id integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_listing record;
BEGIN
  -- Get listing
  SELECT * INTO v_listing
  FROM public.market_listings
  WHERE id = p_listing_id AND seller_id = v_player_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Listing % not found or does not belong to you', p_listing_id;
  END IF;

  IF v_listing.purchased_at IS NOT NULL THEN
    RAISE EXCEPTION 'Listing % already purchased', p_listing_id;
  END IF;

  -- Return items to inventory
  INSERT INTO public.inventory (player_id, item_id, quantity)
  VALUES (v_player_id, v_listing.item_id, v_listing.quantity::bigint)
  ON CONFLICT (player_id, item_id) DO UPDATE SET
    quantity = inventory.quantity + excluded.quantity;

  -- Delete listing
  DELETE FROM public.market_listings WHERE id = p_listing_id;
END;
$$;

COMMENT ON FUNCTION public.cancel_listing(integer) IS 'Cancel a listing: returns items to seller inventory';

