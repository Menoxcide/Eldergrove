-- Convert regatta and coven points to XP for level progression

-- Update submit_regatta_task to grant XP when points are awarded
-- Conversion: 1 regatta point = 10 XP
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
  v_xp_gained integer;
  v_levels_gained integer;
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

  -- Grant XP: 1 regatta point = 10 XP
  v_xp_gained := v_points * 10;
  v_levels_gained := public.grant_xp(v_player_id, v_xp_gained);

  -- Return result
  SELECT jsonb_build_object(
    'success', true,
    'points_awarded', v_points,
    'total_points', v_participant.points + v_points,
    'xp_gained', v_xp_gained,
    'levels_gained', v_levels_gained
  ) INTO v_result;

  RETURN v_result;
END;
$$;

COMMENT ON FUNCTION public.submit_regatta_task(integer, integer) IS 'Submit completion of a regatta task. Awards XP for level progression (1 point = 10 XP).';

-- Update contribute_to_task to grant XP when coven task is completed
-- Grant XP to all contributing members when task completes
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
  v_coven_points integer;
  v_xp_per_member integer;
  v_member record;
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

    -- Grant XP to all contributing members when task completes
    -- Conversion: 1 coven point = 10 XP, divided among all members
    IF v_task.rewards ? 'coven_points' THEN
      v_coven_points := (v_task.rewards->>'coven_points')::integer;
      
      -- Get member count
      SELECT COUNT(*) INTO v_idx
      FROM public.coven_members
      WHERE coven_id = v_task.coven_id;
      
      IF v_idx > 0 THEN
        -- Calculate XP per member (total XP divided equally)
        v_xp_per_member := (v_coven_points * 10) / v_idx;
        
        -- Grant XP to all members who contributed
        FOR v_member IN
          SELECT DISTINCT player_id 
          FROM public.coven_task_progress 
          WHERE task_id = p_task_id
        LOOP
          PERFORM public.grant_xp(v_member.player_id, v_xp_per_member);
        END LOOP;
      END IF;
    END IF;
  END IF;
END;
$$;

COMMENT ON FUNCTION public.contribute_to_task(integer, text, integer) IS 'Contribute to a coven task: updates player progress and checks for completion. Awards XP to all contributors when task completes (1 coven point = 10 XP per member).';

