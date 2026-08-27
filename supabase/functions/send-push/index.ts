// Supabase Edge Function: send-push
// Dipanggil oleh DB trigger saat ada message baru.
// Mengirim FCM V1 push notification via Firebase Cloud Messaging.
// WebCrypto global (crypto.subtle) tersedia di Supabase Edge Runtime.

const FCM_SCOPE = 'https://www.googleapis.com/auth/firebase.messaging';

// Satu project Firebase: chatyuk-7c9e4 (milik zunixe). Semua app (user &
// admin) mendaftar FCM di sini sejak migrasi flavor-gate. Project lama
// chatyuk-8470e tidak dipakai lagi.
const FCM_PROJECTS = [
  { id: 'chatyuk-7c9e4', envKey: 'FIREBASE_SERVICE_ACCOUNT' },
];

function base64UrlEncode(data) {
  const bytes = new TextEncoder().encode(data);
  let binary = '';
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

async function getAccessToken(saJson: Record<string, unknown>) {
  const sa = saJson;
  const now = Math.floor(Date.now() / 1000);
  const header = { alg: 'RS256', typ: 'JWT' };
  const payload = {
    iss: sa.client_email,
    scope: FCM_SCOPE,
    aud: sa.token_uri,
    iat: now,
    exp: now + 3600,
  };
  const signed = `${base64UrlEncode(JSON.stringify(header))}.${base64UrlEncode(JSON.stringify(payload))}`;
  const key = await crypto.subtle.importKey(
    'pkcs8',
    parsePem(sa.private_key),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const sig = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, new TextEncoder().encode(signed));
  const sigB64 = btoa(String.fromCharCode(...new Uint8Array(sig)))
    .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  const jwt = `${signed}.${sigB64}`;

  const res = await fetch(sa.token_uri, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}`,
  });
  const data = await res.json();
  return data.access_token;
}

function parsePem(pem) {
  const b64 = pem
    .replace('-----BEGIN PRIVATE KEY-----', '')
    .replace('-----END PRIVATE KEY-----', '')
    // Buang semua karakter non-base64 — melindungi dari newline yang
    // ter-escape (\n literal) saat env var di-copy dari dashboard.
    .replace(/[^A-Za-z0-9+/=]/g, '');
  const raw = atob(b64);
  const bytes = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i++) bytes[i] = raw.charCodeAt(i);
  return bytes;
}

Deno.serve(async (req) => {
  try {
    if (req.method !== 'POST') {
      return new Response('Method not allowed', { status: 405 });
    }
    const body = await req.json();
    const { token, title, body: msgBody, data } = body;
    if (!token) {
      return new Response(JSON.stringify({ error: 'no token' }), { status: 400 });
    }

    // Data-only untuk tipe yang teksnya dirender client (bilingual):
    // online, follow, friend_request, subscribe.
    // 'call' & 'call_ended' data-only → ditangani Flutter (localNotifications)
    // dengan id yang sama (notifIdForKey(chatId)) sehingga call_ended
    // MENG-UPDATE notif ringing yang sama, bukan nambah notifikasi baru.
    // Jika call_ended dikirim sebagai notification block, FCM auto-tampilkan
    // 1 notif sistem (id random) + Flutter tampilkan 1 lagi (id chatId) =
    // dobel (penyebab 3 notifikasi). Jadi HARUS data-only.
    const dataOnlyTypes = ['online', 'follow', 'friend_request', 'subscribe', 'call', 'call_ended'];
    const isDataOnly = dataOnlyTypes.includes(body.data?.type);

    // Untuk call, susun teks dari data (nama caller + tipe).
    const isCall = body.data?.type === 'call';
    const notifTitle = isCall
      ? (body.data?.fromName || body.data?.otherName || title || 'Panggilan')
      : (title || 'Pesan baru');
    const notifBody = isCall
      ? (body.data?.callType === 'video' ? 'Panggilan video' : 'Panggilan suara')
      : (msgBody || 'Ada pesan baru');

    const message = {
      message: {
        token,
        ...(isDataOnly
          ? {}
          : {
              notification: {
                title: notifTitle,
                body: notifBody,
              },
            }),
        data: data || {},
        android: {
          priority: 'high',
        },
      },
    };

    let lastStatus = 500;
    let lastBody = '{"error":"no project attempted"}';
    for (const proj of FCM_PROJECTS) {
      const saRaw = Deno.env.get(proj.envKey);
      if (!saRaw) continue;
      try {
        const sa = JSON.parse(saRaw);
        const accessToken = await getAccessToken(sa);
        const endpoint =
          `https://fcm.googleapis.com/v1/projects/${proj.id}/messages:send`;
        const res = await fetch(endpoint, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            Authorization: `Bearer ${accessToken}`,
          },
          body: JSON.stringify(message),
        });
        const resBody = await res.text();
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
