// Supabase Edge Function: send-push
// Dipanggil oleh DB trigger saat ada message baru.
// Mengirim FCM V1 push notification via Firebase Cloud Messaging.

const crypto = await import('https://deno.land/std@0.203.0/crypto/mod.ts');

const FCM_SCOPE = 'https://www.googleapis.com/auth/firebase.messaging';
const FCM_ENDPOINT = 'https://fcm.googleapis.com/v1/projects/chatyuk-8470e/messages:send';

function base64UrlEncode(data) {
  const bytes = new TextEncoder().encode(data);
  let binary = '';
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

async function getAccessToken() {
  const sa = JSON.parse(Deno.env.get('FIREBASE_SERVICE_ACCOUNT') || '{}');
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
    .replace(/\s/g, '');
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

    const accessToken = await getAccessToken();
    // Data-only untuk tipe yang teksnya dirender client (bilingual):
    // online, follow, friend_request, subscribe. Lainnya pakai notification block.
    const dataOnlyTypes = ['online', 'follow', 'friend_request', 'subscribe', 'call'];
    const isDataOnly = dataOnlyTypes.includes(body.data?.type);
    const message = {
      message: {
        token,
        ...(isDataOnly
          ? {}
          : {
              notification: {
                title: title || 'Pesan baru',
                body: msgBody || 'Ada pesan baru',
              },
            }),
        data: data || {},
        android: { priority: 'high' },
      },
    };

    const res = await fetch(FCM_ENDPOINT, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${accessToken}`,
      },
      body: JSON.stringify(message),
    });

    const resBody = await res.text();
    return new Response(resBody, {
      status: res.ok ? 200 : res.status,
      headers: { 'Content-Type': 'application/json' },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    });
  }
});
