-- Create co-op tasks system for coven enhancements

-- Create coven_tasks table
CREATE TABLE IF NOT EXISTS public.coven_tasks (
  id serial PRIMARY KEY,
  coven_id uuid NOT NULL REFERENCES public.coven(id) ON DELETE CASCADE,
  name text NOT NULL,
  description text NOT NULL,
  objectives jsonb NOT NULL, -- [{type: 'produce', target: 1000, item: 'bread'}, ...]
  rewards jsonb NOT NULL, -- {coven_points: 100, shared_crystals: 500}
  created_by uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  created_at timestamptz DEFAULT now(),
  expires_at timestamptz,
  completed boolean DEFAULT false,
  completed_at timestamptz
);

-- Create coven_task_progress table
CREATE TABLE IF NOT EXISTS public.coven_task_progress (
  task_id integer NOT NULL REFERENCES public.coven_tasks(id) ON DELETE CASCADE,
  player_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  contribution jsonb NOT NULL, -- Same structure as objectives but with current values
  contributed_at timestamptz DEFAULT now(),
  PRIMARY KEY (task_id, player_id)
);

-- Enable RLS
ALTER TABLE public.coven_tasks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.coven_task_progress ENABLE ROW LEVEL SECURITY;

-- Policy: Coven members can view coven tasks
CREATE POLICY "Coven members can view tasks" ON public.coven_tasks
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.coven_members
      WHERE coven_id = coven_tasks.coven_id
        AND player_id = auth.uid()
    )
  );

-- Policy: Leaders and elders can create tasks
CREATE POLICY "Leaders and elders can create tasks" ON public.coven_tasks
  FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.coven_members
      WHERE coven_id = coven_tasks.coven_id
        AND player_id = auth.uid()
        AND role IN ('leader', 'elder')
    )
  );

-- Policy: Leaders and elders can update tasks
CREATE POLICY "Leaders and elders can update tasks" ON public.coven_tasks
  FOR UPDATE TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.coven_members
      WHERE coven_id = coven_tasks.coven_id
        AND player_id = auth.uid()
        AND role IN ('leader', 'elder')
    )
  );

-- Policy: Coven members can view task progress
CREATE POLICY "Coven members can view task progress" ON public.coven_task_progress
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.coven_members cm
      JOIN public.coven_tasks ct ON ct.coven_id = cm.coven_id
      WHERE ct.id = coven_task_progress.task_id
        AND cm.player_id = auth.uid()
    )
  );

-- Policy: Coven members can contribute to tasks
CREATE POLICY "Coven members can contribute to tasks" ON public.coven_task_progress
  FOR INSERT TO authenticated
  WITH CHECK (
    auth.uid() = player_id AND
    EXISTS (
      SELECT 1 FROM public.coven_members cm
      JOIN public.coven_tasks ct ON ct.coven_id = cm.coven_id
      WHERE ct.id = coven_task_progress.task_id
        AND cm.player_id = auth.uid()
    )
  );

CREATE POLICY "Coven members can update own contributions" ON public.coven_task_progress
  FOR UPDATE TO authenticated
  USING (auth.uid() = player_id)
  WITH CHECK (auth.uid() = player_id);

-- Enable realtime
ALTER PUBLICATION supabase_realtime ADD TABLE public.coven_tasks;
ALTER PUBLICATION supabase_realtime ADD TABLE public.coven_task_progress;

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_coven_tasks_coven ON public.coven_tasks(coven_id);
CREATE INDEX IF NOT EXISTS idx_coven_tasks_completed ON public.coven_tasks(completed);
CREATE INDEX IF NOT EXISTS idx_coven_task_progress_task ON public.coven_task_progress(task_id);
CREATE INDEX IF NOT EXISTS idx_coven_task_progress_player ON public.coven_task_progress(player_id);

-- Function to create a coven task
CREATE OR REPLACE FUNCTION public.create_coven_task(
  p_coven_id uuid,
  p_name text,
  p_description text,
  p_objectives jsonb,
  p_rewards jsonb,
  p_expires_hours integer DEFAULT 168 -- Default 7 days
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_member_role text;
  v_task_id integer;
BEGIN
  -- Check if player is leader or elder
  SELECT role INTO v_member_role
  FROM public.coven_members
  WHERE coven_id = p_coven_id AND player_id = v_player_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'You are not a member of this coven';
  END IF;

  IF v_member_role NOT IN ('leader', 'elder') THEN
    RAISE EXCEPTION 'Only leaders and elders can create tasks';
  END IF;

  -- Create task
  INSERT INTO public.coven_tasks (
    coven_id,
    name,
    description,
    objectives,
    rewards,
    created_by,
    expires_at
  )
  VALUES (
    p_coven_id,
    p_name,
    p_description,
    p_objectives,
    p_rewards,
    v_player_id,
    now() + (p_expires_hours || ' hours')::interval
  )
  RETURNING id INTO v_task_id;

  RETURN v_task_id;
END;
$$;

COMMENT ON FUNCTION public.create_coven_task(uuid, text, text, jsonb, jsonb, integer) IS 'Create a coven task (leaders and elders only)';

-- Function to contribute to a coven task
CREATE OR REPLACE FUNCTION public.contribute_to_task(
  p_task_id integer,
  p_objective_type text,
  p_increment integer DEFAULT 1
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_task record;
  v_progress record;
  v_contribution jsonb;
  v_objective jsonb;
  v_current_value integer;
  v_target_value integer;
  v_idx integer;
  v_total_progress jsonb;
  v_all_completed boolean;
BEGIN
  -- Get task
  SELECT * INTO v_task
  FROM public.coven_tasks
  WHERE id = p_task_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Task % not found', p_task_id;
  END IF;

  -- Check if player is member of coven
  IF NOT EXISTS (
    SELECT 1 FROM public.coven_members
    WHERE coven_id = v_task.coven_id AND player_id = v_player_id
  ) THEN
    RAISE EXCEPTION 'You are not a member of this coven';
  END IF;

  IF v_task.completed THEN
    RAISE EXCEPTION 'Task % is already completed', p_task_id;
  END IF;

  IF v_task.expires_at < now() THEN
    RAISE EXCEPTION 'Task % has expired', p_task_id;
  END IF;

  -- Get or create progress
  SELECT * INTO v_progress
  FROM public.coven_task_progress
  WHERE task_id = p_task_id AND player_id = v_player_id;

  IF NOT FOUND THEN
    -- Initialize with zeros
    v_contribution := v_task.objectives;
    FOR v_idx IN 0..jsonb_array_length(v_contribution) - 1 LOOP
      v_contribution := jsonb_set(
        v_contribution,
        ARRAY[v_idx::text, 'current'],
        0::jsonb
      );
    END LOOP;
    
    INSERT INTO public.coven_task_progress (task_id, player_id, contribution)
    VALUES (p_task_id, v_player_id, v_contribution);
    
    v_progress.contribution := v_contribution;
  END IF;

  v_contribution := v_progress.contribution;

  -- Update contribution for matching objective type
  FOR v_idx IN 0..jsonb_array_length(v_contribution) - 1 LOOP
    v_objective := v_contribution->v_idx;
    
    IF (v_objective->>'type') = p_objective_type THEN
      v_current_value := COALESCE((v_objective->>'current')::integer, 0);
      v_target_value := (v_objective->>'target')::integer;
      
      v_current_value := LEAST(v_current_value + p_increment, v_target_value);
      
      v_contribution := jsonb_set(
        v_contribution,
        ARRAY[v_idx::text, 'current'],
        v_current_value::jsonb
      );
    END IF;
  END LOOP;

  -- Update progress
  UPDATE public.coven_task_progress
  SET contribution = v_contribution,
      contributed_at = now()
  WHERE task_id = p_task_id AND player_id = v_player_id;

  -- Calculate total progress across all members (simplified check)

  -- Check if all objectives completed
  v_all_completed := true;
  FOR v_idx IN 0..jsonb_array_length(v_task.objectives) - 1 LOOP
    v_objective := v_task.objectives->v_idx;
    v_target_value := (v_objective->>'target')::integer;
    
    -- Sum contributions from all members for this objective type
    SELECT COALESCE(SUM((elem->>'current')::integer), 0) INTO v_current_value
    FROM public.coven_task_progress,
    LATERAL jsonb_array_elements(contribution) elem
    WHERE task_id = p_task_id
      AND (elem->>'type') = (v_objective->>'type');
    
    IF v_current_value < v_target_value THEN
      v_all_completed := false;
      EXIT;
    END IF;
  END LOOP;

  -- Mark task as completed if all objectives met
  IF v_all_completed AND NOT v_task.completed THEN
    UPDATE public.coven_tasks
    SET completed = true,
        completed_at = now()
    WHERE id = p_task_id;

    -- Award rewards to coven
    IF v_task.rewards ? 'shared_crystals' THEN
      UPDATE public.coven_resources
      SET crystals = crystals + (v_task.rewards->>'shared_crystals')::bigint
      WHERE coven_id = v_task.coven_id;
    END IF;
  END IF;
END;
$$;

COMMENT ON FUNCTION public.contribute_to_task(integer, text, integer) IS 'Contribute to a coven task: updates player progress and checks for completion';

-- Function to claim task rewards (distribute to members)
CREATE OR REPLACE FUNCTION public.claim_coven_task_rewards(p_task_id integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_task record;
  v_member_count integer;
  v_crystals_per_member bigint;
  v_member record;
BEGIN
  -- Get task
  SELECT * INTO v_task
  FROM public.coven_tasks
  WHERE id = p_task_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Task % not found', p_task_id;
  END IF;

  -- Check if player is leader or elder
  IF NOT EXISTS (
    SELECT 1 FROM public.coven_members
    WHERE coven_id = v_task.coven_id
      AND player_id = v_player_id
      AND role IN ('leader', 'elder')
  ) THEN
    RAISE EXCEPTION 'Only leaders and elders can claim rewards';
  END IF;

  IF NOT v_task.completed THEN
    RAISE EXCEPTION 'Task % is not completed', p_task_id;
  END IF;

  -- Get member count
  SELECT count(*) INTO v_member_count
  FROM public.coven_members
  WHERE coven_id = v_task.coven_id;

  -- Distribute shared crystals
  IF v_task.rewards ? 'shared_crystals' AND v_member_count > 0 THEN
    v_crystals_per_member := (v_task.rewards->>'shared_crystals')::bigint / v_member_count;

    -- Award to all members
    FOR v_member IN
      SELECT player_id FROM public.coven_members WHERE coven_id = v_task.coven_id
    LOOP
      UPDATE public.profiles
      SET crystals = crystals + v_crystals_per_member
      WHERE id = v_member.player_id;
    END LOOP;
  END IF;
END;
$$;

COMMENT ON FUNCTION public.claim_coven_task_rewards(integer) IS 'Claim and distribute coven task rewards to all members';

-- Helper function to auto-contribute to active coven tasks
CREATE OR REPLACE FUNCTION public.auto_contribute_coven_tasks(
  p_objective_type text,
  p_increment integer DEFAULT 1
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_coven_id uuid;
  v_task record;
BEGIN
  -- Get player's coven
  SELECT coven_id INTO v_coven_id
  FROM public.coven_members
  WHERE player_id = v_player_id
  LIMIT 1;

  IF v_coven_id IS NULL THEN
    RETURN; -- Not in a coven, silently exit
  END IF;

  -- Find active tasks for this coven
  FOR v_task IN
    SELECT * FROM public.coven_tasks
    WHERE coven_id = v_coven_id
      AND completed = false
      AND (expires_at IS NULL OR expires_at > now())
  LOOP
    -- Check if task has this objective type
    IF EXISTS (
      SELECT 1 FROM jsonb_array_elements(v_task.objectives) obj
      WHERE (obj->>'type') = p_objective_type
    ) THEN
      -- Contribute to task
      PERFORM public.contribute_to_task(v_task.id, p_objective_type, p_increment);
    END IF;
  END LOOP;
END;
$$;

COMMENT ON FUNCTION public.auto_contribute_coven_tasks(text, integer) IS 'Automatically contribute to active coven tasks for the player';

