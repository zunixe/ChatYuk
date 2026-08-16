// Supabase Edge Function: r (referral redirect)
// Dipanggil saat orang membuka link share:
//   https://<project>.functions.supabase.co/r?u=<sharer_uid>
// Alur:
//   1. Ambil IP pengklik (header x-forwarded-for).
//   2. RPC award_share_click(sharer, ip) — reward koin ke sharer (anti-farming).
//   3. Tampilkan landing page: coba buka deep link app (bila terpasang),
//      lalu redirect otomatis ke share_url (apkpure) sebagai fallback unduh.
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

  // Escape URL untuk disisipkan ke HTML/JS.
  const esc = (s) => s.replace(/</g, '&lt;').replace(/"/g, '&quot;');
  const deepLink = sharer ? `chatyuk://referral?u=${sharer}` : null;
  const safeDest = esc(dest);
  const safeDeep = deepLink ? esc(deepLink) : null;

  // JS: coba buka deep link via iframe tersembunyi (tidak memicu alert),
  // lalu redirect ke halaman unduh setelah jeda bila app tidak terbuka.
  const openScript = safeDeep
    ? `
    var frame = document.createElement('iframe');
    frame.style.display = 'none';
    frame.src = "${safeDeep}";
    document.body.appendChild(frame);
    setTimeout(function () { window.location.href = "${safeDest}"; }, 1500);`
    : `setTimeout(function () { window.location.href = "${safeDest}"; }, 800);`;

  const html = `<!DOCTYPE html>
<html lang="id">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>ChatYuk</title>
<style>
  body { font-family: system-ui, sans-serif; background: #1E1E2E; color: #fff;
         display: flex; flex-direction: column; align-items: center; justify-content: center;
         min-height: 100vh; margin: 0; text-align: center; padding: 24px; }
  .btn { display: inline-block; margin-top: 20px; padding: 14px 28px; background: #2ECC71;
         color: #fff; border-radius: 24px; text-decoration: none; font-weight: 700; }
  .hint { color: #aaa; margin-top: 12px; font-size: 14px; }
</style>
</head>
<body>
  <h1>ChatYuk</h1>
  <p>Chat bebas, di mana saja.</p>
  <a class="btn" href="${safeDeep || safeDest}">Buka ChatYuk</a>
  <p class="hint">Jika aplikasi belum terpasang, kamu akan diarahkan ke halaman unduh.</p>
  <script>${openScript}</script>
</body>
</html>`;

  return new Response(html, {
    status: 200,
    headers: { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store' },
  });
});
