import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.7.1';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

serve(async (req) => {
  // Handle CORS preflight requests
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    const { newEmail } = await req.json();
    
    // Get user from JWT
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) {
      throw new Error('No authorization header');
    }
    
    const token = authHeader.replace('Bearer ', '');
    
    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      { global: { headers: { Authorization: authHeader } } }
    );
    
    const { data: { user }, error: userError } = await supabaseClient.auth.getUser(token);
    if (userError || !user) {
      throw new Error('Unauthorized');
    }
    
    // Validate email format
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    if (!emailRegex.test(newEmail)) {
      throw new Error('Неверный формат email');
    }
    
    // Check if new email is the same as current
    if (user.email?.toLowerCase() === newEmail.toLowerCase()) {
      throw new Error('Новый email совпадает с текущим');
    }
    
    console.log(`Changing email for user ${user.id} from ${user.email} to ${newEmail}`);
    
    // Update in auth.users via Admin API
    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
      { auth: { autoRefreshToken: false, persistSession: false } }
    );
    
    const { error: authError } = await supabaseAdmin.auth.admin.updateUserById(
      user.id,
      { email: newEmail }
    );
    
    if (authError) {
      console.error('Auth error:', authError);
      if (authError.message.includes('already registered') || authError.message.includes('already exists')) {
        throw new Error('Email уже используется другим пользователем');
      }
      throw new Error(authError.message || 'Ошибка при обновлении email');
    }
    
    // Update in profiles
    const { error: profileError } = await supabaseAdmin
      .from('profiles')
      .update({ 
        email: newEmail, 
        updated_at: new Date().toISOString() 
      })
      .eq('id', user.id);
    
    if (profileError) {
      console.error('Profile error:', profileError);
      throw new Error('Ошибка при обновлении профиля');
    }
    
    // Log the change
    await supabaseAdmin
      .from('activity_log')
      .insert({
        user_id: user.id,
        type: 'email_changed',
        payload: {
          old_email: user.email,
          new_email: newEmail,
          changed_at: new Date().toISOString()
        }
      });
    
    console.log(`Email changed successfully for user ${user.id}`);
    
    return new Response(
      JSON.stringify({ 
        success: true, 
        message: 'Email успешно изменён. Войдите заново используя новый email.' 
      }),
      { 
        headers: { 
          ...corsHeaders,
          "Content-Type": "application/json" 
        } 
      }
    );
  } catch (error) {
    console.error('Change email error:', error);
    return new Response(
      JSON.stringify({ 
        success: false, 
        error: error.message || 'Произошла ошибка при смене email' 
      }),
      { 
        status: 400, 
        headers: { 
          ...corsHeaders,
          "Content-Type": "application/json" 
        } 
      }
    );
  }
});