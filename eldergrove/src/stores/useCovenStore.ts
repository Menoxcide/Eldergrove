import { create } from 'zustand';
import { createClient } from '@/lib/supabase/client';
import { handleError } from '@/hooks/useErrorHandler';
import {
  getCovenByPlayerId,
  createCoven as createCovenService,
  joinCoven as joinCovenService,
  leaveCoven as leaveCovenService,
  kickMember as kickMemberService,
  updateMemberRole as updateMemberRoleService,
  getCovenMembers,
  searchCovens as searchCovensService,
  getAllCovens as getAllCovensService,
  type Coven,
  type CovenMember,
  type CovenWithMembers,
} from '@/lib/services/covenService';

interface CovenState {
  currentCoven: CovenWithMembers | null;
  availableCovens: Coven[];
  loading: boolean;
  error: string | null;
  setCurrentCoven: (coven: CovenWithMembers | null) => void;
  setAvailableCovens: (covens: Coven[]) => void;
  setLoading: (loading: boolean) => void;
  setError: (error: string | null) => void;
  fetchCoven: () => Promise<void>;
  createCoven: (name: string, emblem?: string | null) => Promise<void>;
  joinCoven: (covenId: string) => Promise<void>;
  leaveCoven: () => Promise<void>;
  kickMember: (memberId: string) => Promise<void>;
  updateMemberRole: (memberId: string, role: 'member' | 'elder' | 'leader') => Promise<void>;
  searchCovens: (query: string) => Promise<void>;
  refreshCovens: () => Promise<void>;
  subscribeToCovenUpdates: () => () => void;
}

export const useCovenStore = create<CovenState>((set, get) => ({
  currentCoven: null,
  availableCovens: [],
  loading: false,
  error: null,
  setCurrentCoven: (coven) => set({ currentCoven: coven, error: null }),
  setAvailableCovens: (covens) => set({ availableCovens: covens }),
  setLoading: (loading) => set({ loading }),
  setError: (error) => set({ error }),
  fetchCoven: async () => {
    const { setCurrentCoven, setLoading, setError } = get();
    setLoading(true);
    setError(null);
    try {
      const supabase = createClient();
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) {
        setCurrentCoven(null);
        return;
      }
      const coven = await getCovenByPlayerId(user.id);
      setCurrentCoven(coven);
    } catch (err: unknown) {
      const errorMessage = err instanceof Error ? err.message : 'Failed to fetch coven';
      setError(errorMessage);
      console.error('Error fetching coven:', err);
      setCurrentCoven(null);
    } finally {
      setLoading(false);
    }
  },
  createCoven: async (name: string, emblem?: string | null) => {
    const { fetchCoven, setError } = get();
    try {
      await createCovenService(name, emblem);
      const { useGameMessageStore } = await import('@/stores/useGameMessageStore');
      useGameMessageStore.getState().addMessage('success', `Coven "${name}" created successfully!`);
      await fetchCoven();
    } catch (err: unknown) {
      const errorMsg = err instanceof Error ? err.message : 'Failed to create coven';
      setError(errorMsg);
      handleError(err, errorMsg);
      throw err;
    }
  },
  joinCoven: async (covenId: string) => {
    const { fetchCoven, setError } = get();
    try {
      await joinCovenService(covenId);
      const { useGameMessageStore } = await import('@/stores/useGameMessageStore');
      useGameMessageStore.getState().addMessage('success', 'Successfully joined the coven!');
      await fetchCoven();
    } catch (err: unknown) {
      const errorMsg = err instanceof Error ? err.message : 'Failed to join coven';
      setError(errorMsg);
      handleError(err, errorMsg);
      throw err;
    }
  },
  leaveCoven: async () => {
    const { fetchCoven, setError } = get();
    try {
      await leaveCovenService();
      const { useGameMessageStore } = await import('@/stores/useGameMessageStore');
      useGameMessageStore.getState().addMessage('success', 'Left the coven successfully');
      set({ currentCoven: null });
    } catch (err: unknown) {
      const errorMsg = err instanceof Error ? err.message : 'Failed to leave coven';
      setError(errorMsg);
      handleError(err, errorMsg);
      throw err;
    }
  },
  kickMember: async (memberId: string) => {
    const { fetchCoven, setError } = get();
    try {
      await kickMemberService(memberId);
      const { useGameMessageStore } = await import('@/stores/useGameMessageStore');
      useGameMessageStore.getState().addMessage('success', 'Member kicked successfully');
      await fetchCoven();
    } catch (err: unknown) {
      const errorMsg = err instanceof Error ? err.message : 'Failed to kick member';
      setError(errorMsg);
      handleError(err, errorMsg);
      throw err;
    }
  },
  updateMemberRole: async (memberId: string, role: 'member' | 'elder' | 'leader') => {
    const { fetchCoven, setError } = get();
    try {
      await updateMemberRoleService(memberId, role);
      const { useGameMessageStore } = await import('@/stores/useGameMessageStore');
      useGameMessageStore.getState().addMessage('success', `Member role updated to ${role}`);
      await fetchCoven();
    } catch (err: unknown) {
      const errorMsg = err instanceof Error ? err.message : 'Failed to update member role';
      setError(errorMsg);
      handleError(err, errorMsg);
      throw err;
    }
  },
  searchCovens: async (query: string) => {
    const { setAvailableCovens, setLoading, setError } = get();
    setLoading(true);
    setError(null);
    try {
      const covens = await searchCovensService(query);
      setAvailableCovens(covens);
    } catch (err: unknown) {
      const errorMessage = err instanceof Error ? err.message : 'Failed to search covens';
      setError(errorMessage);
      console.error('Error searching covens:', err);
    } finally {
      setLoading(false);
    }
  },
  refreshCovens: async () => {
    const { setAvailableCovens, setLoading, setError } = get();
    setLoading(true);
    setError(null);
    try {
      const covens = await getAllCovensService();
      setAvailableCovens(covens);
    } catch (err: unknown) {
      const errorMessage = err instanceof Error ? err.message : 'Failed to refresh covens';
      setError(errorMessage);
      console.error('Error refreshing covens:', err);
    } finally {
      setLoading(false);
    }
  },
  subscribeToCovenUpdates: () => {
    const supabase = createClient();
    const { fetchCoven } = get();
    
    const channel = supabase.channel('coven_updates');
    
    // Subscribe to coven_members changes
    channel
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'coven_members' },
        () => {
          // Refresh coven data when members change
          fetchCoven().catch((err) => {
            console.error('Error in subscription callback:', err);
          });
        }
      )
      // Also listen to coven table changes
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'coven' },
        () => {
          fetchCoven().catch((err) => {
            console.error('Error in subscription callback:', err);
          });
        }
      )
      .subscribe((status) => {
        if (status === 'SUBSCRIBED') {
          console.log('Subscribed to coven updates');
        } else if (status === 'CHANNEL_ERROR') {
          const { setError } = get();
          setError('Failed to subscribe to real-time updates');
          console.error('Subscription error for coven');
        }
      });

    return () => {
      supabase.removeChannel(channel);
    };
  },
}));

