-- Add mining energy restoration via crystals
-- Cost: 50 crystals to fully restore mining energy (100 energy)

-- RPC function to restore mining energy with crystals
CREATE OR REPLACE FUNCTION public.restore_mining_energy_crystals()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_player_id UUID := auth.uid();
  v_mine_dig record;
  v_current_crystals BIGINT;
  v_cost INTEGER := 50; -- Cost in crystals to restore full energy
  v_energy_restored INTEGER;
BEGIN
  IF v_player_id IS NULL THEN
    RAISE EXCEPTION 'User must be authenticated';
  END IF;

  -- Get current crystals
  SELECT crystals INTO v_current_crystals
  FROM public.profiles
  WHERE id = v_player_id;

  IF v_current_crystals IS NULL OR v_current_crystals < v_cost THEN
    RAISE EXCEPTION 'Insufficient crystals: required %, available %', v_cost, COALESCE(v_current_crystals, 0);
  END IF;

  -- Get or create mine_digs entry
  SELECT * INTO v_mine_dig
  FROM public.mine_digs
  WHERE player_id = v_player_id;

  IF NOT FOUND THEN
    PERFORM public.initialize_mining(v_player_id);
    SELECT * INTO v_mine_dig
    FROM public.mine_digs
    WHERE player_id = v_player_id;
  END IF;

  -- Calculate energy to restore (current energy used)
  v_energy_restored := v_mine_dig.energy_used_today;

  -- If already at full energy, return early
  IF v_energy_restored = 0 THEN
    RETURN jsonb_build_object(
      'success', false,
      'message', 'Energy is already at maximum',
      'energy_restored', 0
    );
  END IF;

  -- Deduct crystals
  UPDATE public.profiles
  SET crystals = crystals - v_cost
  WHERE id = v_player_id;

  -- Restore energy to full (set energy_used_today to 0)
  UPDATE public.mine_digs
  SET energy_used_today = 0,
      last_energy_reset = now()
  WHERE player_id = v_player_id;

  -- Return success result
  RETURN jsonb_build_object(
    'success', true,
    'energy_restored', v_energy_restored,
    'crystals_spent', v_cost,
    'new_crystals', v_current_crystals - v_cost
  );
END;
$$;

COMMENT ON FUNCTION public.restore_mining_energy_crystals() IS 'Restore full mining energy (100) using 50 crystals.';

