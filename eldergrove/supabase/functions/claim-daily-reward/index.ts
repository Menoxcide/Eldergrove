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
  alreadyClaimed?: boolean;
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
      .select('last_claimed_date, crystals')
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
    
    if (profile.last_claimed_date === today) {
      return new Response(
        JSON.stringify({ 
          success: true, 
          message: 'Daily reward already claimed today',
          alreadyClaimed: true
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
    
    const crystalsToAdd = 500;
    const newCrystalsTotal = profile.crystals + crystalsToAdd;
    
    const { data: updatedProfile, error: updateError } = await supabase
      .from('profiles')
      .update({
        crystals: newCrystalsTotal,
        last_claimed_date: today
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
    
    return new Response(
      JSON.stringify({ 
        success: true, 
        message: `Successfully claimed ${crystalsToAdd} crystals!`,
        crystalsAwarded: crystalsToAdd,
        alreadyClaimed: false
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