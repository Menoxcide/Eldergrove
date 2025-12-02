-- Create friend/neighbor system for social features

-- Create friends table
CREATE TABLE IF NOT EXISTS public.friends (
  id serial PRIMARY KEY,
  player_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  friend_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  status text NOT NULL CHECK (status IN ('pending', 'accepted', 'blocked')),
  requested_by uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  created_at timestamptz DEFAULT now(),
  accepted_at timestamptz,
  UNIQUE(player_id, friend_id)
);

-- Create friend_help table (track help given/received)
CREATE TABLE IF NOT EXISTS public.friend_help (
  id serial PRIMARY KEY,
  helper_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  helped_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  help_type text NOT NULL CHECK (help_type IN ('speed_production', 'fill_order', 'water_crops')),
  target_id integer, -- factory_id, order_id, or plot_index depending on help_type
  created_at timestamptz DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.friends ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.friend_help ENABLE ROW LEVEL SECURITY;

-- Policy: Players can view their own friendships
CREATE POLICY "Players can view own friendships" ON public.friends
  FOR SELECT TO authenticated
  USING (auth.uid() = player_id OR auth.uid() = friend_id);

CREATE POLICY "Players can insert own friend requests" ON public.friends
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = player_id OR auth.uid() = friend_id);

CREATE POLICY "Players can update own friendships" ON public.friends
  FOR UPDATE TO authenticated
  USING (auth.uid() = player_id OR auth.uid() = friend_id)
  WITH CHECK (auth.uid() = player_id OR auth.uid() = friend_id);

CREATE POLICY "Players can delete own friendships" ON public.friends
  FOR DELETE TO authenticated
  USING (auth.uid() = player_id OR auth.uid() = friend_id);

-- Policy: Players can view help they gave/received
CREATE POLICY "Players can view own help" ON public.friend_help
  FOR SELECT TO authenticated
  USING (auth.uid() = helper_id OR auth.uid() = helped_id);

CREATE POLICY "Players can insert own help" ON public.friend_help
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = helper_id);

-- Enable realtime
ALTER PUBLICATION supabase_realtime ADD TABLE public.friends;
ALTER PUBLICATION supabase_realtime ADD TABLE public.friend_help;

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_friends_player ON public.friends(player_id);
CREATE INDEX IF NOT EXISTS idx_friends_friend ON public.friends(friend_id);
CREATE INDEX IF NOT EXISTS idx_friends_status ON public.friends(status);
CREATE INDEX IF NOT EXISTS idx_friend_help_helper ON public.friend_help(helper_id);
CREATE INDEX IF NOT EXISTS idx_friend_help_helped ON public.friend_help(helped_id);

-- Function to send friend request
CREATE OR REPLACE FUNCTION public.send_friend_request(p_friend_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
BEGIN
  IF v_player_id = p_friend_id THEN
    RAISE EXCEPTION 'Cannot send friend request to yourself';
  END IF;

  -- Check if already friends or request exists
  IF EXISTS (
    SELECT 1 FROM public.friends
    WHERE (player_id = v_player_id AND friend_id = p_friend_id)
       OR (player_id = p_friend_id AND friend_id = v_player_id)
  ) THEN
    RAISE EXCEPTION 'Friend request already exists or already friends';
  END IF;

  -- Create friend request (bidirectional)
  INSERT INTO public.friends (player_id, friend_id, status, requested_by)
  VALUES (v_player_id, p_friend_id, 'pending', v_player_id),
         (p_friend_id, v_player_id, 'pending', v_player_id);
END;
$$;

COMMENT ON FUNCTION public.send_friend_request(uuid) IS 'Send a friend request to another player';

-- Function to accept friend request
CREATE OR REPLACE FUNCTION public.accept_friend_request(p_friend_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
BEGIN
  -- Check if request exists
  IF NOT EXISTS (
    SELECT 1 FROM public.friends
    WHERE player_id = v_player_id
      AND friend_id = p_friend_id
      AND status = 'pending'
      AND requested_by != v_player_id
  ) THEN
    RAISE EXCEPTION 'No pending friend request from %', p_friend_id;
  END IF;

  -- Accept both directions
  UPDATE public.friends
  SET status = 'accepted',
      accepted_at = now()
  WHERE (player_id = v_player_id AND friend_id = p_friend_id)
     OR (player_id = p_friend_id AND friend_id = v_player_id);
END;
$$;

COMMENT ON FUNCTION public.accept_friend_request(uuid) IS 'Accept a friend request';

-- Function to remove friend
CREATE OR REPLACE FUNCTION public.remove_friend(p_friend_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
BEGIN
  DELETE FROM public.friends
  WHERE (player_id = v_player_id AND friend_id = p_friend_id)
     OR (player_id = p_friend_id AND friend_id = v_player_id);
END;
$$;

COMMENT ON FUNCTION public.remove_friend(uuid) IS 'Remove a friend (both directions)';

-- Function to help friend speed up production
CREATE OR REPLACE FUNCTION public.help_friend_speed_production(
  p_friend_id uuid,
  p_factory_type text,
  p_slot integer
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_queue_item record;
  v_speedup_minutes integer := 30; -- Reduce by 30 minutes
BEGIN
  -- Check if friends
  IF NOT EXISTS (
    SELECT 1 FROM public.friends
    WHERE ((player_id = v_player_id AND friend_id = p_friend_id)
        OR (player_id = p_friend_id AND friend_id = v_player_id))
      AND status = 'accepted'
  ) THEN
    RAISE EXCEPTION 'You are not friends with this player';
  END IF;

  -- Get queue item
  SELECT * INTO v_queue_item
  FROM public.factory_queue
  WHERE player_id = p_friend_id
    AND factory_type = p_factory_type
    AND slot = p_slot;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Production slot not found';
  END IF;

  -- Speed up production
  UPDATE public.factory_queue
  SET finishes_at = GREATEST(finishes_at - (v_speedup_minutes || ' minutes')::interval, now())
  WHERE player_id = p_friend_id
    AND factory_type = p_factory_type
    AND slot = p_slot;

  -- Record help
  INSERT INTO public.friend_help (helper_id, helped_id, help_type, target_id)
  VALUES (v_player_id, p_friend_id, 'speed_production', p_slot);

  -- Check achievements
  PERFORM public.check_achievements('help_count', 1);
END;
$$;

COMMENT ON FUNCTION public.help_friend_speed_production(uuid, text, integer) IS 'Help a friend by speeding up their factory production';

-- Function to help friend fill order
CREATE OR REPLACE FUNCTION public.help_friend_fill_order(
  p_friend_id uuid,
  p_order_id integer
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_order record;
  v_requirements jsonb;
  v_key text;
  v_value text;
  v_item_id integer;
  v_required_qty integer;
  v_current_qty bigint;
BEGIN
  -- Check if friends
  IF NOT EXISTS (
    SELECT 1 FROM public.friends
    WHERE ((player_id = v_player_id AND friend_id = p_friend_id)
        OR (player_id = p_friend_id AND friend_id = v_player_id))
      AND status = 'accepted'
  ) THEN
    RAISE EXCEPTION 'You are not friends with this player';
  END IF;

  -- Get order
  SELECT * INTO v_order
  FROM public.skyport_orders
  WHERE id = p_order_id AND player_id = p_friend_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found';
  END IF;

  IF v_order.completed_at IS NOT NULL THEN
    RAISE EXCEPTION 'Order already completed';
  END IF;

  v_requirements := v_order.requirements;

  -- Check and deduct items from helper's inventory
  FOR v_key, v_value IN SELECT key, value FROM jsonb_each_text(v_requirements) LOOP
    v_item_id := v_key::integer;
    v_required_qty := v_value::integer;

    SELECT COALESCE(quantity, 0) INTO v_current_qty
    FROM public.inventory
    WHERE player_id = v_player_id AND item_id = v_item_id;

    IF v_current_qty < v_required_qty THEN
      RAISE EXCEPTION 'Insufficient item %: required %, available %', v_item_id, v_required_qty, v_current_qty;
    END IF;

    -- Deduct from helper's inventory
    UPDATE public.inventory
    SET quantity = quantity - v_required_qty
    WHERE player_id = v_player_id AND item_id = v_item_id;
  END LOOP;

  -- Mark order as completed (friend gets rewards)
  UPDATE public.skyport_orders
  SET completed_at = now()
  WHERE id = p_order_id;

  -- Award rewards to friend
  IF v_order.rewards ? 'crystals' THEN
    UPDATE public.profiles
    SET crystals = crystals + (v_order.rewards->>'crystals')::integer,
        xp = xp + COALESCE((v_order.rewards->>'xp')::integer, 0)
    WHERE id = p_friend_id;
  END IF;

  -- Record help
  INSERT INTO public.friend_help (helper_id, helped_id, help_type, target_id)
  VALUES (v_player_id, p_friend_id, 'fill_order', p_order_id);

  -- Check achievements
  PERFORM public.check_achievements('help_count', 1);
END;
$$;

COMMENT ON FUNCTION public.help_friend_fill_order(uuid, integer) IS 'Help a friend by filling their skyport order';

-- Function to get friend's town data (read-only)
CREATE OR REPLACE FUNCTION public.visit_friend_town(p_friend_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_buildings jsonb;
  v_result jsonb;
BEGIN
  -- Check if friends
  IF NOT EXISTS (
    SELECT 1 FROM public.friends
    WHERE ((player_id = v_player_id AND friend_id = p_friend_id)
        OR (player_id = p_friend_id AND friend_id = v_player_id))
      AND status = 'accepted'
  ) THEN
    RAISE EXCEPTION 'You are not friends with this player';
  END IF;

  -- Get buildings (read-only)
  SELECT jsonb_agg(row_to_json(b))
  INTO v_buildings
  FROM (
    SELECT building_type, grid_x, grid_y, level
    FROM public.buildings
    WHERE player_id = p_friend_id
  ) b;

  -- Return read-only town data
  SELECT jsonb_build_object(
    'buildings', COALESCE(v_buildings, '[]'::jsonb),
    'friend_id', p_friend_id
  ) INTO v_result;

  RETURN v_result;
END;
$$;

COMMENT ON FUNCTION public.visit_friend_town(uuid) IS 'Visit a friend''s town (read-only view)';

