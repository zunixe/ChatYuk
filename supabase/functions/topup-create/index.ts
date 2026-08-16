// Supabase Edge Function: topup-create
// Dipanggil client (authenticated). Membuat order top-up + minta Snap token
// ke Midtrans. Server yang menentukan coins & harga (dari topup_packages),
// client hanya kirim package_id.
//
// Secrets yang diperlukan (set via `supabase secrets set`):
//   MIDTRANS_SERVER_KEY   — Server Key Midtrans (Sandbox/Production)
//   MIDTRANS_IS_PRODUCTION — 'true' | 'false' (default false = sandbox)
//   SUPABASE_URL           — otomatis tersedia
//   SUPABASE_SERVICE_ROLE_KEY — otomatis tersedia

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SERVICE_ROLE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const MIDTRANS_SERVER_KEY = Deno.env.get('MIDTRANS_SERVER_KEY') || '';
const IS_PROD = (Deno.env.get('MIDTRANS_IS_PRODUCTION') || 'false') === 'true';

const SNAP_URL = IS_PROD
  ? 'https://app.midtrans.com/snap/v1/transactions'
  : 'https://app.sandbox.midtrans.com/snap/v1/transactions';

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

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405);

  try {
    // Identitas user dari JWT (Authorization: Bearer <access_token>)
    const authHeader = req.headers.get('Authorization') || '';
    const jwt = authHeader.replace('Bearer ', '');
    if (!jwt) return json({ error: 'Unauthorized' }, 401);

    const admin = createClient(SUPABASE_URL, SERVICE_ROLE);
    const { data: userData, error: userErr } = await admin.auth.getUser(jwt);
    if (userErr || !userData?.user) return json({ error: 'Unauthorized' }, 401);
    const user = userData.user;

    const { package_id } = await req.json();
    if (!package_id) return json({ error: 'package_id required' }, 400);

    // Ambil paket dari DB (server-authoritative)
    const { data: pkg, error: pkgErr } = await admin
      .from('topup_packages')
      .select('id, coins, price_idr, active')
      .eq('id', package_id)
      .eq('active', true)
      .single();
    if (pkgErr || !pkg) return json({ error: 'Invalid package' }, 400);

    // order_id unik
    const orderId = `tp_${user.id.slice(0, 8)}_${Date.now()}`;

    if (!MIDTRANS_SERVER_KEY) {
      // Belum ada key → buat order pending tanpa Snap (mode setup)
      await admin.rpc('create_topup_order', {
        p_order_id: orderId, p_user: user.id, p_package_id: pkg.id, p_snap_token: null,
      });
      return json({
        error: 'MIDTRANS_SERVER_KEY not configured',
        order_id: orderId,
      }, 503);
    }

    // Panggil Midtrans Snap
    const auth = btoa(`${MIDTRANS_SERVER_KEY}:`);
    const snapBody = {
      transaction_details: { order_id: orderId, gross_amount: pkg.price_idr },
      item_details: [{
        id: pkg.id, price: pkg.price_idr, quantity: 1,
        name: `${pkg.coins} ChatYuk Coins`,
      }],
      customer_details: {
        first_name: (user.user_metadata?.nickname || 'ChatYuk User').slice(0, 40),
        email: user.email || `${user.id}@chatyuk.app`,
      },
      credit_card: { secure: true },
    };

    const snapRes = await fetch(SNAP_URL, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'Authorization': `Basic ${auth}`,
      },
      body: JSON.stringify(snapBody),
    });
    const snap = await snapRes.json();
    if (!snapRes.ok || !snap.token) {
      return json({ error: 'Midtrans error', detail: snap }, 502);
    }

    // Simpan order pending + snap token
    const { error: rpcErr } = await admin.rpc('create_topup_order', {
      p_order_id: orderId, p_user: user.id, p_package_id: pkg.id, p_snap_token: snap.token,
    });
    if (rpcErr) return json({ error: 'DB error', detail: rpcErr.message }, 500);

    return json({
      order_id: orderId,
      snap_token: snap.token,
      redirect_url: snap.redirect_url,
      coins: pkg.coins,
      price_idr: pkg.price_idr,
    });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
