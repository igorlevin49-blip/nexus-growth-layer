import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

interface NotificationPayload {
  notification_id: string;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""
    );

    const { notification_id } = (await req.json()) as NotificationPayload;

    if (!notification_id) {
      throw new Error("notification_id is required");
    }

    console.log(`Processing notification: ${notification_id}`);

    // Get notification
    const { data: notification, error: notifError } = await supabaseAdmin
      .from("system_notifications")
      .select("*")
      .eq("id", notification_id)
      .single();

    if (notifError || !notification) {
      throw new Error(`Notification not found: ${notifError?.message}`);
    }

    // Update status to sending
    await supabaseAdmin
      .from("system_notifications")
      .update({ status: "sending" })
      .eq("id", notification_id);

    // Get target users based on audience
    let usersQuery = supabaseAdmin
      .from("profiles")
      .select("id, email, full_name, telegram_chat_id")
      .eq("is_active", true)
      .is("deleted_at", null);

    if (notification.target_audience === "active") {
      usersQuery = usersQuery.eq("subscription_status", "active");
    } else if (notification.target_audience === "inactive") {
      usersQuery = usersQuery.neq("subscription_status", "active");
    } else if (notification.target_audience === "custom" && notification.target_user_ids) {
      usersQuery = usersQuery.in("id", notification.target_user_ids);
    }

    const { data: users, error: usersError } = await usersQuery;

    if (usersError) {
      throw new Error(`Failed to fetch users: ${usersError.message}`);
    }

    console.log(`Found ${users?.length || 0} target users`);

    const channels = notification.channels as string[];
    const logs: Array<{
      notification_id: string;
      user_id: string;
      channel: string;
      recipient: string;
      success: boolean;
      error_message?: string;
    }> = [];

    // Get Telegram bot token if needed
    const telegramBotToken = Deno.env.get("TELEGRAM_BOT_TOKEN");

    for (const user of users || []) {
      // Modal notifications
      if (channels.includes("modal")) {
        try {
          await supabaseAdmin.from("user_modal_notifications").insert({
            user_id: user.id,
            notification_id: notification_id,
            title: notification.title,
            message: notification.message,
            type: notification.type,
          });

          logs.push({
            notification_id,
            user_id: user.id,
            channel: "modal",
            recipient: user.id,
            success: true,
          });
        } catch (err) {
          logs.push({
            notification_id,
            user_id: user.id,
            channel: "modal",
            recipient: user.id,
            success: false,
            error_message: err.message,
          });
        }
      }

      // Telegram notifications
      if (channels.includes("telegram") && user.telegram_chat_id && telegramBotToken) {
        try {
          const telegramMessage = `*${notification.title}*\n\n${notification.message}`;
          
          const telegramRes = await fetch(
            `https://api.telegram.org/bot${telegramBotToken}/sendMessage`,
            {
              method: "POST",
              headers: { "Content-Type": "application/json" },
              body: JSON.stringify({
                chat_id: user.telegram_chat_id,
                text: telegramMessage,
                parse_mode: "Markdown",
              }),
            }
          );

          const telegramResult = await telegramRes.json();

          logs.push({
            notification_id,
            user_id: user.id,
            channel: "telegram",
            recipient: user.telegram_chat_id,
            success: telegramResult.ok === true,
            error_message: telegramResult.ok ? undefined : telegramResult.description,
          });
        } catch (err) {
          logs.push({
            notification_id,
            user_id: user.id,
            channel: "telegram",
            recipient: user.telegram_chat_id || "unknown",
            success: false,
            error_message: err.message,
          });
        }
      }

      // Email notifications (using Supabase edge function if available)
      if (channels.includes("email") && user.email) {
        try {
          // Use Resend if available
          const resendApiKey = Deno.env.get("RESEND_API_KEY");
          
          if (resendApiKey) {
            const emailRes = await fetch("https://api.resend.com/emails", {
              method: "POST",
              headers: {
                "Content-Type": "application/json",
                Authorization: `Bearer ${resendApiKey}`,
              },
              body: JSON.stringify({
                from: "no-reply@mg-market.kz",
                to: user.email,
                subject: notification.title,
                html: `
                  <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto;">
                    <h1 style="color: #333;">${notification.title}</h1>
                    <p style="color: #666; white-space: pre-wrap;">${notification.message}</p>
                    <hr style="margin: 20px 0; border: none; border-top: 1px solid #eee;" />
                    <p style="color: #999; font-size: 12px;">MG-Market</p>
                  </div>
                `,
              }),
            });

            const emailResult = await emailRes.json();
            const success = emailRes.ok;

            logs.push({
              notification_id,
              user_id: user.id,
              channel: "email",
              recipient: user.email,
              success,
              error_message: success ? undefined : JSON.stringify(emailResult),
            });
          } else {
            logs.push({
              notification_id,
              user_id: user.id,
              channel: "email",
              recipient: user.email,
              success: false,
              error_message: "RESEND_API_KEY not configured",
            });
          }
        } catch (err) {
          logs.push({
            notification_id,
            user_id: user.id,
            channel: "email",
            recipient: user.email,
            success: false,
            error_message: err.message,
          });
        }
      }
    }

    // Insert all logs
    if (logs.length > 0) {
      await supabaseAdmin.from("system_notification_logs").insert(logs);
    }

    // Update notification status
    const successCount = logs.filter((l) => l.success).length;
    const totalCount = logs.length;

    await supabaseAdmin
      .from("system_notifications")
      .update({
        status: "sent",
        sent_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      })
      .eq("id", notification_id);

    console.log(`Notification sent: ${successCount}/${totalCount} successful`);

    return new Response(
      JSON.stringify({
        success: true,
        sent: successCount,
        failed: totalCount - successCount,
        total: totalCount,
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (error) {
    console.error("Error sending notification:", error);

    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
