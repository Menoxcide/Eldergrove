import { createClient } from '@/lib/supabase/client';

export interface Coven {
  id: string;
  name: string;
  emblem: string | null;
  leader_id: string;
  created_at: string;
}

export interface CovenMember {
  coven_id: string;
  player_id: string;
  role: 'member' | 'elder' | 'leader';
  contribution: number;
  joined_at: string;
  // Joined profile data
  username?: string;
}

export interface CovenWithMembers extends Coven {
  members: CovenMember[];
}

/**
 * Get coven that the current player belongs to
 */
export async function getCovenByPlayerId(playerId: string): Promise<CovenWithMembers | null> {
  const supabase = createClient();
  
  // Get the member record
  const { data: memberData, error: memberError } = await supabase
    .from('coven_members')
    .select('coven_id')
    .eq('player_id', playerId)
    .single();

  if (memberError || !memberData) {
    return null;
  }

  // Get the coven
  const { data: coven, error: covenError } = await supabase
    .from('coven')
    .select('*')
    .eq('id', memberData.coven_id)
    .single();

  if (covenError || !coven) {
    return null;
  }

  // Get members
  const { data: members, error: membersError } = await supabase
    .from('coven_members')
    .select('*')
    .eq('coven_id', coven.id)
    .order('joined_at', { ascending: true });

  if (membersError) {
    throw membersError;
  }

  // Fetch usernames for each member
  const membersWithUsernames: CovenMember[] = await Promise.all(
    (members || []).map(async (member) => {
      const { data: profile } = await supabase
        .from('profiles')
        .select('username')
        .eq('id', member.player_id)
        .single();
      
      return {
        ...member,
        username: profile?.username || null,
      };
    })
  );

  return {
    ...coven,
    members: membersWithUsernames,
  };
}

/**
 * Create a new coven
 */
export async function createCoven(name: string, emblem: string | null = null): Promise<Coven> {
  const supabase = createClient();
  const { data: { user } } = await supabase.auth.getUser();

  if (!user) {
    throw new Error('Not authenticated');
  }

  // Create coven with current user as leader
  const { data: coven, error: covenError } = await supabase
    .from('coven')
    .insert({
      name,
      emblem,
      leader_id: user.id,
    })
    .select()
    .single();

  if (covenError) {
    throw covenError;
  }

  // Add creator as leader member
  const { error: memberError } = await supabase
    .from('coven_members')
    .insert({
      coven_id: coven.id,
      player_id: user.id,
      role: 'leader',
    });

  if (memberError) {
    // Rollback coven creation
    await supabase.from('coven').delete().eq('id', coven.id);
    throw memberError;
  }

  return coven;
}

/**
 * Join a coven
 */
export async function joinCoven(covenId: string): Promise<void> {
  const supabase = createClient();
  const { data: { user } } = await supabase.auth.getUser();

  if (!user) {
    throw new Error('Not authenticated');
  }

  // Check if already in a coven
  const { data: existingMember } = await supabase
    .from('coven_members')
    .select('coven_id')
    .eq('player_id', user.id)
    .single();

  if (existingMember) {
    throw new Error('You are already in a coven');
  }

  // Join the coven
  const { error } = await supabase
    .from('coven_members')
    .insert({
      coven_id: covenId,
      player_id: user.id,
      role: 'member',
    });

  if (error) {
    throw error;
  }
}

/**
 * Leave current coven
 */
export async function leaveCoven(): Promise<void> {
  const supabase = createClient();
  const { data: { user } } = await supabase.auth.getUser();

  if (!user) {
    throw new Error('Not authenticated');
  }

  // Check if user is leader
  const { data: member } = await supabase
    .from('coven_members')
    .select('coven_id, role')
    .eq('player_id', user.id)
    .single();

  if (!member) {
    throw new Error('You are not in a coven');
  }

  if (member.role === 'leader') {
    throw new Error('Leaders cannot leave their coven. Transfer leadership first or disband the coven.');
  }

  // Leave the coven
  const { error } = await supabase
    .from('coven_members')
    .delete()
    .eq('player_id', user.id);

  if (error) {
    throw error;
  }
}

/**
 * Kick a member from coven (leader only)
 */
export async function kickMember(memberId: string): Promise<void> {
  const supabase = createClient();
  const { data: { user } } = await supabase.auth.getUser();

  if (!user) {
    throw new Error('Not authenticated');
  }

  // Get member's coven
  const { data: member } = await supabase
    .from('coven_members')
    .select('coven_id')
    .eq('player_id', memberId)
    .single();

  if (!member) {
    throw new Error('Member not found');
  }

  // Verify current user is leader
  const { data: coven } = await supabase
    .from('coven')
    .select('leader_id')
    .eq('id', member.coven_id)
    .single();

  if (!coven || coven.leader_id !== user.id) {
    throw new Error('Only the coven leader can kick members');
  }

  // Prevent kicking yourself
  if (memberId === user.id) {
    throw new Error('You cannot kick yourself');
  }

  // Kick the member
  const { error } = await supabase
    .from('coven_members')
    .delete()
    .eq('player_id', memberId)
    .eq('coven_id', member.coven_id);

  if (error) {
    throw error;
  }
}

/**
 * Update member role (leader only)
 */
export async function updateMemberRole(memberId: string, role: 'member' | 'elder' | 'leader'): Promise<void> {
  const supabase = createClient();
  const { data: { user } } = await supabase.auth.getUser();

  if (!user) {
    throw new Error('Not authenticated');
  }

  // Get member's coven
  const { data: member } = await supabase
    .from('coven_members')
    .select('coven_id')
    .eq('player_id', memberId)
    .single();

  if (!member) {
    throw new Error('Member not found');
  }

  // Verify current user is leader
  const { data: coven } = await supabase
    .from('coven')
    .select('leader_id')
    .eq('id', member.coven_id)
    .single();

  if (!coven || coven.leader_id !== user.id) {
    throw new Error('Only the coven leader can update roles');
  }

  // Update role
  const { error } = await supabase
    .from('coven_members')
    .update({ role })
    .eq('player_id', memberId)
    .eq('coven_id', member.coven_id);

  if (error) {
    throw error;
  }
}

/**
 * Get coven members
 */
export async function getCovenMembers(covenId: string): Promise<CovenMember[]> {
  const supabase = createClient();

  const { data: members, error } = await supabase
    .from('coven_members')
    .select('*')
    .eq('coven_id', covenId)
    .order('joined_at', { ascending: true });

  if (error) {
    throw error;
  }

  // Fetch usernames for each member
  const membersWithUsernames: CovenMember[] = await Promise.all(
    (members || []).map(async (member) => {
      const { data: profile } = await supabase
        .from('profiles')
        .select('username')
        .eq('id', member.player_id)
        .single();
      
      return {
        ...member,
        username: profile?.username || null,
      };
    })
  );

  return membersWithUsernames;
}

/**
 * Search for covens by name
 */
export async function searchCovens(query: string, limit: number = 20): Promise<Coven[]> {
  const supabase = createClient();

  const { data: covens, error } = await supabase
    .from('coven')
    .select('*')
    .ilike('name', `%${query}%`)
    .limit(limit)
    .order('created_at', { ascending: false });

  if (error) {
    throw error;
  }

  return covens || [];
}

/**
 * Get all covens (for browsing)
 */
export async function getAllCovens(limit: number = 50): Promise<Coven[]> {
  const supabase = createClient();

  const { data: covens, error } = await supabase
    .from('coven')
    .select('*')
    .limit(limit)
    .order('created_at', { ascending: false });

  if (error) {
    throw error;
  }

  return covens || [];
}

