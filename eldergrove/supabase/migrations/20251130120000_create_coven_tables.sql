-- Create coven table
CREATE TABLE public.coven (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text UNIQUE NOT NULL,
  emblem text,
  leader_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  created_at timestamptz DEFAULT now(),
  -- Enhanced columns
  description TEXT,
  visibility TEXT DEFAULT 'public' CHECK (visibility IN ('public', 'private', 'invite_only')),
  member_count INTEGER DEFAULT 0,
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  deleted_at TIMESTAMPTZ
);

-- Create coven_members table
CREATE TABLE public.coven_members (
  coven_id uuid NOT NULL REFERENCES public.coven(id) ON DELETE CASCADE,
  player_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  role text DEFAULT 'member' CHECK (role IN ('member', 'elder', 'leader')),
  contribution bigint DEFAULT 0,
  joined_at timestamptz DEFAULT now(),
  PRIMARY KEY (coven_id, player_id),
  -- Enhanced columns
  invited_by UUID REFERENCES public.profiles(id),
  invite_accepted_at TIMESTAMPTZ,
  last_active TIMESTAMPTZ,
  title TEXT,
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Create coven_invitations table
CREATE TABLE public.coven_invitations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  coven_id UUID NOT NULL REFERENCES public.coven(id) ON DELETE CASCADE,
  inviter_id UUID NOT NULL REFERENCES public.profiles(id),
  invitee_id UUID NOT NULL REFERENCES public.profiles(id),
  status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'declined', 'cancelled')),
  message TEXT,
  expires_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Create coven_resources table
CREATE TABLE public.coven_resources (
  coven_id UUID PRIMARY KEY REFERENCES public.coven(id) ON DELETE CASCADE,
  crystals BIGINT DEFAULT 0,
  herbs BIGINT DEFAULT 0,
  runes BIGINT DEFAULT 0,
  artifacts BIGINT DEFAULT 0,
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Create coven_activity_log table
CREATE TABLE public.coven_activity_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  coven_id UUID NOT NULL REFERENCES public.coven(id) ON DELETE CASCADE,
  actor_id UUID NOT NULL REFERENCES public.profiles(id),
  action TEXT NOT NULL,
  target_type TEXT,
  target_id UUID,
  metadata JSONB,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Create indexes for coven table
CREATE INDEX idx_coven_leader_id ON public.coven(leader_id);
CREATE INDEX idx_coven_visibility ON public.coven(visibility);
CREATE INDEX idx_coven_member_count ON public.coven(member_count);
CREATE INDEX idx_coven_updated_at ON public.coven(updated_at);

-- Create indexes for coven_members table
CREATE INDEX idx_coven_members_player_id ON public.coven_members(player_id);
CREATE INDEX idx_coven_members_coven_id ON public.coven_members(coven_id);
CREATE INDEX idx_coven_members_role ON public.coven_members(role);
CREATE INDEX idx_coven_members_last_active ON public.coven_members(last_active);
CREATE INDEX idx_coven_members_contribution ON public.coven_members(contribution);

-- Create indexes for coven_invitations table
CREATE INDEX idx_coven_invitations_coven_id ON public.coven_invitations(coven_id);
CREATE INDEX idx_coven_invitations_invitee_id ON public.coven_invitations(invitee_id);
CREATE INDEX idx_coven_invitations_status ON public.coven_invitations(status);

-- Create indexes for coven_activity_log table
CREATE INDEX idx_coven_activity_log_coven_id ON public.coven_activity_log(coven_id);
CREATE INDEX idx_coven_activity_log_actor_id ON public.coven_activity_log(actor_id);
CREATE INDEX idx_coven_activity_log_action ON public.coven_activity_log(action);
CREATE INDEX idx_coven_activity_log_created_at ON public.coven_activity_log(created_at);

-- Enable RLS on coven table
ALTER TABLE public.coven ENABLE ROW LEVEL SECURITY;

-- Policy: Read access based on visibility settings
DROP POLICY IF EXISTS "Enable conditional read access on coven" ON public.coven;
CREATE POLICY "Enable conditional read access on coven"
  ON public.coven
  FOR SELECT
  TO authenticated
  USING (
    visibility = 'public' OR
    EXISTS (
      SELECT 1 FROM public.coven_members cm
      WHERE cm.coven_id = coven.id AND cm.player_id = auth.uid()
    ) OR
    EXISTS (
      SELECT 1 FROM public.coven_invitations ci
      WHERE ci.coven_id = coven.id AND ci.invitee_id = auth.uid() AND ci.status = 'pending'
    )
  );

-- Policy: Leaders can update their own coven
DROP POLICY IF EXISTS "Leaders can update own coven" ON public.coven;
CREATE POLICY "Leaders can update own coven"
  ON public.coven
  FOR UPDATE
  TO authenticated
  USING (leader_id = auth.uid())
  WITH CHECK (leader_id = auth.uid());

-- Policy: Authenticated users can create covens (they become leader)
DROP POLICY IF EXISTS "Users can create coven" ON public.coven;
CREATE POLICY "Users can create coven"
  ON public.coven
  FOR INSERT
  TO authenticated
  WITH CHECK (leader_id = auth.uid());

-- Enable RLS on coven_members table
ALTER TABLE public.coven_members ENABLE ROW LEVEL SECURITY;

-- Policy: Members can view members of their coven
DROP POLICY IF EXISTS "Members can view coven members" ON public.coven_members;
CREATE POLICY "Members can view coven members"
  ON public.coven_members
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.coven_members cm
      WHERE cm.coven_id = coven_members.coven_id
      AND cm.player_id = auth.uid()
    )
  );

-- Policy: Users can join covens (insert themselves)
DROP POLICY IF EXISTS "Users can join coven" ON public.coven_members;
CREATE POLICY "Users can join coven"
  ON public.coven_members
  FOR INSERT
  TO authenticated
  WITH CHECK (player_id = auth.uid());

-- Policy: Users can leave their own coven
DROP POLICY IF EXISTS "Users can leave coven" ON public.coven_members;
CREATE POLICY "Users can leave coven"
  ON public.coven_members
  FOR DELETE
  TO authenticated
  USING (player_id = auth.uid());

-- Policy: Leaders can update/delete members (kick, promote, etc.)
DROP POLICY IF EXISTS "Leaders can manage coven members" ON public.coven_members;
CREATE POLICY "Leaders can manage coven members"
  ON public.coven_members
  FOR UPDATE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.coven c
      WHERE c.id = coven_members.coven_id
      AND c.leader_id = auth.uid()
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.coven c
      WHERE c.id = coven_members.coven_id
      AND c.leader_id = auth.uid()
    )
  );

-- Policy: Leaders can delete members (kick)
DROP POLICY IF EXISTS "Leaders can kick coven members" ON public.coven_members;
CREATE POLICY "Leaders can kick coven members"
  ON public.coven_members
  FOR DELETE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.coven c
      WHERE c.id = coven_members.coven_id
      AND c.leader_id = auth.uid()
    )
  );

-- Policy: Members can update their own last_active timestamp
DROP POLICY IF EXISTS "Members can update their last_active" ON public.coven_members;
CREATE POLICY "Members can update their last_active"
  ON public.coven_members
  FOR UPDATE
  TO authenticated
  USING (player_id = auth.uid())
  WITH CHECK (player_id = auth.uid());

-- Enable RLS on coven_invitations table
ALTER TABLE public.coven_invitations ENABLE ROW LEVEL SECURITY;

-- Policy: Users can view their own invitations
DROP POLICY IF EXISTS "Users can view their invitations" ON public.coven_invitations;
CREATE POLICY "Users can view their invitations"
  ON public.coven_invitations
  FOR SELECT
  TO authenticated
  USING (invitee_id = auth.uid());

-- Policy: Leaders/elders can view invitations for their coven
DROP POLICY IF EXISTS "Leaders can view coven invitations" ON public.coven_invitations;
CREATE POLICY "Leaders can view coven invitations"
  ON public.coven_invitations
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.coven_members cm
      WHERE cm.coven_id = coven_invitations.coven_id
      AND cm.player_id = auth.uid()
      AND cm.role IN ('leader', 'elder')
    )
  );

-- Policy: Leaders/elders can create invitations for their coven
DROP POLICY IF EXISTS "Leaders can create coven invitations" ON public.coven_invitations;
CREATE POLICY "Leaders can create coven invitations"
  ON public.coven_invitations
  FOR INSERT
  TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.coven_members cm
      WHERE cm.coven_id = coven_invitations.coven_id
      AND cm.player_id = auth.uid()
      AND cm.role IN ('leader', 'elder')
    )
  );

-- Policy: Users can update their own invitations (accept/decline)
DROP POLICY IF EXISTS "Users can update their invitations" ON public.coven_invitations;
CREATE POLICY "Users can update their invitations"
  ON public.coven_invitations
  FOR UPDATE
  TO authenticated
  USING (invitee_id = auth.uid())
  WITH CHECK (invitee_id = auth.uid());

-- Enable RLS on coven_resources table
ALTER TABLE public.coven_resources ENABLE ROW LEVEL SECURITY;

-- Policy: Members can view coven resources
DROP POLICY IF EXISTS "Members can view coven resources" ON public.coven_resources;
CREATE POLICY "Members can view coven resources"
  ON public.coven_resources
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.coven_members cm
      WHERE cm.coven_id = coven_resources.coven_id
      AND cm.player_id = auth.uid()
    )
  );

-- Policy: Leaders/elders can update coven resources
DROP POLICY IF EXISTS "Leaders can update coven resources" ON public.coven_resources;
CREATE POLICY "Leaders can update coven resources"
  ON public.coven_resources
  FOR UPDATE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.coven_members cm
      WHERE cm.coven_id = coven_resources.coven_id
      AND cm.player_id = auth.uid()
      AND cm.role IN ('leader', 'elder')
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.coven_members cm
      WHERE cm.coven_id = coven_resources.coven_id
      AND cm.player_id = auth.uid()
      AND cm.role IN ('leader', 'elder')
    )
  );

-- Enable RLS on coven_activity_log table
ALTER TABLE public.coven_activity_log ENABLE ROW LEVEL SECURITY;

-- Policy: Members can view coven activity
DROP POLICY IF EXISTS "Members can view coven activity" ON public.coven_activity_log;
CREATE POLICY "Members can view coven activity"
  ON public.coven_activity_log
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.coven_members cm
      WHERE cm.coven_id = coven_activity_log.coven_id
      AND cm.player_id = auth.uid()
    )
  );

-- Create RPC function to transfer coven leadership
CREATE OR REPLACE FUNCTION public.transfer_coven_leadership(p_coven_id UUID, p_new_leader_id UUID)
RETURNS VOID AS $$
BEGIN
  -- Check if current user is leader
  IF NOT EXISTS (
    SELECT 1 FROM public.coven 
    WHERE id = p_coven_id AND leader_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Only the current leader can transfer leadership';
  END IF;

  -- Check if new leader is a member
  IF NOT EXISTS (
    SELECT 1 FROM public.coven_members 
    WHERE coven_id = p_coven_id AND player_id = p_new_leader_id
  ) THEN
    RAISE EXCEPTION 'New leader must be a member of the coven';
  END IF;

  -- Update coven leader
  UPDATE public.coven 
  SET leader_id = p_new_leader_id 
  WHERE id = p_coven_id;

  -- Update roles
  UPDATE public.coven_members 
  SET role = 'leader' 
  WHERE coven_id = p_coven_id AND player_id = p_new_leader_id;

  UPDATE public.coven_members 
  SET role = 'elder' 
  WHERE coven_id = p_coven_id AND player_id = auth.uid();

  -- Log activity
  INSERT INTO public.coven_activity_log (coven_id, actor_id, action, target_type, target_id)
  VALUES (p_coven_id, auth.uid(), 'leadership_transfer', 'player', p_new_leader_id);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION public.transfer_coven_leadership(UUID, UUID) IS 'Transfer coven leadership to another member';

-- Create RPC function to disband coven
CREATE OR REPLACE FUNCTION public.disband_coven(p_coven_id UUID)
RETURNS VOID AS $$
BEGIN
  -- Check if current user is leader
  IF NOT EXISTS (
    SELECT 1 FROM public.coven 
    WHERE id = p_coven_id AND leader_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Only the leader can disband the coven';
  END IF;

  -- Log activity
  INSERT INTO public.coven_activity_log (coven_id, actor_id, action, metadata)
  VALUES (p_coven_id, auth.uid(), 'coven_disbanded', jsonb_build_object('member_count', (
    SELECT COUNT(*) FROM public.coven_members WHERE coven_id = p_coven_id
  )));

  -- Delete coven (cascade will handle members)
  DELETE FROM public.coven WHERE id = p_coven_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION public.disband_coven(UUID) IS 'Disband a coven permanently';

-- Create RPC function to invite player to coven
CREATE OR REPLACE FUNCTION public.invite_to_coven(p_coven_id UUID, p_invitee_id UUID, p_message TEXT DEFAULT NULL)
RETURNS UUID AS $$
DECLARE
  v_invitation_id UUID;
BEGIN
  -- Check if current user is member with invite permissions
  IF NOT EXISTS (
    SELECT 1 FROM public.coven_members 
    WHERE coven_id = p_coven_id 
    AND player_id = auth.uid() 
    AND role IN ('leader', 'elder')
  ) THEN
    RAISE EXCEPTION 'Only leaders and elders can invite players';
  END IF;

  -- Check if invitee is already a member
  IF EXISTS (
    SELECT 1 FROM public.coven_members 
    WHERE coven_id = p_coven_id AND player_id = p_invitee_id
  ) THEN
    RAISE EXCEPTION 'Player is already a member of this coven';
  END IF;

  -- Create invitation
  INSERT INTO public.coven_invitations (
    coven_id, inviter_id, invitee_id, message, expires_at
  ) VALUES (
    p_coven_id, auth.uid(), p_invitee_id, p_message, NOW() + INTERVAL '7 days'
  ) RETURNING id INTO v_invitation_id;

  -- Log activity
  INSERT INTO public.coven_activity_log (coven_id, actor_id, action, target_type, target_id)
  VALUES (p_coven_id, auth.uid(), 'invitation_sent', 'player', p_invitee_id);

  RETURN v_invitation_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION public.invite_to_coven(UUID, UUID, TEXT) IS 'Invite a player to join a coven';

-- Create function to update coven member count
CREATE OR REPLACE FUNCTION public.update_coven_member_count()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    UPDATE public.coven 
    SET member_count = member_count + 1, updated_at = NOW()
    WHERE id = NEW.coven_id;
    RETURN NEW;
  ELSIF TG_OP = 'DELETE' THEN
    UPDATE public.coven 
    SET member_count = member_count - 1, updated_at = NOW()
    WHERE id = OLD.coven_id;
    RETURN OLD;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Create trigger to update coven member count
DROP TRIGGER IF EXISTS update_coven_member_count_trigger ON public.coven_members;
CREATE TRIGGER update_coven_member_count_trigger
AFTER INSERT OR DELETE ON public.coven_members
FOR EACH ROW EXECUTE FUNCTION public.update_coven_member_count();

-- Create function to auto-delete empty covens
CREATE OR REPLACE FUNCTION public.auto_delete_empty_coven()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    -- If this was the last member, delete the coven
    IF NOT EXISTS (
      SELECT 1 FROM public.coven_members 
      WHERE coven_id = OLD.coven_id
    ) THEN
      DELETE FROM public.coven WHERE id = OLD.coven_id;
    END IF;
    RETURN OLD;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Create trigger to auto-delete empty covens
DROP TRIGGER IF EXISTS auto_delete_empty_coven_trigger ON public.coven_members;
CREATE TRIGGER auto_delete_empty_coven_trigger
AFTER DELETE ON public.coven_members
FOR EACH ROW EXECUTE FUNCTION public.auto_delete_empty_coven();

-- Create function to update member last active
CREATE OR REPLACE FUNCTION public.update_member_last_active()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE public.coven_members 
  SET last_active = NOW(), updated_at = NOW()
  WHERE coven_id = NEW.coven_id AND player_id = auth.uid();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION public.update_member_last_active() IS 'Update last active timestamp for a coven member';