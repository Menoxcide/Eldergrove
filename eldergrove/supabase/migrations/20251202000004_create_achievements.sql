-- Create achievement system

-- Create achievements table (master list)
CREATE TABLE IF NOT EXISTS public.achievements (
  id serial PRIMARY KEY,
  name text UNIQUE NOT NULL,
  description text NOT NULL,
  category text NOT NULL CHECK (category IN ('farming', 'factory', 'city', 'social', 'general')),
  condition_type text NOT NULL, -- e.g., 'harvest_count', 'produce_count', 'build_count'
  condition_value integer NOT NULL, -- e.g., 100 harvests
  reward_crystals integer DEFAULT 0,
  reward_xp integer DEFAULT 0,
  reward_title text, -- e.g., "Master Farmer"
  icon text DEFAULT '🏆'
);

-- Create player_achievements table (progress tracking)
CREATE TABLE IF NOT EXISTS public.player_achievements (
  player_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  achievement_id integer NOT NULL REFERENCES public.achievements(id) ON DELETE CASCADE,
  progress integer NOT NULL DEFAULT 0,
  completed boolean NOT NULL DEFAULT false,
  completed_at timestamptz,
  claimed boolean NOT NULL DEFAULT false,
  claimed_at timestamptz,
  PRIMARY KEY (player_id, achievement_id)
);

-- Enable RLS
ALTER TABLE public.achievements ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.player_achievements ENABLE ROW LEVEL SECURITY;

-- Policy: Everyone can view achievements
CREATE POLICY "Anyone can view achievements" ON public.achievements
  FOR SELECT TO authenticated
  USING (true);

-- Policy: Players can view own progress
CREATE POLICY "Players can view own achievements" ON public.player_achievements
  FOR SELECT TO authenticated
  USING (auth.uid() = player_id);

CREATE POLICY "Players can update own achievements" ON public.player_achievements
  FOR UPDATE TO authenticated
  USING (auth.uid() = player_id)
  WITH CHECK (auth.uid() = player_id);

CREATE POLICY "Players can insert own achievements" ON public.player_achievements
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = player_id);

-- Enable realtime
ALTER PUBLICATION supabase_realtime ADD TABLE public.player_achievements;

-- Seed achievements
INSERT INTO public.achievements (name, description, category, condition_type, condition_value, reward_crystals, reward_xp, reward_title, icon) VALUES
-- Farming achievements
('First Harvest', 'Harvest your first crop', 'farming', 'harvest_count', 1, 50, 10, null, '🌾'),
('Farmer', 'Harvest 10 crops', 'farming', 'harvest_count', 10, 100, 50, 'Farmer', '🌾'),
('Master Farmer', 'Harvest 100 crops', 'farming', 'harvest_count', 100, 500, 250, 'Master Farmer', '🌾'),
('Crop Collector', 'Harvest 5 different crop types', 'farming', 'crop_variety', 5, 200, 100, 'Crop Collector', '🌽'),
-- Factory achievements
('First Production', 'Complete your first factory production', 'factory', 'produce_count', 1, 50, 10, null, '⚙️'),
('Craftsman', 'Complete 50 factory productions', 'factory', 'produce_count', 50, 300, 150, 'Craftsman', '⚙️'),
('Master Craftsman', 'Complete 500 factory productions', 'factory', 'produce_count', 500, 2000, 1000, 'Master Craftsman', '⚙️'),
('Recipe Master', 'Unlock 5 different recipes', 'factory', 'recipe_variety', 5, 400, 200, 'Recipe Master', '📜'),
-- City achievements
('Builder', 'Place 5 buildings', 'city', 'build_count', 5, 200, 100, 'Builder', '🏗️'),
('Architect', 'Place 20 buildings', 'city', 'build_count', 20, 1000, 500, 'Architect', '🏛️'),
('Upgrader', 'Upgrade a building to level 3', 'city', 'upgrade_level', 3, 300, 150, 'Upgrader', '⬆️'),
-- Social achievements
('Helper', 'Help 10 friends', 'social', 'help_count', 10, 200, 100, 'Helper', '🤝'),
('Trader', 'Complete 10 trades', 'social', 'trade_count', 10, 300, 150, 'Trader', '💼'),
-- General achievements
('Level Up', 'Reach level 5', 'general', 'player_level', 5, 200, 100, null, '⭐'),
('Crystal Collector', 'Earn 1000 crystals', 'general', 'crystals_earned', 1000, 500, 250, 'Crystal Collector', '💎'),
('Daily Player', 'Claim daily reward 7 days in a row', 'general', 'daily_streak', 7, 500, 250, 'Daily Player', '📅'),
-- Mining achievements
('First Dig', 'Mine your first ore', 'general', 'mine_count', 1, 50, 10, null, '⛏️'),
('Miner', 'Mine 50 ores', 'general', 'mine_count', 50, 300, 150, 'Miner', '⛏️'),
('Master Miner', 'Mine 500 ores', 'general', 'mine_count', 500, 2000, 1000, 'Master Miner', '⛏️'),
('Deep Explorer', 'Reach depth 100', 'general', 'mine_depth', 100, 1000, 500, 'Deep Explorer', '🕳️')
ON CONFLICT (name) DO NOTHING;

-- Function to check and update achievements
CREATE OR REPLACE FUNCTION public.check_achievements(p_condition_type text, p_increment integer DEFAULT 1)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_achievement record;
  v_current_progress integer;
  v_new_progress integer;
BEGIN
  -- Find all achievements matching the condition type
  FOR v_achievement IN
    SELECT * FROM public.achievements
    WHERE condition_type = p_condition_type
  LOOP
    -- Get or create player achievement progress
    SELECT progress INTO v_current_progress
    FROM public.player_achievements
    WHERE player_id = v_player_id AND achievement_id = v_achievement.id;

    IF NOT FOUND THEN
      -- Create new progress entry
      INSERT INTO public.player_achievements (player_id, achievement_id, progress)
      VALUES (v_player_id, v_achievement.id, p_increment);
      v_new_progress := p_increment;
    ELSE
      -- Update progress
      v_new_progress := v_current_progress + p_increment;
      UPDATE public.player_achievements
      SET progress = v_new_progress
      WHERE player_id = v_player_id AND achievement_id = v_achievement.id;
    END IF;

    -- Check if achievement is completed
    IF v_new_progress >= v_achievement.condition_value AND NOT EXISTS (
      SELECT 1 FROM public.player_achievements
      WHERE player_id = v_player_id AND achievement_id = v_achievement.id AND completed = true
    ) THEN
      -- Mark as completed
      UPDATE public.player_achievements
      SET completed = true, completed_at = now()
      WHERE player_id = v_player_id AND achievement_id = v_achievement.id;
    END IF;
  END LOOP;
END;
$$;

COMMENT ON FUNCTION public.check_achievements(text, integer) IS 'Check and update achievement progress for a condition type';

-- Function to claim achievement reward
CREATE OR REPLACE FUNCTION public.claim_achievement(p_achievement_id integer)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_achievement record;
  v_player_achievement record;
  v_result jsonb;
BEGIN
  -- Get achievement
  SELECT * INTO v_achievement
  FROM public.achievements
  WHERE id = p_achievement_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Achievement % not found', p_achievement_id;
  END IF;

  -- Get player achievement
  SELECT * INTO v_player_achievement
  FROM public.player_achievements
  WHERE player_id = v_player_id AND achievement_id = p_achievement_id;

  IF NOT FOUND OR NOT v_player_achievement.completed THEN
    RAISE EXCEPTION 'Achievement % is not completed', p_achievement_id;
  END IF;

  IF v_player_achievement.claimed THEN
    RAISE EXCEPTION 'Achievement % reward already claimed', p_achievement_id;
  END IF;

  -- Award rewards
  IF v_achievement.reward_crystals > 0 THEN
    UPDATE public.profiles
    SET crystals = crystals + v_achievement.reward_crystals
    WHERE id = v_player_id;
  END IF;

  IF v_achievement.reward_xp > 0 THEN
    UPDATE public.profiles
    SET xp = xp + v_achievement.reward_xp
    WHERE id = v_player_id;
  END IF;

  -- Mark as claimed
  UPDATE public.player_achievements
  SET claimed = true, claimed_at = now()
  WHERE player_id = v_player_id AND achievement_id = p_achievement_id;

  -- Return result
  SELECT jsonb_build_object(
    'success', true,
    'crystals_awarded', v_achievement.reward_crystals,
    'xp_awarded', v_achievement.reward_xp,
    'title', v_achievement.reward_title
  ) INTO v_result;

  RETURN v_result;
END;
$$;

COMMENT ON FUNCTION public.claim_achievement(integer) IS 'Claim achievement reward: awards crystals, XP, and title';

-- Trigger to check achievements on harvest
CREATE OR REPLACE FUNCTION public.check_achievements_on_harvest()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM public.check_achievements('harvest_count', 1);
  RETURN NEW;
END;
$$;

-- Note: We'll call check_achievements manually from RPCs rather than using triggers
-- for better control and to avoid performance issues

