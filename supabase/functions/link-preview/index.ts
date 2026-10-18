// ChatYuk: link preview (og:* metadata) — SERVER-SIDE fetch (mirip Telegram
// messages.getWebPage). Kenapa di server: (a) IP server lebih lolos anti-bot
// (TikTok/Shopee) daripada device, (b) hasil konsisten lintas device, (c) tak
// membocorkan IP user ke situs tujuan.
//
// Auth: verify_jwt Supabase (default gateway) — dipanggil klien yang login.
// Input : POST { url } — hanya http(s), panjang dibatasi (anti-SSRF sederhana).
// Output: { ok, title, description, image, siteName }
//
// Parser + fetch DIPINDAH ke `_shared/link_preview.ts` supaya dipakai bersama
// `send-push` (notifikasi pesan berisi link: deskripsi + gambar).

import {
  fetchPreviewWithFallback,
  MAX_URL_LEN,
} from '../_shared/link_preview.ts';

const FETCH_TIMEOUT_MS = 8000;

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') return json({ error: 'method' }, 405);

  let url = '';
  try {
    const body = await req.json();
    url = (body?.url ?? '').toString().trim();
  } catch (_) {
    return json({ error: 'bad json' }, 400);
  }
  if (!url || url.length > MAX_URL_LEN || !/^https?:\/\//i.test(url)) {
    return json({ error: 'bad url' }, 400);
  }

  try {
    const p = await fetchPreviewWithFallback(url, FETCH_TIMEOUT_MS);
    if (!p) return json({ ok: false, error: 'fetch failed' });
    return json({ ok: true, ...p });
  } catch (e) {
    return json({ ok: false, error: `${e}` });
  }
});
