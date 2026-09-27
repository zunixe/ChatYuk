// Supabase Edge Function: outbox-worker (self-contained — tanpa import _shared)
//
// Menguras tabel public.outbox dan meneruskan tiap baris ke edge function
// yang sesuai. Menggantikan pola `net.http_post` SINKRON di trigger (bikin
// transaksi INSERT pesan/profil menunggu HTTP round-trip).
//
// Dipanggil pg_cron via net.http_post (dengan x-app-secret) atau service_role.
// Baris yang sudah terkirim di-set sent_at = now() (idempoten, tidak dobel).
//
// Skema payload per baris (kolom `type` = 'push' | 'fanout'):
//   type='push'   → { endpoint?:'send-push'(default), ...body utk send-push }
//   type='fanout' → { endpoint:'fanout', ...body utk fanout (type,id) }
// Backward-compat: baris lama { token,title,body,data } tanpa `endpoint`
// tetap dikirim ke send-push.
//
// Catatan: deploy via Management API single-file TIDAK menyertakan folder
// _shared → auth di-inline di sini (samakan dgn _shared/auth.ts).

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const BATCH = 200;            // maks baris per invokasi
const MAX_AGE_MIN = 60 * 24;  // baris > 24 jam dianggap basi → dibuang

function checkAppSecret(req: Request): boolean {
  const expected = Deno.env.get('APP_SHARED_SECRET');
  if (!expected) return false;
  return req.headers.get('x-app-secret') === expected;
}

function isServiceRoleJwt(req: Request): boolean {
  try {
    const token = (req.headers.get('Authorization') ?? '').replace(/^Bearer\s+/i, '');
    if (!token) return false;
    const payloadB64 = token.split('.')[1];
    if (!payloadB64) return false;
    const norm = payloadB64.replace(/-/g, '+').replace(/_/g, '/');
    const payload = JSON.parse(atob(norm));
    return payload.role === 'service_role';
  } catch (_) {
    return false;
  }
}

Deno.serve(async (req) => {
  try {
    if (req.method !== 'POST') return new Response('Method not allowed', { status: 405 });
    if (!checkAppSecret(req) && !isServiceRoleJwt(req)) {
      return new Response(JSON.stringify({ error: 'unauthorized' }), { status: 401 });
    }

    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const secret = Deno.env.get('APP_SHARED_SECRET') ?? '';
    const admin = createClient(supabaseUrl, serviceKey);

    // Ambil batch baris yang belum terkirim (paling lama dulu → urutan benar).
    const { data: rows, error } = await admin
      .from('outbox')
      .select('id, type, payload, created_at')
      .is('sent_at', null)
      .order('id', { ascending: true })
      .limit(BATCH);
    if (error) {
      return new Response(JSON.stringify({ error: error.message }), { status: 500 });
    }
    if (!rows || rows.length === 0) {
      return new Response(JSON.stringify({ ok: true, processed: 0 }), { status: 200 });
    }

    const nowMs = Date.now();
    let sent = 0, failed = 0, dropped = 0;

    for (const row of rows) {
      // Drop baris basi (worker lama mati) → cegah backlog abadi.
      const ageMin = (nowMs - new Date(row.created_at).getTime()) / 60000;
      if (ageMin > MAX_AGE_MIN) {
        await admin.from('outbox').update({ sent_at: new Date().toISOString() }).eq('id', row.id);
        dropped++;
        continue;
      }

      let ok = false;
      try {
        const p = row.payload ?? {};
        const endpoint = p.endpoint ?? (row.type === 'fanout' ? 'fanout' : 'send-push');
        // Buang field 'endpoint' dari body yang dikirim (bukan bagian kontrak edge).
        const { endpoint: _ignore, ...body } = p;

        if (endpoint === 'fanout') {
          const res = await fetch(`${supabaseUrl}/functions/v1/fanout`, {
            method: 'POST',
            headers: {
              'Content-Type': 'application/json',
              Authorization: `Bearer ${serviceKey}`,
            },
            body: JSON.stringify(body),
            signal: AbortSignal.timeout(8000),
          });
          ok = res.ok;
        } else {
          const res = await fetch(`${supabaseUrl}/functions/v1/send-push`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', 'x-app-secret': secret },
            body: JSON.stringify(body),
            signal: AbortSignal.timeout(8000),
          });
          ok = res.ok;
        }
      } catch (_) {
        ok = false;
      }

      if (ok) {
        await admin.from('outbox').update({ sent_at: new Date().toISOString() }).eq('id', row.id);
        sent++;
      } else {
        failed++; // biarkan sent_at null → dicoba lagi di invokasi berikutnya
      }
    }

    return new Response(JSON.stringify({ ok: true, processed: rows.length, sent, failed, dropped }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), { status: 500 });
  }
});
