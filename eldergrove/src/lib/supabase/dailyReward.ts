import { createClient } from '@/lib/supabase/client';
import { handleError } from '@/hooks/useErrorHandler';

export interface DailyRewardResponse {
  success: boolean;
  message: string;
  crystalsAwarded?: number;
  alreadyClaimed?: boolean;
}

/**
 * Claims the daily reward for the current user
 * @returns Promise resolving to the response from the edge function
 */
export async function claimDailyReward(): Promise<DailyRewardResponse> {
  try {
    const supabase = createClient();

    // Get the current session
    const { data: { session }, error: sessionError } = await supabase.auth.getSession();

    if (sessionError || !session) {
      throw new Error('No active session found');
    }

    const userId = session.user.id;
    const today = new Date().toISOString().split('T')[0]; // YYYY-MM-DD format

    // Check if user has already claimed today
    const { data: profile, error: profileError } = await supabase
      .from('profiles')
      .select('last_claimed_date, crystals')
      .eq('id', userId)
      .single();

    if (profileError) {
      throw new Error('Failed to fetch profile data');
    }

    // If already claimed today, return appropriate response
    if (profile.last_claimed_date === today) {
      const response: DailyRewardResponse = {
        success: true,
        message: 'Daily reward already claimed today',
        alreadyClaimed: true
      };

      const { useGameMessageStore } = await import('@/stores/useGameMessageStore');
      useGameMessageStore.getState().addMessage('success', response.message);
      return response;
    }

    // User hasn't claimed today, so award 500 crystals
    const crystalsToAdd = 500;
    const newCrystalsTotal = profile.crystals + crystalsToAdd;

    // Update profile with new crystals and last claimed date
    const { error: updateError } = await supabase
      .from('profiles')
      .update({
        crystals: newCrystalsTotal,
        last_claimed_date: today
      })
      .eq('id', userId);

    if (updateError) {
      throw new Error('Failed to update profile with daily reward');
    }

    const response: DailyRewardResponse = {
      success: true,
      message: `Successfully claimed ${crystalsToAdd} crystals!`,
      crystalsAwarded: crystalsToAdd,
      alreadyClaimed: false
    };

    // Refresh player profile to ensure store is in sync
    try {
      const { usePlayerStore } = await import('@/stores/usePlayerStore');
      await usePlayerStore.getState().fetchPlayerProfile();
    } catch (profileError) {
      console.warn('Failed to refresh player profile after daily reward:', profileError);
    }

    const { useGameMessageStore } = await import('@/stores/useGameMessageStore');
    useGameMessageStore.getState().addMessage('success', response.message);

    return response;
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : 'Failed to claim daily reward';
    handleError(error, errorMessage);
    return {
      success: false,
      message: errorMessage,
    };
  }
}