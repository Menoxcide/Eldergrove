-- Create regatta competitions system (weekly competitive events)

-- Create regatta_events table
CREATE TABLE IF NOT EXISTS public.regatta_events (
  id serial PRIMARY KEY,
  name text NOT NULL,
  start_date timestamptz NOT NULL,
  end_date timestamptz NOT NULL,
  tasks jsonb NOT NULL, -- [{type: 'produce', target: 1000, item: 'bread'}, ...]
  rewards jsonb NOT NULL, -- {top_10: {crystals: 1000}, top_25: {crystals: 500}, participation: {crystals: 100}}
  status text DEFAULT 'upcoming' CHECK (status IN ('upcoming', 'active', 'completed')),
  created_at timestamptz DEFAULT now()
);

-- Create regatta_participants table
CREATE TABLE IF NOT EXISTS public.regatta_participants (
  regatta_id integer NOT NULL REFERENCES public.regatta_events(id) ON DELETE CASCADE,
  player_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  coven_id uuid REFERENCES public.coven(id) ON DELETE SET NULL,
  points integer DEFAULT 0,
  tasks_completed jsonb DEFAULT '[]'::jsonb, -- Array of completed task IDs
  joined_at timestamptz DEFAULT now(),
  PRIMARY KEY (regatta_id, player_id)
);

-- Create regatta_task_submissions table
CREATE TABLE IF NOT EXISTS public.regatta_task_submissions (
  id serial PRIMARY KEY,
  regatta_id integer NOT NULL REFERENCES public.regatta_events(id) ON DELETE CASCADE,
  player_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  task_index integer NOT NULL, -- Index in the tasks array
  submitted_at timestamptz DEFAULT now(),
  points_awarded integer DEFAULT 0,
  UNIQUE(regatta_id, player_id, task_index)
);

-- Enable RLS
ALTER TABLE public.regatta_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.regatta_participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.regatta_task_submissions ENABLE ROW LEVEL SECURITY;

-- Policy: Anyone can view active/upcoming regattas
CREATE POLICY "Anyone can view regattas" ON public.regatta_events
  FOR SELECT TO authenticated
  USING (status IN ('upcoming', 'active'));

-- Policy: Players can view own participation
CREATE POLICY "Players can view own participation" ON public.regatta_participants
  FOR SELECT TO authenticated
  USING (auth.uid() = player_id OR EXISTS (
    SELECT 1 FROM public.coven_members
    WHERE coven_id = regatta_participants.coven_id AND player_id = auth.uid()
  ));

CREATE POLICY "Players can insert own participation" ON public.regatta_participants
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = player_id);

CREATE POLICY "Players can update own participation" ON public.regatta_participants
  FOR UPDATE TO authenticated
  USING (auth.uid() = player_id)
  WITH CHECK (auth.uid() = player_id);

-- Policy: Players can view own submissions
CREATE POLICY "Players can view own submissions" ON public.regatta_task_submissions
  FOR SELECT TO authenticated
  USING (auth.uid() = player_id);

CREATE POLICY "Players can insert own submissions" ON public.regatta_task_submissions
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = player_id);

-- Enable realtime
ALTER PUBLICATION supabase_realtime ADD TABLE public.regatta_events;
ALTER PUBLICATION supabase_realtime ADD TABLE public.regatta_participants;
ALTER PUBLICATION supabase_realtime ADD TABLE public.regatta_task_submissions;

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_regatta_events_status ON public.regatta_events(status);
CREATE INDEX IF NOT EXISTS idx_regatta_events_dates ON public.regatta_events(start_date, end_date);
CREATE INDEX IF NOT EXISTS idx_regatta_participants_regatta ON public.regatta_participants(regatta_id);
CREATE INDEX IF NOT EXISTS idx_regatta_participants_points ON public.regatta_participants(regatta_id, points DESC);
CREATE INDEX IF NOT EXISTS idx_regatta_participants_coven ON public.regatta_participants(regatta_id, coven_id, points DESC);

-- Function to join regatta
CREATE OR REPLACE FUNCTION public.join_regatta(p_regatta_id integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_regatta record;
  v_coven_id uuid;
BEGIN
  -- Get regatta
  SELECT * INTO v_regatta
  FROM public.regatta_events
  WHERE id = p_regatta_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Regatta % not found', p_regatta_id;
  END IF;

  IF v_regatta.status != 'active' THEN
    RAISE EXCEPTION 'Regatta % is not active', p_regatta_id;
  END IF;

  IF now() < v_regatta.start_date OR now() > v_regatta.end_date THEN
    RAISE EXCEPTION 'Regatta % is not currently running', p_regatta_id;
  END IF;

  -- Check if already joined
  IF EXISTS (
    SELECT 1 FROM public.regatta_participants
    WHERE regatta_id = p_regatta_id AND player_id = v_player_id
  ) THEN
    RAISE EXCEPTION 'Already joined regatta %', p_regatta_id;
  END IF;

  -- Get player's coven (optional)
  SELECT coven_id INTO v_coven_id
  FROM public.coven_members
  WHERE player_id = v_player_id
  LIMIT 1;

  -- Join regatta
  INSERT INTO public.regatta_participants (regatta_id, player_id, coven_id, points)
  VALUES (p_regatta_id, v_player_id, v_coven_id, 0);
END;
$$;

COMMENT ON FUNCTION public.join_regatta(integer) IS 'Join an active regatta competition';

-- Function to submit regatta task
CREATE OR REPLACE FUNCTION public.submit_regatta_task(
  p_regatta_id integer,
  p_task_index integer
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_regatta record;
  v_participant record;
  v_task jsonb;
  v_points integer;
  v_result jsonb;
BEGIN
  -- Get regatta
  SELECT * INTO v_regatta
  FROM public.regatta_events
  WHERE id = p_regatta_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Regatta % not found', p_regatta_id;
  END IF;

  IF v_regatta.status != 'active' THEN
    RAISE EXCEPTION 'Regatta % is not active', p_regatta_id;
  END IF;

  -- Get participant
  SELECT * INTO v_participant
  FROM public.regatta_participants
  WHERE regatta_id = p_regatta_id AND player_id = v_player_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'You have not joined regatta %', p_regatta_id;
  END IF;

  -- Check if already submitted
  IF EXISTS (
    SELECT 1 FROM public.regatta_task_submissions
    WHERE regatta_id = p_regatta_id
      AND player_id = v_player_id
      AND task_index = p_task_index
  ) THEN
    RAISE EXCEPTION 'Task % already submitted', p_task_index;
  END IF;

  -- Get task
  SELECT value INTO v_task
  FROM jsonb_array_elements(v_regatta.tasks) WITH ORDINALITY AS t(value, idx)
  WHERE idx - 1 = p_task_index;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Task index % not found', p_task_index;
  END IF;

  -- Calculate points (based on task difficulty)
  v_points := COALESCE((v_task->>'points')::integer, 100);

  -- Record submission
  INSERT INTO public.regatta_task_submissions (regatta_id, player_id, task_index, points_awarded)
  VALUES (p_regatta_id, v_player_id, p_task_index, v_points);

  -- Update participant points
  UPDATE public.regatta_participants
  SET points = points + v_points,
      tasks_completed = tasks_completed || jsonb_build_array(p_task_index)
  WHERE regatta_id = p_regatta_id AND player_id = v_player_id;

  -- Return result
  SELECT jsonb_build_object(
    'success', true,
    'points_awarded', v_points,
    'total_points', v_participant.points + v_points
  ) INTO v_result;

  RETURN v_result;
END;
$$;

COMMENT ON FUNCTION public.submit_regatta_task(integer, integer) IS 'Submit completion of a regatta task';

-- Function to get regatta leaderboard
CREATE OR REPLACE FUNCTION public.get_regatta_leaderboard(
  p_regatta_id integer,
  p_leaderboard_type text DEFAULT 'global' -- 'global' or 'coven'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_result jsonb;
BEGIN
  IF p_leaderboard_type = 'coven' THEN
    -- Coven leaderboard
    SELECT jsonb_agg(
      jsonb_build_object(
        'coven_id', coven_id,
        'coven_name', (SELECT name FROM public.coven WHERE id = coven_id),
        'total_points', SUM(points),
        'member_count', count(*)
      ) ORDER BY SUM(points) DESC
    )
    INTO v_result
    FROM public.regatta_participants
    WHERE regatta_id = p_regatta_id
      AND coven_id IS NOT NULL
    GROUP BY coven_id;
  ELSE
    -- Global leaderboard
    SELECT jsonb_agg(
      jsonb_build_object(
        'player_id', player_id,
        'username', (SELECT username FROM public.profiles WHERE id = player_id),
        'points', points,
        'coven_id', coven_id,
        'coven_name', CASE WHEN coven_id IS NOT NULL THEN (SELECT name FROM public.coven WHERE id = coven_id) ELSE NULL END
      ) ORDER BY points DESC
    )
    INTO v_result
    FROM public.regatta_participants
    WHERE regatta_id = p_regatta_id
    ORDER BY points DESC
    LIMIT 100;
  END IF;

  RETURN COALESCE(v_result, '[]'::jsonb);
END;
$$;

COMMENT ON FUNCTION public.get_regatta_leaderboard(integer, text) IS 'Get regatta leaderboard (global or coven)';

-- Function to claim regatta rewards
CREATE OR REPLACE FUNCTION public.claim_regatta_rewards(p_regatta_id integer)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_regatta record;
  v_participant record;
  v_total_participants integer;
  v_player_rank integer;
  v_reward jsonb;
  v_crystals integer;
BEGIN
  -- Get regatta
  SELECT * INTO v_regatta
  FROM public.regatta_events
  WHERE id = p_regatta_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Regatta % not found', p_regatta_id;
  END IF;

  IF v_regatta.status != 'completed' THEN
    RAISE EXCEPTION 'Regatta % is not completed yet', p_regatta_id;
  END IF;

  -- Get participant
  SELECT * INTO v_participant
  FROM public.regatta_participants
  WHERE regatta_id = p_regatta_id AND player_id = v_player_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'You did not participate in regatta %', p_regatta_id;
  END IF;

  -- Calculate rank
  SELECT count(*) INTO v_total_participants
  FROM public.regatta_participants
  WHERE regatta_id = p_regatta_id;

  SELECT count(*) + 1 INTO v_player_rank
  FROM public.regatta_participants
  WHERE regatta_id = p_regatta_id
    AND points > v_participant.points;

  -- Determine reward tier
  IF v_player_rank <= v_total_participants * 0.1 THEN
    -- Top 10%
    v_reward := v_regatta.rewards->'top_10';
  ELSIF v_player_rank <= v_total_participants * 0.25 THEN
    -- Top 25%
    v_reward := v_regatta.rewards->'top_25';
  ELSE
    -- Participation
    v_reward := v_regatta.rewards->'participation';
  END IF;

  -- Award crystals
  IF v_reward ? 'crystals' THEN
    v_crystals := (v_reward->>'crystals')::integer;
    UPDATE public.profiles
    SET crystals = crystals + v_crystals
    WHERE id = v_player_id;
  END IF;

  -- Return result
  RETURN jsonb_build_object(
    'success', true,
    'rank', v_player_rank,
    'total_participants', v_total_participants,
    'crystals_awarded', v_crystals
  );
END;
$$;

COMMENT ON FUNCTION public.claim_regatta_rewards(integer) IS 'Claim regatta rewards based on final rank';

-- Function to create weekly regatta (to be called by cron or admin)
CREATE OR REPLACE FUNCTION public.create_weekly_regatta()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_regatta_id integer;
  v_start_date timestamptz;
  v_end_date timestamptz;
BEGIN
  -- Start next Monday, end next Sunday
  v_start_date := date_trunc('week', now() + interval '1 week') + interval '1 day'; -- Monday
  v_end_date := v_start_date + interval '6 days'; -- Sunday

  -- Create regatta with default tasks
  INSERT INTO public.regatta_events (
    name,
    start_date,
    end_date,
    tasks,
    rewards,
    status
  )
  VALUES (
    'Weekly Regatta - ' || to_char(v_start_date, 'Month YYYY'),
    v_start_date,
    v_end_date,
    '[
      {"type": "produce", "target": 100, "item": "bread", "points": 50},
      {"type": "harvest", "target": 200, "points": 30},
      {"type": "mine", "target": 50, "points": 40},
      {"type": "order", "target": 10, "points": 60}
    ]'::jsonb,
    '{
      "top_10": {"crystals": 2000},
      "top_25": {"crystals": 1000},
      "participation": {"crystals": 200}
    }'::jsonb,
    'upcoming'
  )
  RETURNING id INTO v_regatta_id;

  RETURN v_regatta_id;
END;
$$;

COMMENT ON FUNCTION public.create_weekly_regatta() IS 'Create a weekly regatta event (to be called by cron)';

