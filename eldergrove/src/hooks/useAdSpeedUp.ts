import { useState, useEffect, useCallback } from 'react';
import { createClient } from '@/lib/supabase/client';
import { showRewardedAd, initializeAds } from '@/lib/ads/adService';
import { AD_SPEED_UP_MINUTES } from '@/lib/ads/config';
import { handleError } from '@/hooks/useErrorHandler';

interface AdEligibility {
  can_watch: boolean;
  ads_watched_this_hour: number;
  ads_remaining: number;
  hourly_limit: number;
}

export function useAdSpeedUp() {
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
        p_production_type: null
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

  const watchAdForSpeedUp = useCallback(async (
    productionType: 'farm' | 'factory' | 'zoo' | 'armory',
    productionId: number,
    minutesReduced: number = AD_SPEED_UP_MINUTES
  ): Promise<void> => {
    if (loading) return;

    setLoading(true);
    try {
      const supabase = createClient();
      const { data: eligibilityData, error: eligibilityError } = await supabase.rpc('can_watch_ad', {
        p_production_type: null
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

      const { data, error } = await supabase.rpc('watch_ad_speed_up', {
        p_production_type: productionType,
        p_production_id: productionId,
        p_minutes_reduced: minutesReduced
      });

      if (error) {
        throw error;
      }

      const result = data as { success: boolean; ads_remaining: number };

      if (result.success) {
        const { useGameMessageStore } = await import('@/stores/useGameMessageStore');
        useGameMessageStore.getState().addMessage('success', `Production sped up by ${minutesReduced} minutes!`);
        await checkEligibility();
      } else {
        throw new Error('Speed-up failed');
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
    watchAdForSpeedUp,
    checkEligibility
  };
}

