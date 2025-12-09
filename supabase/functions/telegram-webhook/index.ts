import { serve } from "https://deno.land/std@0.190.0/http/server.ts";
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.7.1';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

const TELEGRAM_BOT_TOKEN = Deno.env.get('TELEGRAM_BOT_TOKEN');
const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

interface TelegramUpdate {
  update_id: number;
  message?: {
    message_id: number;
    from: {
      id: number;
      is_bot: boolean;
      first_name: string;
      last_name?: string;
      username?: string;
      language_code?: string;
    };
    chat: {
      id: number;
      first_name: string;
      last_name?: string;
      username?: string;
      type: string;
    };
    date: number;
    text?: string;
  };
}

async function sendTelegramMessage(chatId: number, text: string): Promise<void> {
  await fetch(`https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      chat_id: chatId,
      text: text,
      parse_mode: 'HTML',
    }),
  });
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    const update: TelegramUpdate = await req.json();
    console.log('Received Telegram update:', JSON.stringify(update));
    
    if (!update.message?.text) {
      return new Response('OK', { status: 200 });
    }
    
    const chatId = update.message.chat.id;
    const username = update.message.from.username;
    const text = update.message.text.trim();
    const firstName = update.message.from.first_name;
    
    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
    
    // Handle /start command
    if (text === '/start' || text.startsWith('/start ')) {
      console.log(`User ${username} (${chatId}) started bot`);
      
      if (!username) {
        await sendTelegramMessage(chatId, 
          `Здравствуйте, ${firstName}!\n\n` +
          `Для привязки аккаунта вам нужно установить username в настройках Telegram.\n\n` +
          `После этого напишите /start ещё раз.`
        );
        return new Response('OK', { status: 200 });
      }
      
      // Try to find user by telegram_username
      const { data: profile, error: profileError } = await supabase
        .from('profiles')
        .select('id, full_name, telegram_chat_id')
        .eq('telegram_username', username)
        .single();
      
      if (profileError || !profile) {
        // User not found - might need to update username in profile
        console.log(`Profile not found for username: ${username}`);
        
        // Also try with @ prefix
        const { data: profileWithAt } = await supabase
          .from('profiles')
          .select('id, full_name, telegram_chat_id')
          .eq('telegram_username', `@${username}`)
          .single();
        
        if (profileWithAt) {
          // Update chat_id
          await supabase
            .from('profiles')
            .update({ telegram_chat_id: chatId.toString() })
            .eq('id', profileWithAt.id);
          
          await sendTelegramMessage(chatId,
            `✅ Аккаунт привязан!\n\n` +
            `Здравствуйте, ${profileWithAt.full_name || firstName}!\n\n` +
            `Ваш Telegram успешно привязан к аккаунту MG Market.\n` +
            `Теперь вы будете получать уведомления о:\n` +
            `• Приближающейся активации\n` +
            `• Новых партнёрах в вашей сети\n` +
            `• Начислении комиссий\n\n` +
            `Управлять уведомлениями можно в настройках профиля.`
          );
          return new Response('OK', { status: 200 });
        }
        
        await sendTelegramMessage(chatId,
          `Здравствуйте, ${firstName}!\n\n` +
          `Ваш Telegram (@${username}) не найден в системе MG Market.\n\n` +
          `Чтобы получать уведомления:\n` +
          `1. Войдите в личный кабинет на mg-market.kz\n` +
          `2. Откройте "Настройки" → "Профиль"\n` +
          `3. Укажите ваш Telegram: @${username}\n` +
          `4. Напишите сюда /start ещё раз`
        );
        return new Response('OK', { status: 200 });
      }
      
      // Check if already linked
      if (profile.telegram_chat_id === chatId.toString()) {
        await sendTelegramMessage(chatId,
          `Здравствуйте, ${profile.full_name || firstName}!\n\n` +
          `Ваш Telegram уже привязан к аккаунту MG Market. ✅\n\n` +
          `Вы получаете уведомления о:\n` +
          `• Приближающейся активации\n` +
          `• Новых партнёрах в вашей сети\n` +
          `• Начислении комиссий`
        );
        return new Response('OK', { status: 200 });
      }
      
      // Link chat_id to profile
      const { error: updateError } = await supabase
        .from('profiles')
        .update({ telegram_chat_id: chatId.toString() })
        .eq('id', profile.id);
      
      if (updateError) {
        console.error('Error updating profile:', updateError);
        await sendTelegramMessage(chatId,
          `Произошла ошибка при привязке аккаунта. Попробуйте позже.`
        );
        return new Response('OK', { status: 200 });
      }
      
      await sendTelegramMessage(chatId,
        `✅ Аккаунт привязан!\n\n` +
        `Здравствуйте, ${profile.full_name || firstName}!\n\n` +
        `Ваш Telegram успешно привязан к аккаунту MG Market.\n` +
        `Теперь вы будете получать уведомления о:\n` +
        `• Приближающейся активации\n` +
        `• Новых партнёрах в вашей сети\n` +
        `• Начислении комиссий\n\n` +
        `Управлять уведомлениями можно в настройках профиля.`
      );
      return new Response('OK', { status: 200 });
    }
    
    // Handle /status command
    if (text === '/status') {
      if (!username) {
        await sendTelegramMessage(chatId, `Установите username в Telegram для использования бота.`);
        return new Response('OK', { status: 200 });
      }
      
      const { data: profile } = await supabase
        .from('profiles')
        .select('full_name, subscription_status, monthly_activation_completed, activation_due_from')
        .or(`telegram_username.eq.${username},telegram_username.eq.@${username}`)
        .single();
      
      if (!profile) {
        await sendTelegramMessage(chatId, `Аккаунт не найден. Напишите /start для привязки.`);
        return new Response('OK', { status: 200 });
      }
      
      const statusEmoji = profile.subscription_status === 'active' ? '✅' : '❌';
      const activationEmoji = profile.monthly_activation_completed ? '✅' : '⏳';
      
      let dueInfo = '';
      if (profile.activation_due_from && !profile.monthly_activation_completed) {
        const dueDate = new Date(profile.activation_due_from);
        const now = new Date();
        const daysLeft = Math.ceil((dueDate.getTime() - now.getTime()) / (1000 * 60 * 60 * 24));
        dueInfo = `\n📅 До активации: ${daysLeft} дн.`;
      }
      
      await sendTelegramMessage(chatId,
        `📊 <b>Ваш статус</b>\n\n` +
        `${statusEmoji} Подписка: ${profile.subscription_status === 'active' ? 'Активна' : 'Неактивна'}\n` +
        `${activationEmoji} Активация: ${profile.monthly_activation_completed ? 'Выполнена' : 'Не выполнена'}` +
        dueInfo
      );
      return new Response('OK', { status: 200 });
    }
    
    // Handle /help command
    if (text === '/help') {
      await sendTelegramMessage(chatId,
        `📖 <b>Команды бота MG Market</b>\n\n` +
        `/start - Привязать Telegram к аккаунту\n` +
        `/status - Проверить статус подписки\n` +
        `/help - Показать эту справку\n\n` +
        `❓ По всем вопросам обращайтесь в поддержку на сайте.`
      );
      return new Response('OK', { status: 200 });
    }
    
    // Default response for unknown commands
    await sendTelegramMessage(chatId,
      `Неизвестная команда. Напишите /help для списка доступных команд.`
    );
    
    return new Response('OK', { status: 200 });
  } catch (error) {
    console.error('Error processing Telegram webhook:', error);
    return new Response('OK', { status: 200 }); // Always return 200 to Telegram
  }
});
