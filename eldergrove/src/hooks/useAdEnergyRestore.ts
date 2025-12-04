import { useState, useEffect, useCallback } from 'react';
import { createClient } from '@/lib/supabase/client';
import { showRewardedAd, initializeAds } from '@/lib/ads/adService';
import { handleError } from '@/hooks/useErrorHandler';

interface AdEligibility {
  can_watch: boolean;
  ads_watched_this_hour: number;
  ads_remaining: number;
  hourly_limit: number;
}

export function useAdEnergyRestore() {
  const [eligibility, setEligibility] = useState<AdEligibility | null>(null);
  const [loading, setLoading] = useState(false);
  const [checking, setChecking] = useState(false);

  useEffect(() => {
    initializeAds().catch(console.error);
  }, []);

  const checkEligibility = useCallback(async () => {
    setChecking(true);
    try {
      const supabase = createClient();
      const { data, error } = await supabase.rpc('can_watch_ad', {
        p_production_type: 'mining'
      });

      if (error) {
        throw error;
      }
      setEligibility(data as AdEligibility);
    } catch (error: unknown) {
      handleError(error, 'Failed to check ad availability');
    } finally {
      setChecking(false);
    }
  }, []);

  useEffect(() => {
    checkEligibility();
    const interval = setInterval(checkEligibility, 60000);
    return () => clearInterval(interval);
  }, [checkEligibility]);

  const watchAdForEnergyRestore = useCallback(async (): Promise<void> => {
    if (loading) return;

    setLoading(true);
    try {
      const supabase = createClient();
      const { data: eligibilityData, error: eligibilityError } = await supabase.rpc('can_watch_ad', {
        p_production_type: 'mining'
      });

      if (eligibilityError) {
        throw eligibilityError;
      }

      const canWatch = (eligibilityData as AdEligibility).can_watch;
      if (!canWatch) {
        const remaining = (eligibilityData as AdEligibility).ads_remaining;
        const { showError } = await import('@/hooks/useErrorHandler');
        showError('Ad Limit Reached', `You can watch ${remaining} more ads in the next hour.`);
        return;
      }

      await showRewardedAd();

      const { data, error } = await supabase.rpc('watch_ad_restore_energy');

      if (error) {
        throw error;
      }

      const result = data as { success: boolean; energy_restored: number; ads_remaining: number };

      if (result.success) {
        const { useGameMessageStore } = await import('@/stores/useGameMessageStore');
        useGameMessageStore.getState().addMessage('success', `Energy fully restored! (${result.energy_restored} energy)`);
        await checkEligibility();
      } else {
        throw new Error('Energy restoration failed');
      }
    } catch (error: unknown) {
      const errorMessage = error instanceof Error ? error.message : 'Failed to watch ad';
      handleError(error, errorMessage);
      throw error;
    } finally {
      setLoading(false);
    }
  }, [loading, checkEligibility]);

  return {
    eligibility,
    loading,
    checking,
    canWatchAd: eligibility?.can_watch ?? false,
    adsRemaining: eligibility?.ads_remaining ?? 0,
    adsWatchedThisHour: eligibility?.ads_watched_this_hour ?? 0,
    watchAdForEnergyRestore,
    checkEligibility
  };
}

