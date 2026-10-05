// Supabase Edge Function: email-track (PUBLIK — tanpa JWT).
//
// Dipanggil dari dalam email marketing:
//   - Pixel open : ?t=open&c=<campaign>&u=<uid>
//   - Klik link  : ?t=click&c=<campaign>&u=<uid>&url=<encoded>
//
// Mencatat email_events + update email_recipients (opened_at/clicked_at,
// HANYA sekali per penerima). Menghormati suppression (tetap redirect).
//
// WAJIB verify_jwt = false (lihat supabase/config.toml).

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SERVICE_ROLE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

// GIF 1x1 transparan.
const PIXEL = Uint8Array.from([
  0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 0x01, 0x00, 0x01, 0x00, 0x80, 0x00,
  0x00, 0xff, 0xff, 0xff, 0x00, 0x00, 0x00, 0x21, 0xf9, 0x04, 0x01, 0x00,
  0x00, 0x00, 0x00, 0x2c, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00,
  0x00, 0x02, 0x02, 0x44, 0x01, 0x00, 0x3b,
]);

Deno.serve(async (req) => {
  const url = new URL(req.url);
  const t = url.searchParams.get('t') ?? 'open';
  const cid = Number(url.searchParams.get('c') ?? 0);
  const uid = url.searchParams.get('u') ?? '';
  const dest = url.searchParams.get('url') ?? '';
  const ip =
    req.headers.get('x-forwarded-for')?.split(',')[0]?.trim() ?? '';
  const ua = req.headers.get('user-agent') ?? '';

  try {
    if (cid > 0) {
      const admin = createClient(SUPABASE_URL, SERVICE_ROLE);
      const type = t === 'click' ? 'click' : 'open';

      await admin.from('email_events').insert({
        campaign_id: cid,
        uid: uid || null,
        type,
        url: dest || null,
        user_agent: ua,
        ip,
      });

      // Update recipient (first-touch saja; jangan downgrade 'clicked').
      if (uid) {
        const { data: rows } = await admin
          .from('email_recipients')
          .select('id, opened_at, clicked_at')
          .eq('campaign_id', cid)
          .eq('uid', uid)
          .order('id', { ascending: true })
          .limit(1);
        const existing = rows && rows.length > 0 ? rows[0] : null;
        if (existing) {
          const patch: Record<string, unknown> = {};
          if (type === 'click') {
            if (!existing.clicked_at) {
              patch['clicked_at'] = new Date().toISOString();
            }
            // Jangan turunkan status 'clicked' → cukup naikkan bila belum.
            patch['status'] = 'clicked';
          } else if (!existing.opened_at) {
            patch['opened_at'] = new Date().toISOString();
            // 'opened' hanya bila belum pernah diklik.
            if (!existing.clicked_at) patch['status'] = 'opened';
          }
          if (Object.keys(patch).length > 0) {
            await admin.from('email_recipients').update(patch).eq('id', existing.id);
          }
        }
      }

      // Recount ringan (agregat campaign).
      try {
        await admin.rpc('email_recount_campaign', { p_id: cid });
      } catch (_) {}
    }
  } catch (_) {
    // Tracking tidak boleh menghalangi respons.
  }

  if (t === 'click') {
    const target = dest && /^https?:\/\//i.test(dest) ? dest : 'https://chatyuk.com';
    return new Response(null, { status: 302, headers: { Location: target } });
  }

  return new Response(PIXEL, {
    status: 200,
    headers: {
      'Content-Type': 'image/gif',
      'Cache-Control': 'no-store, no-cache, must-revalidate, private',
      'Content-Length': String(PIXEL.length),
    },
  });
});
