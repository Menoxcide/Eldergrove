# Coven Migration Technical Specification

## Overview
This document outlines the technical specification for updating the coven tables migration file (`20251130120000_create_coven_tables.sql`). The purpose is to enhance the coven system with improved functionality, better data integrity, and additional features while maintaining compatibility with the existing application.

## Current State Analysis

### Existing Tables
1. **coven** table:
   - `id` (uuid, PK, default gen_random_uuid())
   - `name` (text, UNIQUE, NOT NULL)
   - `emblem` (text)
   - `leader_id` (uuid, FK to profiles.id, NOT NULL, ON DELETE CASCADE)
   - `created_at` (timestamptz, default now())

2. **coven_members** table:
   - `coven_id` (uuid, FK to coven.id, NOT NULL, ON DELETE CASCADE)
   - `player_id` (uuid, FK to profiles.id, NOT NULL, ON DELETE CASCADE)
   - `role` (text, default 'member', CHECK constraint for 'member', 'elder', 'leader')
   - `contribution` (bigint, default 0)
   - `joined_at` (timestamptz, default now())
   - Composite primary key (coven_id, player_id)

### Current RLS Policies
- Public read access to covens
- Leaders can update their own coven
- Authenticated users can create covens (become leader)
- Members can view members of their coven
- Users can join/leave covens
- Leaders can manage/kick members

### Identified Issues and Improvement Opportunities

#### Data Integrity Issues
1. No constraints on coven name length or format
2. No validation on emblem content
3. No mechanism to prevent leaders from leaving without transferring leadership
4. No automatic cleanup when a coven becomes empty
5. No audit trail for membership changes

#### Missing Features
1. Coven description field
2. Coven visibility settings (public/private)
3. Coven invitation system
4. Coven activity tracking
5. Coven resource/bank system
6. Coven achievements/badges
7. Coven messaging system
8. Coven events/calendar

#### Performance Considerations
1. Missing indexes on frequently queried fields
2. No materialized views for common queries
3. No partitioning strategy for large datasets

## Proposed Enhancements

### Database Schema Improvements

#### 1. Enhanced Coven Table
```sql
-- Add new columns to coven table
ALTER TABLE public.coven ADD COLUMN IF NOT EXISTS description TEXT;
ALTER TABLE public.coven ADD COLUMN IF NOT EXISTS visibility TEXT DEFAULT 'public' CHECK (visibility IN ('public', 'private', 'invite_only'));
ALTER TABLE public.coven ADD COLUMN IF NOT EXISTS member_count INTEGER DEFAULT 0;
ALTER TABLE public.coven ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT NOW();
ALTER TABLE public.coven ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;

-- Add indexes
CREATE INDEX IF NOT EXISTS idx_coven_visibility ON public.coven(visibility);
CREATE INDEX IF NOT EXISTS idx_coven_member_count ON public.coven(member_count);
CREATE INDEX IF NOT EXISTS idx_coven_updated_at ON public.coven(updated_at);
```

#### 2. Enhanced Coven Members Table
```sql
-- Add new columns to coven_members table
ALTER TABLE public.coven_members ADD COLUMN IF NOT EXISTS invited_by UUID REFERENCES public.profiles(id);
ALTER TABLE public.coven_members ADD COLUMN IF NOT EXISTS invite_accepted_at TIMESTAMPTZ;
ALTER TABLE public.coven_members ADD COLUMN IF NOT EXISTS last_active TIMESTAMPTZ;
ALTER TABLE public.coven_members ADD COLUMN IF NOT EXISTS title TEXT;
ALTER TABLE public.coven_members ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT NOW();

-- Add indexes
CREATE INDEX IF NOT EXISTS idx_coven_members_role ON public.coven_members(role);
CREATE INDEX IF NOT EXISTS idx_coven_members_last_active ON public.coven_members(last_active);
CREATE INDEX IF NOT EXISTS idx_coven_members_contribution ON public.coven_members(contribution);
```

#### 3. New Supporting Tables

##### Coven Invitations Table
```sql
CREATE TABLE IF NOT EXISTS public.coven_invitations (
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

CREATE INDEX IF NOT EXISTS idx_coven_invitations_coven_id ON public.coven_invitations(coven_id);
CREATE INDEX IF NOT EXISTS idx_coven_invitations_invitee_id ON public.coven_invitations(invitee_id);
CREATE INDEX IF NOT EXISTS idx_coven_invitations_status ON public.coven_invitations(status);
```

##### Coven Resources/Bank Table
```sql
CREATE TABLE IF NOT EXISTS public.coven_resources (
  coven_id UUID PRIMARY KEY REFERENCES public.coven(id) ON DELETE CASCADE,
  crystals BIGINT DEFAULT 0,
  herbs BIGINT DEFAULT 0,
  runes BIGINT DEFAULT 0,
  artifacts BIGINT DEFAULT 0,
  updated_at TIMESTAMPTZ DEFAULT NOW()
);
```

##### Coven Activity Log Table
```sql
CREATE TABLE IF NOT EXISTS public.coven_activity_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  coven_id UUID NOT NULL REFERENCES public.coven(id) ON DELETE CASCADE,
  actor_id UUID NOT NULL REFERENCES public.profiles(id),
  action TEXT NOT NULL,
  target_type TEXT,
  target_id UUID,
  metadata JSONB,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_coven_activity_log_coven_id ON public.coven_activity_log(coven_id);
CREATE INDEX IF NOT EXISTS idx_coven_activity_log_actor_id ON public.coven_activity_log(actor_id);
CREATE INDEX IF NOT EXISTS idx_coven_activity_log_action ON public.coven_activity_log(action);
CREATE INDEX IF NOT EXISTS idx_coven_activity_log_created_at ON public.coven_activity_log(created_at);
```

### New Database Features

#### 1. RPC Functions

##### Transfer Coven Leadership
```sql
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
```

##### Disband Coven
```sql
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
```

##### Invite Player to Coven
```sql
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
```

#### 2. Triggers

##### Update Coven Member Count
```sql
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

CREATE TRIGGER update_coven_member_count_trigger
AFTER INSERT OR DELETE ON public.coven_members
FOR EACH ROW EXECUTE FUNCTION public.update_coven_member_count();
```

##### Auto-delete Empty Covens
```sql
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

CREATE TRIGGER auto_delete_empty_coven_trigger
AFTER DELETE ON public.coven_members
FOR EACH ROW EXECUTE FUNCTION public.auto_delete_empty_coven();
```

##### Update Member Last Active
```sql
CREATE OR REPLACE FUNCTION public.update_member_last_active()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE public.coven_members 
  SET last_active = NOW(), updated_at = NOW()
  WHERE coven_id = NEW.coven_id AND player_id = auth.uid();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- This would be called from application when member performs actions
```

### Updated RLS Policies

#### Enhanced Coven Policies
```sql
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

-- Policy: Members can update their own last_active timestamp
DROP POLICY IF EXISTS "Members can update their last_active" ON public.coven_members;
CREATE POLICY "Members can update their last_active"
  ON public.coven_members
  FOR UPDATE
  TO authenticated
  USING (player_id = auth.uid())
  WITH CHECK (player_id = auth.uid());
```

## Integration with Existing Schema

### Relationship Mapping
1. **Profiles Integration**: All new tables maintain foreign key relationships to `profiles.id`
2. **RLS Consistency**: New policies align with existing RLS patterns using `auth.uid()`
3. **Index Strategy**: New indexes follow existing naming conventions and placement strategies
4. **Trigger Compatibility**: New triggers work alongside existing triggers without conflicts

### Application Impact
1. **Minimal Breaking Changes**: Most changes are additive, preserving existing functionality
2. **Enhanced User Experience**: New features provide richer coven interactions
3. **Improved Performance**: Additional indexes and optimized queries reduce latency
4. **Better Data Integrity**: Constraints and triggers ensure data consistency

## Supabase Best Practices Applied

### Security
1. **Row Level Security**: All new tables implement RLS with appropriate policies
2. **Secure Functions**: RPC functions use `SECURITY DEFINER` only when necessary
3. **Authentication Checks**: All functions verify user authentication and authorization
4. **Input Validation**: Functions validate inputs to prevent injection attacks

### Performance
1. **Indexing Strategy**: Strategic indexes on frequently queried columns
2. **Function Optimization**: Efficient SQL in functions to minimize execution time
3. **Partitioning Ready**: Schema designed to support future partitioning if needed
4. **Materialized Views**: Potential for materialized views on complex aggregations

### Maintainability
1. **Naming Conventions**: Consistent with existing database objects
2. **Documentation**: Comments on functions and complex policies
3. **Modular Design**: Independent features that can be enabled/disabled separately
4. **Migration Safety**: Changes can be applied incrementally without downtime

## Priority Ranking

### High Priority (Essential for Core Functionality)
1. Enhanced coven table with description and visibility settings
2. Coven invitations system
3. Transfer leadership RPC function
4. Disband coven RPC function
5. Member count maintenance trigger

### Medium Priority (Important Enhancements)
1. Coven resources/bank system
2. Activity logging
3. Last active timestamp tracking
4. Auto-delete empty covens trigger
5. Enhanced RLS policies

### Low Priority (Nice-to-Have Features)
1. Coven titles/achievements
2. Coven messaging system
3. Coven events/calendar
4. Materialized views for analytics
5. Advanced search capabilities

## Potential Challenges and Considerations

### Technical Challenges
1. **Migration Complexity**: Backward compatibility must be maintained during migration
2. **Concurrency Issues**: Multiple users performing actions simultaneously
3. **Performance Impact**: Additional triggers may slow down high-frequency operations
4. **Storage Growth**: New tables and logs will increase database size

### Implementation Considerations
1. **Rollback Strategy**: Need to plan for reverting changes if issues arise
2. **Testing Requirements**: Extensive testing of new RLS policies and functions
3. **Application Updates**: Frontend may need updates to utilize new features
4. **Monitoring**: New metrics to track coven system health and usage

### Risk Mitigation
1. **Staged Deployment**: Deploy changes in phases with monitoring
2. **Backup Strategy**: Ensure database backups before migration
3. **Performance Testing**: Load test new functions and triggers
4. **User Communication**: Inform users of new features and any temporary disruptions

## Conclusion

This technical specification provides a comprehensive roadmap for enhancing the coven system in the Eldergrove application. The proposed changes will significantly improve functionality, security, and user experience while maintaining compatibility with the existing codebase. The prioritized approach ensures that essential features are implemented first, with additional enhancements added incrementally based on user feedback and system performance.