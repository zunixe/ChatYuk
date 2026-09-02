// Shared-secret auth untuk edge functions.
// Semua endpoint non-publik wajib cek header `x-app-secret` — nilainya
// di-set via `supabase secrets set APP_SHARED_SECRET=<random>`.
// DB trigger (net.http_post) ikut mengirim secret yang sama — simpan
// juga di app_settings jika dipanggil dari SQL.
export const APP_SECRET_HEADER = 'x-app-secret';

export function checkAppSecret(req: Request): boolean {
  const expected = Deno.env.get('APP_SHARED_SECRET');
  if (!expected) return false;
  const got = req.headers.get(APP_SECRET_HEADER);
  return got === expected;
}

export function unauthorized(): Response {
  return new Response(JSON.stringify({ error: 'unauthorized' }), {
    status: 401,
    headers: { 'Content-Type': 'application/json' },
  });
}

/// Verifikasi klaim service_role pada JWT Supabase (decode payload saja —
/// signature SUDAH diverifikasi gateway karena verify_jwt=true).
export function isServiceRoleJwt(req: Request): boolean {
  try {
    const auth = req.headers.get('Authorization') ?? '';
    const token = auth.replace(/^Bearer\s+/i, '');
    if (!token) return false;
    const payloadB64 = token.split('.')[1];
    if (!payloadB64) return false;
    const norm = payloadB64.replace(/-/g, '+').replace(/_/g, '/');
    const payload = JSON.parse(atob(norm));
    return payload.role === 'service_role';
  } catch (_) {
    return false;
  }
}
