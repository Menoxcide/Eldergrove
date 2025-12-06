-- Add armory speed-up support
-- This migration adds 'armory' as a supported production type for speed-ups

-- Update speed_ups table to allow 'armory' as speed_up_type
ALTER TABLE public.speed_ups 
  DROP CONSTRAINT IF EXISTS speed_ups_speed_up_type_check;

ALTER TABLE public.speed_ups 
  ADD CONSTRAINT speed_ups_speed_up_type_check 
  CHECK (speed_up_type IN ('factory', 'crop', 'global', 'armory'));

-- Update watch_ad_speed_up function to support armory
CREATE OR REPLACE FUNCTION public.watch_ad_speed_up(
  p_production_type TEXT,
  p_production_id INTEGER,
  p_minutes_reduced INTEGER DEFAULT 30
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_player_id UUID := auth.uid();
  v_eligibility JSONB;
  v_can_watch BOOLEAN;
  v_current_time TIMESTAMPTZ := now();
  v_new_time TIMESTAMPTZ;
  v_remaining_minutes INTEGER;
  v_result JSONB;
BEGIN
  IF v_player_id IS NULL THEN
    RAISE EXCEPTION 'User must be authenticated';
  END IF;

  -- Validate production type
  IF p_production_type NOT IN ('farm', 'factory', 'zoo', 'armory') THEN
    RAISE EXCEPTION 'Invalid production_type: % (must be farm, factory, zoo, or armory)', p_production_type;
  END IF;

  -- Check eligibility
  SELECT can_watch_ad() INTO v_eligibility;
  v_can_watch := (v_eligibility->>'can_watch')::BOOLEAN;

  IF NOT v_can_watch THEN
    RAISE EXCEPTION 'Ad watch limit reached. You can watch % more ads in the next hour.', 
      (v_eligibility->>'ads_remaining')::INTEGER;
  END IF;

  -- Apply speed-up based on production type
  IF p_production_type = 'farm' THEN
    -- Update farm plot ready_at
    SELECT ready_at INTO v_new_time
    FROM public.farm_plots
    WHERE player_id = v_player_id
      AND plot_index = p_production_id
      AND crop_id IS NOT NULL
      AND ready_at IS NOT NULL;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Farm plot % not found or has no active crop', p_production_id;
    END IF;

    -- Calculate remaining time and apply speed-up
    v_remaining_minutes := GREATEST(0, EXTRACT(EPOCH FROM (v_new_time - v_current_time)) / 60);
    v_new_time := v_current_time + (GREATEST(0, v_remaining_minutes - p_minutes_reduced) || ' minutes')::INTERVAL;

    UPDATE public.farm_plots
    SET ready_at = v_new_time
    WHERE player_id = v_player_id
      AND plot_index = p_production_id;

  ELSIF p_production_type = 'factory' THEN
    -- Update factory queue finishes_at
    SELECT finishes_at INTO v_new_time
    FROM public.factory_queue
    WHERE player_id = v_player_id
      AND slot = p_production_id;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Factory slot % not found or has no active production', p_production_id;
    END IF;

    -- Calculate remaining time and apply speed-up
    v_remaining_minutes := GREATEST(0, EXTRACT(EPOCH FROM (v_new_time - v_current_time)) / 60);
    v_new_time := v_current_time + (GREATEST(0, v_remaining_minutes - p_minutes_reduced) || ' minutes')::INTERVAL;

    UPDATE public.factory_queue
    SET finishes_at = v_new_time
    WHERE player_id = v_player_id
      AND slot = p_production_id;

  ELSIF p_production_type = 'zoo' THEN
    -- For zoo, production_id encodes enclosure_id * 10 + slot (e.g., enclosure 5 slot 1 = 51)
    DECLARE
      v_enclosure_id INTEGER;
      v_slot INTEGER;
      v_enclosure RECORD;
      v_animal_id INTEGER;
      v_interval_minutes INTEGER;
      v_produced_at TIMESTAMPTZ;
      v_next_production_time TIMESTAMPTZ;
    BEGIN
      -- Decode production_id: enclosure_id = floor(production_id / 10), slot = production_id % 10
      v_enclosure_id := p_production_id / 10;
      v_slot := p_production_id % 10;

      IF v_slot NOT IN (1, 2) THEN
        RAISE EXCEPTION 'Invalid slot % for zoo (must be 1 or 2)', v_slot;
      END IF;

      SELECT * INTO v_enclosure
      FROM public.zoo_enclosures
      WHERE id = v_enclosure_id
        AND player_id = v_player_id;

      IF NOT FOUND THEN
        RAISE EXCEPTION 'Zoo enclosure % not found', v_enclosure_id;
      END IF;

      -- Get animal info based on slot
      IF v_slot = 1 THEN
        v_animal_id := v_enclosure.animal1_id;
        v_produced_at := v_enclosure.animal1_produced_at;
      ELSE
        v_animal_id := v_enclosure.animal2_id;
        v_produced_at := v_enclosure.animal2_produced_at;
      END IF;

      IF v_animal_id IS NULL OR v_produced_at IS NULL THEN
        RAISE EXCEPTION 'No active animal production found in enclosure % slot %', v_enclosure_id, v_slot;
      END IF;

      -- Get animal interval
      SELECT produces_interval_minutes INTO v_interval_minutes
      FROM public.animal_types
      WHERE id = v_animal_id;

      IF NOT FOUND THEN
        RAISE EXCEPTION 'Animal type % not found', v_animal_id;
      END IF;

      -- Calculate next production time
      v_next_production_time := v_produced_at + (v_interval_minutes || ' minutes')::INTERVAL;
      
      -- Calculate remaining time and apply speed-up
      v_remaining_minutes := GREATEST(0, EXTRACT(EPOCH FROM (v_next_production_time - v_current_time)) / 60);
      v_new_time := v_current_time + (GREATEST(0, v_remaining_minutes - p_minutes_reduced) || ' minutes')::INTERVAL;

      -- Update produced_at to make next production happen at v_new_time
      -- We need to set produced_at such that produced_at + interval = v_new_time
      v_produced_at := v_new_time - (v_interval_minutes || ' minutes')::INTERVAL;

      -- Update the appropriate slot
      IF v_slot = 1 THEN
        UPDATE public.zoo_enclosures
        SET animal1_produced_at = v_produced_at
        WHERE id = v_enclosure_id;
      ELSE
        UPDATE public.zoo_enclosures
        SET animal2_produced_at = v_produced_at
        WHERE id = v_enclosure_id;
      END IF;
    END;

  ELSIF p_production_type = 'armory' THEN
    -- Update armory queue finishes_at
    SELECT finishes_at INTO v_new_time
    FROM public.armory_queue
    WHERE player_id = v_player_id
      AND slot = p_production_id;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Armory slot % not found or has no active production', p_production_id;
    END IF;

    -- Calculate remaining time and apply speed-up
    v_remaining_minutes := GREATEST(0, EXTRACT(EPOCH FROM (v_new_time - v_current_time)) / 60);
    v_new_time := v_current_time + (GREATEST(0, v_remaining_minutes - p_minutes_reduced) || ' minutes')::INTERVAL;

    UPDATE public.armory_queue
    SET finishes_at = v_new_time
    WHERE player_id = v_player_id
      AND slot = p_production_id;
  END IF;

  -- Record the ad watch
  INSERT INTO public.ad_watches (
    player_id,
    production_type,
    production_id,
    minutes_reduced
  ) VALUES (
    v_player_id,
    p_production_type,
    p_production_id,
    p_minutes_reduced
  );

  -- Return success result
  SELECT can_watch_ad() INTO v_eligibility;
  RETURN jsonb_build_object(
    'success', true,
    'minutes_reduced', p_minutes_reduced,
    'new_completion_time', v_new_time,
    'ads_remaining', (v_eligibility->>'ads_remaining')::INTEGER
  );
END;
$$;

COMMENT ON FUNCTION public.watch_ad_speed_up(TEXT, INTEGER, INTEGER) IS 'Watch ad and apply speed-up to production. Validates eligibility, updates production timer, and records ad watch. Supports farm, factory, zoo, and armory.';

-- Function to apply speed-up to armory production
CREATE OR REPLACE FUNCTION public.apply_armory_speed_up(
  p_armory_type text,
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
  FROM public.armory_queue
  WHERE player_id = v_player_id
    AND armory_type = p_armory_type
    AND slot = p_slot;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Armory production slot not found';
  END IF;

  -- Apply speed-up (reduce finish time)
  UPDATE public.armory_queue
  SET finishes_at = GREATEST(finishes_at - (p_minutes || ' minutes')::interval, now())
  WHERE player_id = v_player_id
    AND armory_type = p_armory_type
    AND slot = p_slot;

  -- Record speed-up usage
  INSERT INTO public.speed_ups (player_id, speed_up_type, target_id, minutes)
  VALUES (v_player_id, 'armory', p_slot, p_minutes);
END;
$$;

COMMENT ON FUNCTION public.apply_armory_speed_up(text, integer, integer) IS 'Apply speed-up to armory production slot';

