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

    const authHeader = req.headers.get('Authorization');
    if (!authHeader) {
      throw new Error('Missing authorization header');
    }

    const { data: { user }, error: authError } = await supabase.auth.getUser(
      authHeader.replace('Bearer ', '')
    );

    if (authError || !user) {
      throw new Error('Unauthorized');
    }

    const { amount_cents, description } = await req.json();

    if (!amount_cents || amount_cents <= 0) {
      throw new Error('Invalid amount');
    }

    const merchantId = Deno.env.get('FREEDOMPAY_MERCHANT_ID');
    const apiKey = Deno.env.get('FREEDOMPAY_API_KEY');
    const secretKey = Deno.env.get('FREEDOMPAY_SECRET_KEY');
    const apiUrl = Deno.env.get('FREEDOMPAY_API_URL') || 'https://api.freedompay.kz';
    const appUrl = Deno.env.get('APP_URL') || 'https://mg-market.kz';

    if (!merchantId || !apiKey || !secretKey) {
      throw new Error('Freedom Pay credentials not configured');
    }

    // Create order in our database
    const { data: order, error: orderError } = await supabase
      .from('orders')
      .insert({
        user_id: user.id,
        status: 'pending',
        total_usd: amount_cents / 100,
        total_kzt: 0,
      })
      .select()
      .single();

    if (orderError || !order) {
      console.error('Order creation error:', orderError);
      throw new Error('Failed to create order');
    }

    // Create payment request to Freedom Pay
    const orderId = order.id;
    const amountKzt = Math.round((amount_cents / 100) * 450); // Convert USD to KZT (approximate rate)
    
    const paymentData = {
      merchant_id: merchantId,
      order_id: orderId,
      amount: amountKzt,
      currency: 'KZT',
      description: description || 'Monthly activation payment',
      success_url: `${appUrl}/dashboard?payment=success`,
      failure_url: `${appUrl}/dashboard?payment=failure`,
      callback_url: `${Deno.env.get('SUPABASE_URL')}/functions/v1/freedompay-callback`,
    };

    // Generate signature
    const signatureString = `${merchantId}${orderId}${amountKzt}${secretKey}`;
    const encoder = new TextEncoder();
    const data = encoder.encode(signatureString);
    const hashBuffer = await crypto.subtle.digest('SHA-256', data);
    const hashArray = Array.from(new Uint8Array(hashBuffer));
    const signature = hashArray.map(b => b.toString(16).padStart(2, '0')).join('');

    const response = await fetch(`${apiUrl}/v1/payments/init`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${apiKey}`,
      },
      body: JSON.stringify({
        ...paymentData,
        signature,
      }),
    });

    if (!response.ok) {
      const errorText = await response.text();
      console.error('Freedom Pay API error:', errorText);
      throw new Error('Failed to create payment');
    }

    const result = await response.json();

    console.log('Payment created:', { orderId, paymentUrl: result.payment_url });

    return new Response(
      JSON.stringify({
        success: true,
        payment_url: result.payment_url,
        order_id: orderId,
      }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );

  } catch (error) {
    console.error('Error in freedompay-create-payment:', error);
    return new Response(
      JSON.stringify({ error: error.message }),
      { 
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      }
    );
  }
});