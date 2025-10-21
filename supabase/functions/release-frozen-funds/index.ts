import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    );

    console.log('Starting frozen funds release process');

    // Update transactions where frozen_until has passed
    const { data, error } = await supabase
      .from('transactions')
      .update({ frozen_until: null })
      .lte('frozen_until', new Date().toISOString())
      .not('frozen_until', 'is', null)
      .select();

    if (error) {
      console.error('Error releasing frozen funds:', error);
      throw error;
    }

    console.log(`Released ${data?.length || 0} frozen transactions`);

    return new Response(
      JSON.stringify({ 
        success: true, 
        released: data?.length || 0,
        message: 'Frozen funds released successfully'
      }),
      { 
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 200 
      }
    );
  } catch (error) {
    console.error('Error in release-frozen-funds:', error);
    return new Response(
      JSON.stringify({ error: error instanceof Error ? error.message : 'Unknown error' }),
      { 
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 500 
      }
    );
  }
});
