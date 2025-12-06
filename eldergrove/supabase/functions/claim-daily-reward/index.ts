import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const supabase = createClient(
  Deno.env.get('SUPABASE_URL') ?? '',
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
);

interface ClaimResponse {
  success: boolean;
  message: string;
  crystalsAwarded?: number;
  seedsAwarded?: Array<{ item_id: number; quantity: number; name: string }>;
  alreadyClaimed?: boolean;
  new_crystal_balance?: number;
}

serve(async (_req) => {
  try {
    const authHeader = _req.headers.get('Authorization');
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return new Response(
        JSON.stringify({ 
          success: false, 
          message: 'Missing or invalid authorization header' 
        }),
        {
          headers: {
            'Content-Type': 'application/json; charset=utf-8',
            'Cache-Control': 'no-store'
          },
          status: 401
        }
      );
    }

    const token = authHeader.substring(7);
    
    const { data: { user }, error: userError } = await supabase.auth.getUser(token);
    if (userError || !user) {
      return new Response(
        JSON.stringify({ 
          success: false, 
          message: 'Invalid or expired token' 
        }),
        {
          headers: {
            'Content-Type': 'application/json; charset=utf-8',
            'Cache-Control': 'no-store'
          },
          status: 401
        }
      );
    }

    const userId = user.id;
    const today = new Date().toISOString().split('T')[0]; // Get date in YYYY-MM-DD format
    
    const { data: profile, error: profileError } = await supabase
      .from('profiles')
      .select('last_claimed_date, crystals, daily_streak')
      .eq('id', userId)
      .single();

    if (profileError) {
      return new Response(
        JSON.stringify({ 
          success: false, 
          message: 'Error fetching profile data' 
        }),
        {
          headers: {
            'Content-Type': 'application/json; charset=utf-8',
            'Cache-Control': 'no-store'
          },
          status: 500
        }
      );
    }
    
    // Check if already claimed today (handle both string and date comparison)
    const lastClaimedDate = profile.last_claimed_date ? new Date(profile.last_claimed_date).toISOString().split('T')[0] : null;
    if (lastClaimedDate === today) {
      return new Response(
        JSON.stringify({ 
          success: true, 
          message: 'Daily reward already claimed today',
          alreadyClaimed: true,
          streak: profile.daily_streak || 0
        }),
        {
          headers: {
            'Content-Type': 'application/json; charset=utf-8',
            'Cache-Control': 'no-store'
          },
          status: 200
        }
      );
    }
    
    // Calculate new streak
    let newStreak = 1;
    if (lastClaimedDate === null) {
      // First time claiming
      newStreak = 1;
    } else {
      // Check if claimed yesterday (consecutive day)
      const yesterday = new Date();
      yesterday.setDate(yesterday.getDate() - 1);
      const yesterdayStr = yesterday.toISOString().split('T')[0];
      
      if (lastClaimedDate === yesterdayStr) {
        // Consecutive day
        newStreak = (profile.daily_streak || 0) + 1;
      } else {
        // Streak broken, reset to 1
        newStreak = 1;
      }
    }
    
    // Get cinema bonus (crystal generation multiplier)
    const { data: bonuses } = await supabase.rpc('get_building_bonuses', { p_player_id: userId });
    const cinemaBonus = bonuses?.crystal_generation || 0;
    
    // Base reward crystals
    let crystalsToAdd = 500;
    // Apply cinema bonus to daily reward
    crystalsToAdd = Math.floor(crystalsToAdd * (1.0 + cinemaBonus));
    
    const newCrystalsTotal = profile.crystals + crystalsToAdd;
    
    // Award basic seeds: Wheat (101), Carrot (102), Potato (103)
    // Each seed item_id = 100 + crop item_id
    const seedsToAward = [
      { item_id: 101, quantity: 5, name: 'Wheat Seed' },  // Wheat crop item_id = 1
      { item_id: 102, quantity: 5, name: 'Carrot Seed' }, // Carrot crop item_id = 2
      { item_id: 103, quantity: 5, name: 'Potato Seed' }  // Potato crop item_id = 3
    ];
    
    // Add seeds to inventory using RPC function or direct upsert
    // We'll use a database function to handle the increment properly
    for (const seed of seedsToAward) {
      // First, try to get current quantity
      const { data: existingItem } = await supabase
        .from('inventory')
        .select('quantity')
        .eq('player_id', userId)
        .eq('item_id', seed.item_id)
        .single();
      
      const currentQuantity = existingItem?.quantity || 0;
      const newQuantity = currentQuantity + seed.quantity;
      
      // Upsert with new total quantity
      const { error: inventoryError } = await supabase
        .from('inventory')
        .upsert({
          player_id: userId,
          item_id: seed.item_id,
          quantity: newQuantity
        }, {
          onConflict: 'player_id,item_id'
        });
      
      if (inventoryError) {
        console.error(`Error adding seed ${seed.item_id} to inventory:`, inventoryError);
      }
    }
    
    const { data: updatedProfile, error: updateError } = await supabase
      .from('profiles')
      .update({
        crystals: newCrystalsTotal,
        last_claimed_date: today,
        daily_streak: newStreak
      })
      .eq('id', userId)
      .select('crystals')
      .single();

    if (updateError) {
      return new Response(
        JSON.stringify({ 
          success: false, 
          message: 'Error updating profile with daily reward' 
        }),
        {
          headers: {
            'Content-Type': 'application/json; charset=utf-8',
            'Cache-Control': 'no-store'
          },
          status: 500
        }
      );
    }
    
    // Check achievements for daily_streak
    await supabase.rpc('check_achievements', { 
      achievement_type: 'daily_streak', 
      value: newStreak 
    });
    
    // Build message with seeds info
    const seedNames = seedsToAward.map(s => `${s.quantity}x ${s.name}`).join(', ');
    const message = `Successfully claimed ${crystalsToAdd} crystals and ${seedNames}!`;
    
    return new Response(
      JSON.stringify({
        success: true,
        message: message,
        crystalsAwarded: crystalsToAdd,
        seedsAwarded: seedsToAward,
        alreadyClaimed: false,
        new_crystal_balance: updatedProfile.crystals,
        streak: newStreak,
        cinema_bonus: cinemaBonus
      }),
      {
        headers: {
          'Content-Type': 'application/json; charset=utf-8',
          'Cache-Control': 'no-store'
        },
        status: 200
      }
    );

  } catch (error) {
    console.error('Error in claim_daily_reward function:', error);
    return new Response(
      JSON.stringify({ 
        success: false, 
        message: 'Internal server error' 
      }),
      {
        headers: {
          'Content-Type': 'application/json; charset=utf-8',
          'Cache-Control': 'no-store'
        },
        status: 500
      }
    );
  }
});