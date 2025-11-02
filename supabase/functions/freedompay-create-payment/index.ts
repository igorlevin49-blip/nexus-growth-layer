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
  console.log('[ACTIVATION_PAYMENT]', correlationId, 'Request received');

  try {
    // Initialize Supabase client
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const supabase = createClient(supabaseUrl, supabaseKey);

    // Authenticate user
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) {
      console.error('[ACTIVATION_PAYMENT]', correlationId, 'No authorization header');
      return new Response(
        JSON.stringify({ error: 'UNAUTHORIZED', message: 'Требуется авторизация', correlationId }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    const token = authHeader.replace('Bearer ', '');
    const { data: { user }, error: userError } = await supabase.auth.getUser(token);

    if (userError || !user) {
      console.error('[ACTIVATION_PAYMENT]', correlationId, 'Auth error:', userError);
      return new Response(
        JSON.stringify({ error: 'UNAUTHORIZED', message: 'Неверный токен авторизации', correlationId }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    console.log('[ACTIVATION_PAYMENT]', correlationId, 'User authenticated:', user.id);

    // Check if user has active subscription (business rule)
    const { data: profile, error: profileError } = await supabase
      .from('profiles')
      .select('subscription_status')
      .eq('id', user.id)
      .single();

    if (profileError) {
      console.error('[ACTIVATION_PAYMENT]', correlationId, 'Failed to fetch profile:', profileError);
      return new Response(
        JSON.stringify({ 
          error: 'DATABASE_ERROR', 
          message: 'Не удалось проверить статус подписки', 
          correlationId 
        }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    if (profile.subscription_status !== 'active') {
      console.warn('[ACTIVATION_PAYMENT]', correlationId, 'Subscription required but not active');
      return new Response(
        JSON.stringify({ 
          error: 'SUBSCRIPTION_REQUIRED', 
          message: 'Сначала активируйте годовую подписку', 
          correlationId 
        }),
        { status: 409, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Parse request body
    const body = await req.json();
    const { products, method = 'card' } = body;
    
    console.log('[ACTIVATION_PAYMENT]', correlationId, 'Request data:', { products, method });

    // Validate products
    if (!products || !Array.isArray(products) || products.length === 0) {
      console.error('[ACTIVATION_PAYMENT]', correlationId, 'Missing or invalid products');
      return new Response(
        JSON.stringify({ 
          error: 'VALIDATION_ERROR', 
          message: 'Необходимо указать активационные товары', 
          correlationId 
        }),
        { status: 422, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Fetch activation products and calculate total
    let totalUSD = 0;
    let totalKZT = 0;
    const productDetails = [];

    for (const item of products) {
      const { data: product, error: productError } = await supabase
        .from('products')
        .select('*')
        .eq('id', item.product_id)
        .eq('is_activation', true)
        .single();

      if (productError || !product) {
        console.error('[ACTIVATION_PAYMENT]', correlationId, 'Product not found:', item.product_id);
        return new Response(
          JSON.stringify({ 
            error: 'VALIDATION_ERROR', 
            message: 'Один из активационных товаров не найден', 
            correlationId 
          }),
          { status: 422, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        );
      }

      if (!product.price_usd || !product.price_kzt || product.price_usd <= 0 || product.price_kzt <= 0) {
        console.error('[ACTIVATION_PAYMENT]', correlationId, 'Invalid product prices:', product);
        return new Response(
          JSON.stringify({ 
            error: 'CONFIGURATION_ERROR', 
            message: 'Цены на товар не настроены корректно', 
            correlationId 
          }),
          { status: 422, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        );
      }

      const quantity = item.quantity || 1;
      totalUSD += product.price_usd * quantity;
      totalKZT += product.price_kzt * quantity;
      productDetails.push({ ...product, quantity });
    }

    console.log('[ACTIVATION_PAYMENT]', correlationId, 'Total amounts:', { totalUSD, totalKZT });

    // Check provider credentials based on method
    if (method === 'card' || method === 'kaspi') {
      const merchantId = Deno.env.get('FREEDOMPAY_MERCHANT_ID');
      const secretKey = Deno.env.get('FREEDOMPAY_SECRET_KEY');
      
      if (!merchantId || !secretKey) {
        console.error('[ACTIVATION_PAYMENT]', correlationId, 'Missing FreedomPay credentials for method:', method);
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

    // Get FreedomPay credentials from environment
    const merchantId = Deno.env.get('FREEDOMPAY_MERCHANT_ID');
    const secretKey = Deno.env.get('FREEDOMPAY_SECRET_KEY');
    const appUrl = Deno.env.get('VITE_APP_URL') || 'https://mg-market.kz';

    // Create order in database with activation items
    const { data: order, error: orderError } = await supabase
      .from('orders')
      .insert({
        user_id: user.id,
        total_usd: totalUSD,
        total_kzt: totalKZT,
        status: 'pending'
      })
      .select()
      .single();

    if (orderError || !order) {
      console.error('[ACTIVATION_PAYMENT]', correlationId, 'Failed to create order:', orderError);
      return new Response(
        JSON.stringify({ 
          error: 'DATABASE_ERROR', 
          message: 'Не удалось создать заказ', 
          correlationId 
        }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    console.log('[ACTIVATION_PAYMENT]', correlationId, 'Order created:', order.id);

    // Add products to order items
    for (const product of productDetails) {
      const { error: itemError } = await supabase
        .from('order_items')
        .insert({
          order_id: order.id,
          product_id: product.id,
          qty: product.quantity,
          price_usd: product.price_usd,
          price_kzt: product.price_kzt,
          is_activation_snapshot: true
        });

      if (itemError) {
        console.error('[ACTIVATION_PAYMENT]', correlationId, 'Failed to add order item:', itemError);
        return new Response(
          JSON.stringify({ 
            error: 'DATABASE_ERROR', 
            message: 'Не удалось добавить товар в заказ', 
            correlationId 
          }),
          { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        );
      }
    }

    // Prepare payment data for FreedomPay
    const orderId = `ACT-${order.id}`;
    const description = productDetails.map(p => p.title).join(', ');
    const paymentData = {
      pg_merchant_id: merchantId,
      pg_order_id: orderId,
      pg_currency: 'KZT',
      pg_amount: totalKZT,
      pg_description: `Активация: ${description}`,
      pg_salt: crypto.randomUUID(),
      pg_success_url: `${appUrl}/payment/success`,
      pg_failure_url: `${appUrl}/payment/failure`,
      pg_result_url: `${supabaseUrl}/functions/v1/freedompay-callback`,
    };

    console.log('[ACTIVATION_PAYMENT]', correlationId, 'Payment data prepared:', orderId);

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

    console.log('[ACTIVATION_PAYMENT]', correlationId, 'Calling FreedomPay API');

    const freedomPayResponse = await fetch('https://api.freedompay.kz/payment.php', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: formData,
    });

    const responseText = await freedomPayResponse.text();
    console.log('[ACTIVATION_PAYMENT]', correlationId, 'FreedomPay response:', responseText);

    // SECURITY: Parse XML response using DOMParser (not available in Deno, using regex with validation)
    // Note: For production, consider using a proper XML parser library
    const paymentUrlMatch = responseText.match(/<pg_redirect_url>(https?:\/\/[^<]+)<\/pg_redirect_url>/);
    const statusMatch = responseText.match(/<pg_status>(ok|error|failed)<\/pg_status>/);

    if (statusMatch && statusMatch[1] === 'ok' && paymentUrlMatch) {
      const paymentUrl = paymentUrlMatch[1];
      console.log('[ACTIVATION_PAYMENT]', correlationId, 'Payment URL generated:', paymentUrl);

      return new Response(
        JSON.stringify({ 
          payment_url: paymentUrl, 
          order_id: orderId,
          products: productDetails.map(p => ({ id: p.id, title: p.title })),
          amount_usd: totalUSD,
          amount_kzt: totalKZT,
          correlationId 
        }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    } else {
      console.error('[ACTIVATION_PAYMENT]', correlationId, 'Invalid FreedomPay response');
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
    console.error('[ACTIVATION_PAYMENT]', correlationId, 'Unexpected error:', error);
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
