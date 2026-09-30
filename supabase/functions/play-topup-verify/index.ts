// Supabase Edge Function: play-topup-verify
// Dipanggil client (authenticated) SETELAH Google Play Billing menghasilkan
// purchase_token. Verifikasi token ke Google Play Developer API, lalu kredit
// coin via RPC credit_play_topup (idempoten by token).
//
// Secrets yang diperlukan (set via `supabase secrets set`):
//   GOOGLE_PLAY_SA_JSON     — JSON service account (Play Developer API) [wajib]
//   ANDROID_PACKAGE_NAME    — mis. com.chatyuk.chatyuk (default)
//   SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY — otomatis
//
// Service account butuh akses "Manage orders & subscriptions" di Play Console
// + scope https://www.googleapis.com/auth/androidpublisher.
//
// Tanpa GOOGLE_PLAY_SA_JSON → 503 (mode setup), tidak mengkredit apa pun.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SERVICE_ROLE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const SA_JSON = Deno.env.get('GOOGLE_PLAY_SA_JSON') || '';
const PKG = Deno.env.get('ANDROID_PACKAGE_NAME') || 'com.chatyuk.chatyuk';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

// ── OAuth2: tukar service-account JWT → access token (tanpa library) ──
function b64url(input: Uint8Array | string): string {
  const bytes = typeof input === 'string' ? new TextEncoder().encode(input) : input;
  let bin = '';
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

async function getAccessToken(sa: {
  client_email: string;
  private_key: string;
}): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = b64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const claim = b64url(JSON.stringify({
    iss: sa.client_email,
    scope: 'https://www.googleapis.com/auth/androidpublisher',
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
  }));
  const unsigned = `${header}.${claim}`;

  // Import PKCS8 private key.
  const pem = sa.private_key.replace(/-----[^-]+-----/g, '').replace(/\s+/g, '');
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey(
    'pkcs8', der,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false, ['sign'],
  );
  const sig = new Uint8Array(
    await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, new TextEncoder().encode(unsigned)),
  );
  const jwt = `${unsigned}.${b64url(sig)}`;

  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: jwt,
    }),
  });
  const j = await res.json();
  if (!res.ok || !j.access_token) throw new Error(`token error: ${JSON.stringify(j)}`);
  return j.access_token as string;
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405);

  try {
    const authHeader = req.headers.get('Authorization') || '';
    const jwt = authHeader.replace('Bearer ', '');
    if (!jwt) return json({ error: 'Unauthorized' }, 401);

    const admin = createClient(SUPABASE_URL, SERVICE_ROLE);
    const { data: userData, error: userErr } = await admin.auth.getUser(jwt);
    if (userErr || !userData?.user) return json({ error: 'Unauthorized' }, 401);
    const user = userData.user;

    const { product_id, purchase_token } = await req.json();
    if (!product_id || !purchase_token) {
      return json({ error: 'product_id & purchase_token required' }, 400);
    }

    if (!SA_JSON) {
      return json({ error: 'GOOGLE_PLAY_SA_JSON not configured' }, 503);
    }

    // Verifikasi ke Google Play Developer API (product = one-time).
    const sa = JSON.parse(SA_JSON);
    const accessToken = await getAccessToken(sa);
    const url =
      `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${PKG}` +
      `/purchases/products/${encodeURIComponent(product_id)}/tokens/${encodeURIComponent(purchase_token)}`;
    const vres = await fetch(url, {
      headers: { Authorization: `Bearer ${accessToken}` },
    });
    const vjson = await vres.json();
    if (!vres.ok) {
      return json({ error: 'Play verify failed', detail: vjson }, 502);
    }
    // purchaseState 0 = purchased. (1 = canceled, 2 = pending)
    const purchaseState = vjson.purchaseState;
    if (purchaseState !== 0) {
      return json({ error: 'Not purchased', state: purchaseState }, 409);
    }

    // Kredit coin (idempoten by token).
    const { data: credit, error: rpcErr } = await admin.rpc('credit_play_topup', {
      p_user: user.id,
      p_play_product_id: product_id,
      p_purchase_token: purchase_token,
      p_play_order_id: vjson.orderId ?? null,
      p_raw: vjson,
    });
    if (rpcErr) return json({ error: 'DB error', detail: rpcErr.message }, 500);

    return json({
      ok: true,
      coins: credit?.coins ?? 0,
      already: credit?.already ?? false,
    });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
