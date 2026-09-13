// Supabase Edge Function: send-push
// Dipanggil oleh DB trigger saat ada message baru.
// Mengirim FCM V1 push notification via Firebase Cloud Messaging.
// WebCrypto global (crypto.subtle) tersedia di Supabase Edge Runtime.

import { checkAppSecret, unauthorized } from '../_shared/auth.ts';
import { getAccessToken } from '../_shared/fcm.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

// Satu project Firebase: chatyuk-7c9e4 (milik zunixe). Semua app (user &
// admin) mendaftar FCM di sini sejak migrasi flavor-gate. Project lama
// chatyuk-8470e tidak dipakai lagi.
const FCM_PROJECTS = [
  { id: 'chatyuk-7c9e4', envKey: 'FIREBASE_SERVICE_ACCOUNT' },
];

Deno.serve(async (req) => {
  try {
    if (req.method !== 'POST') {
      return new Response('Method not allowed', { status: 405 });
    }
    // Auth: hanya caller yang punya APP_SHARED_SECRET (DB trigger kirim
    // header yang sama). Tanpa ini siapa pun bisa spam push ke seluruh user.
    if (!checkAppSecret(req)) return unauthorized();
    const body = await req.json();
    const { token, topic, title, body: msgBody, data } = body;
    if (!token && !topic) {
      return new Response(JSON.stringify({ error: 'no token/topic' }), { status: 400 });
    }
    // Resolve avatar path -> public URL untuk BigPicture (Android) / image (iOS)
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    if (data?.avatarUrl && data.avatarUrl.startsWith('avatars/')) {
      data.avatarUrl = `${supabaseUrl}/storage/v1/object/public/chat-photos/${data.avatarUrl}`;
    }

    // Data-only untuk tipe yang teksnya dirender client (bilingual):
    // online, follow, friend_request, subscribe.
    // 'call' & 'call_ended' data-only → ditangani Flutter (localNotifications)
    // dengan id yang sama (notifIdForKey(chatId)) sehingga call_ended
    // MENG-UPDATE notif ringing yang sama, bukan nambah notifikasi baru.
    // Jika call_ended dikirim sebagai notification block, FCM auto-tampilkan
    // 1 notif sistem (id random) + Flutter tampilkan 1 lagi (id chatId) =
    // dobel (penyebab 3 notifikasi). Jadi HARUS data-only.
    const dataOnlyTypes = ['online', 'follow', 'friend_request', 'subscribe', 'call', 'call_ended', 'call_canceled', 'message', 'broadcast'];
    const isDataOnly = dataOnlyTypes.includes(body.data?.type);

    // Untuk call, susun teks dari data (nama caller + tipe).
    const isCall = body.data?.type === 'call';
    const notifTitle = isCall
      ? (body.data?.fromName || body.data?.otherName || title || 'Panggilan')
      : (title || 'Pesan baru');
    const notifBody = isCall
      ? (body.data?.callType === 'video' ? 'Panggilan video' : 'Panggilan suara')
      : (msgBody || 'Ada pesan baru');

    // Avatar untuk FCM image (BigPicture) — hanya jika ada URL http
    const avatarImage = data?.avatarUrl && data.avatarUrl.startsWith('http') ? data.avatarUrl : undefined;
    const message = {
      message: {
        ...(token ? { token } : {}),
        ...(topic ? { topic } : {}),
        ...(isDataOnly
          ? {}
          : {
              notification: {
                title: notifTitle,
                body: notifBody,
                ...(avatarImage ? { image: avatarImage } : {}),
              },
            }),
        data: data ? Object.fromEntries(Object.entries(data).map(([k,v])=>[k, String(v)])) : {},
        android: {
          priority: 'high',
          ...(avatarImage && !isDataOnly ? { notification: { image: avatarImage } } : {}),
        },
        apns: avatarImage ? { payload: { aps: { 'mutable-content': 1 } }, fcm_options: { image: avatarImage } } : undefined,
      },
    };

    let lastStatus = 500;
    let lastBody = '{"error":"no project attempted"}';
    // Satu client admin untuk cache token DB + cleanup token mati.
    const admin = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    );
    for (const proj of FCM_PROJECTS) {
      const saRaw = Deno.env.get(proj.envKey);
      if (!saRaw) continue;
      try {
        const sa = JSON.parse(saRaw);
        const accessToken = await getAccessToken(sa, proj.envKey, admin);
        const endpoint =
          `https://fcm.googleapis.com/v1/projects/${proj.id}/messages:send`;
        const res = await fetch(endpoint, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            Authorization: `Bearer ${accessToken}`,
          },
          body: JSON.stringify(message),
          signal: AbortSignal.timeout(5000),
        });
        const resBody = await res.text();
        // Auto-clean token mati: FCM 404 NotRegistered / 410 = token tidak
        // terdaftar lagi (app di-install ulang, dsb). Bersihkan supaya
        // tidak dipukul berulang (boros kuota + notif tidak pernah sampai).
        if (token && !res.ok && /NotRegistered|UNREGISTERED/.test(resBody)) {
          try {
            await admin
              .from('profiles')
              .update({ fcm_token: null })
              .eq('fcm_token', token);
            await admin.from('user_devices').delete().eq('fcm_token', token);
          } catch (_) {}
        }
        if (res.ok) {
          return new Response(resBody, {
            status: 200,
            headers: { 'Content-Type': 'application/json' },
          });
        }
        lastStatus = res.status;
        lastBody = resBody;
      } catch (projErr) {
        lastBody = JSON.stringify({ error: String(projErr), project: proj.id });
      }
    }
    return new Response(lastBody, {
      status: lastStatus,
      headers: { 'Content-Type': 'application/json' },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    });
  }
});
