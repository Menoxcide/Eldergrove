import { createClient } from '@/lib/supabase/client';
import { handleError } from '@/hooks/useErrorHandler';
import { crystalTransactionManager } from '@/lib/crystalTransactionManager';

export interface DailyRewardResponse {
  success: boolean;
  message: string;
  crystalsAwarded?: number;
  seedsAwarded?: Array<{ item_id: number; quantity: number; name: string }>;
  alreadyClaimed?: boolean;
  new_crystal_balance?: number;
}

/**
 * Claims the daily reward for the current user
 * @returns Promise resolving to the response from the edge function
 */
export async function claimDailyReward(): Promise<DailyRewardResponse> {
  let response: DailyRewardResponse;

  await crystalTransactionManager.executeCrystalOperation(async (): Promise<void> => {
    const { usePlayerStore } = await import('@/stores/usePlayerStore');
    const supabase = createClient();

    const { data, error } = await supabase.functions.invoke('claim-daily-reward');

    if (error) {
      throw new Error(error.message || 'Failed to claim daily reward');
    }

    response = data as DailyRewardResponse;

    if (response.success && !response.alreadyClaimed) {
      if (response.new_crystal_balance !== null && response.new_crystal_balance !== undefined) {
        // Validate that the new balance is not negative
        if (response.new_crystal_balance < 0) {
          throw new Error('Daily reward would result in negative crystal balance');
        }
        usePlayerStore.getState().setCrystals(response.new_crystal_balance);
      }
    }

    const { useGameMessageStore } = await import('@/stores/useGameMessageStore');
    useGameMessageStore.getState().addMessage('success', response.message);
  }, 'Claim daily reward');

  return response!;
}