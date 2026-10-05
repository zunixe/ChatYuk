// Supabase Edge Function: email-unsubscribe (PUBLIK — tanpa JWT).
//
// Link di footer email marketing: ?u=<uid>&c=<campaign>&t=<token>.
// Menambahkan email ke email_suppressions (agar tidak dikirim lagi) lalu
// menampilkan halaman konfirmasi sederhana.
//
// WAJIB verify_jwt = false.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SERVICE_ROLE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

function page(title: string, msg: string): Response {
  const html = `<!doctype html><html lang="id"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>${title}</title></head>
<body style="font-family:sans-serif;background:#f5f5f7;margin:0;padding:48px 16px;text-align:center">
<div style="max-width:420px;margin:0 auto;background:#fff;border-radius:16px;padding:32px 24px">
<h2 style="margin:0 0 12px">${title}</h2>
<p style="color:#555;margin:0">${msg}</p>
</div></body></html>`;
  return new Response(html, {
    status: 200,
    headers: { 'Content-Type': 'text/html; charset=utf-8' },
  });
}

Deno.serve(async (req) => {
  const url = new URL(req.url);
  const uid = url.searchParams.get('u') ?? '';
  const cid = Number(url.searchParams.get('c') ?? 0);

  if (!uid) {
    return page('Link tidak valid', 'Tautan berhenti berlangganan tidak lengkap.');
  }

  try {
    const admin = createClient(SUPABASE_URL, SERVICE_ROLE);
    const { data: prof } = await admin
      .from('profiles')
      .select('email')
      .eq('id', uid)
      .maybeSingle();
    const email = `${prof?.email ?? ''}`;
    if (email) {
      await admin.from('email_suppressions').upsert(
        { email, uid, reason: 'unsubscribe' },
        { onConflict: 'email' },
      );
      if (cid > 0) {
        await admin.from('email_events').insert({
          campaign_id: cid,
          uid,
          email,
          type: 'unsubscribe',
        });
        try {
          await admin.rpc('email_recount_campaign', { p_id: cid });
        } catch (_) {}
      }
    }
  } catch (_) {}

  return page(
    'Berhenti berlangganan',
    'Anda tidak akan lagi menerima email promosi dari ChatYuk. Email penting (keamanan/akun) tetap dikirim.',
  );
});
