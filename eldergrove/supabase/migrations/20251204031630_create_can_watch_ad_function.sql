-- Create the can_watch_ad RPC function for checking ad eligibility
-- This function determines if a player can watch an ad based on hourly limits

CREATE OR REPLACE FUNCTION public.can_watch_ad(p_production_type TEXT DEFAULT NULL)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_player_id UUID := auth.uid();
  v_ads_watched_this_hour INTEGER;
  v_hourly_limit INTEGER;
  v_can_watch BOOLEAN;
  v_ads_remaining INTEGER;
BEGIN
  RAISE LOG 'can_watch_ad called with production_type: %, player_id: %', p_production_type, v_player_id;

  IF v_player_id IS NULL THEN
    RAISE EXCEPTION 'User must be authenticated';
  END IF;

  -- Set hourly limit based on production type
  IF p_production_type = 'mining' THEN
    v_hourly_limit := 3;
  ELSE
    v_hourly_limit := 5; -- Default for production speed-ups and other types
  END IF;

  RAISE LOG 'can_watch_ad: hourly_limit set to % for production_type %', v_hourly_limit, p_production_type;

  -- Count ads watched in the last hour for this production type
  IF p_production_type IS NOT NULL THEN
    SELECT COUNT(*) INTO v_ads_watched_this_hour
    FROM public.ad_watches
    WHERE player_id = v_player_id
      AND production_type = p_production_type
      AND watched_at > now() - INTERVAL '1 hour';
  ELSE
    -- Count all ads when production_type is NULL
    SELECT COUNT(*) INTO v_ads_watched_this_hour
    FROM public.ad_watches
    WHERE player_id = v_player_id
      AND watched_at > now() - INTERVAL '1 hour';
  END IF;

  RAISE LOG 'can_watch_ad: ads_watched_this_hour = %', v_ads_watched_this_hour;

  -- Calculate if can watch and remaining ads
  v_ads_remaining := GREATEST(0, v_hourly_limit - v_ads_watched_this_hour);
  v_can_watch := v_ads_watched_this_hour < v_hourly_limit;

  RAISE LOG 'can_watch_ad: can_watch = %, ads_remaining = %', v_can_watch, v_ads_remaining;

  RETURN jsonb_build_object(
    'can_watch', v_can_watch,
    'ads_watched_this_hour', v_ads_watched_this_hour,
    'ads_remaining', v_ads_remaining,
    'hourly_limit', v_hourly_limit
  );
END;
$$;

COMMENT ON FUNCTION public.can_watch_ad(TEXT) IS 'Check if player can watch an ad. For mining: 3 per hour, for production/other: 5 per hour. Returns JSON with eligibility status.';