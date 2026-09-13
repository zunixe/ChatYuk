// FCM V1 helper bersama untuk edge functions (send-push & fanout).
// Auth JWT service-account + pertukaran OAuth token Google (dengan cache
// modul sampai `exp - 60 dtk` supaya tidak fetch token tiap pesan).

const FCM_SCOPE = 'https://www.googleapis.com/auth/firebase.messaging';

export function base64UrlEncode(data: string): string {
  const bytes = new TextEncoder().encode(data);
  let binary = '';
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

export function parsePem(pem: string): Uint8Array {
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

// Cache token per project (envKey) — hidup di level modul selama isolate
// edge function aktif. Tiap envKey service account punya token sendiri.
const tokenCache = new Map<string, { token: string; expAt: number }>();

// Ambil token valid dari cache DB lintas-invokasi (tabel fcm_token_cache).
// Cold-start isolate baru tetap hemat 1 HTTP Google bila baris masih segar.
async function readDbCache(
  admin: any,
  envKey: string,
): Promise<string | null> {
  try {
    const { data } = await admin
      .from('fcm_token_cache')
      .select('token, exp_at')
      .eq('service', envKey)
      .maybeSingle();
    const token = (data as any)?.token as string | undefined;
    const expAt = (data as any)?.exp_at as string | undefined;
    if (
      token && expAt &&
      new Date(expAt).getTime() - 60000 > Date.now()
    ) {
      return token;
    }
  } catch (_) {}
  return null;
}

async function writeDbCache(
  admin: any,
  envKey: string,
  token: string,
  expAtMs: number,
): Promise<void> {
  try {
    await admin.from('fcm_token_cache').upsert(
      {
        service: envKey,
        token,
        exp_at: new Date(expAtMs).toISOString(),
        updated_at: new Date().toISOString(),
      },
      { onConflict: 'service' },
    );
  } catch (_) {}
}

export async function getAccessToken(
  saJson: Record<string, unknown>,
  envKey: string,
  admin?: any,
): Promise<string> {
  const cached = tokenCache.get(envKey);
  if (cached && cached.expAt > Date.now()) return cached.token;
  // Lintas-invokasi: cek DB dulu sebelum sign + HTTP ke Google.
  if (admin != null) {
    const dbToken = await readDbCache(admin, envKey);
    if (dbToken) {
      tokenCache.set(envKey, {
        token: dbToken,
        // exp pasti tidak diketahui di sini — readDbCache sudah potong 60 dtk;
        // simpan pendek (5 mnt) agar tidak menahan token basi di memori.
        expAt: Date.now() + 5 * 60 * 1000,
      });
      return dbToken;
    }
  }

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
    parsePem(sa.private_key as string),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const sig = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    key,
    new TextEncoder().encode(signed),
  );
  const sigB64 = btoa(String.fromCharCode(...new Uint8Array(sig)))
    .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  const jwt = `${signed}.${sigB64}`;

  const res = await fetch(sa.token_uri as string, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}`,
    signal: AbortSignal.timeout(5000),
  });
  const data = await res.json();
  const token = data.access_token as string;
  // Cache sampai `exp - 60 dtk` (jeda aman agar tidak dipakai saat kedaluwarsa).
  const expSec = Number(data.expires_in) || 3600;
  const expAt = Date.now() + (expSec - 60) * 1000;
  tokenCache.set(envKey, { token, expAt });
  // Tulis ke DB agar isolate berikutnya (cold-start) ikut hemat.
  if (admin != null && token) {
    await writeDbCache(admin, envKey, token, expAt);
  }
  return token;
}
