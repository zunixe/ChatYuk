// Supabase Edge Function: play-voided-sync (self-contained).
//
// Dipanggil pg_cron harian (x-app-secret) atau service_role. Membaca daftar
// pembelian Google Play yang DIBATALKAN/REFUND (Voided Purchases API, maks
// 30 hari ke belakang) lalu memanggil RPC reverse_play_topup per token:
// koin pembeli ditarik balik dan pembeli + penerima koinnya ditahan
// (fraud_holds) sampai admin meninjau. Idempoten (order 'refunded' dilewati).
//
// Secrets: GOOGLE_PLAY_SA_JSON (sama dgn play-topup-verify), APP_SHARED_SECRET,
//   ANDROID_PACKAGE_NAME (opsional). SUPABASE_URL / SERVICE_ROLE otomatis.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SERVICE_ROLE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const SA_JSON = Deno.env.get('GOOGLE_PLAY_SA_JSON') || '';
const PKG = Deno.env.get('ANDROID_PACKAGE_NAME') || 'com.chatyuk.chatyuk';

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

function checkAppSecret(req: Request): boolean {
  const expected = Deno.env.get('APP_SHARED_SECRET');
  if (!expected) return false;
  return req.headers.get('x-app-secret') === expected;
}

function isServiceRoleJwt(req: Request): boolean {
  try {
    const token = (req.headers.get('Authorization') ?? '').replace(/^Bearer\s+/i, '');
    const payloadB64 = token.split('.')[1];
    if (!payloadB64) return false;
    const payload = JSON.parse(atob(payloadB64.replace(/-/g, '+').replace(/_/g, '/')));
    return payload.role === 'service_role';
  } catch (_) {
    return false;
  }
}

function b64url(input: Uint8Array | string): string {
  const bytes = typeof input === 'string' ? new TextEncoder().encode(input) : input;
  let bin = '';
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

async function getAccessToken(sa: { client_email: string; private_key: string }) {
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
  const pem = sa.private_key.replace(/-----[^-]+-----/g, '').replace(/\s+/g, '');
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey(
    'pkcs8', der, { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign'],
  );
  const sig = new Uint8Array(
    await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, new TextEncoder().encode(unsigned)),
  );
  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: `${unsigned}.${b64url(sig)}`,
    }),
  });
  const j = await res.json();
  if (!res.ok || !j.access_token) throw new Error(`token error: ${JSON.stringify(j)}`);
  return j.access_token as string;
}

type Voided = { purchaseToken: string; voidedReason?: number; voidedSource?: number };

Deno.serve(async (req) => {
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405);
  if (!checkAppSecret(req) && !isServiceRoleJwt(req)) {
    return json({ error: 'Unauthorized' }, 401);
  }
  if (!SA_JSON) return json({ error: 'GOOGLE_PLAY_SA_JSON not configured' }, 503);

  try {
    const accessToken = await getAccessToken(JSON.parse(SA_JSON));
    // API hanya mengizinkan ≤ 30 hari ke belakang.
    const startTime = Date.now() - 29 * 24 * 3600 * 1000;
    const voided: Voided[] = [];
    let page: string | undefined;
    do {
      const url = new URL(
        `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${PKG}/purchases/voidedpurchases`,
      );
      url.searchParams.set('startTime', String(startTime));
      url.searchParams.set('type', '0'); // 0 = in-app product
      url.searchParams.set('maxResults', '1000');
      if (page) url.searchParams.set('token', page);
      const r = await fetch(url, { headers: { Authorization: `Bearer ${accessToken}` } });
      const j = await r.json();
      if (!r.ok) return json({ error: 'Play voided list failed', detail: j }, 502);
      voided.push(...(j.voidedPurchases ?? []));
      page = j.tokenPagination?.nextPageToken;
    } while (page);

    const admin = createClient(SUPABASE_URL, SERVICE_ROLE);
    const results: unknown[] = [];
    for (const v of voided) {
      const reason = `voided:src${v.voidedSource ?? '?'}:r${v.voidedReason ?? '?'}`;
      const { data, error } = await admin.rpc('reverse_play_topup', {
        p_purchase_token: v.purchaseToken,
        p_reason: reason,
      });
      results.push(error ? { error: error.message } : data);
    }
    const reversed = results.filter(
      (r) => (r as { ok?: boolean; already?: boolean })?.ok &&
        !(r as { already?: boolean })?.already,
    ).length;
    return json({ ok: true, voided: voided.length, reversed });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
