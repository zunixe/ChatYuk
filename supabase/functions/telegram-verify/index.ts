// Supabase Edge Function: telegram-verify
//
// Sisi CLIENT verifikasi nomor HP via Telegram (verify_jwt = true).
// Dipanggil app Flutter dengan JWT user (authenticated).
//
// Aksi:
//   { action: "start"  } → buat sesi verifikasi; balikan deep-link Telegram.
//   { action: "status" } → status verifikasi diri sendiri.
//
// RPC DB yang dipakai: phone_verify_start(), phone_verify_status().
// Secrets: TELEGRAM_BOT_USERNAME.
//
// Konfirmasi (set verified) TIDAK di sini — itu di telegram-webhook setelah
// user menekan "Bagikan nomor".

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY')!;
const BOT_USERNAME = Deno.env.get('TELEGRAM_BOT_USERNAME') ?? '';

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') {
    return json({ error: 'method_not_allowed' }, 405);
  }

  // Client memakai JWT user → client Supabase dengan Authorization diteruskan
  // supaya auth.uid() benar di dalam RPC.
  const auth = req.headers.get('Authorization') ?? '';
  const sb = createClient(SUPABASE_URL, ANON_KEY, {
    global: { headers: { Authorization: auth } },
  });

  const body = await req.json().catch(() => ({}));
  const action = `${body?.action ?? ''}`;

  try {
    if (action === 'start') {
      const { data, error } = await sb.rpc('phone_verify_start');
      if (error) {
        // Teruskan alasan terstruktur ke app (rate_limited / phone_empty).
        const msg = `${error.message ?? ''}`;
        return json({ ok: false, reason: msg }, 200);
      }
      const token = `${(data as Record<string, unknown>)?.token ?? ''}`;
      return json({
        ok: true,
        token,
        url: BOT_USERNAME
          ? `https://t.me/${BOT_USERNAME}?start=${token}`
          : '',
        expires_at: (data as Record<string, unknown>)?.expires_at ?? null,
      });
    }

    if (action === 'status') {
      const { data, error } = await sb.rpc('phone_verify_status');
      if (error) return json({ ok: false, reason: `${error.message}` }, 200);
      return json({ ok: true, ...(data as Record<string, unknown>) });
    }

    return json({ error: 'unknown_action' }, 400);
  } catch (e) {
    return json({ ok: false, reason: `${e}` }, 500);
  }
});
