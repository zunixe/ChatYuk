import { assert, assertEquals } from 'https://deno.land/std/assert/mod.ts';
import {
  FANOUT_TYPES,
  REQUIRED_PRIVATE_MESSAGE_COLS,
  SEND_PUSH_DATA_ONLY_TYPES,
  WALLET_KEYS,
  fanoutTopic,
} from './edge-contract.ts';

// ── Kontrak murni (tanpa I/O) ──

Deno.test('send-push: call & call_ended wajib data-only (anti dobel notif)', () => {
  const t = [...SEND_PUSH_DATA_ONLY_TYPES];
  assert(t.includes('call'), 'call harus data-only');
  assert(t.includes('call_ended'), 'call_ended harus data-only');
  assert(t.includes('call_canceled'), 'call_canceled harus data-only');
});

Deno.test('send-push: tipe sosial bilingual tetap data-only', () => {
  const t = [...SEND_PUSH_DATA_ONLY_TYPES];
  for (const k of ['online', 'follow', 'friend_request', 'subscribe']) {
    assert(t.includes(k as never), `${k} harus data-only`);
  }
});

Deno.test('fanout: topic terdokumentasi', () => {
  assertEquals(fanoutTopic('online', 'abc'), 'online-abc');
  assertEquals(fanoutTopic('timeline', 'x'), 'timeline-all');
  assertEquals(fanoutTopic('room', 'r1'), 'room-r1');
  assertEquals([...FANOUT_TYPES], ['online', 'timeline', 'room']);
});

Deno.test('wallet: kunci yang dipakai PointsProvider', () => {
  assertEquals([...WALLET_KEYS], ['bonus', 'earned', 'total']);
});

Deno.test('chat: kolom anti-regresi', () => {
  assert(([...REQUIRED_PRIVATE_MESSAGE_COLS] as string[]).includes('is_forwarded'));
});

// ── Sinkronisasi dengan index.ts asli (tripwire) ──

async function read(rel: string): Promise<string> {
  return await Deno.readTextFile(
    new URL(rel, import.meta.url),
  );
}

Deno.test('kontrak sinkron dengan send-push/index.ts', async () => {
  const src = await read('../send-push/index.ts');
  for (const t of SEND_PUSH_DATA_ONLY_TYPES) {
    assert(src.includes(`'${t}'`), `send-push/index.ts kehilangan '${t}'`);
  }
  assert(src.includes('no token/topic'), 'guard token/topic hilang');
  assert(src.includes('checkAppSecret'), 'guard app secret hilang');
});

Deno.test('kontrak sinkron dengan fanout/index.ts', async () => {
  const src = await read('../fanout/index.ts');
  assert(src.includes('isServiceRoleJwt'), 'guard service_role hilang');
  assert(src.includes('online-'), 'topic online- hilang');
  assert(src.includes('timeline-all'), 'topic timeline-all hilang');
  assert(src.includes('room-'), 'topic room- hilang');
});
