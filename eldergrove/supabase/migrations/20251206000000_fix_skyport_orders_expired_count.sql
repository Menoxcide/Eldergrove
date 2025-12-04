-- Fix generate_skyport_orders to exclude expired orders from count
-- This prevents expired orders from blocking new order generation

CREATE OR REPLACE FUNCTION public.generate_skyport_orders(p_player_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order_count integer;
  v_order_type text;
  v_requirements jsonb;
  v_rewards jsonb;
  v_expires_minutes integer;
  v_i integer;
BEGIN
  -- Count active orders (non-expired and non-completed)
  SELECT count(*) INTO v_order_count
  FROM public.skyport_orders
  WHERE player_id = p_player_id 
    AND completed_at IS NULL
    AND expires_at > now();

  -- Generate orders up to max (3 quick, 2 standard, 1 premium = 6 total)
  -- Quick orders (helicopter) - 3 slots, 30 min expiry
  FOR v_i IN 1..3 LOOP
    -- Re-count active orders before each check to ensure we don't exceed limit
    SELECT count(*) INTO v_order_count
    FROM public.skyport_orders
    WHERE player_id = p_player_id 
      AND completed_at IS NULL
      AND expires_at > now();
    
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
    -- Re-count active orders before each check
    SELECT count(*) INTO v_order_count
    FROM public.skyport_orders
    WHERE player_id = p_player_id 
      AND completed_at IS NULL
      AND expires_at > now();
    
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
  -- Re-count active orders before check
  SELECT count(*) INTO v_order_count
  FROM public.skyport_orders
  WHERE player_id = p_player_id 
    AND completed_at IS NULL
    AND expires_at > now();
  
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

COMMENT ON FUNCTION public.generate_skyport_orders(uuid) IS 'Generate new skyport orders for a player (max 6 active non-expired orders)';

