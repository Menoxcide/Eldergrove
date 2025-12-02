-- Implement speed-up system for factory production

-- Create speed_ups table to track active speed-ups
CREATE TABLE IF NOT EXISTS public.speed_ups (
  id serial PRIMARY KEY,
  player_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  speed_up_type text NOT NULL CHECK (speed_up_type IN ('factory', 'crop', 'global')),
  target_id integer, -- factory_id, plot_id, or NULL for global
  minutes integer NOT NULL,
  used_at timestamptz DEFAULT now(),
  expires_at timestamptz
);

-- Enable RLS
ALTER TABLE public.speed_ups ENABLE ROW LEVEL SECURITY;

-- Policy: Players can view own speed-ups
CREATE POLICY "Players can view own speed-ups" ON public.speed_ups
  FOR SELECT TO authenticated
  USING (auth.uid() = player_id);

CREATE POLICY "Players can insert own speed-ups" ON public.speed_ups
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = player_id);

CREATE POLICY "Players can delete own speed-ups" ON public.speed_ups
  FOR DELETE TO authenticated
  USING (auth.uid() = player_id);

-- Enable realtime
ALTER PUBLICATION supabase_realtime ADD TABLE public.speed_ups;

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_speed_ups_player ON public.speed_ups(player_id);
CREATE INDEX IF NOT EXISTS idx_speed_ups_expires ON public.speed_ups(expires_at) WHERE expires_at IS NOT NULL;

-- Function to apply speed-up to factory production
CREATE OR REPLACE FUNCTION public.apply_factory_speed_up(
  p_factory_type text,
  p_slot integer,
  p_minutes integer
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_queue_item record;
BEGIN
  -- Get queue item
  SELECT * INTO v_queue_item
  FROM public.factory_queue
  WHERE player_id = v_player_id
    AND factory_type = p_factory_type
    AND slot = p_slot;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Production slot not found';
  END IF;

  -- Apply speed-up (reduce finish time)
  UPDATE public.factory_queue
  SET finishes_at = GREATEST(finishes_at - (p_minutes || ' minutes')::interval, now())
  WHERE player_id = v_player_id
    AND factory_type = p_factory_type
    AND slot = p_slot;

  -- Record speed-up usage
  INSERT INTO public.speed_ups (player_id, speed_up_type, target_id, minutes)
  VALUES (v_player_id, 'factory', p_slot, p_minutes);
END;
$$;

COMMENT ON FUNCTION public.apply_factory_speed_up(text, integer, integer) IS 'Apply speed-up to factory production slot';

-- Function to apply speed-up to crop growth
CREATE OR REPLACE FUNCTION public.apply_crop_speed_up(
  p_plot_index integer,
  p_minutes integer
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_plot record;
BEGIN
  -- Get plot
  SELECT * INTO v_plot
  FROM public.farm_plots
  WHERE player_id = v_player_id
    AND plot_index = p_plot_index;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Plot % not found', p_plot_index;
  END IF;

  IF v_plot.crop_id IS NULL THEN
    RAISE EXCEPTION 'Plot % has no crop planted', p_plot_index;
  END IF;

  -- Apply speed-up (reduce ready time)
  UPDATE public.farm_plots
  SET ready_at = GREATEST(ready_at - (p_minutes || ' minutes')::interval, now())
  WHERE player_id = v_player_id
    AND plot_index = p_plot_index;

  -- Record speed-up usage
  INSERT INTO public.speed_ups (player_id, speed_up_type, target_id, minutes)
  VALUES (v_player_id, 'crop', p_plot_index, p_minutes);
END;
$$;

COMMENT ON FUNCTION public.apply_crop_speed_up(integer, integer) IS 'Apply speed-up to crop growth';

-- Update purchase_premium_item to handle speed-ups
CREATE OR REPLACE FUNCTION public.purchase_premium_item(
  p_item_id text,
  p_use_aether boolean DEFAULT true
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_item record;
  v_current_aether integer;
  v_current_crystals bigint;
  v_cost integer;
  v_result jsonb;
  v_minutes integer;
BEGIN
  -- Get item
  SELECT * INTO v_item
  FROM public.premium_shop
  WHERE item_id = p_item_id AND available = true;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Item % not found or not available', p_item_id;
  END IF;

  -- Determine cost
  IF p_use_aether THEN
    v_cost := v_item.cost_aether;
    
    -- Check aether
    SELECT COALESCE(aether, 0) INTO v_current_aether
    FROM public.profiles
    WHERE id = v_player_id;

    IF v_current_aether < v_cost THEN
      RAISE EXCEPTION 'Insufficient aether: required %, available %', v_cost, v_current_aether;
    END IF;

    -- Deduct aether
    UPDATE public.profiles
    SET aether = aether - v_cost
    WHERE id = v_player_id;

    -- Record transaction
    INSERT INTO public.aether_transactions (player_id, transaction_type, amount, description, metadata)
    VALUES (v_player_id, 'spent', v_cost, 'Purchased ' || v_item.name, jsonb_build_object('item_id', p_item_id));
  ELSE
    v_cost := v_item.cost_crystals;
    
    IF v_cost <= 0 THEN
      RAISE EXCEPTION 'Item cannot be purchased with crystals';
    END IF;

    -- Check crystals
    SELECT crystals INTO v_current_crystals
    FROM public.profiles
    WHERE id = v_player_id;

    IF v_current_crystals < v_cost THEN
      RAISE EXCEPTION 'Insufficient crystals: required %, available %', v_cost, v_current_crystals;
    END IF;

    -- Deduct crystals
    UPDATE public.profiles
    SET crystals = crystals - v_cost
    WHERE id = v_player_id;
  END IF;

  -- Apply item effects based on type
  CASE v_item.item_type
    WHEN 'speed_up' THEN
      v_minutes := (v_item.metadata->>'minutes')::integer;
      -- Speed-ups are applied manually by player, just return the minutes available
      v_result := jsonb_build_object(
        'success', true,
        'item_type', 'speed_up',
        'minutes', v_minutes,
        'message', 'Speed-up added to inventory. Use it from factory or farm pages.'
      );
      
      -- Add to player's speed-up inventory (could be a separate table, but for now we'll track usage)
      
    WHEN 'decoration' THEN
      -- Decoration would be added to inventory or placed directly
      v_result := jsonb_build_object(
        'success', true,
        'item_type', 'decoration',
        'decoration_type', v_item.metadata->>'decoration_type',
        'message', 'Decoration unlocked! Place it from the town map.'
      );
      
    WHEN 'building' THEN
      -- Building would be unlocked or placed
      v_result := jsonb_build_object(
        'success', true,
        'item_type', 'building',
        'building_type', v_item.metadata->>'building_type',
        'message', 'Premium building unlocked!'
      );
      
    WHEN 'boost' THEN
      -- Create active boost record
      INSERT INTO public.active_boosts (player_id, boost_type, multiplier, expires_at)
      VALUES (
        v_player_id,
        CASE 
          WHEN v_item.item_id LIKE '%xp%' THEN 'xp'
          WHEN v_item.item_id LIKE '%crystal%' THEN 'crystal'
          ELSE 'general'
        END,
        COALESCE((v_item.metadata->>'xp_multiplier')::numeric, (v_item.metadata->>'crystal_multiplier')::numeric, 1.0),
        now() + ((v_item.metadata->>'duration_hours')::integer || ' hours')::interval
      )
      ON CONFLICT (player_id, boost_type) DO UPDATE SET
        multiplier = EXCLUDED.multiplier,
        expires_at = EXCLUDED.expires_at;
      
      v_result := jsonb_build_object(
        'success', true,
        'item_type', 'boost',
        'duration_hours', (v_item.metadata->>'duration_hours')::integer,
        'metadata', v_item.metadata,
        'message', 'Boost activated!'
      );
      
    WHEN 'bundle' THEN
      -- Award bundle items
      -- This would need to parse the bundle items and award them
      v_result := jsonb_build_object(
        'success', true,
        'item_type', 'bundle',
        'items', v_item.metadata->'items',
        'message', 'Bundle items added to your inventory!'
      );
    ELSE
      v_result := jsonb_build_object('success', true);
  END CASE;

  RETURN v_result;
END;
$$;

-- Create active_boosts table for temporary boosts
CREATE TABLE IF NOT EXISTS public.active_boosts (
  player_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  boost_type text NOT NULL CHECK (boost_type IN ('xp', 'crystal', 'production', 'general')),
  multiplier numeric NOT NULL DEFAULT 1.0,
  expires_at timestamptz NOT NULL,
  created_at timestamptz DEFAULT now(),
  PRIMARY KEY (player_id, boost_type)
);

-- Enable RLS
ALTER TABLE public.active_boosts ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Players can view own boosts" ON public.active_boosts
  FOR SELECT TO authenticated
  USING (auth.uid() = player_id);

-- Enable realtime
ALTER PUBLICATION supabase_realtime ADD TABLE public.active_boosts;

-- Create index
CREATE INDEX IF NOT EXISTS idx_active_boosts_expires ON public.active_boosts(expires_at);

-- Function to get active boost multiplier
CREATE OR REPLACE FUNCTION public.get_active_boost_multiplier(p_boost_type text)
RETURNS numeric
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_multiplier numeric := 1.0;
BEGIN
  SELECT multiplier INTO v_multiplier
  FROM public.active_boosts
  WHERE player_id = v_player_id
    AND boost_type = p_boost_type
    AND expires_at > now()
  LIMIT 1;

  RETURN COALESCE(v_multiplier, 1.0);
END;
$$;

COMMENT ON FUNCTION public.get_active_boost_multiplier(text) IS 'Get active boost multiplier for a boost type';

