// Supabase Edge Function: ipaymu-callback
// Webhook notifikasi dari iPaymu (Redirect Payment). Verifikasi signature
// HMAC-SHA256 lalu credit coin via RPC credit_topup_order (idempoten).
// Coin masuk bucket 'topup'.
//
// Set URL ini di dashboard iPaymu: Integration > Setting > Callback URL:
//   https://<project-ref>.supabase.co/functions/v1/ipaymu-callback
//
// Secret untuk validasi signature = Nomor VA (IPAYMU_VA).

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SERVICE_ROLE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const IPAYMU_VA = Deno.env.get('IPAYMU_VA') || '';

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status, headers: { 'Content-Type': 'application/json' },
  });
}

async function hmacSha256Hex(key: string, input: string): Promise<string> {
  const enc = new TextEncoder();
  const keyData = await crypto.subtle.importKey(
    'raw', enc.encode(key), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign'],
  );
  const sig = await crypto.subtle.sign('HMAC', keyData, enc.encode(input));
  return [...new Uint8Array(sig)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

function normalize(raw: Record<string, unknown>): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const key of Object.keys(raw)) {
    let val = raw[key];
    if (key === 'is_escrow') {
      out[key] = val === 'true' || val === '1' || val === 1;
    } else if (['trx_id', 'status_code', 'transaction_status_code', 'paid_off'].includes(key)) {
      out[key] = parseInt(String(val), 10);
    } else if (key === 'additional_info') {
      out[key] = val === '[]' ? [] : val;
    } else {
      out[key] = String(val);
    }
  }
  if (!('additional_info' in out)) out['additional_info'] = [];
  return out;
}

function phpKsort(obj: Record<string, unknown>): Record<string, unknown> {
  const sorted: Record<string, unknown> = {};
  Object.keys(obj).sort((a, b) => a.localeCompare(b)).forEach((k) => { sorted[k] = obj[k]; });
  return sorted;
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405);

  try {
    const contentType = req.headers.get('content-type') || '';
    let raw: Record<string, unknown>;
    if (contentType.includes('application/json')) {
      raw = await req.json();
    } else {
      const form = await req.formData();
      raw = {};
      for (const [k, v] of form.entries()) raw[k] = v;
    }

    // Hapus field signature bila ada di body
    delete raw.signature;

    // Validasi signature (secret key = Nomor VA)
    const receivedSig = req.headers.get('x-signature') || '';
    const normalized = normalize(raw);
    const sorted = phpKsort(normalized);
    let jsonStr = JSON.stringify(sorted);
    jsonStr = jsonStr.replace(/\//g, '\\/');
    const expected = await hmacSha256Hex(IPAYMU_VA, jsonStr);

    if (receivedSig && expected !== receivedSig) {
      return json({ error: 'Invalid signature' }, 403);
    }

    const referenceId = String(raw.reference_id ?? raw.referenceId ?? '');
    const statusCode = parseInt(String(raw.status_code ?? raw.transaction_status_code ?? '0'), 10);

    // status_code 1 = berhasil, 0 = pending, -2 = expired
    let mapped: 'paid' | 'pending' | 'expired' | 'cancelled' | 'failed' = 'pending';
    if (statusCode === 1 || statusCode === 6) mapped = 'paid';
    else if (statusCode === -2) mapped = 'expired';
    else if (statusCode < 0) mapped = 'cancelled';
    else mapped = 'pending';

    if (!referenceId) return json({ error: 'Missing reference_id' }, 400);

    const admin = createClient(SUPABASE_URL, SERVICE_ROLE);
    const { error } = await admin.rpc('credit_topup_order', {
      p_order_id: referenceId,
      p_status: mapped,
      p_provider_ref: String(raw.trx_id ?? ''),
      p_raw: raw,
    });
    if (error) return json({ error: 'DB error', detail: error.message }, 500);

    return json({ ok: true, status: mapped });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
