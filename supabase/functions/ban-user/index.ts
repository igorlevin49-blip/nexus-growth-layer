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
    const { userId, action } = await req.json(); // action: 'ban' | 'unban'
    
    if (!userId || !action) {
      throw new Error('Missing userId or action');
    }
    
    if (action !== 'ban' && action !== 'unban') {
      throw new Error('Invalid action. Must be "ban" or "unban"');
    }

    // Verify admin authorization
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) {
      throw new Error('No authorization header');
    }
    
    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      { global: { headers: { Authorization: authHeader } } }
    );
    
    const { data: { user: admin } } = await supabaseClient.auth.getUser();
    if (!admin) {
      throw new Error('Unauthorized');
    }
    
    // Check for admin/superadmin role
    const { data: roleData } = await supabaseClient
      .from('user_roles')
      .select('role')
      .eq('user_id', admin.id)
      .in('role', ['admin', 'superadmin'])
      .limit(1);
    
    if (!roleData || roleData.length === 0) {
      throw new Error('Access denied: admin role required');
    }

    // Prevent banning yourself
    if (userId === admin.id) {
      throw new Error('Cannot ban yourself');
    }
    
    // Use service role for admin operations
    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
      { auth: { autoRefreshToken: false, persistSession: false } }
    );

    // Check target user exists
    const { data: targetProfile } = await supabaseAdmin
      .from('profiles')
      .select('id, email, full_name')
      .eq('id', userId)
      .single();

    if (!targetProfile) {
      throw new Error('User not found');
    }
    
    // Ban/unban user in Auth
    const banDuration = action === 'ban' ? '876000h' : 'none'; // 100 years or remove ban
    const { error: authError } = await supabaseAdmin.auth.admin.updateUserById(
      userId,
      { ban_duration: banDuration }
    );
    
    if (authError) {
      console.error('Auth ban error:', authError);
      throw new Error(`Failed to ${action} user: ${authError.message}`);
    }
    
    // Update profile status
    const newStatus = action === 'ban' ? 'frozen' : 'inactive';
    const { error: profileError } = await supabaseAdmin
      .from('profiles')
      .update({ 
        subscription_status: newStatus,
        updated_at: new Date().toISOString()
      })
      .eq('id', userId);
    
    if (profileError) {
      console.error('Profile update error:', profileError);
      // Don't throw - auth ban was successful
    }
    
    // Audit log
    await supabaseAdmin.from('admin_audit').insert({
      admin_id: admin.id,
      action_type: action === 'ban' ? 'ban_user' : 'unban_user',
      target_type: 'user',
      target_id: userId,
      metadata: {
        user_email: targetProfile.email,
        user_name: targetProfile.full_name
      }
    });

    console.log(`User ${userId} ${action === 'ban' ? 'banned' : 'unbanned'} by admin ${admin.id}`);
    
    return new Response(
      JSON.stringify({ 
        success: true, 
        action,
        newStatus 
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (error) {
    console.error('Ban user error:', error);
    return new Response(
      JSON.stringify({ success: false, error: error.message }),
      { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
