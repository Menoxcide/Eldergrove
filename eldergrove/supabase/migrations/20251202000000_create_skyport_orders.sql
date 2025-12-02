-- Create skyport orders system for transportation orders

-- Create skyport_orders table
CREATE TABLE IF NOT EXISTS public.skyport_orders (
  id serial PRIMARY KEY,
  player_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  order_type text NOT NULL CHECK (order_type IN ('quick', 'standard', 'premium')),
  requirements jsonb NOT NULL, -- {item_id: quantity} format
  rewards jsonb NOT NULL, -- {crystals: amount, xp: amount, items: {item_id: quantity}}
  expires_at timestamptz NOT NULL,
  completed_at timestamptz,
  created_at timestamptz DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.skyport_orders ENABLE ROW LEVEL SECURITY;

-- Policy: Players can view and manage their own orders
CREATE POLICY "Players can view own orders" ON public.skyport_orders
  FOR SELECT TO authenticated
  USING (auth.uid() = player_id);

CREATE POLICY "Players can insert own orders" ON public.skyport_orders
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = player_id);

CREATE POLICY "Players can update own orders" ON public.skyport_orders
  FOR UPDATE TO authenticated
  USING (auth.uid() = player_id)
  WITH CHECK (auth.uid() = player_id);

-- Enable realtime
ALTER PUBLICATION supabase_realtime ADD TABLE public.skyport_orders;

-- Create index for faster queries
CREATE INDEX IF NOT EXISTS idx_skyport_orders_player_active ON public.skyport_orders(player_id, completed_at) WHERE completed_at IS NULL;

-- Function to generate new orders for a player
CREATE OR REPLACE FUNCTION public.generate_skyport_orders(p_player_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_order_count integer;
  v_order_type text;
  v_requirements jsonb;
  v_rewards jsonb;
  v_expires_minutes integer;
  v_i integer;
BEGIN
  -- Count active orders
  SELECT count(*) INTO v_order_count
  FROM public.skyport_orders
  WHERE player_id = p_player_id AND completed_at IS NULL;

  -- Generate orders up to max (3 quick, 2 standard, 1 premium = 6 total)
  -- Quick orders (helicopter) - 3 slots, 30 min expiry
  FOR v_i IN 1..3 LOOP
    IF v_order_count < 6 THEN
      v_order_type := 'quick';
      v_expires_minutes := 30;
      
      -- Generate random requirements (1-2 items, small quantities)
      v_requirements := jsonb_build_object(
        floor(random() * 10 + 1)::text, floor(random() * 3 + 1)::text
      );
      
      -- Generate rewards (small crystals, XP)
      v_rewards := jsonb_build_object(
        'crystals', floor(random() * 20 + 10),
        'xp', floor(random() * 50 + 25)
      );
      
      INSERT INTO public.skyport_orders (player_id, order_type, requirements, rewards, expires_at)
      VALUES (p_player_id, v_order_type, v_requirements, v_rewards, now() + (v_expires_minutes || ' minutes')::interval);
      
      v_order_count := v_order_count + 1;
    END IF;
  END LOOP;
  
  -- Standard orders (skyport) - 2 slots, 2 hour expiry
  FOR v_i IN 1..2 LOOP
    IF v_order_count < 6 THEN
      v_order_type := 'standard';
      v_expires_minutes := 120;
      
      -- Generate random requirements (2-3 items, medium quantities)
      v_requirements := jsonb_build_object(
        floor(random() * 10 + 1)::text, floor(random() * 5 + 2)::text,
        floor(random() * 10 + 1)::text, floor(random() * 5 + 2)::text
      );
      
      -- Generate rewards (medium crystals, XP)
      v_rewards := jsonb_build_object(
        'crystals', floor(random() * 50 + 30),
        'xp', floor(random() * 100 + 50)
      );
      
      INSERT INTO public.skyport_orders (player_id, order_type, requirements, rewards, expires_at)
      VALUES (p_player_id, v_order_type, v_requirements, v_rewards, now() + (v_expires_minutes || ' minutes')::interval);
      
      v_order_count := v_order_count + 1;
    END IF;
  END LOOP;
  
  -- Premium orders (spirit whale) - 1 slot, 4 hour expiry
  IF v_order_count < 6 THEN
    v_order_type := 'premium';
    v_expires_minutes := 240;
    
    -- Generate random requirements (3-4 items, larger quantities)
    v_requirements := jsonb_build_object(
      floor(random() * 10 + 1)::text, floor(random() * 8 + 5)::text,
      floor(random() * 10 + 1)::text, floor(random() * 8 + 5)::text,
      floor(random() * 10 + 1)::text, floor(random() * 8 + 5)::text
    );
    
    -- Generate rewards (large crystals, XP, bonus items)
    v_rewards := jsonb_build_object(
      'crystals', floor(random() * 100 + 75),
      'xp', floor(random() * 200 + 150),
      'items', jsonb_build_object('3', '10') -- Bonus crystals item
    );
    
    INSERT INTO public.skyport_orders (player_id, order_type, requirements, rewards, expires_at)
    VALUES (p_player_id, v_order_type, v_requirements, v_rewards, now() + (v_expires_minutes || ' minutes')::interval);
  END IF;
END;
$$;

COMMENT ON FUNCTION public.generate_skyport_orders(uuid) IS 'Generate new skyport orders for a player (max 6 active orders)';

-- Function to fulfill an order
CREATE OR REPLACE FUNCTION public.fulfill_skyport_order(p_order_id integer)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_order record;
  v_requirements jsonb;
  v_rewards jsonb;
  v_item_id integer;
  v_required_qty integer;
  v_current_qty bigint;
  v_key text;
  v_value text;
  v_result jsonb;
BEGIN
  -- Get order
  SELECT * INTO v_order
  FROM public.skyport_orders
  WHERE id = p_order_id AND player_id = v_player_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order % not found or does not belong to this player', p_order_id;
  END IF;

  IF v_order.completed_at IS NOT NULL THEN
    RAISE EXCEPTION 'Order % has already been completed', p_order_id;
  END IF;

  IF v_order.expires_at < now() THEN
    RAISE EXCEPTION 'Order % has expired', p_order_id;
  END IF;

  v_requirements := v_order.requirements;
  v_rewards := v_order.rewards;

  -- Check and deduct required items
  FOR v_key, v_value IN SELECT key, value FROM jsonb_each_text(v_requirements) LOOP
    v_item_id := v_key::integer;
    v_required_qty := v_value::integer;

    SELECT COALESCE(quantity, 0) INTO v_current_qty
    FROM public.inventory
    WHERE player_id = v_player_id AND item_id = v_item_id;

    IF v_current_qty < v_required_qty THEN
      RAISE EXCEPTION 'Insufficient item %: required %, available %', v_item_id, v_required_qty, v_current_qty;
    END IF;

    -- Deduct from inventory
    UPDATE public.inventory
    SET quantity = quantity - v_required_qty
    WHERE player_id = v_player_id AND item_id = v_item_id;
  END LOOP;

  -- Award rewards
  -- Crystals
  IF v_rewards ? 'crystals' THEN
    UPDATE public.profiles
    SET crystals = crystals + (v_rewards->>'crystals')::integer,
        xp = xp + COALESCE((v_rewards->>'xp')::integer, 0)
    WHERE id = v_player_id;
  END IF;

  -- XP (if separate from crystals update)
  IF v_rewards ? 'xp' AND NOT (v_rewards ? 'crystals') THEN
    UPDATE public.profiles
    SET xp = xp + (v_rewards->>'xp')::integer
    WHERE id = v_player_id;
  END IF;

  -- Items
  IF v_rewards ? 'items' THEN
    FOR v_key, v_value IN SELECT key, value FROM jsonb_each_text(v_rewards->'items') LOOP
      v_item_id := v_key::integer;
      v_required_qty := v_value::integer;

      INSERT INTO public.inventory (player_id, item_id, quantity)
      VALUES (v_player_id, v_item_id, v_required_qty::bigint)
      ON CONFLICT (player_id, item_id) DO UPDATE SET
        quantity = inventory.quantity + excluded.quantity;
    END LOOP;
  END IF;

  -- Mark order as completed
  UPDATE public.skyport_orders
  SET completed_at = now()
  WHERE id = p_order_id;

  -- Update quest progress
  PERFORM public.update_quest_progress(NULL, 'order', 1);

  -- Return result
  SELECT jsonb_build_object(
    'success', true,
    'crystals_awarded', COALESCE((v_rewards->>'crystals')::integer, 0),
    'xp_awarded', COALESCE((v_rewards->>'xp')::integer, 0)
  ) INTO v_result;

  RETURN v_result;
END;
$$;

COMMENT ON FUNCTION public.fulfill_skyport_order(integer) IS 'Fulfill a skyport order: deduct requirements from inventory, award rewards, mark complete';

