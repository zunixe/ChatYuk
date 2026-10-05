// Supabase Edge Function: email-worker (self-contained — tanpa import _shared).
//
// Mengirim email marketing campaign via Resend API. Dipanggil pg_cron /
// outbox-worker (x-app-secret) atau service_role.
//
// Alur per invokasi:
//   1. Cari baris outbox type='email_batch' (belum terkirim) → campaign_id.
//   2. email_worker_claim(campaign_id, batch) → daftar penerima 'pending'.
//   3. Untuk tiap penerima: bangun HTML (pixel open + redirect click +
//      footer unsubscribe) → kirim via Resend (Idempotency-Key per recipient).
//   4. Update status recipient + counter campaign.
//   5. Tidak ada 'pending' lagi → tandai campaign 'sent'.
//
// Secrets yang dipakai: RESEND_API_KEY, PUBLIC_FUNCTIONS_URL (opsional),
//   APP_SHARED_SECRET. Base URL diturunkan dari SUPABASE_URL.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const BATCH = 100;

function checkAppSecret(req: Request): boolean {
  const expected = Deno.env.get('APP_SHARED_SECRET');
  if (!expected) return false;
  return req.headers.get('x-app-secret') === expected;
}

function isServiceRoleJwt(req: Request): boolean {
  try {
    const auth = req.headers.get('Authorization') ?? '';
    const token = auth.replace(/^Bearer\s+/i, '');
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

function escapeHtml(s: string): string {
  return s
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

/// Ubah tautan <a href="..."> → redirect lewat email-track (ukur klik).
function wrapLinks(html: string, base: string, cid: number, uid: string): string {
  return html.replace(/href\s*=\s*"([^"]+)"/gi, (_m, url: string) => {
    if (url.startsWith('mailto:') || url.includes('/functions/v1/email-')) {
      return `href="${url}"`;
    }
    const enc = encodeURIComponent(url);
    return `href="${base}/functions/v1/email-track?t=click&c=${cid}&u=${uid}&url=${enc}"`;
  });
}

function buildHtml(
  body: string,
  base: string,
  cid: number,
  uid: string,
  unsubToken: string,
): string {
  const withLinks = wrapLinks(body, base, cid, uid);
  const pixel = `<img src="${base}/functions/v1/email-track?t=open&c=${cid}&u=${uid}" width="1" height="1" alt="" style="display:none" />`;
  const unsub = `<div style="margin-top:24px;padding-top:12px;border-top:1px solid #ddd;font-size:12px;color:#888;text-align:center">
    <a href="${base}/functions/v1/email-unsubscribe?u=${uid}&c=${cid}&t=${unsubToken}" style="color:#888">Berhenti berlangganan</a>
  </div>`;
  return `<!doctype html><html><body style="font-family:sans-serif;color:#222;max-width:600px;margin:0 auto;padding:16px">
${withLinks}${unsub}${pixel}</body></html>`;
}

Deno.serve(async (req) => {
  try {
    if (req.method !== 'POST') {
      return new Response('Method not allowed', { status: 405 });
    }
    if (!checkAppSecret(req) && !isServiceRoleJwt(req)) {
      return new Response(JSON.stringify({ error: 'unauthorized' }), { status: 401 });
    }

    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const resendKey = Deno.env.get('RESEND_API_KEY') ?? '';
    if (!resendKey) {
      return new Response(JSON.stringify({ error: 'RESEND_API_KEY belum diset' }), { status: 500 });
    }

    const admin = createClient(supabaseUrl, serviceKey);

    // Setelan pengirim + kill-switch.
    const { data: cfg } = await admin
      .from('app_settings')
      .select('email_marketing_enabled, email_from_name, email_from_address, email_daily_cap')
      .eq('id', 'global')
      .maybeSingle();
    if (!cfg || cfg.email_marketing_enabled !== true) {
      return new Response(JSON.stringify({ ok: true, skipped: 'disabled' }), { status: 200 });
    }
    const fromName = cfg.email_from_name || 'ChatYuk';
    const fromAddr = cfg.email_from_address || 'noreply@chatyuk.com';
    const from = `${fromName} <${fromAddr}>`;

    // Daily cap: batasi total kirim/hari (resend kuota). Hitung dari
    // email_events type='send' hari ini (UTC).
    const cap = Number(cfg.email_daily_cap ?? 500);
    if (cap > 0) {
      const sinceUtc = new Date();
      sinceUtc.setUTCHours(0, 0, 0, 0);
      const { count: sentToday } = await admin
        .from('email_events')
        .select('id', { count: 'exact', head: true })
        .eq('type', 'send')
        .gte('created_at', sinceUtc.toISOString());
      if ((sentToday ?? 0) >= cap) {
        return new Response(
          JSON.stringify({ ok: true, skipped: 'daily_cap', sent_today: sentToday }),
          { status: 200 },
        );
      }
    }

    // Ambil campaign dari outbox (email_batch) yang belum diproses.
    const { data: batches } = await admin
      .from('outbox')
      .select('id, payload')
      .is('sent_at', null)
      .eq('type', 'email_batch')
      .order('id', { ascending: true })
      .limit(5);

    if (!batches || batches.length === 0) {
      return new Response(JSON.stringify({ ok: true, processed: 0 }), { status: 200 });
    }

    let sentTotal = 0;
    let failTotal = 0;

    for (const b of batches) {
      const cid = Number((b.payload ?? {}).campaign_id ?? 0);
      if (!cid) {
        await admin.from('outbox').update({ sent_at: new Date().toISOString() }).eq('id', b.id);
        continue;
      }

      // Tandai outbox SEGERA (idempoten) — jangan biarkan batch diproses ulang
      // berkali-kali dalam satu siklus; sisa 'pending' diambil lewat claim
      // berikutnya (cron/min berikutnya). Cegah duplikat.
      await admin.from('outbox').update({ sent_at: new Date().toISOString() }).eq('id', b.id);

      const { data: claim, error: claimErr } = await admin.rpc('email_worker_claim', {
        p_campaign_id: cid,
        p_batch: BATCH,
      });
      if (claimErr || !claim) {
        failTotal++;
        await admin
          .from('email_campaigns')
          .update({ last_error: claimErr?.message ?? 'claim failed' })
          .eq('id', cid);
        // Buka kembali outbox agar dicoba lagi nanti (claim gagal).
        await admin.from('outbox').update({ sent_at: null }).eq('id', b.id);
        continue;
      }

      const recipients = claim.recipients ?? [];
      const subject = claim.subject ?? '(tanpa subjek)';
      const body = claim.html_body ?? '';

      for (const r of recipients) {
        const uid = String(r.uid ?? '');
        const unsubToken = btoa(`${cid}:${uid}`).replace(/=+$/, '');
        const html = buildHtml(body, supabaseUrl, cid, uid, unsubToken);
        try {
          const res = await fetch('https://api.resend.com/emails', {
            method: 'POST',
            headers: {
              Authorization: `Bearer ${resendKey}`,
              'Content-Type': 'application/json',
              // Idempotency: percobaan ulang penerima yang sama tidak dobel.
              'Idempotency-Key': `camp-${cid}-rcpt-${r.id}`,
            },
            body: JSON.stringify({
              from,
              to: [r.email],
              subject,
              html,
            }),
            signal: AbortSignal.timeout(10000),
          });
          if (res.ok) {
            const jr = await res.json().catch(() => ({}));
            await admin.rpc('email_mark_sent', {
              p_recipient_id: r.id,
              p_msg_id: `${jr?.id ?? ''}`,
            });
            await admin.from('email_events').insert({
              campaign_id: cid,
              uid: uid || null,
              email: r.email,
              type: 'send',
            });
            sentTotal++;
          } else {
            const txt = await res.text().catch(() => '');
            const permanent = res.status >= 400 && res.status < 500;
            await admin.rpc('email_mark_failed', {
              p_recipient_id: r.id,
              p_error: `${res.status}: ${txt}`,
              p_permanent: permanent,
            });
            failTotal++;
          }
        } catch (e) {
          // Transient (network/timeout) → mark_failed memutuskan retry/failed.
          await admin.rpc('email_mark_failed', {
            p_recipient_id: r.id,
            p_error: `${e}`,
            p_permanent: false,
          });
          failTotal++;
        }
      }

      // Update counter + finalisasi (campaign 'sent' bila tak ada pending).
      try {
        await admin.rpc('email_recount_campaign', { p_id: cid });
        await admin.rpc('email_finalize_campaign', { p_id: cid });
      } catch (_) {}
    }

    return new Response(
      JSON.stringify({ ok: true, sent: sentTotal, failed: failTotal }),
      { status: 200, headers: { 'Content-Type': 'application/json' } },
    );
  } catch (e) {
    return new Response(JSON.stringify({ error: `${e}` }), { status: 500 });
  }
});
