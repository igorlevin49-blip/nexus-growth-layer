import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    console.log("Starting auto-activation processing...");

    // Get activation threshold
    const { data: shopSettings } = await supabase
      .from("shop_settings")
      .select("monthly_activation_required_kzt")
      .single();

    const activationAmountKzt = shopSettings?.monthly_activation_required_kzt || 20000;
    const activationAmountCents = activationAmountKzt * 100;

    console.log(`Activation threshold: ${activationAmountKzt} KZT (${activationAmountCents} cents)`);

    // Find users with overdue activation and sufficient balance
    // Step 1: Get users with overdue activation
    const { data: overdueUsers, error: overdueError } = await supabase
      .from("profiles")
      .select("id, email, full_name, activation_due_from, monthly_activation_completed")
      .eq("monthly_activation_completed", false)
      .not("activation_due_from", "is", null)
      .lt("activation_due_from", new Date().toISOString());

    if (overdueError) {
      console.error("Error fetching overdue users:", overdueError);
      throw overdueError;
    }

    console.log(`Found ${overdueUsers?.length || 0} users with overdue activation`);

    const results: Array<{ userId: string; email: string; success: boolean; error?: string }> = [];

    // Process each user
    for (const user of overdueUsers || []) {
      try {
        // Get user balance
        const { data: balanceData, error: balanceError } = await supabase
          .rpc("get_user_balance", { p_user_id: user.id });

        if (balanceError) {
          console.error(`Error getting balance for ${user.email}:`, balanceError);
          results.push({ userId: user.id, email: user.email || "", success: false, error: balanceError.message });
          continue;
        }

        const balance = balanceData?.[0]?.available_cents || 0;
        console.log(`User ${user.email}: balance = ${balance} cents, required = ${activationAmountCents} cents`);

        if (balance >= activationAmountCents) {
          // Process auto-activation
          const { data: activationResult, error: activationError } = await supabase
            .rpc("process_auto_activation", { p_user_id: user.id });

          if (activationError) {
            console.error(`Error processing activation for ${user.email}:`, activationError);
            results.push({ userId: user.id, email: user.email || "", success: false, error: activationError.message });
            continue;
          }

          const result = activationResult as { success: boolean; error?: string; order_id?: string };
          
          if (result?.success) {
            console.log(`Successfully auto-activated ${user.email}, order_id: ${result.order_id}`);
            results.push({ userId: user.id, email: user.email || "", success: true });
            
            // TODO: Send notification to user about auto-deduction
          } else {
            console.error(`Failed to auto-activate ${user.email}:`, result?.error);
            results.push({ userId: user.id, email: user.email || "", success: false, error: result?.error });
          }
        } else {
          console.log(`User ${user.email} has insufficient balance: ${balance} < ${activationAmountCents}`);
        }
      } catch (userError) {
        console.error(`Exception processing user ${user.email}:`, userError);
        results.push({ 
          userId: user.id, 
          email: user.email || "", 
          success: false, 
          error: userError instanceof Error ? userError.message : "Unknown error" 
        });
      }
    }

    const successCount = results.filter(r => r.success).length;
    const failCount = results.filter(r => !r.success).length;

    console.log(`Auto-activation complete. Success: ${successCount}, Failed: ${failCount}`);

    return new Response(
      JSON.stringify({
        success: true,
        processed: results.length,
        successCount,
        failCount,
        results,
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (error) {
    console.error("Error in process-auto-activations:", error);
    return new Response(
      JSON.stringify({ 
        success: false, 
        error: error instanceof Error ? error.message : "Unknown error" 
      }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
