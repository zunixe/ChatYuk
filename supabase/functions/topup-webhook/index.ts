// Supabase Edge Function: topup-webhook
// Endpoint notifikasi (HTTP notification) dari Midtrans. Verifikasi signature
// SHA512(order_id + status_code + gross_amount + ServerKey) lalu credit coin
// via RPC credit_topup_order (idempoten). Coin masuk bucket 'topup'.
//
// Set URL ini di Midtrans Dashboard > Settings > Configuration >
//   Payment Notification URL:
//   https://<project-ref>.functions.supabase.co/topup-webhook
//
// Secrets: MIDTRANS_SERVER_KEY, SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SERVICE_ROLE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const MIDTRANS_SERVER_KEY = Deno.env.get('MIDTRANS_SERVER_KEY') || '';

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status, headers: { 'Content-Type': 'application/json' },
  });
}

// SHA-512 hex
async function sha512Hex(input: string): Promise<string> {
  const data = new TextEncoder().encode(input);
  const buf = await crypto.subtle.digest('SHA-512', data);
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405);

  try {
    const body = await req.json();
    const orderId = body.order_id;
    const statusCode = body.status_code;
    const grossAmount = body.gross_amount;
    const signatureKey = body.signature_key;
    const txStatus = body.transaction_status;
    const fraudStatus = body.fraud_status;
    const transactionId = body.transaction_id;

    if (!orderId || !statusCode || !grossAmount || !signatureKey) {
      return json({ error: 'Invalid payload' }, 400);
    }

    // Verifikasi signature Midtrans
    const expected = await sha512Hex(`${orderId}${statusCode}${grossAmount}${MIDTRANS_SERVER_KEY}`);
    if (expected !== signatureKey) {
      return json({ error: 'Invalid signature' }, 403);
    }

    // Map status Midtrans → status order kita
    // settlement/capture(accept) = paid; pending = pending; lainnya = failed/expired
    let mapped = 'pending';
    if (txStatus === 'settlement' || (txStatus === 'capture' && fraudStatus === 'accept')) {
      mapped = 'paid';
    } else if (txStatus === 'pending') {
      mapped = 'pending';
    } else if (txStatus === 'expire') {
      mapped = 'expired';
    } else if (txStatus === 'cancel' || txStatus === 'deny') {
      mapped = 'cancelled';
    } else {
      mapped = 'failed';
    }

    const admin = createClient(SUPABASE_URL, SERVICE_ROLE);
    const { data, error } = await admin.rpc('credit_topup_order', {
      p_order_id: orderId,
      p_status: mapped,
      p_provider_ref: transactionId || null,
      p_raw: body,
    });
    if (error) return json({ error: 'DB error', detail: error.message }, 500);

    return json({ ok: true, result: data });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
