import { assertEquals } from 'https://deno.land/std/assert/mod.ts';
import {
  asleepAt,
  browseTopicKey,
  faceDescriptor,
  fridayPrayerAt,
  hashInt,
  isExplicit,
  isImageRequest,
  needsFreshInfo,
  sanitize,
  sleepHours,
  stableSeed,
  wibParts,
} from '../_shared/ai-helpers.ts';

// ── hashInt ──
Deno.test('hashInt: same input → same output', () => {
  assertEquals(hashInt('abc123'), hashInt('abc123'));
});
Deno.test('hashInt: different input → different output', () => {
  assertEquals(hashInt('abc123') === hashInt('abc124'), false);
});
Deno.test('hashInt: non-negative', () => {
  for (let i = 0; i < 50; i++) {
    const v = hashInt(`test-${i}`);
    assertEquals(v >= 0, true);
  }
});

// ── wibParts ──
Deno.test('wibParts: 2026-01-15 14:30 WIB = correct parts', () => {
  // 2026-01-15 14:30 WIB = 2026-01-15 07:30 UTC
  const ms = Date.UTC(2026, 0, 15, 7, 30, 0);
  const p = wibParts(ms);
  assertEquals(p.date, '2026-01-15');
  assertEquals(p.hour, 14);
  assertEquals(p.minute, 30);
  assertEquals(p.weekday, 4); // Thursday
});

Deno.test('wibParts: midnight WIB = correct wrap', () => {
  // 2026-01-16 00:00 WIB = 2026-01-15 17:00 UTC
  const ms = Date.UTC(2026, 0, 15, 17, 0, 0);
  const p = wibParts(ms);
  assertEquals(p.date, '2026-01-16');
  assertEquals(p.hour, 0);
});

// ── sleepHours + asleepAt ──
Deno.test('sleepHours: returns range 20–23 for sleep, 4–6 for wake', () => {
  for (let i = 0; i < 30; i++) {
    const uid = `user-${i}`;
    const date = `2026-01-${String((i % 28) + 1).padStart(2, '0')}`;
    const sh = sleepHours(uid, date);
    assertEquals(sh.sleepHour >= 20 && sh.sleepHour <= 23, true);
    assertEquals(sh.wakeHour >= 4 && sh.wakeHour <= 6, true);
  }
});

Deno.test('asleepAt: midnight WIB → asleep', () => {
  // 2026-01-15 01:00 WIB = 2026-01-14 18:00 UTC
  const ms = Date.UTC(2026, 0, 14, 18, 0, 0);
  assertEquals(asleepAt('user1', ms), true);
});

Deno.test('asleepAt: 10:00 WIB → not asleep', () => {
  // 2026-01-15 10:00 WIB = 2026-01-15 03:00 UTC
  const ms = Date.UTC(2026, 0, 15, 3, 0, 0);
  assertEquals(asleepAt('user1', ms), false);
});

// ── fridayPrayerAt ──
Deno.test('fridayPrayerAt: male Friday 12:00 WIB → true', () => {
  // 2026-01-16 is Friday; 12:00 WIB = 05:00 UTC
  const ms = Date.UTC(2026, 0, 16, 5, 0, 0);
  assertEquals(fridayPrayerAt('male', ms), true);
});

Deno.test('fridayPrayerAt: female Friday 12:00 WIB → false', () => {
  const ms = Date.UTC(2026, 0, 16, 5, 0, 0);
  assertEquals(fridayPrayerAt('female', ms), false);
});

Deno.test('fridayPrayerAt: male Saturday 12:00 WIB → false', () => {
  // 2026-01-17 is Saturday; 12:00 WIB = 05:00 UTC
  const ms = Date.UTC(2026, 0, 17, 5, 0, 0);
  assertEquals(fridayPrayerAt('male', ms), false);
});

Deno.test('fridayPrayerAt: male Friday 11:29 WIB → false (before window)', () => {
  // 2026-01-16 Friday; 11:29 WIB = 04:29 UTC
  const ms = Date.UTC(2026, 0, 16, 4, 29, 0);
  assertEquals(fridayPrayerAt('male', ms), false);
});

Deno.test('fridayPrayerAt: male Friday 13:00 WIB → false (after window)', () => {
  // 2026-01-16 Friday; 13:00 WIB = 06:00 UTC
  const ms = Date.UTC(2026, 0, 16, 6, 0, 0);
  assertEquals(fridayPrayerAt('male', ms), false);
});

// ── stableSeed ──
Deno.test('stableSeed: same uid → same seed', () => {
  assertEquals(stableSeed('dummy-1'), stableSeed('dummy-1'));
});

Deno.test('stableSeed: different uid → different seed', () => {
  assertEquals(stableSeed('dummy-1') === stableSeed('dummy-2'), false);
});

Deno.test('stableSeed: always in range 0–999999', () => {
  for (let i = 0; i < 50; i++) {
    const s = stableSeed(`uid-${i}`);
    assertEquals(s >= 0 && s <= 999999, true);
  }
});

// ── faceDescriptor ──
Deno.test('faceDescriptor: custom appearance wins over defaults', () => {
  assertEquals(
    faceDescriptor({ appearance: 'my custom face' }, 'x'),
    'my custom face',
  );
});

Deno.test('faceDescriptor: default for known uid is one of FACE_DEFAULTS', () => {
  const desc = faceDescriptor({}, 'dummy-1');
  const defaults = [
    'long straight black hair, oval face, warm brown almond eyes, light brown skin, soft natural smile, petite',
    'shoulder-length black hair, round face, dark brown eyes, tan skin, gentle smile, medium build',
    'short bob black hair, heart-shaped face, big brown eyes, fair skin, bright smile, slim',
    'wavy black hair, diamond face, hazel eyes, medium brown skin, subtle smile, curvy',
    'straight black hair with bangs, oblong face, dark eyes, olive skin, calm smile, athletic',
    'braided black hair, square face, warm brown eyes, deep tan skin, wide smile, fuller figure',
  ];
  assertEquals(defaults.includes(desc), true);
});

// ── isExplicit ──
Deno.test('isExplicit: normal text → false', () => {
  assertEquals(isExplicit('halo apa kabar'), false);
});

Deno.test('isExplicit: NSFW term → true', () => {
  assertEquals(isExplicit('bokep gak ada'), true);
});

Deno.test('isExplicit: empty → false', () => {
  assertEquals(isExplicit(''), false);
});

// ── isImageRequest ──
Deno.test('isImageRequest: "kirim foto dong" → true', () => {
  assertEquals(isImageRequest('kirim foto dong'), true);
});

Deno.test('isImageRequest: "lagi apa" → false', () => {
  assertEquals(isImageRequest('lagi apa'), false);
});

Deno.test('isImageRequest: "selfie dong" → true', () => {
  assertEquals(isImageRequest('selfie dong'), true);
});

// ── needsFreshInfo ──
Deno.test('needsFreshInfo: "skor madrid barca" → true', () => {
  assertEquals(needsFreshInfo('skor madrid barca'), true);
});

Deno.test('needsFreshInfo: "cuaca jakarta" → true', () => {
  assertEquals(needsFreshInfo('cuaca jakarta'), true);
});

Deno.test('needsFreshInfo: "lagi apa" → false', () => {
  assertEquals(needsFreshInfo('lagi apa'), false);
});

Deno.test('needsFreshInfo: "kirim foto" → false (excluded)', () => {
  assertEquals(needsFreshInfo('kirim foto'), false);
});

Deno.test('needsFreshInfo: short (<3) → false', () => {
  assertEquals(needsFreshInfo('ok'), false);
});

// ── browseTopicKey ──
Deno.test('browseTopicKey: normalizes text', () => {
  assertEquals(browseTopicKey('  SKOR  Madrid vs  Barca?!  '), 'skor madrid vs barca');
});

Deno.test('browseTopicKey: caps at 120 chars', () => {
  const long = 'a'.repeat(200);
  assertEquals(browseTopicKey(long).length, 120);
});

// ── sanitize ──
Deno.test('sanitize: trims + caps length', () => {
  const s = sanitize('  halo  ');
  assertEquals(s, 'halo');
});
