-- Add mining energy restoration via ad watches
-- Extend can_watch_ad to support mining energy restoration (separate limit: 3 per hour)

-- Update can_watch_ad to accept optional production_type parameter
CREATE OR REPLACE FUNCTION public.can_watch_ad(p_production_type TEXT DEFAULT NULL)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id UUID := auth.uid();
  v_ads_watched_this_hour INTEGER;
  v_hourly_limit INTEGER;
  v_can_watch BOOLEAN;
  v_ads_remaining INTEGER;
BEGIN
  IF v_player_id IS NULL THEN
    RAISE EXCEPTION 'User must be authenticated';
  END IF;

  -- Set hourly limit based on production type
  IF p_production_type = 'mining' THEN
    v_hourly_limit := 3;
  ELSE
    v_hourly_limit := 5; -- Default for production speed-ups
  END IF;

  -- Count ads watched in the last hour for this production type
  IF p_production_type IS NOT NULL THEN
    SELECT COUNT(*) INTO v_ads_watched_this_hour
    FROM public.ad_watches
    WHERE player_id = v_player_id
      AND production_type = p_production_type
      AND watched_at > now() - INTERVAL '1 hour';
  ELSE
    -- Count all ads (for backward compatibility)
    SELECT COUNT(*) INTO v_ads_watched_this_hour
    FROM public.ad_watches
    WHERE player_id = v_player_id
      AND watched_at > now() - INTERVAL '1 hour';
  END IF;

  -- Calculate if can watch and remaining ads
  v_ads_remaining := GREATEST(0, v_hourly_limit - v_ads_watched_this_hour);
  v_can_watch := v_ads_watched_this_hour < v_hourly_limit;

  RETURN jsonb_build_object(
    'can_watch', v_can_watch,
    'ads_watched_this_hour', v_ads_watched_this_hour,
    'ads_remaining', v_ads_remaining,
    'hourly_limit', v_hourly_limit
  );
END;
$$;

COMMENT ON FUNCTION public.can_watch_ad(TEXT) IS 'Check if player can watch an ad. For mining: 3 per hour, for production speed-ups: 5 per hour.';

-- RPC function to watch ad and restore mining energy
CREATE OR REPLACE FUNCTION public.watch_ad_restore_energy()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id UUID := auth.uid();
  v_eligibility JSONB;
  v_can_watch BOOLEAN;
  v_mine_dig record;
  v_result JSONB;
BEGIN
  IF v_player_id IS NULL THEN
    RAISE EXCEPTION 'User must be authenticated';
  END IF;

  -- Check eligibility (3 ads per hour for mining)
  SELECT can_watch_ad('mining') INTO v_eligibility;
  v_can_watch := (v_eligibility->>'can_watch')::BOOLEAN;

  IF NOT v_can_watch THEN
    RAISE EXCEPTION 'Ad watch limit reached for mining energy. You can watch % more ads in the next hour.', 
      (v_eligibility->>'ads_remaining')::INTEGER;
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

  -- Restore energy to full (set energy_used_today to 0)
  UPDATE public.mine_digs
  SET energy_used_today = 0,
      last_energy_reset = now()
  WHERE player_id = v_player_id;

  -- Record the ad watch
  INSERT INTO public.ad_watches (
    player_id,
    production_type,
    production_id,
    minutes_reduced
  ) VALUES (
    v_player_id,
    'mining',
    0, -- Not applicable for energy restoration
    0  -- Not applicable for energy restoration
  );

  -- Return success result
  SELECT can_watch_ad('mining') INTO v_eligibility;
  RETURN jsonb_build_object(
    'success', true,
    'energy_restored', 100,
    'ads_remaining', (v_eligibility->>'ads_remaining')::INTEGER
  );
END;
$$;

COMMENT ON FUNCTION public.watch_ad_restore_energy() IS 'Watch ad and restore full mining energy (100). Limited to 3 ads per hour.';

