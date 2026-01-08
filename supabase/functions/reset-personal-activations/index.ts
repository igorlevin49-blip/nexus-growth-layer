import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    console.log('[reset-personal-activations] Starting personal activation reset check...');

    // Call the reset function
    const { data: resetUsers, error } = await supabase.rpc('reset_personal_activations');

    if (error) {
      console.error('[reset-personal-activations] Error calling reset function:', error);
      throw error;
    }

    const resetCount = resetUsers?.length || 0;
    console.log(`[reset-personal-activations] Reset ${resetCount} users`);

    // Log each reset
    if (resetUsers && resetUsers.length > 0) {
      for (const user of resetUsers) {
        console.log(`[reset-personal-activations] Reset user ${user.full_name} (${user.user_id}): period ${user.old_period} -> ${user.new_period}`);
        
        // Log to activity_log
        await supabase.from('activity_log').insert({
          user_id: user.user_id,
          action: 'personal_activation_period_reset',
          details: {
            old_period: user.old_period,
            new_period: user.new_period,
            reset_at: new Date().toISOString()
          }
        });
      }
    }

    return new Response(
      JSON.stringify({
        success: true,
        message: `Reset ${resetCount} user activations`,
        reset_users: resetUsers || []
      }),
      { 
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 200 
      }
    );

  } catch (error) {
    console.error('[reset-personal-activations] Error:', error);
    return new Response(
      JSON.stringify({ 
        success: false, 
        error: error.message 
      }),
      { 
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 500 
      }
    );
  }
});
