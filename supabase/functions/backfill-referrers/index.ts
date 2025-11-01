import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.75.1';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
      {
        auth: {
          autoRefreshToken: false,
          persistSession: false,
        },
      }
    );

    // Get auth header
    const authHeader = req.headers.get('Authorization')!;
    
    // Get user from JWT
    const { data: { user }, error: userError } = await supabaseClient.auth.getUser(
      authHeader.replace('Bearer ', '')
    );

    if (userError || !user) {
      throw new Error('Unauthorized');
    }

    // Check if user is superadmin
    const { data: userRole } = await supabaseClient
      .from('user_roles')
      .select('role')
      .eq('user_id', user.id)
      .single();

    if (userRole?.role !== 'superadmin') {
      throw new Error('Only superadmin can run backfill');
    }

    console.log('Starting referrer backfill...');

    // Get all users without referrer_id
    const { data: usersWithoutReferrer, error: fetchError } = await supabaseClient
      .from('profiles')
      .select('id, email, created_at')
      .is('sponsor_id', null)
      .order('created_at', { ascending: true });

    if (fetchError) {
      throw fetchError;
    }

    console.log(`Found ${usersWithoutReferrer?.length || 0} users without referrer`);

    let processed = 0;
    let foundViaReferrals = 0;
    let foundViaActivityLog = 0;
    let notFound = 0;

    for (const profile of usersWithoutReferrer || []) {
      let sponsorId: string | null = null;
      let referrerSnapshot: any = null;

      // 1. Try to find in referrals table
      const { data: referralData } = await supabaseClient
        .from('referrals')
        .select('referrer_id')
        .eq('referred_user_id', profile.id)
        .eq('structure_type', 1)
        .maybeSingle();

      if (referralData?.referrer_id) {
        sponsorId = referralData.referrer_id;
        foundViaReferrals++;
        console.log(`Found sponsor via referrals for user ${profile.email}`);
      } else {
        // 2. Try to find in activity_log (registration event)
        const { data: activityData } = await supabaseClient
          .from('activity_log')
          .select('payload')
          .eq('user_id', profile.id)
          .eq('type', 'registration')
          .maybeSingle();

        if (activityData?.payload?.sponsor_id) {
          sponsorId = activityData.payload.sponsor_id;
          foundViaActivityLog++;
          console.log(`Found sponsor via activity_log for user ${profile.email}`);
        }
      }

      // If we found a sponsor, get their snapshot and update profile
      if (sponsorId) {
        const { data: sponsorData } = await supabaseClient
          .from('profiles')
          .select('full_name, email')
          .eq('id', sponsorId)
          .single();

        if (sponsorData) {
          referrerSnapshot = {
            full_name: sponsorData.full_name,
            email: sponsorData.email,
          };

          // Update the profile
          const { error: updateError } = await supabaseClient
            .from('profiles')
            .update({
              sponsor_id: sponsorId,
              referrer_snapshot: referrerSnapshot,
            })
            .eq('id', profile.id);

          if (updateError) {
            console.error(`Error updating user ${profile.email}:`, updateError);
          } else {
            processed++;
            console.log(`Updated user ${profile.email} with sponsor ${sponsorData.email}`);
          }

          // Create referral record if it doesn't exist
          const { error: referralError } = await supabaseClient
            .from('referrals')
            .insert({
              referrer_id: sponsorId,
              referred_user_id: profile.id,
              structure_type: 1,
            })
            .select()
            .single();

          if (referralError && !referralError.message.includes('duplicate')) {
            console.error(`Error creating referral for ${profile.email}:`, referralError);
          }
        }
      } else {
        notFound++;
        console.log(`No sponsor found for user ${profile.email}`);
      }
    }

    const result = {
      success: true,
      total_users: usersWithoutReferrer?.length || 0,
      processed,
      found_via_referrals: foundViaReferrals,
      found_via_activity_log: foundViaActivityLog,
      not_found: notFound,
    };

    console.log('Backfill completed:', result);

    return new Response(JSON.stringify(result), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 200,
    });
  } catch (error) {
    console.error('Error in backfill-referrers:', error);
    return new Response(JSON.stringify({ error: error.message }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 400,
    });
  }
});
