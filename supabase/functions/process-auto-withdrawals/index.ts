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
    // Verify JWT token for authentication
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: 'Missing authorization header' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 401 }
      );
    }

    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      { global: { headers: { Authorization: authHeader } } }
    );

    // Verify user is authenticated
    const { data: { user }, error: userError } = await supabaseClient.auth.getUser();
    if (userError || !user) {
      console.error('[AUTO_WITHDRAW] Authentication failed');
      return new Response(
        JSON.stringify({ error: 'Authentication required' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 401 }
      );
    }

    // SECURITY: Verify user has admin or superadmin role
    const { data: roleData, error: roleError } = await supabaseClient
      .from('user_roles')
      .select('role')
      .eq('user_id', user.id)
      .in('role', ['admin', 'superadmin'])
      .single();

    if (roleError || !roleData) {
      console.error('[AUTO_WITHDRAW] Unauthorized access attempt by user:', user.id);
      return new Response(
        JSON.stringify({ error: 'Insufficient permissions' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 403 }
      );
    }

    console.log('[AUTO_WITHDRAW] Authorized admin user:', user.id, 'role:', roleData.role);

    // Use service role client for the actual operation
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    );

    console.log('Starting auto-withdrawal processing by user:', user.id);

    // Get all enabled auto-withdraw rules
    const { data: rules, error: rulesError } = await supabase
      .from('auto_withdraw_rules')
      .select('*')
      .eq('enabled', true);

    if (rulesError) throw rulesError;

    let processedCount = 0;
    
    for (const rule of rules || []) {
      // Get user balance
      const { data: balanceData, error: balanceError } = await supabase
        .rpc('get_user_balance', { p_user_id: rule.user_id });

      if (balanceError) {
        console.error(`Error getting balance for user ${rule.user_id}:`, balanceError);
        continue;
      }

      const balance = balanceData?.[0];
      if (!balance) continue;

      // Check if balance meets threshold
      if (balance.available_cents >= rule.threshold_cents && balance.available_cents >= rule.min_amount_cents) {
        console.log(`Processing auto-withdrawal for user ${rule.user_id}, amount: ${balance.available_cents}`);

        // Use atomic function to create withdrawal + transaction in single transaction
        const { data: result, error: withdrawalError } = await supabase
          .rpc('create_user_withdrawal', {
            p_user_id: rule.user_id,
            p_amount_cents: balance.available_cents,
            p_method_id: rule.method_id
          });

        if (withdrawalError) {
          console.error(`Error creating withdrawal for user ${rule.user_id}:`, withdrawalError);
          continue;
        }

        const withdrawalResult = result as { success: boolean; message?: string; withdrawal_id?: string };
        if (!withdrawalResult.success) {
          console.error(`Withdrawal failed for user ${rule.user_id}:`, withdrawalResult.message);
          continue;
        }

        console.log(`Auto-withdrawal created for user ${rule.user_id}, withdrawal_id: ${withdrawalResult.withdrawal_id}`);
        processedCount++;
      }
    }

    console.log(`Processed ${processedCount} auto-withdrawals`);

    return new Response(
      JSON.stringify({ 
        success: true, 
        processed: processedCount,
        message: 'Auto-withdrawals processed successfully'
      }),
      { 
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 200 
      }
    );
  } catch (error) {
    // SECURITY: Log detailed error server-side, return generic message to client
    console.error('[AUTO_WITHDRAW] Unexpected error:', error);
    return new Response(
      JSON.stringify({ error: 'Internal server error occurred' }),
      { 
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 500 
      }
    );
  }
});
