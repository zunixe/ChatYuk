// Supabase Edge Function: dummy-manage
// Dipanggil dari tab Dummy di Admin Panel (authenticated).
// Membuat akun dummy ANONYMOUS (tanpa email/password) via GoTrue
// signInAnonymously + RPC server-side, bebas rate-limit signup.
//
// Actions:
//   create     { nickname }  -> buat akun anonymous + profil + simpan refresh_token
//   delete     { uid }       -> hapus akun + history chat
//   list       {}            -> daftar akun dummy (tanpa kredensial)
//   set_status { uid, status } -> ubah status (online/idle/offline)

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SERVICE_ROLE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const ADMIN_EMAIL = 'zunixe@gmail.com';

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
    const authHeader = req.headers.get('Authorization') || '';
    const jwt = authHeader.replace('Bearer ', '');
    if (!jwt) return json({ error: 'Unauthorized' }, 401);

    const admin = createClient(SUPABASE_URL, SERVICE_ROLE);
    const { data: userData, error: userErr } = await admin.auth.getUser(jwt);
    if (userErr || !userData?.user) return json({ error: 'Unauthorized' }, 401);
    if (userData.user.email !== ADMIN_EMAIL) return json({ error: 'Forbidden' }, 403);

    const body = await req.json();
    const action = body.action;

    if (action === 'create') {
      const { nickname, gender, age, country, city } = body;
      if (!nickname) return json({ error: 'nickname required' }, 400);

      // Buat user anonymous langsung via endpoint GoTrue (fetch mentah supaya
      // sesi client service_role tidak berubah -> RPC berikutnya tetap aman).
      const anonRes = await fetch(`${SUPABASE_URL}/auth/v1/signup`, {
        method: 'POST',
        headers: {
          apikey: SERVICE_ROLE,
          Authorization: `Bearer ${SERVICE_ROLE}`,
          'Content-Type': 'application/json',
        },
        body: '{}',
      });
      const anon = await anonRes.json();
      if (!anonRes.ok || !anon.user?.id || !anon.refresh_token) {
        return json({ error: 'anon sign-in failed', detail: anon }, 500);
      }

      const { error: rpcErr } = await admin.rpc('admin_register_dummy', {
        p_uid: anon.user.id,
        p_nickname: nickname,
        p_refresh_token: anon.refresh_token,
        p_gender: gender || 'male',
        p_age: typeof age === 'number' ? age : 25,
        p_country: country || 'Indonesia',
        p_city: city || 'Jakarta',
      });
      if (rpcErr) return json({ error: 'DB error', detail: rpcErr.message }, 500);

      return json({ ok: true, uid: anon.user.id });
    }

    if (action === 'delete') {
      const { uid } = body;
      if (!uid) return json({ error: 'uid required' }, 400);
      const { data, error: rpcErr } = await admin.rpc('admin_delete_dummy', { p_uid: uid });
      if (rpcErr) return json({ error: 'DB error', detail: rpcErr.message }, 500);
      return json(data ?? { ok: true, chats_deleted: 0 });
    }

    if (action === 'list') {
      const { data, error: rpcErr } = await admin.rpc('admin_list_dummies');
      if (rpcErr) return json({ error: 'DB error', detail: rpcErr.message }, 500);
      return json({ dummies: data ?? [] });
    }

    if (action === 'set_status') {
      const { uid, status } = body;
      if (!uid || !['online', 'idle', 'offline'].includes(status)) {
        return json({ error: 'uid + status (online/idle/offline) required' }, 400);
      }
      const { data, error: rpcErr } = await admin.rpc('admin_set_dummy_status', { p_uid: uid, p_status: status });
      if (rpcErr) return json({ error: 'DB error', detail: rpcErr.message }, 500);
      return json(data ?? { ok: true });
    }

    if (action === 'renew') {
      // Regenerasi sesi GoTrue ASLI untuk dummy yang tokennya mati:
      // set password via Admin API -> login password -> refresh_token valid.
      const { uid } = body;
      if (!uid) return json({ error: 'uid required' }, 400);

      const { data: uData, error: uErr } = await admin.auth.admin.getUserById(uid);
      const user = uData?.user;
      if (uErr || !user) return json({ error: 'user not found', detail: uErr?.message }, 404);
      const email = user.email || `${crypto.randomUUID().slice(0, 8)}@dummy.chatyuk.local`;
      if (!user.email) {
        await admin.auth.admin.updateUserById(uid, { email, email_confirm: true });
      }
      const password = `dm-${crypto.randomUUID()}`;
      const { error: pErr } = await admin.auth.admin.updateUserById(uid, { password });
      if (pErr) return json({ error: 'set password failed', detail: pErr.message }, 500);

      const loginRes = await fetch(`${SUPABASE_URL}/auth/v1/token?grant_type=password`, {
        method: 'POST',
        headers: {
          apikey: SERVICE_ROLE,
          Authorization: `Bearer ${SERVICE_ROLE}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ email, password }),
      });
      const login = await loginRes.json();
      if (!loginRes.ok || !login.refresh_token) {
        return json({ error: 'password login failed', detail: login }, 500);
      }
      await admin.rpc('admin_update_dummy_token', {
        p_uid: uid,
        p_refresh_token: login.refresh_token,
      });
      return json({ ok: true, refresh_token: login.refresh_token });
    }

    return json({ error: 'Unknown action' }, 400);
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
