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
  IF v_player_id IS NULL THEN
    RAISE EXCEPTION 'User must be authenticated';
  END IF;

  IF p_production_type = 'mining' THEN
    v_hourly_limit := 3;
  ELSE
    v_hourly_limit := 5;
  END IF;

  IF p_production_type IS NOT NULL THEN
    SELECT COUNT(*) INTO v_ads_watched_this_hour
    FROM public.ad_watches
    WHERE player_id = v_player_id
      AND production_type = p_production_type
      AND watched_at > now() - INTERVAL '1 hour';
  ELSE
    SELECT COUNT(*) INTO v_ads_watched_this_hour
    FROM public.ad_watches
    WHERE player_id = v_player_id
      AND watched_at > now() - INTERVAL '1 hour';
  END IF;

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

COMMENT ON FUNCTION public.can_watch_ad(TEXT) IS 'Check if player can watch an ad. For mining: 3 per hour, for production/other: 5 per hour. Returns JSON with eligibility status.';