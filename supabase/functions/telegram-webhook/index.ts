// Supabase Edge Function: telegram-webhook
//
// Sisi PUBLIK verifikasi nomor HP via Telegram (verify_jwt = false).
// Dipanggil oleh server Telegram (bukan app). Autentikasi lewat header
// rahasia `x-telegram-bot-api-secret-token` yang diset saat setWebhook.
//
// Alur:
//   /start <token>   → simpan telegram_chat_id, kirim tombol "Verifikasi Nomor Saya".
//   message.contact  → RPC phone_verify_confirm(token, phone, chat_id).
//
// Token sesi disimpan di tabel phone_verifications (kolom telegram_chat_id)
// lewat chat_id; /start memetakan chat ke token. Contact membawa chat_id →
// cari token pending milik chat itu → konfirmasi.
//
// Secrets: TELEGRAM_BOT_TOKEN, TELEGRAM_WEBHOOK_SECRET.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SERVICE_ROLE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const BOT_TOKEN = Deno.env.get('TELEGRAM_BOT_TOKEN') ?? '';
const WEBHOOK_SECRET = Deno.env.get('TELEGRAM_WEBHOOK_SECRET') ?? '';

const admin = createClient(SUPABASE_URL, SERVICE_ROLE);

/** Kirim pesan. `opts`: { parse_mode?, keyboard?, resize_keyboard?,
 *  one_time_keyboard?, remove_keyboard? } — keyboard dikirim sebagai
 *  reply_markup; sisanya diteruskan langsung ke Telegram. */
async function sendMessage(
  chatId: number,
  text: string,
  opts?: {
    parse_mode?: string;
    keyboard?: unknown;
    resize_keyboard?: boolean;
    one_time_keyboard?: boolean;
    remove_keyboard?: boolean;
  },
): Promise<void> {
  if (!BOT_TOKEN) return;
  const body: Record<string, unknown> = { chat_id: chatId, text };
  if (opts?.parse_mode) body.parse_mode = opts.parse_mode;
  if (opts?.remove_keyboard) {
    body.reply_markup = { remove_keyboard: true };
  } else if (opts?.keyboard) {
    body.reply_markup = {
      keyboard: opts.keyboard,
      resize_keyboard: opts.resize_keyboard ?? true,
      one_time_keyboard: opts.one_time_keyboard ?? true,
    };
  }
  try {
    await fetch(`https://api.telegram.org/bot${BOT_TOKEN}/sendMessage`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });
  } catch (_) { /* best-effort */ }
}

/// Ambil token dari teks `/start <token>`.
function parseStartToken(text: string): string | null {
  const m = text.trim().match(/^\/start(?:\s+(.+))?$/);
  const t = (m?.[1] ?? '').trim();
  return t.length > 0 ? t : null;
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') {
    return new Response('Method not allowed', { status: 405 });
  }

  // Autentikasi: header rahasia Telegram (dibandingkan konstan waktu).
  const got = req.headers.get('x-telegram-bot-api-secret-token') ?? '';
  if (!WEBHOOK_SECRET || got !== WEBHOOK_SECRET) {
    return new Response(JSON.stringify({ ok: false }), { status: 401 });
  }

  const update = await req.json().catch(() => ({}));
  const message = update?.message;
  if (!message) return new Response('ok', { status: 200 });

  const chatId: number | undefined = message?.chat?.id;
  const text: string = `${message?.text ?? ''}`;

  // /start <token> → kaitkan chat ini dengan token verifikasi.
  if (chatId && text.startsWith('/start')) {
    const token = parseStartToken(text);
    if (token) {
      const { data } = await admin
        .from('phone_verifications')
        .update({ telegram_chat_id: chatId })
        .eq('token', token)
        .eq('status', 'pending')
        .select('id')
        .maybeSingle();

      if (data?.id) {
        await sendMessage(
          chatId,
          '👋 Halo! Ini *ChatYuk*.\n\n' +
            'Untuk menyelesaikan verifikasi, silakan tekan tombol *📱 Verifikasi Nomor Saya* di bawah. ' +
            'Telegram akan menampilkan konfirmasi "bagikan nomor" — itu *aman*, nomor kamu ' +
            'hanya dipakai ChatYuk untuk menandai akunmu terverifikasi (badge centang emas). ' +
            'Kami tidak pernah membagikan nomornya ke pengguna lain.',
          {
            parse_mode: 'Markdown',
            keyboard: [[{ text: '📱 Verifikasi Nomor Saya', request_contact: true }]],
            resize_keyboard: true,
            one_time_keyboard: true,
          },
        );
      } else {
        await sendMessage(
          chatId,
          'Maaf, link verifikasi ini sudah tidak berlaku 🙂\n\n' +
            'Silakan buka aplikasi *ChatYuk* dan mulai verifikasi ulang dari menu Profil.',
          { parse_mode: 'Markdown' },
        );
      }
    } else {
      await sendMessage(
        chatId,
        'Halo! Untuk memverifikasi nomor HP, silakan buka aplikasi *ChatYuk* ' +
          'dan ikuti langkah verifikasi dari menu Profil ya 🙂',
        { parse_mode: 'Markdown' },
      );
    }
    return new Response('ok', { status: 200 });
  }

  // message.contact → nomor dibagikan.
  const contact = message?.contact;
  if (chatId && contact?.phone_number) {
    const phone = `${contact.phone_number}`;

    // Cari sesi pending milik chat ini.
    const { data: row } = await admin
      .from('phone_verifications')
      .select('token')
      .eq('telegram_chat_id', chatId)
      .eq('status', 'pending')
      .order('created_at', { ascending: false })
      .limit(1)
      .maybeSingle();

    if (!row?.token) {
      await sendMessage(
        chatId,
        'Sepertinya tidak ada verifikasi yang sedang berjalan 🙂\n\n' +
          'Silakan buka aplikasi *ChatYuk* lalu mulai verifikasi dari menu Profil',
        { parse_mode: 'Markdown' },
      );
      return new Response('ok', { status: 200 });
    }

    const { data: res, error } = await admin.rpc('phone_verify_confirm', {
      p_token: row.token,
      p_phone: phone,
      p_chat_id: chatId,
    });

    const reason = `${(res as Record<string, unknown>)?.reason ?? ''}`;
    const okVerified = reason === 'verified' || reason === 'already_verified';
    if (error || !okVerified) {
      await sendMessage(
        chatId,
        'Hmm, nomor yang kamu bagikan tidak cocok dengan nomor yang ' +
          'didaftarkan di ChatYuk 🙂\n\nPastikan kamu membagikan nomor yang benar, ' +
          'lalu ulangi verifikasi dari aplikasi ChatYuk.',
        { remove_keyboard: true },
      );
    } else {
      await sendMessage(
        chatId,
        '✅ Nomor HP kamu *berhasil diverifikasi*!\n\n' +
          'Terima kasih sudah memverifikasi. Silakan kembali ke aplikasi *ChatYuk* — ' +
          'badge centang emas sudah aktif di profilmu 🎉',
        { parse_mode: 'Markdown', remove_keyboard: true },
      );
    }
    return new Response('ok', { status: 200 });
  }

  return new Response('ok', { status: 200 });
});
