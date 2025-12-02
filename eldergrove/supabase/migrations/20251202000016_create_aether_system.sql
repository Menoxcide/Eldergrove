-- Create Aether (premium currency) system

-- Add aether column to profiles if it doesn't exist
DO $$ 
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'profiles' AND column_name = 'aether'
  ) THEN
    ALTER TABLE public.profiles ADD COLUMN aether integer DEFAULT 0;
  END IF;
END $$;

-- Create premium_shop table
CREATE TABLE IF NOT EXISTS public.premium_shop (
  id serial PRIMARY KEY,
  item_type text NOT NULL CHECK (item_type IN ('speed_up', 'decoration', 'building', 'boost', 'bundle')),
  item_id text NOT NULL,
  name text NOT NULL,
  description text,
  icon text,
  cost_aether integer NOT NULL,
  cost_crystals integer DEFAULT 0, -- Some items can be bought with crystals too
  available boolean DEFAULT true,
  sort_order integer DEFAULT 0,
  metadata jsonb -- Additional data (e.g., speed_up_minutes, building_type, etc.)
);

-- Insert premium shop items
INSERT INTO public.premium_shop (item_type, item_id, name, description, icon, cost_aether, cost_crystals, sort_order, metadata) VALUES
  -- Speed-ups
  ('speed_up', 'speed_1h', '1 Hour Speed-Up', 'Instantly complete 1 hour of production', '⏩', 10, 0, 1, '{"minutes": 60}'),
  ('speed_up', 'speed_3h', '3 Hour Speed-Up', 'Instantly complete 3 hours of production', '⏩⏩', 25, 0, 2, '{"minutes": 180}'),
  ('speed_up', 'speed_8h', '8 Hour Speed-Up', 'Instantly complete 8 hours of production', '⏩⏩⏩', 60, 0, 3, '{"minutes": 480}'),
  
  -- Premium Decorations
  ('decoration', 'statue_golden', 'Golden Statue', 'Exclusive golden statue decoration', '🏆', 50, 0, 10, '{"decoration_type": "statue_golden"}'),
  ('decoration', 'fountain_magic', 'Magic Fountain', 'Enchanted fountain with magical effects', '✨', 75, 0, 11, '{"decoration_type": "fountain_magic"}'),
  
  -- Premium Buildings
  ('building', 'factory_premium', 'Premium Factory', 'Upgraded factory with faster production', '🏭', 100, 0, 20, '{"building_type": "premium_factory", "production_speed": 1.5}'),
  
  -- Boosts
  ('boost', 'xp_boost_24h', '24h XP Boost', 'Double XP for 24 hours', '📈', 30, 0, 30, '{"duration_hours": 24, "xp_multiplier": 2.0}'),
  ('boost', 'crystal_boost_24h', '24h Crystal Boost', '50% more crystals from all sources', '💎', 40, 0, 31, '{"duration_hours": 24, "crystal_multiplier": 1.5}'),
  
  -- Bundles
  ('bundle', 'starter_pack', 'Starter Pack', 'Great value starter bundle', '🎁', 100, 0, 100, '{"items": [{"type": "crystals", "amount": 1000}, {"type": "speed_up", "minutes": 120}]}')
ON CONFLICT DO NOTHING;

-- Create aether_transactions table
CREATE TABLE IF NOT EXISTS public.aether_transactions (
  id serial PRIMARY KEY,
  player_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  transaction_type text NOT NULL CHECK (transaction_type IN ('purchase', 'reward', 'spent', 'refund')),
  amount integer NOT NULL,
  description text,
  metadata jsonb,
  created_at timestamptz DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.premium_shop ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.aether_transactions ENABLE ROW LEVEL SECURITY;

-- Policy: Anyone can view premium shop
CREATE POLICY "Anyone can view premium shop" ON public.premium_shop
  FOR SELECT TO authenticated
  USING (available = true);

-- Policy: Players can view own transactions
CREATE POLICY "Players can view own transactions" ON public.aether_transactions
  FOR SELECT TO authenticated
  USING (auth.uid() = player_id);

-- Policy: System can insert transactions
CREATE POLICY "System can insert transactions" ON public.aether_transactions
  FOR INSERT TO authenticated
  WITH CHECK (true);

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_aether_transactions_player ON public.aether_transactions(player_id);
CREATE INDEX IF NOT EXISTS idx_aether_transactions_type ON public.aether_transactions(transaction_type);

-- Function to purchase premium shop item
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
      -- Speed-up logic would be handled by client or separate RPC
      v_result := jsonb_build_object(
        'success', true,
        'item_type', 'speed_up',
        'minutes', (v_item.metadata->>'minutes')::integer
      );
    WHEN 'decoration' THEN
      -- Decoration would be added to inventory or placed directly
      v_result := jsonb_build_object(
        'success', true,
        'item_type', 'decoration',
        'decoration_type', v_item.metadata->>'decoration_type'
      );
    WHEN 'building' THEN
      -- Building would be unlocked or placed
      v_result := jsonb_build_object(
        'success', true,
        'item_type', 'building',
        'building_type', v_item.metadata->>'building_type'
      );
    WHEN 'boost' THEN
      -- Boost would be activated
      v_result := jsonb_build_object(
        'success', true,
        'item_type', 'boost',
        'duration_hours', (v_item.metadata->>'duration_hours')::integer,
        'metadata', v_item.metadata
      );
    WHEN 'bundle' THEN
      -- Bundle items would be awarded
      v_result := jsonb_build_object(
        'success', true,
        'item_type', 'bundle',
        'items', v_item.metadata->'items'
      );
    ELSE
      v_result := jsonb_build_object('success', true);
  END CASE;

  RETURN v_result;
END;
$$;

COMMENT ON FUNCTION public.purchase_premium_item(text, boolean) IS 'Purchase an item from the premium shop using aether or crystals';

-- Function to award aether (for admin/rewards)
CREATE OR REPLACE FUNCTION public.award_aether(
  p_player_id uuid,
  p_amount integer,
  p_description text DEFAULT 'Awarded aether'
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Award aether
  UPDATE public.profiles
  SET aether = COALESCE(aether, 0) + p_amount
  WHERE id = p_player_id;

  -- Record transaction
  INSERT INTO public.aether_transactions (player_id, transaction_type, amount, description)
  VALUES (p_player_id, 'reward', p_amount, p_description);
END;
$$;

COMMENT ON FUNCTION public.award_aether(uuid, integer, text) IS 'Award aether to a player (admin/system use)';

