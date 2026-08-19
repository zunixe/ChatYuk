// Supabase Edge Function: r (referral redirect)
// Dipanggil saat orang membuka link share:
//   https://<project>.functions.supabase.co/r?u=<sharer_uid>
// Alur:
//   1. Ambil IP pengklik (header x-forwarded-for).
//   2. RPC award_share_click(sharer, ip) — reward koin ke sharer (anti-farming).
//   3. Redirect 302 ke share_url (apkpure) — fallback unduh.
// Catatan: TIDAK mengembalikan HTML — Edge Runtime men-sandbox response HTML
// (CSP default-src 'none'; sandbox + Content-Type text/plain) sehingga browser
// menampilkan HTML mentah. Redirect 302 adalah cara yang andal.
// Publik (verify_jwt = false) — dibuka dari browser mana pun.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SERVICE_ROLE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const FALLBACK_URL = 'https://apkpure.com/chatyuk/com.chatyuk.chatyuk';

Deno.serve(async (req) => {
  const url = new URL(req.url);
  const sharer = url.searchParams.get('u');

  const admin = createClient(SUPABASE_URL, SERVICE_ROLE);

  // Ambil tujuan redirect (admin bisa ganti; fallback apkpure).
  let dest = FALLBACK_URL;
  try {
    const { data } = await admin.rpc('get_share_url');
    if (typeof data === 'string' && data.length > 0) dest = data;
  } catch (_) { /* pakai fallback */ }

  // Catat klik + reward (best-effort, jangan blokir redirect).
  if (sharer) {
    const ip = (req.headers.get('x-forwarded-for') || '')
      .split(',')[0].trim() || null;
    try {
      await admin.rpc('award_share_click', { p_sharer: sharer, p_ip: ip });
    } catch (_) { /* abaikan, tetap redirect */ }
  }

  return Response.redirect(dest, 302);
});