import { serve } from "https://deno.land/std@0.190.0/http/server.ts";
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.7.1';
import { Resend } from "npm:resend@2.0.0";

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

const TELEGRAM_BOT_TOKEN = Deno.env.get('TELEGRAM_BOT_TOKEN');
const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY');
const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

const resend = new Resend(RESEND_API_KEY);

interface UserForReminder {
  id: string;
  email: string;
  full_name: string;
  telegram_chat_id: string | null;
  telegram_username: string | null;
  activation_due_from: string;
  days_until: number;
}

interface NotificationSettings {
  email_system: boolean;
  telegram_enabled: boolean;
}

// Get urgency level for styling
function getUrgencyInfo(daysLeft: number): { emoji: string; color: string; urgency: string } {
  if (daysLeft <= 1) return { emoji: '🔴', color: '#EF4444', urgency: 'Критическая' };
  if (daysLeft <= 2) return { emoji: '⚠️', color: '#F59E0B', urgency: 'Высокая' };
  if (daysLeft <= 3) return { emoji: '⚡', color: '#EAB308', urgency: 'Средняя' };
  return { emoji: '📅', color: '#3B82F6', urgency: 'Низкая' };
}

// Format date in Russian
function formatDateRu(dateStr: string): string {
  const date = new Date(dateStr);
  return date.toLocaleDateString('ru-RU', { 
    day: 'numeric', 
    month: 'long', 
    year: 'numeric' 
  });
}

// Send Telegram message
async function sendTelegramMessage(chatId: string, message: string): Promise<{ success: boolean; error?: string }> {
  try {
    const response = await fetch(
      `https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          chat_id: chatId,
          text: message,
          parse_mode: 'HTML',
        }),
      }
    );
    
    const result = await response.json();
    if (!result.ok) {
      console.error('Telegram API error:', result);
      return { success: false, error: result.description || 'Unknown Telegram error' };
    }
    return { success: true };
  } catch (error) {
    console.error('Telegram send error:', error);
    return { success: false, error: error.message };
  }
}

// Send Email via Resend
async function sendEmail(
  to: string, 
  subject: string, 
  html: string
): Promise<{ success: boolean; error?: string }> {
  try {
    const emailResponse = await resend.emails.send({
      from: 'MG Market <notifications@mg-market.kz>',
      to: [to],
      subject: subject,
      html: html,
    });
    
    console.log('Email sent:', emailResponse);
    return { success: true };
  } catch (error) {
    console.error('Resend error:', error);
    return { success: false, error: error.message };
  }
}

// Build Telegram message
function buildTelegramMessage(user: UserForReminder): string {
  const { emoji, urgency } = getUrgencyInfo(user.days_until);
  const dueDate = formatDateRu(user.activation_due_from);
  const daysWord = user.days_until === 1 ? 'день' : 
                   user.days_until <= 4 ? 'дня' : 'дней';
  
  return `${emoji} <b>Напоминание об активации</b>

Здравствуйте, ${user.full_name || 'Партнёр'}!

До истечения срока ежемесячной активации осталось: <b>${user.days_until} ${daysWord}</b>
Дата активации: <b>${dueDate}</b>
Срочность: <b>${urgency}</b>

Чтобы сохранить активный статус и продолжать получать MLM-комиссии, совершите покупку на сумму от $40.

👉 <a href="https://mg-market.kz/shop?activation=true">Перейти в магазин</a>

С уважением,
Команда MG Market`;
}

// Build Email HTML
function buildEmailHtml(user: UserForReminder): string {
  const { emoji, color } = getUrgencyInfo(user.days_until);
  const dueDate = formatDateRu(user.activation_due_from);
  const daysWord = user.days_until === 1 ? 'день' : 
                   user.days_until <= 4 ? 'дня' : 'дней';

  return `
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
</head>
<body style="font-family: Arial, sans-serif; line-height: 1.6; color: #333; max-width: 600px; margin: 0 auto; padding: 20px;">
  <div style="background: linear-gradient(135deg, ${color}20, ${color}05); border-left: 4px solid ${color}; padding: 20px; border-radius: 8px; margin-bottom: 20px;">
    <h1 style="color: ${color}; margin: 0 0 10px 0; font-size: 24px;">
      ${emoji} Напоминание об активации
    </h1>
    <p style="margin: 0; font-size: 18px; font-weight: bold;">
      Осталось ${user.days_until} ${daysWord}
    </p>
  </div>
  
  <p>Здравствуйте, <strong>${user.full_name || 'Партнёр'}</strong>!</p>
  
  <p>Напоминаем, что <strong>${dueDate}</strong> истекает срок вашей ежемесячной активации.</p>
  
  <div style="background: #f8f9fa; padding: 15px; border-radius: 8px; margin: 20px 0;">
    <p style="margin: 0;"><strong>Что нужно сделать:</strong></p>
    <p style="margin: 10px 0 0 0;">Совершите покупку на сумму от <strong>$40</strong>, чтобы сохранить активный статус и продолжать получать MLM-комиссии.</p>
  </div>
  
  <div style="text-align: center; margin: 30px 0;">
    <a href="https://mg-market.kz/shop?activation=true" 
       style="display: inline-block; background: ${color}; color: white; padding: 15px 30px; text-decoration: none; border-radius: 8px; font-weight: bold; font-size: 16px;">
      Перейти в магазин
    </a>
  </div>
  
  <hr style="border: none; border-top: 1px solid #eee; margin: 30px 0;">
  
  <p style="color: #666; font-size: 14px;">
    С уважением,<br>
    Команда MG Market
  </p>
  
  <p style="color: #999; font-size: 12px; margin-top: 20px;">
    Это автоматическое уведомление. Если вы не хотите получать такие письма, отключите уведомления в настройках профиля.
  </p>
</body>
</html>`;
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    console.log('Starting activation reminder job...');
    
    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
    
    // Find users who need reminders (1-5 days before activation_due_from)
    const today = new Date();
    const fiveDaysFromNow = new Date(today);
    fiveDaysFromNow.setDate(today.getDate() + 5);
    const oneDayFromNow = new Date(today);
    oneDayFromNow.setDate(today.getDate() + 1);
    
    const { data: users, error: usersError } = await supabase
      .from('profiles')
      .select('id, email, full_name, telegram_chat_id, telegram_username, activation_due_from')
      .eq('subscription_status', 'active')
      .eq('monthly_activation_completed', false)
      .not('activation_due_from', 'is', null)
      .gte('activation_due_from', oneDayFromNow.toISOString())
      .lte('activation_due_from', fiveDaysFromNow.toISOString());
    
    if (usersError) {
      console.error('Error fetching users:', usersError);
      throw usersError;
    }
    
    console.log(`Found ${users?.length || 0} users needing reminders`);
    
    const results = {
      telegram: { sent: 0, failed: 0, skipped: 0 },
      email: { sent: 0, failed: 0, skipped: 0 },
    };
    
    const todayDate = today.toISOString().split('T')[0];
    
    for (const user of users || []) {
      // Calculate days until activation
      const dueDate = new Date(user.activation_due_from);
      const daysUntil = Math.ceil((dueDate.getTime() - today.getTime()) / (1000 * 60 * 60 * 24));
      
      const userForReminder: UserForReminder = {
        ...user,
        days_until: daysUntil,
      };
      
      // Get user notification settings
      const { data: settings } = await supabase
        .from('notification_settings')
        .select('email_system, telegram_enabled')
        .eq('user_id', user.id)
        .single();
      
      const notificationSettings: NotificationSettings = settings || {
        email_system: false,
        telegram_enabled: true,
      };
      
      // Check if already sent today for this days_before
      const { data: existingLog } = await supabase
        .from('activation_reminder_logs')
        .select('id')
        .eq('user_id', user.id)
        .eq('days_before', daysUntil)
        .eq('sent_date', todayDate)
        .limit(1);
      
      const alreadySent = {
        telegram: existingLog?.some(l => false), // Will check per channel
        email: existingLog?.some(l => false),
      };
      
      // Check per channel
      const { data: telegramLog } = await supabase
        .from('activation_reminder_logs')
        .select('id')
        .eq('user_id', user.id)
        .eq('channel', 'telegram')
        .eq('days_before', daysUntil)
        .eq('sent_date', todayDate)
        .limit(1);
      
      const { data: emailLog } = await supabase
        .from('activation_reminder_logs')
        .select('id')
        .eq('user_id', user.id)
        .eq('channel', 'email')
        .eq('days_before', daysUntil)
        .eq('sent_date', todayDate)
        .limit(1);
      
      // Send Telegram notification
      if (notificationSettings.telegram_enabled && user.telegram_chat_id) {
        if (telegramLog && telegramLog.length > 0) {
          results.telegram.skipped++;
          console.log(`Telegram already sent to ${user.id} for ${daysUntil} days`);
        } else {
          const message = buildTelegramMessage(userForReminder);
          const telegramResult = await sendTelegramMessage(user.telegram_chat_id, message);
          
          await supabase.from('activation_reminder_logs').insert({
            user_id: user.id,
            channel: 'telegram',
            days_before: daysUntil,
            recipient: user.telegram_chat_id,
            success: telegramResult.success,
            error_message: telegramResult.error,
            sent_date: todayDate,
          });
          
          if (telegramResult.success) {
            results.telegram.sent++;
            console.log(`Telegram sent to ${user.full_name}`);
          } else {
            results.telegram.failed++;
            console.error(`Telegram failed for ${user.full_name}: ${telegramResult.error}`);
          }
        }
      } else {
        results.telegram.skipped++;
      }
      
      // Send Email notification
      if (notificationSettings.email_system && user.email) {
        if (emailLog && emailLog.length > 0) {
          results.email.skipped++;
          console.log(`Email already sent to ${user.id} for ${daysUntil} days`);
        } else {
          const daysWord = daysUntil === 1 ? 'день' : daysUntil <= 4 ? 'дня' : 'дней';
          const subject = `⏰ Напоминание: до активации осталось ${daysUntil} ${daysWord}`;
          const html = buildEmailHtml(userForReminder);
          const emailResult = await sendEmail(user.email, subject, html);
          
          await supabase.from('activation_reminder_logs').insert({
            user_id: user.id,
            channel: 'email',
            days_before: daysUntil,
            recipient: user.email,
            success: emailResult.success,
            error_message: emailResult.error,
            sent_date: todayDate,
          });
          
          if (emailResult.success) {
            results.email.sent++;
            console.log(`Email sent to ${user.email}`);
          } else {
            results.email.failed++;
            console.error(`Email failed for ${user.email}: ${emailResult.error}`);
          }
        }
      } else {
        results.email.skipped++;
      }
    }
    
    console.log('Reminder job completed:', results);
    
    return new Response(
      JSON.stringify({ 
        success: true, 
        users_processed: users?.length || 0,
        results 
      }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  } catch (error) {
    console.error('Error in send-activation-reminder:', error);
    return new Response(
      JSON.stringify({ success: false, error: error.message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }
});
