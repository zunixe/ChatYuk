// Supabase Edge Function: welcome-bonus
// Klaim welcome bonus YukCoin (anon 100 / register 100) via RPC
// credit_welcome_bonus (service_role). IP ditangkap SERVER-SIDE
// (x-forwarded-for) supaya anti-farming per IP bisa dipercaya.
//
// Dipanggil client authenticated. Body: { install_id, kind }
//   kind = 'anon' | 'register'
//
// Anti-farming (di RPC): sekali per install_id + limit klaim per IP / 24 jam.
//
// Secrets: SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY (otomatis).

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SERVICE_ROLE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
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
    const authHeader = req.headers.get('Authorization') || '';
    const jwt = authHeader.replace('Bearer ', '');
    if (!jwt) return json({ error: 'Unauthorized' }, 401);

    const admin = createClient(SUPABASE_URL, SERVICE_ROLE);
    const { data: userData, error: userErr } = await admin.auth.getUser(jwt);
    if (userErr || !userData?.user) return json({ error: 'Unauthorized' }, 401);
    const user = userData.user;

    const { install_id, kind } = await req.json();
    if (!install_id || !kind) {
      return json({ error: 'install_id & kind required' }, 400);
    }

    // IP asli dari proxy (Cloudflare/Supabase) — server-side, tepercaya.
    const ip = (req.headers.get('x-forwarded-for') || '')
      .split(',')[0]
      .trim() || null;

    const { data, error } = await admin.rpc('credit_welcome_bonus', {
      p_user: user.id,
      p_install_id: install_id,
      p_kind: kind,
      p_ip: ip,
    });
    if (error) return json({ error: 'DB error', detail: error.message }, 500);

    return json(data ?? { granted: false, coins: 0 });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
