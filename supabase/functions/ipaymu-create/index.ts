// Supabase Edge Function: ipaymu-create
// Dipanggil client (authenticated). Membuat order top-up + minta URL checkout
// iPaymu (Redirect Payment). Server yang menentukan coins & harga (dari
// topup_packages), client hanya kirim package_id.
//
// Secrets (via `supabase secrets set`):
//   IPAYMU_VA          — Nomor Virtual Account iPaymu (sandbox/production)
//   IPAYMU_API_KEY     — API Key iPaymu
//   IPAYMU_IS_PRODUCTION — 'true' | 'false' (default false = sandbox)
//
// Alur:
//   1. client POST {package_id}
//   2. server ambil paket dari DB
//   3. POST /api/v2/payment (redirect) dengan signature HMAC-SHA256
//   4. return {session_id, url, coins, price_idr, order_id}
//
// Signature: Method:VA:SHA256(body):APIKey → HMAC-SHA256(key=APIKey)

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SERVICE_ROLE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const IPAYMU_VA = Deno.env.get('IPAYMU_VA') || '';
const IPAYMU_API_KEY = Deno.env.get('IPAYMU_API_KEY') || '';
const IS_PROD = (Deno.env.get('IPAYMU_IS_PRODUCTION') || 'false') === 'true';

const BASE = IS_PROD ? 'https://my.ipaymu.com' : 'https://sandbox.ipaymu.com';

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

async function sha256Hex(input: string): Promise<string> {
  const data = new TextEncoder().encode(input);
  const buf = await crypto.subtle.digest('SHA-256', data);
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

async function hmacSha256Hex(key: string, input: string): Promise<string> {
  const enc = new TextEncoder();
  const keyData = await crypto.subtle.importKey(
    'raw', enc.encode(key), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign'],
  );
  const sig = await crypto.subtle.sign('HMAC', keyData, enc.encode(input));
  return [...new Uint8Array(sig)].map((b) => b.toString(16).padStart(2, '0')).join('');
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

    const { package_id } = await req.json();
    if (!package_id) return json({ error: 'package_id required' }, 400);

    const { data: pkg, error: pkgErr } = await admin
      .from('topup_packages')
      .select('id, coins, price_idr, active')
      .eq('id', package_id)
      .eq('active', true)
      .single();
    if (pkgErr || !pkg) return json({ error: 'Invalid package' }, 400);

    if (!IPAYMU_VA || !IPAYMU_API_KEY) {
      return json({ error: 'iPaymu credentials not configured' }, 503);
    }

    // order_id unik (disimpan di topup_orders + dipakai referenceId)
    const orderId = `tp_${user.id.slice(0, 8)}_${Date.now()}`;

    const notifyUrl = `${SUPABASE_URL}/functions/v1/ipaymu-callback`;
    const returnUrl = `${SUPABASE_URL}/functions/v1/ipaymu-return?status=success`;
    const cancelUrl = `${SUPABASE_URL}/functions/v1/ipaymu-return?status=cancel`;

    const body = {
      product: [`${pkg.coins} ChatYuk Coins`],
      qty: ['1'],
      price: [String(pkg.price_idr)],
      description: ['ChatYuk top-up'],
      returnUrl,
      notifyUrl,
      cancelUrl,
      referenceId: orderId,
      buyerName: (user.user_metadata?.nickname || 'ChatYuk User').slice(0, 40),
      buyerEmail: user.email || `${user.id}@chatyuk.app`,
    };

    const bodyStr = JSON.stringify(body);
    const bodyHash = await sha256Hex(bodyStr);
    const stringToSign = `POST:${IPAYMU_VA}:${bodyHash}:${IPAYMU_API_KEY}`;
    const signature = await hmacSha256Hex(IPAYMU_API_KEY, stringToSign);
    const timestamp = new Date().toISOString().replace(/[-:TZ.]/g, '').slice(0, 14);

    const ipaymuRes = await fetch(`${BASE}/api/v2/payment`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'va': IPAYMU_VA,
        'signature': signature,
        'timestamp': timestamp,
      },
      body: bodyStr,
    });

    const ipaymu = await ipaymuRes.json();
    if (!ipaymuRes.ok || ipaymu.Status !== 200 || !ipaymu.Data?.Url) {
      return json({ error: 'iPaymu error', detail: ipaymu }, 502);
    }

    // Simpan order pending + session id
    await admin.rpc('create_topup_order', {
      p_order_id: orderId,
      p_user: user.id,
      p_package_id: pkg.id,
      p_snap_token: ipaymu.Data.SessionID,
    });

    return json({
      order_id: orderId,
      session_id: ipaymu.Data.SessionID,
      redirect_url: ipaymu.Data.Url,
      coins: pkg.coins,
      price_idr: pkg.price_idr,
    });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
