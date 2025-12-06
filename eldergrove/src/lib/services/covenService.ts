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

export async function getCovenByPlayerId(playerId: string): Promise<CovenWithMembers | null> {
  const supabase = createClient();
  
  const { data: memberData, error: memberError } = await supabase
    .from('coven_members')
    .select('coven_id')
    .eq('player_id', playerId)
    .single();

  if (memberError) {
    if (memberError.code !== 'PGRST116') {
      throw memberError;
    }
    return null;
  }
  if (!memberData) {
    return null;
  }

  const { data: coven, error: covenError } = await supabase
    .from('coven')
    .select('*')
    .eq('id', memberData.coven_id)
    .is('deleted_at', null)
    .single();

  if (covenError) {
    throw covenError;
  }
  if (!coven) {
    return null;
  }

  const { data: members, error: membersError } = await supabase
    .from('coven_members')
    .select('*')
    .eq('coven_id', coven.id)
    .order('joined_at', { ascending: true });

  if (membersError) {
    throw membersError;
  }

  // Optimize N+1 queries: fetch all usernames in one query
  const playerIds = (members || []).map(member => member.player_id);
  const { data: profiles } = await supabase
    .from('profiles')
    .select('id, username')
    .in('id', playerIds);

  // Create a map for quick lookup
  const usernameMap = new Map(profiles?.map(profile => [profile.id, profile.username]) || []);

  const membersWithUsernames: CovenMember[] = (members || []).map(member => ({
    ...member,
    username: usernameMap.get(member.player_id) || null,
  }));

  return {
    ...coven,
    members: membersWithUsernames,
  };
}

export async function createCoven(name: string, emblem: string | null = null): Promise<Coven> {
  // Validate coven name
  const trimmedName = name.trim();
  if (trimmedName.length === 0) {
    throw new Error('Coven name cannot be empty');
  }
  if (trimmedName.length > 50) {
    throw new Error('Coven name cannot exceed 50 characters');
  }
  // Allow only alphanumeric characters, spaces, hyphens, and apostrophes
  if (!/^[a-zA-Z0-9\s\-']+$/.test(trimmedName)) {
    throw new Error('Coven name can only contain letters, numbers, spaces, hyphens, and apostrophes');
  }

  // Validate emblem if provided
  if (emblem && emblem.length > 10) {
    throw new Error('Emblem cannot exceed 10 characters');
  }

  const supabase = createClient();
  const { data: { user } } = await supabase.auth.getUser();

  if (!user) {
    throw new Error('Not authenticated');
  }

  // Check if user is already in a coven
  const { data: existingMember } = await supabase
    .from('coven_members')
    .select('coven_id')
    .eq('player_id', user.id)
    .single();

  if (existingMember) {
    // Check if the coven still exists and is not deleted
    const { data: existingCoven } = await supabase
      .from('coven')
      .select('id, name, deleted_at')
      .eq('id', existingMember.coven_id)
      .single();

    if (existingCoven && !existingCoven.deleted_at) {
      throw new Error('You are already in a coven. Please leave your current coven before creating a new one.');
    }
    if (existingCoven?.deleted_at) {
      await supabase
        .from('coven_members')
        .delete()
        .eq('player_id', user.id);
    }
  }

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
    if (covenError.code === '23505') {
      throw new Error('A coven with this name already exists. Please choose a different name.');
    }
    throw covenError;
  }

  const { error: memberError } = await supabase
    .from('coven_members')
    .insert({
      coven_id: coven.id,
      player_id: user.id,
      role: 'leader',
    });

  if (memberError) {
    await supabase.from('coven').delete().eq('id', coven.id);
    if (memberError.code === '23505') {
      throw new Error('You are already in a coven. Please leave your current coven before creating a new one.');
    }
    throw memberError;
  }

  return coven;
}

export async function joinCoven(covenId: string): Promise<void> {
  // Validate covenId is a valid UUID
  const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
  if (!uuidRegex.test(covenId)) {
    throw new Error('Invalid coven ID format');
  }

  const supabase = createClient();
  const { data: { user } } = await supabase.auth.getUser();

  if (!user) {
    throw new Error('Not authenticated');
  }

  const { data: coven, error: covenCheckError } = await supabase
    .from('coven')
    .select('id, deleted_at')
    .eq('id', covenId)
    .single();

  if (covenCheckError || !coven) {
    throw new Error('Coven not found');
  }

  if (coven.deleted_at) {
    throw new Error('This coven has been deleted');
  }

  const { data: existingMember } = await supabase
    .from('coven_members')
    .select('coven_id')
    .eq('player_id', user.id)
    .single();

  if (existingMember) {
    const { data: existingCoven } = await supabase
      .from('coven')
      .select('id, deleted_at')
      .eq('id', existingMember.coven_id)
      .single();

    if (existingCoven && !existingCoven.deleted_at) {
      throw new Error('You are already in a coven');
    }
    if (existingCoven?.deleted_at) {
      await supabase
        .from('coven_members')
        .delete()
        .eq('player_id', user.id);
    }
  }

  const { error } = await supabase
    .from('coven_members')
    .insert({
      coven_id: covenId,
      player_id: user.id,
      role: 'member',
    });

  if (error) {
    // Check if it's a unique constraint violation (already in a coven)
    if (error.code === '23505') {
      throw new Error('You are already in a coven');
    }
    throw error;
  }
}

export async function leaveCoven(): Promise<void> {
  const supabase = createClient();
  const { data: { user } } = await supabase.auth.getUser();

  if (!user) {
    throw new Error('Not authenticated');
  }

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

  const { error } = await supabase
    .from('coven_members')
    .delete()
    .eq('player_id', user.id);

  if (error) {
    throw error;
  }
}

export async function kickMember(memberId: string): Promise<void> {
  const supabase = createClient();
  const { data: { user } } = await supabase.auth.getUser();

  if (!user) {
    throw new Error('Not authenticated');
  }

  const { data: member } = await supabase
    .from('coven_members')
    .select('coven_id')
    .eq('player_id', memberId)
    .single();

  if (!member) {
    throw new Error('Member not found');
  }

  const { data: coven } = await supabase
    .from('coven')
    .select('leader_id')
    .eq('id', member.coven_id)
    .single();

  if (!coven || coven.leader_id !== user.id) {
    throw new Error('Only the coven leader can kick members');
  }

  if (memberId === user.id) {
    throw new Error('You cannot kick yourself');
  }

  const { error } = await supabase
    .from('coven_members')
    .delete()
    .eq('player_id', memberId)
    .eq('coven_id', member.coven_id);

  if (error) {
    throw error;
  }
}

export async function updateMemberRole(memberId: string, role: 'member' | 'elder' | 'leader'): Promise<void> {
  const supabase = createClient();
  const { data: { user } } = await supabase.auth.getUser();

  if (!user) {
    throw new Error('Not authenticated');
  }

  const { data: member } = await supabase
    .from('coven_members')
    .select('coven_id')
    .eq('player_id', memberId)
    .single();

  if (!member) {
    throw new Error('Member not found');
  }

  const { data: coven } = await supabase
    .from('coven')
    .select('leader_id')
    .eq('id', member.coven_id)
    .single();

  if (!coven || coven.leader_id !== user.id) {
    throw new Error('Only the coven leader can update roles');
  }

  const { error } = await supabase
    .from('coven_members')
    .update({ role })
    .eq('player_id', memberId)
    .eq('coven_id', member.coven_id);

  if (error) {
    throw error;
  }
}

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

  // Optimize N+1 queries: fetch all usernames in one query
  const playerIds = (members || []).map(member => member.player_id);
  const { data: profiles } = await supabase
    .from('profiles')
    .select('id, username')
    .in('id', playerIds);

  // Create a map for quick lookup
  const usernameMap = new Map(profiles?.map(profile => [profile.id, profile.username]) || []);

  const membersWithUsernames: CovenMember[] = (members || []).map(member => ({
    ...member,
    username: usernameMap.get(member.player_id) || null,
  }));

  return membersWithUsernames;
}

export async function searchCovens(query: string, limit: number = 20): Promise<Coven[]> {
  // Validate search query
  const trimmedQuery = query.trim();
  if (trimmedQuery.length === 0) {
    throw new Error('Search query cannot be empty');
  }
  if (trimmedQuery.length > 50) {
    throw new Error('Search query cannot exceed 50 characters');
  }
  // Allow only alphanumeric characters, spaces, hyphens, and apostrophes
  if (!/^[a-zA-Z0-9\s\-']+$/.test(trimmedQuery)) {
    throw new Error('Search query can only contain letters, numbers, spaces, hyphens, and apostrophes');
  }

  // Validate limit
  if (limit < 1 || limit > 50) {
    throw new Error('Limit must be between 1 and 50');
  }

  const supabase = createClient();

  const { data: covens, error } = await supabase
    .from('coven')
    .select('*')
    .ilike('name', `%${query}%`)
    .is('deleted_at', null)
    .limit(limit)
    .order('created_at', { ascending: false });

  if (error) {
    throw error;
  }

  return covens || [];
}

export async function getAllCovens(limit: number = 50): Promise<Coven[]> {
  const supabase = createClient();

  const { data: covens, error } = await supabase
    .from('coven')
    .select('*')
    .is('deleted_at', null)
    .limit(limit)
    .order('created_at', { ascending: false });

  if (error) {
    throw error;
  }

  return covens || [];
}

