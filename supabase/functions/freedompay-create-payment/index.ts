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
      console.error('Missing authorization header');
      return new Response(
        JSON.stringify({ error: 'Необходима авторизация' }),
        { 
          headers: { ...corsHeaders, 'Content-Type': 'application/json' }, 
          status: 401 
        }
      );
    }

    const { data: { user }, error: authError } = await supabase.auth.getUser(
      authHeader.replace('Bearer ', '')
    );

    if (authError || !user) {
      console.error('Auth error:', authError);
      return new Response(
        JSON.stringify({ error: 'Необходима авторизация' }),
        { 
          headers: { ...corsHeaders, 'Content-Type': 'application/json' }, 
          status: 401 
        }
      );
    }

    const { amount_cents, description } = await req.json();

    // Валидация входных данных
    if (!amount_cents || typeof amount_cents !== 'number' || amount_cents <= 0) {
      console.error('Invalid amount:', amount_cents);
      return new Response(
        JSON.stringify({ error: 'Некорректная сумма платежа. Сумма должна быть больше 0.' }),
        { 
          headers: { ...corsHeaders, 'Content-Type': 'application/json' }, 
          status: 422 
        }
      );
    }

    if (!description || typeof description !== 'string') {
      console.error('Invalid description:', description);
      return new Response(
        JSON.stringify({ error: 'Описание платежа обязательно' }),
        { 
          headers: { ...corsHeaders, 'Content-Type': 'application/json' }, 
          status: 422 
        }
      );
    }

    const merchantId = Deno.env.get('FREEDOMPAY_MERCHANT_ID');
    const apiKey = Deno.env.get('FREEDOMPAY_API_KEY');
    const secretKey = Deno.env.get('FREEDOMPAY_SECRET_KEY');
    const apiUrl = Deno.env.get('FREEDOMPAY_API_URL') || 'https://api.freedompay.kz';
    const appUrl = 'https://mg-market.kz';

    if (!merchantId || !apiKey || !secretKey) {
      console.error('Freedom Pay credentials not configured');
      return new Response(
        JSON.stringify({ error: 'Платёжная система не настроена. Обратитесь к администратору.' }),
        { 
          headers: { ...corsHeaders, 'Content-Type': 'application/json' }, 
          status: 500 
        }
      );
    }

    // Get exchange rate from shop settings
    const { data: settings, error: settingsError } = await supabase
      .from('shop_settings')
      .select('rate_usd_kzt')
      .eq('id', 1)
      .single();

    if (settingsError || !settings) {
      console.error('Settings error:', settingsError);
      return new Response(
        JSON.stringify({ error: 'Не удалось получить настройки курса валют' }),
        { 
          headers: { ...corsHeaders, 'Content-Type': 'application/json' }, 
          status: 500 
        }
      );
    }

    const exchangeRate = settings.rate_usd_kzt || 450;

    // Create order in our database
    const { data: order, error: orderError } = await supabase
      .from('orders')
      .insert({
        user_id: user.id,
        status: 'pending',
        total_usd: amount_cents / 100,
        total_kzt: (amount_cents / 100) * exchangeRate,
      })
      .select()
      .single();

    if (orderError || !order) {
      console.error('Order creation error:', orderError);
      return new Response(
        JSON.stringify({ error: 'Не удалось создать заказ: ' + (orderError?.message || 'неизвестная ошибка') }),
        { 
          headers: { ...corsHeaders, 'Content-Type': 'application/json' }, 
          status: 500 
        }
      );
    }

    // Create payment request to Freedom Pay
    const orderId = order.id;
    const amountKzt = Math.round((amount_cents / 100) * exchangeRate);
    
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
      return new Response(
        JSON.stringify({ error: 'Не удалось создать платёж в платёжной системе' }),
        { 
          headers: { ...corsHeaders, 'Content-Type': 'application/json' }, 
          status: 500 
        }
      );
    }

    const result = await response.json();

    console.log('Payment created:', { orderId, paymentUrl: result.payment_url, amount_cents, exchangeRate });

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
    
    // Логирование для отладки
    const errorMessage = error instanceof Error ? error.message : 'Неизвестная ошибка';
    console.error('Payment creation failed:', {
      error: errorMessage,
      timestamp: new Date().toISOString(),
    });

    return new Response(
      JSON.stringify({ 
        error: errorMessage.includes('Unauthorized') || errorMessage.includes('авторизация')
          ? 'Необходима авторизация'
          : errorMessage.includes('credentials') || errorMessage.includes('настроена')
          ? 'Платёжная система временно недоступна. Попробуйте позже.'
          : 'Ошибка создания платежа: ' + errorMessage
      }),
      { 
        status: errorMessage.includes('Unauthorized') ? 401 : 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      }
    );
  }
});