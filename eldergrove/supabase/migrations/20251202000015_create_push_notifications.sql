-- Create push notifications system

-- Create push_subscriptions table to store device tokens
CREATE TABLE IF NOT EXISTS public.push_subscriptions (
  id serial PRIMARY KEY,
  player_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  endpoint text NOT NULL,
  p256dh text NOT NULL,
  auth text NOT NULL,
  device_info jsonb,
  created_at timestamptz DEFAULT now(),
  last_used_at timestamptz DEFAULT now(),
  UNIQUE(player_id, endpoint)
);

-- Create notification_preferences table
CREATE TABLE IF NOT EXISTS public.notification_preferences (
  player_id uuid PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
  crops_ready boolean DEFAULT true,
  factory_complete boolean DEFAULT true,
  orders_expiring boolean DEFAULT true,
  quest_available boolean DEFAULT true,
  friend_help boolean DEFAULT true,
  coven_task_complete boolean DEFAULT true,
  updated_at timestamptz DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.push_subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notification_preferences ENABLE ROW LEVEL SECURITY;

-- Policy: Players can manage own subscriptions
CREATE POLICY "Players can view own subscriptions" ON public.push_subscriptions
  FOR SELECT TO authenticated
  USING (auth.uid() = player_id);

CREATE POLICY "Players can insert own subscriptions" ON public.push_subscriptions
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = player_id);

CREATE POLICY "Players can update own subscriptions" ON public.push_subscriptions
  FOR UPDATE TO authenticated
  USING (auth.uid() = player_id)
  WITH CHECK (auth.uid() = player_id);

CREATE POLICY "Players can delete own subscriptions" ON public.push_subscriptions
  FOR DELETE TO authenticated
  USING (auth.uid() = player_id);

-- Policy: Players can manage own preferences
CREATE POLICY "Players can view own preferences" ON public.notification_preferences
  FOR SELECT TO authenticated
  USING (auth.uid() = player_id);

CREATE POLICY "Players can insert own preferences" ON public.notification_preferences
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = player_id);

CREATE POLICY "Players can update own preferences" ON public.notification_preferences
  FOR UPDATE TO authenticated
  USING (auth.uid() = player_id)
  WITH CHECK (auth.uid() = player_id);

-- Function to register push subscription
CREATE OR REPLACE FUNCTION public.register_push_subscription(
  p_endpoint text,
  p_p256dh text,
  p_auth text,
  p_device_info jsonb DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
BEGIN
  INSERT INTO public.push_subscriptions (
    player_id,
    endpoint,
    p256dh,
    auth,
    device_info
  )
  VALUES (
    v_player_id,
    p_endpoint,
    p_p256dh,
    p_auth,
    p_device_info
  )
  ON CONFLICT (player_id, endpoint) DO UPDATE SET
    p256dh = EXCLUDED.p256dh,
    auth = EXCLUDED.auth,
    device_info = EXCLUDED.device_info,
    last_used_at = now();

  -- Initialize preferences if not exists
  INSERT INTO public.notification_preferences (player_id)
  VALUES (v_player_id)
  ON CONFLICT (player_id) DO NOTHING;
END;
$$;

COMMENT ON FUNCTION public.register_push_subscription(text, text, text, jsonb) IS 'Register a push notification subscription for the current user';

-- Function to update notification preferences
CREATE OR REPLACE FUNCTION public.update_notification_preferences(
  p_crops_ready boolean DEFAULT NULL,
  p_factory_complete boolean DEFAULT NULL,
  p_orders_expiring boolean DEFAULT NULL,
  p_quest_available boolean DEFAULT NULL,
  p_friend_help boolean DEFAULT NULL,
  p_coven_task_complete boolean DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_player_id uuid := auth.uid();
BEGIN
  INSERT INTO public.notification_preferences (player_id)
  VALUES (v_player_id)
  ON CONFLICT (player_id) DO NOTHING;

  UPDATE public.notification_preferences
  SET
    crops_ready = COALESCE(p_crops_ready, crops_ready),
    factory_complete = COALESCE(p_factory_complete, factory_complete),
    orders_expiring = COALESCE(p_orders_expiring, orders_expiring),
    quest_available = COALESCE(p_quest_available, quest_available),
    friend_help = COALESCE(p_friend_help, friend_help),
    coven_task_complete = COALESCE(p_coven_task_complete, coven_task_complete),
    updated_at = now()
  WHERE player_id = v_player_id;
END;
$$;

COMMENT ON FUNCTION public.update_notification_preferences(boolean, boolean, boolean, boolean, boolean, boolean) IS 'Update notification preferences for the current user';

-- Function to get subscriptions for a player (for server-side notification sending)
CREATE OR REPLACE FUNCTION public.get_player_subscriptions(p_player_id uuid)
RETURNS TABLE (
  endpoint text,
  p256dh text,
  auth text
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT ps.endpoint, ps.p256dh, ps.auth
  FROM public.push_subscriptions ps
  JOIN public.notification_preferences np ON np.player_id = ps.player_id
  WHERE ps.player_id = p_player_id
    AND ps.last_used_at > now() - interval '30 days'; -- Only active subscriptions
END;
$$;

COMMENT ON FUNCTION public.get_player_subscriptions(uuid) IS 'Get active push subscriptions for a player (server-side use)';

