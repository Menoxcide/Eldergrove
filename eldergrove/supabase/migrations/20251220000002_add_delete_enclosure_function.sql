-- Add function to delete enclosures (only if empty)

-- Function to delete an enclosure (only if both slots are empty)
CREATE OR REPLACE FUNCTION public.delete_enclosure(p_enclosure_id integer)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_player_id uuid := auth.uid();
  v_enclosure record;
  v_result jsonb;
BEGIN
  -- Get enclosure
  SELECT * INTO v_enclosure
  FROM public.zoo_enclosures
  WHERE id = p_enclosure_id AND player_id = v_player_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Enclosure % not found or does not belong to this player', p_enclosure_id;
  END IF;

  -- Check if enclosure is empty (both slots must be NULL)
  IF v_enclosure.animal1_id IS NOT NULL OR v_enclosure.animal2_id IS NOT NULL THEN
    RAISE EXCEPTION 'Cannot delete enclosure: it still contains animals. Please remove all animals first.';
  END IF;

  -- Check if breeding is in progress
  IF v_enclosure.breeding_started_at IS NOT NULL THEN
    RAISE EXCEPTION 'Cannot delete enclosure: breeding is in progress. Please wait for breeding to complete.';
  END IF;

  -- Delete the enclosure
  DELETE FROM public.zoo_enclosures
  WHERE id = p_enclosure_id AND player_id = v_player_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Failed to delete enclosure %', p_enclosure_id;
  END IF;

  -- Return success
  SELECT jsonb_build_object(
    'success', true,
    'enclosure_name', v_enclosure.enclosure_name
  ) INTO v_result;

  RETURN v_result;
END;
$$;

COMMENT ON FUNCTION public.delete_enclosure(integer) IS 'Delete an empty enclosure. Both animal slots must be empty and no breeding in progress.';
