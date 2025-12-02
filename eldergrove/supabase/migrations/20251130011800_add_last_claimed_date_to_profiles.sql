-- Add last_claimed_date column to profiles table for daily reward tracking
alter table public.profiles
add column last_claimed_date date;

comment on column public.profiles.last_claimed_date is 'Date when player last claimed their daily reward';

-- Create RPC function for claiming daily rewards
CREATE OR REPLACE FUNCTION public.claim_daily_reward()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_user_id uuid;
  v_today date;
  v_last_claimed date;
  v_current_crystals integer;
  v_reward_crystals integer := 500;
  v_new_crystals integer;
BEGIN
  -- Get current user ID
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'message', 'No authenticated user'
    );
  END IF;

  v_today := CURRENT_DATE;

  -- Get current profile data
  SELECT last_claimed_date, crystals
  INTO v_last_claimed, v_current_crystals
  FROM public.profiles
  WHERE id = v_user_id;

  -- Check if already claimed today
  IF v_last_claimed = v_today THEN
    RETURN jsonb_build_object(
      'success', true,
      'message', 'Daily reward already claimed today',
      'alreadyClaimed', true
    );
  END IF;

  -- Calculate new crystal total
  v_new_crystals := v_current_crystals + v_reward_crystals;

  -- Update profile
  UPDATE public.profiles
  SET
    crystals = v_new_crystals,
    last_claimed_date = v_today
  WHERE id = v_user_id;

  RETURN jsonb_build_object(
    'success', true,
    'message', format('Successfully claimed %s crystals!', v_reward_crystals),
    'crystalsAwarded', v_reward_crystals,
    'alreadyClaimed', false
  );
END;
$$;

COMMENT ON FUNCTION public.claim_daily_reward() IS 'Claim daily reward of 500 crystals for authenticated user. Can only be claimed once per day.';