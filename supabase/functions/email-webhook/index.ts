// Supabase Edge Function: email-webhook (Resend events).
//
// Terima event Resend (delivered/bounced/complained/opened/clicked) →
// update email_recipients + email_events. Auth: x-app-secret.
//
// Set di dashboard Resend: Webhooks → URL ini, event yang diinginkan.
//
// Catatan: tracking open/click UTAMA lewat email-track (pixel sendiri);
// webhook ini pelengkap untuk delivered/bounce/complaint.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

function checkAppSecret(req: Request): boolean {
  const expected = Deno.env.get('APP_SHARED_SECRET');
  if (!expected) return false;
  return req.headers.get('x-app-secret') === expected;
}

Deno.serve(async (req) => {
  try {
    if (req.method !== 'POST') {
      return new Response('Method not allowed', { status: 405 });
    }
    if (!checkAppSecret(req)) {
      return new Response(JSON.stringify({ error: 'unauthorized' }), { status: 401 });
    }

    const body = await req.json().catch(() => ({}));
    const type = `${body?.type ?? ''}`; // email.delivered, email.bounced, ...
    const data = body?.data ?? {};
    const email = `${data?.to ?? ''}`.replace(/[<>]/g, '').trim();

    const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
    const SERVICE_ROLE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const admin = createClient(SUPABASE_URL, SERVICE_ROLE);

    // Map tipe Resend → aksi.
    let evType = '';
    if (type === 'email.delivered') evType = 'delivered';
    else if (type === 'email.bounced') evType = 'bounce';
    else if (type === 'email.complained') evType = 'complaint';
    else if (type === 'email.opened') evType = 'open';
    else if (type === 'email.clicked') evType = 'click';

    if (email) {
      // Cari penerima terbaru untuk email ini.
      const { data: rec } = await admin
        .from('email_recipients')
        .select('id, campaign_id, uid, opened_at, clicked_at')
        .eq('email', email)
        .order('id', { ascending: false })
        .limit(1)
        .maybeSingle();

      if (rec) {
        if (evType === 'delivered') {
          await admin
            .from('email_recipients')
            .update({ status: 'delivered' })
            .eq('id', rec.id)
            .in('status', ['sent']);
        } else if (evType === 'bounce') {
          await admin
            .from('email_recipients')
            .update({ status: 'bounced', error: 'bounce' })
            .eq('id', rec.id);
          await admin.from('email_suppressions').upsert(
            { email, uid: rec.uid, reason: 'bounce' },
            { onConflict: 'email' },
          );
        } else if (evType === 'complaint') {
          await admin
            .from('email_recipients')
            .update({ status: 'bounced', error: 'complaint' })
            .eq('id', rec.id);
          await admin.from('email_suppressions').upsert(
            { email, uid: rec.uid, reason: 'complaint' },
            { onConflict: 'email' },
          );
        }

        if (evType) {
          await admin.from('email_events').insert({
            campaign_id: rec.campaign_id,
            uid: rec.uid,
            email,
            type: evType,
          });
          try {
            await admin.rpc('email_recount_campaign', { p_id: rec.campaign_id });
          } catch (_) {}
        }
      } else if (evType === 'bounce' || evType === 'complaint') {
        await admin.from('email_suppressions').upsert(
          { email, uid: null, reason: evType === 'bounce' ? 'bounce' : 'complaint' },
          { onConflict: 'email' },
        );
      }
    }

    return new Response(JSON.stringify({ ok: true }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: `${e}` }), { status: 500 });
  }
});
