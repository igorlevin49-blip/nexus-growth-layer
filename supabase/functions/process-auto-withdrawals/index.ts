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

    console.log('Starting auto-withdrawal process');

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

        // Create withdrawal
        const { data: withdrawal, error: withdrawalError } = await supabase
          .from('withdrawals')
          .insert([{
            user_id: rule.user_id,
            method_id: rule.method_id,
            amount_cents: balance.available_cents,
            fee_cents: 0,
            status: 'processing'
          }])
          .select()
          .single();

        if (withdrawalError) {
          console.error(`Error creating withdrawal for user ${rule.user_id}:`, withdrawalError);
          continue;
        }

        // Create transaction
        const { error: transactionError } = await supabase
          .from('transactions')
          .insert([{
            user_id: rule.user_id,
            type: 'withdrawal',
            amount_cents: balance.available_cents,
            status: 'processing',
            source_id: withdrawal.id,
            source_ref: `auto_withdrawal_${withdrawal.id}`
          }]);

        if (transactionError) {
          console.error(`Error creating transaction for user ${rule.user_id}:`, transactionError);
          continue;
        }

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
    console.error('Error in process-auto-withdrawals:', error);
    return new Response(
      JSON.stringify({ error: error instanceof Error ? error.message : 'Unknown error' }),
      { 
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 500 
      }
    );
  }
});
