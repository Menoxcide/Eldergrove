-- Create storage management system with warehouse upgrades

-- Add storage capacity to profiles
DO $$ 
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'profiles' AND column_name = 'storage_capacity'
  ) THEN
    ALTER TABLE public.profiles ADD COLUMN storage_capacity integer DEFAULT 50;
  END IF;
END $$;

-- Create warehouse_upgrades table
CREATE TABLE IF NOT EXISTS public.warehouse_upgrades (
  id serial PRIMARY KEY,
  player_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  level integer NOT NULL DEFAULT 1 CHECK (level >= 1 AND level <= 10),
  upgraded_at timestamptz DEFAULT now(),
  UNIQUE(player_id)
);

-- Enable RLS
ALTER TABLE public.warehouse_upgrades ENABLE ROW LEVEL SECURITY;

-- Policy: Players can view and manage their own upgrades
CREATE POLICY "Players can view own upgrades" ON public.warehouse_upgrades
  FOR SELECT TO authenticated
  USING (auth.uid() = player_id);

CREATE POLICY "Players can insert own upgrades" ON public.warehouse_upgrades
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = player_id);

CREATE POLICY "Players can update own upgrades" ON public.warehouse_upgrades
  FOR UPDATE TO authenticated
  USING (auth.uid() = player_id)
  WITH CHECK (auth.uid() = player_id);

-- Initialize warehouse upgrade for existing players
INSERT INTO public.warehouse_upgrades (player_id, level)
SELECT id, 1 FROM public.profiles
ON CONFLICT (player_id) DO NOTHING;

-- Function to calculate storage capacity from level
CREATE OR REPLACE FUNCTION public.get_storage_capacity(p_level integer)
RETURNS integer
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
  -- Base: 50, each level adds 25
  RETURN 50 + (p_level - 1) * 25;
END;
$$;

COMMENT ON FUNCTION public.get_storage_capacity(integer) IS 'Calculate storage capacity from warehouse level';

-- Function to upgrade warehouse
CREATE OR REPLACE FUNCTION public.upgrade_warehouse()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_current_level integer;
  v_new_level integer;
  v_upgrade_cost integer;
  v_current_crystals bigint;
  v_new_capacity integer;
  v_result jsonb;
BEGIN
  -- Get current warehouse level
  SELECT COALESCE(level, 1) INTO v_current_level
  FROM public.warehouse_upgrades
  WHERE player_id = v_player_id;

  IF v_current_level >= 10 THEN
    RAISE EXCEPTION 'Warehouse is already at maximum level (10)';
  END IF;

  v_new_level := v_current_level + 1;
  
  -- Calculate upgrade cost (exponential: 100 * level^2)
  v_upgrade_cost := 100 * v_new_level * v_new_level;

  -- Check crystals
  SELECT crystals INTO v_current_crystals
  FROM public.profiles
  WHERE id = v_player_id;

  IF v_current_crystals < v_upgrade_cost THEN
    RAISE EXCEPTION 'Insufficient crystals: required %, available %', v_upgrade_cost, v_current_crystals;
  END IF;

  -- Deduct crystals
  UPDATE public.profiles
  SET crystals = crystals - v_upgrade_cost
  WHERE id = v_player_id;

  -- Update or insert warehouse upgrade
  INSERT INTO public.warehouse_upgrades (player_id, level)
  VALUES (v_player_id, v_new_level)
  ON CONFLICT (player_id) DO UPDATE SET
    level = v_new_level,
    upgraded_at = now();

  -- Update storage capacity
  v_new_capacity := public.get_storage_capacity(v_new_level);
  UPDATE public.profiles
  SET storage_capacity = v_new_capacity
  WHERE id = v_player_id;

  -- Return result
  SELECT jsonb_build_object(
    'success', true,
    'new_level', v_new_level,
    'new_capacity', v_new_capacity,
    'cost', v_upgrade_cost
  ) INTO v_result;

  RETURN v_result;
END;
$$;

COMMENT ON FUNCTION public.upgrade_warehouse() IS 'Upgrade warehouse: increases storage capacity, costs crystals based on level';

-- Function to get current storage usage
CREATE OR REPLACE FUNCTION public.get_storage_usage(p_player_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_capacity integer;
  v_used integer;
  v_result jsonb;
BEGIN
  -- Get capacity
  SELECT storage_capacity INTO v_capacity
  FROM public.profiles
  WHERE id = p_player_id;

  -- Count distinct items (each item type counts as 1 slot)
  SELECT count(DISTINCT item_id) INTO v_used
  FROM public.inventory
  WHERE player_id = p_player_id AND quantity > 0;

  SELECT jsonb_build_object(
    'capacity', v_capacity,
    'used', v_used,
    'available', GREATEST(v_capacity - v_used, 0),
    'percentage', ROUND((v_used::numeric / NULLIF(v_capacity, 0)) * 100, 2)
  ) INTO v_result;

  RETURN v_result;
END;
$$;

COMMENT ON FUNCTION public.get_storage_usage(uuid) IS 'Get current storage usage statistics for a player';

