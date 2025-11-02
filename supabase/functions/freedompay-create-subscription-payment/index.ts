import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

Deno.serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders });
  }

  const correlationId = crypto.randomUUID();
  console.log('[SUBSCRIPTION_PAYMENT]', correlationId, 'Request received');

  try {
    // Initialize Supabase client
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const supabase = createClient(supabaseUrl, supabaseKey);

    // Authenticate user
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) {
      console.error('[SUBSCRIPTION_PAYMENT]', correlationId, 'No authorization header');
      return new Response(
        JSON.stringify({ error: 'UNAUTHORIZED', message: 'Требуется авторизация', correlationId }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    const token = authHeader.replace('Bearer ', '');
    const { data: { user }, error: userError } = await supabase.auth.getUser(token);

    if (userError || !user) {
      console.error('[SUBSCRIPTION_PAYMENT]', correlationId, 'Auth error:', userError);
      return new Response(
        JSON.stringify({ error: 'UNAUTHORIZED', message: 'Неверный токен авторизации', correlationId }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    console.log('[SUBSCRIPTION_PAYMENT]', correlationId, 'User authenticated:', user.id);

    // Get subscription price from mlm_settings (SSOT)
    const { data: subscriptionSetting, error: settingError } = await supabase
      .from('mlm_settings')
      .select('value')
      .eq('key', 'finance_subscription_usd')
      .single();

    if (settingError || !subscriptionSetting) {
      console.error('[SUBSCRIPTION_PAYMENT]', correlationId, 'Failed to fetch subscription price:', settingError);
      return new Response(
        JSON.stringify({ 
          error: 'CONFIGURATION_ERROR', 
          message: 'Стоимость подписки не настроена в системе', 
          correlationId 
        }),
        { status: 422, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    const subscriptionUSD = parseFloat(subscriptionSetting.value);

    if (isNaN(subscriptionUSD) || subscriptionUSD <= 0) {
      console.error('[SUBSCRIPTION_PAYMENT]', correlationId, 'Invalid subscription price:', subscriptionUSD);
      return new Response(
        JSON.stringify({ 
          error: 'CONFIGURATION_ERROR', 
          message: 'Некорректная стоимость подписки', 
          correlationId 
        }),
        { status: 422, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Get exchange rate from mlm_settings
    const { data: rateSetting, error: rateError } = await supabase
      .from('mlm_settings')
      .select('value')
      .eq('key', 'finance_usd_kzt_rate')
      .single();

    if (rateError || !rateSetting) {
      console.error('[SUBSCRIPTION_PAYMENT]', correlationId, 'Failed to fetch exchange rate:', rateError);
      return new Response(
        JSON.stringify({ 
          error: 'CONFIGURATION_ERROR', 
          message: 'Курс валюты не настроен в системе', 
          correlationId 
        }),
        { status: 422, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    const exchangeRate = parseFloat(rateSetting.value);
    const subscriptionKZT = Math.round(subscriptionUSD * exchangeRate);

    // Parse request body (method can be "card", "kaspi", or undefined for backward compatibility)
    const body = await req.json();
    const { method = 'card' } = body;

    console.log('[SUBSCRIPTION_PAYMENT]', correlationId, 'Amounts:', { subscriptionUSD, subscriptionKZT, exchangeRate }, 'method:', method);

    // Check provider credentials based on method
    if (method === 'card' || method === 'kaspi') {
      const merchantId = Deno.env.get('FREEDOMPAY_MERCHANT_ID');
      const secretKey = Deno.env.get('FREEDOMPAY_SECRET_KEY');
      
      if (!merchantId || !secretKey) {
        console.error('[SUBSCRIPTION_PAYMENT]', correlationId, 'Missing FreedomPay credentials for method:', method);
        return new Response(
          JSON.stringify({ 
            error: 'PROVIDER_NOT_CONFIGURED', 
            message: 'Онлайн-оплата временно недоступна. Вы можете отправить заявку на ручную оплату.', 
            correlationId 
          }),
          { status: 422, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        );
      }
    }

    // Get FreedomPay credentials
    const merchantId = Deno.env.get('FREEDOMPAY_MERCHANT_ID');
    const secretKey = Deno.env.get('FREEDOMPAY_SECRET_KEY');
    const appUrl = Deno.env.get('VITE_APP_URL') || 'https://mg-market.kz';

    // Create subscription record in DB
    const { data: subscription, error: subscriptionError } = await supabase
      .from('subscriptions')
      .insert({
        user_id: user.id,
        amount_usd: subscriptionUSD,
        amount_kzt: subscriptionKZT,
        status: 'pending',
        payment_method: 'freedompay'
      })
      .select()
      .single();

    if (subscriptionError || !subscription) {
      console.error('[SUBSCRIPTION_PAYMENT]', correlationId, 'Failed to create subscription:', subscriptionError);
      return new Response(
        JSON.stringify({ 
          error: 'DATABASE_ERROR', 
          message: 'Не удалось создать заявку на подписку', 
          correlationId 
        }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    console.log('[SUBSCRIPTION_PAYMENT]', correlationId, 'Subscription created:', subscription.id);

    // Prepare FreedomPay payment data
    const orderId = `SUB-${subscription.id}`;
    const paymentData = {
      pg_merchant_id: merchantId,
      pg_order_id: orderId,
      pg_currency: 'KZT',
      pg_amount: subscriptionKZT,
      pg_description: `Годовая подписка ($${subscriptionUSD})`,
      pg_salt: crypto.randomUUID(),
      pg_success_url: `${appUrl}/payment/success`,
      pg_failure_url: `${appUrl}/payment/failure`,
      pg_result_url: `${supabaseUrl}/functions/v1/freedompay-callback`,
    };

    // Generate signature
    const signatureString = [
      'payment.php',
      paymentData.pg_amount,
      paymentData.pg_currency,
      paymentData.pg_description,
      paymentData.pg_failure_url,
      paymentData.pg_merchant_id,
      paymentData.pg_order_id,
      paymentData.pg_result_url,
      paymentData.pg_salt,
      paymentData.pg_success_url,
      secretKey,
    ].join(';');

    const encoder = new TextEncoder();
    const data = encoder.encode(signatureString);
    const hashBuffer = await crypto.subtle.digest('SHA-256', data);
    const hashArray = Array.from(new Uint8Array(hashBuffer));
    const signature = hashArray.map(b => b.toString(16).padStart(2, '0')).join('');

    // Call FreedomPay API
    const formData = new URLSearchParams({
      ...paymentData,
      pg_sig: signature,
    });

    console.log('[SUBSCRIPTION_PAYMENT]', correlationId, 'Calling FreedomPay API');

    const freedomPayResponse = await fetch('https://api.freedompay.kz/payment.php', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: formData,
    });

    const responseText = await freedomPayResponse.text();
    console.log('[SUBSCRIPTION_PAYMENT]', correlationId, 'FreedomPay response:', responseText);

    // SECURITY: Parse XML response using regex with validation
    // Note: For production, consider using a proper XML parser library
    const paymentUrlMatch = responseText.match(/<pg_redirect_url>(https?:\/\/[^<]+)<\/pg_redirect_url>/);
    const statusMatch = responseText.match(/<pg_status>(ok|error|failed)<\/pg_status>/);

    if (statusMatch && statusMatch[1] === 'ok' && paymentUrlMatch) {
      const paymentUrl = paymentUrlMatch[1];
      console.log('[SUBSCRIPTION_PAYMENT]', correlationId, 'Payment URL generated:', paymentUrl);

      return new Response(
        JSON.stringify({ 
          payment_url: paymentUrl, 
          order_id: orderId,
          subscription_id: subscription.id,
          amount_usd: subscriptionUSD,
          amount_kzt: subscriptionKZT,
          correlationId 
        }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    } else {
      console.error('[SUBSCRIPTION_PAYMENT]', correlationId, 'Invalid FreedomPay response');
      return new Response(
        JSON.stringify({ 
          error: 'PAYMENT_PROVIDER_ERROR', 
          message: 'Не удалось создать платёж. Попробуйте позже', 
          correlationId 
        }),
        { status: 402, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

  } catch (error) {
    // SECURITY: Log detailed error server-side, return generic message to client
    console.error('[SUBSCRIPTION_PAYMENT]', correlationId, 'Unexpected error:', error);
    return new Response(
      JSON.stringify({ 
        error: 'INTERNAL_ERROR', 
        message: 'Внутренняя ошибка сервера', 
        correlationId
      }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }
});
