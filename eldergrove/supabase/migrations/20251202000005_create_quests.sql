-- Create quest system for tutorial, daily, and weekly quests

-- Create quests table (master list)
CREATE TABLE IF NOT EXISTS public.quests (
  id serial PRIMARY KEY,
  name text UNIQUE NOT NULL,
  type text NOT NULL CHECK (type IN ('tutorial', 'daily', 'weekly', 'story')),
  title text NOT NULL,
  description text NOT NULL,
  objectives jsonb NOT NULL, -- [{type: 'harvest', target: 5, current: 0}, ...]
  rewards jsonb NOT NULL, -- {crystals: 100, xp: 50, items: {item_id: quantity}}
  order_index integer DEFAULT 0, -- For tutorial/story ordering
  available boolean DEFAULT true
);

-- Create quest_progress table (player progress)
CREATE TABLE IF NOT EXISTS public.quest_progress (
  player_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  quest_id integer NOT NULL REFERENCES public.quests(id) ON DELETE CASCADE,
  progress jsonb NOT NULL, -- Same structure as objectives but with current values
  completed boolean NOT NULL DEFAULT false,
  completed_at timestamptz,
  claimed boolean NOT NULL DEFAULT false,
  claimed_at timestamptz,
  started_at timestamptz DEFAULT now(),
  expires_at timestamptz, -- For daily/weekly quests
  PRIMARY KEY (player_id, quest_id)
);

-- Enable RLS
ALTER TABLE public.quests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.quest_progress ENABLE ROW LEVEL SECURITY;

-- Policy: Everyone can view available quests
CREATE POLICY "Anyone can view quests" ON public.quests
  FOR SELECT TO authenticated
  USING (available = true);

-- Policy: Players can view own progress
CREATE POLICY "Players can view own quest progress" ON public.quest_progress
  FOR SELECT TO authenticated
  USING (auth.uid() = player_id);

CREATE POLICY "Players can update own quest progress" ON public.quest_progress
  FOR UPDATE TO authenticated
  USING (auth.uid() = player_id)
  WITH CHECK (auth.uid() = player_id);

CREATE POLICY "Players can insert own quest progress" ON public.quest_progress
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = player_id);

-- Enable realtime
ALTER PUBLICATION supabase_realtime ADD TABLE public.quest_progress;

-- Seed tutorial quests
INSERT INTO public.quests (name, type, title, description, objectives, rewards, order_index) VALUES
('tutorial_1', 'tutorial', 'Welcome to Eldergrove', 'Learn the basics of farming', 
 '[
   {"type": "harvest", "target": 1, "description": "Harvest 1 crop"}
 ]'::jsonb,
 '{"crystals": 100, "xp": 50}'::jsonb, 1),
('tutorial_2', 'tutorial', 'First Production', 'Create your first factory item',
 '[
   {"type": "produce", "target": 1, "description": "Complete 1 factory production"}
 ]'::jsonb,
 '{"crystals": 150, "xp": 75}'::jsonb, 2),
('tutorial_3', 'tutorial', 'Build Your Town', 'Place your first building',
 '[
   {"type": "build", "target": 1, "description": "Place 1 building"}
 ]'::jsonb,
 '{"crystals": 200, "xp": 100}'::jsonb, 3),
('tutorial_4', 'tutorial', 'Marketplace', 'Sell items at the marketplace',
 '[
   {"type": "sell", "target": 1, "description": "Sell 1 item"}
 ]'::jsonb,
 '{"crystals": 150, "xp": 75}'::jsonb, 4),
('tutorial_5', 'tutorial', 'Skyport Orders', 'Complete your first skyport order',
 '[
   {"type": "order", "target": 1, "description": "Complete 1 skyport order"}
 ]'::jsonb,
 '{"crystals": 250, "xp": 125}'::jsonb, 5)
ON CONFLICT (name) DO NOTHING;

-- Function to start a quest
CREATE OR REPLACE FUNCTION public.start_quest(p_quest_id integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_quest record;
  v_expires_at timestamptz;
BEGIN
  -- Get quest
  SELECT * INTO v_quest
  FROM public.quests
  WHERE id = p_quest_id AND available = true;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Quest % not found or not available', p_quest_id;
  END IF;

  -- Check if already started
  IF EXISTS (
    SELECT 1 FROM public.quest_progress
    WHERE player_id = v_player_id AND quest_id = p_quest_id
  ) THEN
    RAISE EXCEPTION 'Quest % already started', p_quest_id;
  END IF;

  -- Calculate expiration for daily/weekly quests
  IF v_quest.type = 'daily' THEN
    v_expires_at := now() + interval '24 hours';
  ELSIF v_quest.type = 'weekly' THEN
    v_expires_at := now() + interval '7 days';
  ELSE
    v_expires_at := NULL;
  END IF;

  -- Initialize progress
  INSERT INTO public.quest_progress (player_id, quest_id, progress, expires_at)
  VALUES (v_player_id, p_quest_id, v_quest.objectives, v_expires_at);
END;
$$;

COMMENT ON FUNCTION public.start_quest(integer) IS 'Start a quest for the player';

-- Function to update quest progress
CREATE OR REPLACE FUNCTION public.update_quest_progress(
  p_objective_type text,
  p_quest_id integer DEFAULT NULL,
  p_increment integer DEFAULT 1
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_progress jsonb;
  v_objective jsonb;
  v_current_value integer;
  v_target_value integer;
  v_all_completed boolean;
  v_idx integer;
  v_quest_progress record;
BEGIN
  -- Update all active quests if p_quest_id is NULL, otherwise update specific quest
  FOR v_quest_progress IN
    SELECT * FROM public.quest_progress
    WHERE player_id = v_player_id
      AND (p_quest_id IS NULL OR quest_id = p_quest_id)
      AND NOT completed
      AND (expires_at IS NULL OR expires_at > now())
  LOOP
    v_progress := v_quest_progress.progress;

  -- Update progress for matching objective type
  FOR v_idx IN 0..jsonb_array_length(v_progress) - 1 LOOP
    v_objective := v_progress->v_idx;
    
    IF (v_objective->>'type') = p_objective_type THEN
      v_current_value := COALESCE((v_objective->>'current')::integer, 0);
      v_target_value := (v_objective->>'target')::integer;
      
      v_current_value := LEAST(v_current_value + p_increment, v_target_value);
      
      v_progress := jsonb_set(
        v_progress,
        ARRAY[v_idx::text, 'current'],
        v_current_value::jsonb
      );
    END IF;
  END LOOP;

  -- Check if all objectives completed
  v_all_completed := true;
  FOR v_idx IN 0..jsonb_array_length(v_progress) - 1 LOOP
    v_objective := v_progress->v_idx;
    v_current_value := COALESCE((v_objective->>'current')::integer, 0);
    v_target_value := (v_objective->>'target')::integer;
    
    IF v_current_value < v_target_value THEN
      v_all_completed := false;
      EXIT;
    END IF;
  END LOOP;

    -- Update progress
    UPDATE public.quest_progress
    SET progress = v_progress,
        completed = CASE WHEN v_all_completed THEN true ELSE completed END,
        completed_at = CASE WHEN v_all_completed AND NOT completed THEN now() ELSE completed_at END
    WHERE player_id = v_player_id AND quest_id = v_quest_progress.quest_id;
  END LOOP;
END;
$$;

COMMENT ON FUNCTION public.update_quest_progress(text, integer, integer) IS 'Update quest progress for a specific objective type';

-- Function to claim quest reward
CREATE OR REPLACE FUNCTION public.claim_quest_reward(p_quest_id integer)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_quest record;
  v_progress record;
  v_rewards jsonb;
  v_key text;
  v_value text;
  v_item_id integer;
  v_qty integer;
  v_result jsonb;
BEGIN
  -- Get quest
  SELECT * INTO v_quest
  FROM public.quests
  WHERE id = p_quest_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Quest % not found', p_quest_id;
  END IF;

  -- Get progress
  SELECT * INTO v_progress
  FROM public.quest_progress
  WHERE player_id = v_player_id AND quest_id = p_quest_id;

  IF NOT FOUND OR NOT v_progress.completed THEN
    RAISE EXCEPTION 'Quest % is not completed', p_quest_id;
  END IF;

  IF v_progress.claimed THEN
    RAISE EXCEPTION 'Quest % reward already claimed', p_quest_id;
  END IF;

  v_rewards := v_quest.rewards;

  -- Award crystals
  IF v_rewards ? 'crystals' THEN
    UPDATE public.profiles
    SET crystals = crystals + (v_rewards->>'crystals')::integer
    WHERE id = v_player_id;
  END IF;

  -- Award XP
  IF v_rewards ? 'xp' THEN
    UPDATE public.profiles
    SET xp = xp + (v_rewards->>'xp')::integer
    WHERE id = v_player_id;
  END IF;

  -- Award items
  IF v_rewards ? 'items' THEN
    FOR v_key, v_value IN SELECT key, value FROM jsonb_each_text(v_rewards->'items') LOOP
      v_item_id := v_key::integer;
      v_qty := v_value::integer;

      INSERT INTO public.inventory (player_id, item_id, quantity)
      VALUES (v_player_id, v_item_id, v_qty::bigint)
      ON CONFLICT (player_id, item_id) DO UPDATE SET
        quantity = inventory.quantity + excluded.quantity;
    END LOOP;
  END IF;

  -- Mark as claimed
  UPDATE public.quest_progress
  SET claimed = true, claimed_at = now()
  WHERE player_id = v_player_id AND quest_id = p_quest_id;

  -- Return result
  SELECT jsonb_build_object(
    'success', true,
    'crystals_awarded', COALESCE((v_rewards->>'crystals')::integer, 0),
    'xp_awarded', COALESCE((v_rewards->>'xp')::integer, 0)
  ) INTO v_result;

  RETURN v_result;
END;
$$;

COMMENT ON FUNCTION public.claim_quest_reward(integer) IS 'Claim quest reward: awards crystals, XP, and items';

-- Function to generate daily quests
CREATE OR REPLACE FUNCTION public.generate_daily_quests(p_player_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_quest record;
BEGIN
  -- Delete expired daily quests
  DELETE FROM public.quest_progress
  WHERE player_id = p_player_id
    AND quest_id IN (SELECT id FROM public.quests WHERE type = 'daily')
    AND expires_at < now();

  -- Generate new daily quests (3 per day)
  FOR v_quest IN
    SELECT * FROM public.quests
    WHERE type = 'daily' AND available = true
    ORDER BY random()
    LIMIT 3
  LOOP
    -- Only add if not already active
    IF NOT EXISTS (
      SELECT 1 FROM public.quest_progress
      WHERE player_id = p_player_id AND quest_id = v_quest.id
    ) THEN
      INSERT INTO public.quest_progress (player_id, quest_id, progress, expires_at)
      VALUES (p_player_id, v_quest.id, v_quest.objectives, now() + interval '24 hours')
      ON CONFLICT DO NOTHING;
    END IF;
  END LOOP;
END;
$$;

COMMENT ON FUNCTION public.generate_daily_quests(uuid) IS 'Generate daily quests for a player';

