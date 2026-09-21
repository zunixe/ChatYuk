import { assertEquals, assert } from 'https://deno.land/std/assert/mod.ts';
import {
  APP_SECRET_HEADER,
  checkAppSecret,
  isServiceRoleJwt,
  unauthorized,
} from './auth.ts';

// ── Gerbang keamanan SEMUA edge function non-publik ──
// `checkAppSecret` = shared secret DB trigger → edge.
// `isServiceRoleJwt` = guard fanout (hanya service_role).
// Kalau salah satu bocor, siapa pun bisa memicu push massal / spam.

function req(headers: Record<string, string> = {}): Request {
  return new Request('https://example.com/fn', { method: 'POST', headers });
}

// JWT palsu: hanya payload yang dibaca (signature diverifikasi gateway).
function fakeJwt(payload: Record<string, unknown>): string {
  const b64 = (o: unknown) =>
    btoa(JSON.stringify(o)).replace(/\+/g, '-').replace(/\//g, '_').replace(
      /=+$/,
      '',
    );
  return `${b64({ alg: 'HS256', typ: 'JWT' })}.${b64(payload)}.sig`;
}

Deno.test('APP_SECRET_HEADER nama header stabil', () => {
  assertEquals(APP_SECRET_HEADER, 'x-app-secret');
});

Deno.test('checkAppSecret: false bila env tidak diset (fail-closed)', () => {
  const prev = Deno.env.get('APP_SHARED_SECRET');
  Deno.env.delete('APP_SHARED_SECRET');
  try {
    assertEquals(checkAppSecret(req({ 'x-app-secret': 'apa-saja' })), false);
  } finally {
    if (prev !== undefined) Deno.env.set('APP_SHARED_SECRET', prev);
  }
});

Deno.test('checkAppSecret: false bila header tidak dikirim', () => {
  Deno.env.set('APP_SHARED_SECRET', 'rahasia');
  try {
    assertEquals(checkAppSecret(req()), false);
  } finally {
    Deno.env.delete('APP_SHARED_SECRET');
  }
});

Deno.test('checkAppSecret: false bila secret beda', () => {
  Deno.env.set('APP_SHARED_SECRET', 'rahasia');
  try {
    assertEquals(checkAppSecret(req({ 'x-app-secret': 'salah' })), false);
  } finally {
    Deno.env.delete('APP_SHARED_SECRET');
  }
});

Deno.test('checkAppSecret: true bila secret cocok persis', () => {
  Deno.env.set('APP_SHARED_SECRET', 'rahasia');
  try {
    assertEquals(checkAppSecret(req({ 'x-app-secret': 'rahasia' })), true);
  } finally {
    Deno.env.delete('APP_SHARED_SECRET');
  }
});

Deno.test('unauthorized: 401 + JSON error', async () => {
  const res = unauthorized();
  assertEquals(res.status, 401);
  assertEquals(res.headers.get('Content-Type'), 'application/json');
  const body = await res.json();
  assertEquals(body.error, 'unauthorized');
});

Deno.test('isServiceRoleJwt: false tanpa header Authorization', () => {
  assertEquals(isServiceRoleJwt(req()), false);
});

Deno.test('isServiceRoleJwt: false untuk token kosong setelah Bearer', () => {
  assertEquals(isServiceRoleJwt(req({ Authorization: 'Bearer ' })), false);
});

Deno.test('isServiceRoleJwt: true untuk payload role=service_role', () => {
  const token = fakeJwt({ role: 'service_role' });
  assertEquals(isServiceRoleJwt(req({ Authorization: `Bearer ${token}` })), true);
});

Deno.test('isServiceRoleJwt: false untuk role=authenticated (user biasa)', () => {
  const token = fakeJwt({ role: 'authenticated' });
  assertEquals(isServiceRoleJwt(req({ Authorization: `Bearer ${token}` })), false);
});

Deno.test('isServiceRoleJwt: false untuk role=anon', () => {
  const token = fakeJwt({ role: 'anon' });
  assertEquals(isServiceRoleJwt(req({ Authorization: `Bearer ${token}` })), false);
});

Deno.test('isServiceRoleJwt: false untuk token rusak (bukan JWT)', () => {
  assertEquals(
    isServiceRoleJwt(req({ Authorization: 'Bearer bukan.jwt' })),
    false,
  );
  assertEquals(
    isServiceRoleJwt(req({ Authorization: 'Bearer abc.def.ghi' })),
    false,
  );
});

Deno.test('isServiceRoleJwt: header tanpa prefix Bearer tetap dibaca', () => {
  const token = fakeJwt({ role: 'service_role' });
  assertEquals(isServiceRoleJwt(req({ Authorization: token })), true);
});

Deno.test('isServiceRoleJwt: tidak tertipu role di tempat lain', () => {
  // `role` harus top-level payload, bukan nested.
  const token = fakeJwt({ data: { role: 'service_role' } });
  assert(
    isServiceRoleJwt(req({ Authorization: `Bearer ${token}` })) === false,
  );
});
