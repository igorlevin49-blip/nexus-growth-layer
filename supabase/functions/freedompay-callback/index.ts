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

    const secretKey = Deno.env.get('FREEDOMPAY_SECRET_KEY');
    if (!secretKey) {
      throw new Error('Secret key not configured');
    }

    const payload = await req.json();
    console.log('Freedom Pay callback received:', payload);

    const {
      order_id,
      amount,
      status,
      transaction_id,
      signature: receivedSignature,
    } = payload;

    // Verify signature
    const signatureString = `${order_id}${amount}${status}${transaction_id}${secretKey}`;
    const encoder = new TextEncoder();
    const data = encoder.encode(signatureString);
    const hashBuffer = await crypto.subtle.digest('SHA-256', data);
    const hashArray = Array.from(new Uint8Array(hashBuffer));
    const computedSignature = hashArray.map(b => b.toString(16).padStart(2, '0')).join('');

    if (computedSignature !== receivedSignature) {
      console.error('Invalid signature');
      throw new Error('Invalid signature');
    }

    // Get order
    const { data: order, error: orderError } = await supabase
      .from('orders')
      .select('*, user_id')
      .eq('id', order_id)
      .single();

    if (orderError || !order) {
      console.error('Order not found:', orderError);
      throw new Error('Order not found');
    }

    // Check for duplicate transaction
    const { data: existingTx } = await supabase
      .from('transactions')
      .select('id')
      .eq('source_ref', `freedompay_${transaction_id}`)
      .single();

    if (existingTx) {
      console.log('Duplicate transaction, skipping');
      return new Response(
        JSON.stringify({ success: true, message: 'Already processed' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    if (status === 'success' || status === 'paid') {
      // Update order status
      await supabase
        .from('orders')
        .update({ status: 'paid' })
        .eq('id', order_id);

      // Create transaction record
      const amountCents = Math.round((amount / 450) * 100); // Convert KZT to USD cents
      
      await supabase
        .from('transactions')
        .insert({
          user_id: order.user_id,
          type: 'purchase',
          amount_cents: -amountCents, // Negative for purchases
          status: 'completed',
          source_id: order_id,
          source_ref: `freedompay_${transaction_id}`,
          payload: {
            freedompay_transaction_id: transaction_id,
            amount_kzt: amount,
            payment_method: 'freedompay',
          },
        });

      console.log('Payment processed successfully:', {
        orderId: order_id,
        userId: order.user_id,
        amount: amountCents,
      });

    } else {
      // Update order as failed
      await supabase
        .from('orders')
        .update({ status: 'cancelled' })
        .eq('id', order_id);

      console.log('Payment failed or cancelled:', { orderId: order_id, status });
    }

    return new Response(
      JSON.stringify({ success: true }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );

  } catch (error) {
    console.error('Error in freedompay-callback:', error);
    return new Response(
      JSON.stringify({ error: error.message }),
      { 
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      }
    );
  }
});