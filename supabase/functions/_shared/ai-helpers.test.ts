import { assertEquals } from 'https://deno.land/std/assert/mod.ts';
import {
  asleepAt,
  applySleepToSchedule,
  browseTopicKey,
  chartUrl,
  extractChartJs,
  summarizeNewsRss,  faceDescriptor,
  fridayPrayerAt,
  hashInt,
  hasWord,
  isExplicit,
  userWantsImage,
  extractMermaid,
  isInsult,
  needsFreshInfo,
  sanitize,
  sleepHours,
  stableSeed,
  wibParts,
  // Diekstrak dari index.ts (2026-09-20) — sekarang SATU sumber produksi.
  capEmoji,
  capSentences,
  capLines,
  extractEmojis,
  bannedEmojisFromHistory,
  stripBannedEmojis,
  contentText,
  historyTimeLabel,
  stripTimeLabel,
  bulan,
  parseImagePrompt,
  stripMoodMarker,
  fluxFree,
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

// ── userWantsImage (cermin index.ts) ──
Deno.test('userWantsImage: "kirim foto dong" → true', () => {
  assertEquals(userWantsImage('kirim foto dong'), true);
});

Deno.test('userWantsImage: "lagi apa" → false', () => {
  assertEquals(userWantsImage('lagi apa'), false);
});

Deno.test('userWantsImage: "selfie dong" → true', () => {
  assertEquals(userWantsImage('selfie dong'), true);
});

Deno.test('userWantsImage: "mau liat wajahmu" → true', () => {
  assertEquals(userWantsImage('mau liat wajahmu'), true);
});

// ── extractMermaid (cermin index.ts) ──
Deno.test('extractMermaid: ambil blok pertama', () => {
  const t = 'ini arsitekturnya\n```mermaid\nflowchart TD\n A-->B\n```\nok';
  assertEquals(extractMermaid(t), 'flowchart TD\n A-->B');
});

Deno.test('extractMermaid: tanpa blok → null', () => {
  assertEquals(extractMermaid('cuma teks biasa'), null);
});

Deno.test('extractMermaid: blok tak tertutup → null', () => {
  assertEquals(extractMermaid('```mermaid\nflowchart TD\n A-->B'), null);
});

// ── extractChartJs + chartUrl (cermin index.ts) ──
Deno.test('extractChartJs: pie valid → JSON canonical', () => {
  const t =
    'ini analisanya\n```chartjs\n{"type":"pie","data":{"labels":["A","B"],"datasets":[{"data":[30,70]}]}}\n```\nok';
  assertEquals(
    extractChartJs(t),
    '{"type":"pie","data":{"labels":["A","B"],"datasets":[{"data":[30,70]}]}}',
  );
});

Deno.test('extractChartJs: tanpa blok → null', () => {
  assertEquals(extractChartJs('cuma teks biasa'), null);
});

Deno.test('extractChartJs: JSON rusak → null', () => {
  assertEquals(extractChartJs('```chartjs\n{type:pie,\n```'), null);
});

Deno.test('extractChartJs: type di luar whitelist → null', () => {
  assertEquals(
    extractChartJs('```chartjs\n{"type":"scatter","data":{"datasets":[{}]}}\n```'),
    null,
  );
});

Deno.test('extractChartJs: tanpa datasets → null', () => {
  assertEquals(
    extractChartJs('```chartjs\n{"type":"bar","data":{"labels":["A"]}}\n```'),
    null,
  );
});

Deno.test('chartUrl: memuat config ter-encode + format png', () => {
  const u = chartUrl('{"type":"bar","data":{"datasets":[{}]}}');
  assertEquals(u.startsWith('https://quickchart.io/chart?c='), true);
  assertEquals(u.includes('format=png'), true);
  assertEquals(u.includes('%22type%22'), true);
});

// ── summarizeNewsRss (cermin index.ts) ──
Deno.test('summarizeNewsRss: 3 item + media + tanggal', () => {
  const xml =
    '<rss><channel>' +
    '<item><title>Skor Madrid Menang - Kompas.com</title><pubDate>Sat, 12 Sep 2026 02:32:38 GMT</pubDate></item>' +
    '<item><title>Klasemen Pekan Ini - Bola.net</title><pubDate>Sun, 13 Sep 2026 00:00:00 GMT</pubDate></item>' +
    '<item><title>Jadwal Minggu - Detik</title><pubDate></pubDate></item>' +
    '<item><title>Lama - Arsip</title><pubDate>Wed, 01 Jan 2025 00:00:00 GMT</pubDate></item>' +
    '</channel></rss>';
  assertEquals(
    summarizeNewsRss(xml),
    'Skor Madrid Menang (Kompas.com, 12 Sep) | Klasemen Pekan Ini (Bola.net, 13 Sep) | Jadwal Minggu (Detik)',
  );
});

Deno.test('summarizeNewsRss: kosong/rusak → string kosong', () => {
  assertEquals(summarizeNewsRss(''), '');
  assertEquals(summarizeNewsRss('<rss></rss>'), '');
});

// ── applySleepToSchedule (cermin index.ts) ──
Deno.test('applySleepToSchedule: sisa < 6 jam → siang standar', () => {
  assertEquals(
    applySleepToSchedule([8, 9, 10, 14, 20, 21, 22, 23], 20),
    [7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18],
  );
});

Deno.test('applySleepToSchedule: sisa cukup → jam tidur dibuang', () => {
  assertEquals(
    applySleepToSchedule([7, 8, 9, 10, 11, 14, 15, 16, 17, 18, 19, 21, 22], 20),
    [7, 8, 9, 10, 11, 14, 15, 16, 17, 18, 19],
  );
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

// ── sanitize (kini = sumber produksi setelah drift disatukan) ──
// CATATAN: sejak `_shared/ai-helpers.ts` menjadi SATU-SUMBER (dulu salinan
// manual dari index.ts dan tertinggal), perilaku sanitize = produksi:
// huruf pertama dikapitalkan (gaya chat WhatsApp).
Deno.test('sanitize: trims + kapitalkan huruf pertama', () => {
  const s = sanitize('  halo  ');
  assertEquals(s, 'Halo');
});

Deno.test('sanitize: keepLines pertahankan indentasi kode', () => {
  const s = sanitize('def f():\n    return 1\n      dalam', 3000, true);
  // Huruf pertama dikapitalkan; indentasi baris lain UTUH.
  assertEquals(s, 'Def f():\n    return 1\n      dalam');
});

Deno.test('sanitize: non-keepLines gabung baris + potong di koma', () => {
  const s = sanitize('halo dunia, apa kabar semuanya baik saja kan', 20);
  assertEquals(s.startsWith('Halo dunia'), true);
});

// ── hasWord (word-boundary, bukan substring) ──
Deno.test('hasWord: "kasur" tidak kena "asu"', () => {
  assertEquals(hasWord('masih kucing2an di kasur', 'asu'), false);
});

Deno.test('hasWord: "masuk akal" tidak kena "asu"', () => {
  assertEquals(hasWord('masuk akal', 'asu'), false);
});

Deno.test('hasWord: "menggunakan" tidak kena "guna"', () => {
  assertEquals(hasWord('menggunakan ini', 'guna'), false);
});

Deno.test('hasWord: "mendadak" tidak kena "dada"', () => {
  assertEquals(hasWord('mendadak hujan', 'dada'), false);
});

Deno.test('hasWord: "asu!" kena "asu"', () => {
  assertEquals(hasWord('asu!', 'asu'), true);
});

Deno.test('hasWord: "tak berguna" kena frasa penuh', () => {
  assertEquals(hasWord('tak berguna', 'tak berguna'), true);
});

// ── isInsult ──
Deno.test('isInsult: "kamu bego ya" → true', () => {
  assertEquals(isInsult('kamu bego ya'), true);
});

Deno.test('isInsult: "masuk akal juga" → false', () => {
  assertEquals(isInsult('masuk akal juga'), false);
});

// ── needsFreshInfo: intent teknis ──
Deno.test('needsFreshInfo: "changelog python 3.13" → true', () => {
  assertEquals(needsFreshInfo('changelog python 3.13'), true);
});

Deno.test('needsFreshInfo: "spesifikasi RTX 5090" → true', () => {
  assertEquals(needsFreshInfo('spesifikasi RTX 5090'), true);
});

Deno.test('needsFreshInfo: "benchmark M4 vs Ryzen" → true', () => {
  assertEquals(needsFreshInfo('benchmark M4 vs Ryzen'), true);
});

// ─────────────────────────────────────────────────────────────
// Fungsi yang diekstrak dari ai-reply/index.ts (2026-09-20).
// Sebelumnya hanya ada di index.ts tanpa test; kini satu sumber + teruji.
// ─────────────────────────────────────────────────────────────

// ── capEmoji ──
Deno.test('capEmoji: tanpa emoji → teks apa adanya', () => {
  assertEquals(capEmoji('halo dunia'), 'halo dunia');
});
Deno.test('capEmoji: satu emoji dibiarkan', () => {
  assertEquals(capEmoji('halo 😊'), 'halo 😊');
});
Deno.test('capEmoji: banyak emoji → sisakan yang TERAKHIR', () => {
  const s = capEmoji('a 😀 b 😢 c ❤️');
  assertEquals(s.includes('❤️'), true);
  assertEquals(s.includes('😀'), false);
  assertEquals(s.includes('😢'), false);
});

// ── capSentences ──
Deno.test('capSentences: <= max kalimat → utuh', () => {
  const t = 'Satu. Dua.';
  assertEquals(capSentences(t, 3), t);
});
Deno.test('capSentences: lebih dari max → dipotong', () => {
  const t = 'Satu. Dua. Tiga. Empat.';
  assertEquals(capSentences(t, 2), 'Satu. Dua.');
});

// ── capLines ──
Deno.test('capLines: <= max baris → utuh', () => {
  assertEquals(capLines('a\nb', 3), 'a\nb');
});
Deno.test('capLines: lebih dari max → dipotong + trim', () => {
  assertEquals(capLines('a\nb\nc\nd', 2), 'a\nb');
});

// ── extractEmojis ──
Deno.test('extractEmojis: urut kemunculan', () => {
  // Catatan: `\p{Extended_Pictographic}` mengembalikan basis emoji TANPA
  // variation selector U+FE0F — '❤️' (U+2764 U+FE0F) terbaca '❤'. Ini
  // perilaku produksi (dipakai untuk variasi emoji), bukan bug.
  assertEquals(extractEmojis('a 😀 b ❤️'), ['😀', '❤']);
});
Deno.test('extractEmojis: kosong/null aman', () => {
  assertEquals(extractEmojis(''), []);
  assertEquals(extractEmojis(null as unknown as string), []);
});

// ── contentText ──
Deno.test('contentText: string langsung', () => {
  assertEquals(contentText('halo'), 'halo');
});
Deno.test('contentText: array part → gabung teks saja', () => {
  assertEquals(
    contentText([
      { type: 'text', text: 'a' },
      { type: 'image_url', image_url: 'x' },
      { type: 'text', text: 'b' },
    ]),
    'a b',
  );
});
Deno.test('contentText: null → string kosong', () => {
  assertEquals(contentText(null), '');
});

// ── bannedEmojisFromHistory ──
Deno.test('bannedEmojisFromHistory: ambil emoji balasan assistant terbaru', () => {
  const hist = [
    { role: 'user', content: 'halo 😀' },
    { role: 'assistant', content: 'hai 😢' },
    { role: 'user', content: 'apa kabar' },
    { role: 'assistant', content: 'baik ❤️' },
  ];
  const banned = bannedEmojisFromHistory(hist, 2);
  assertEquals(banned.includes('❤'), true, 'basis emoji tanpa U+FE0F');
  assertEquals(banned.includes('😢'), true);
  assertEquals(banned.includes('😀'), false, 'emoji user tidak dilarang');
});
Deno.test('bannedEmojisFromHistory: tanpa assistant → kosong', () => {
  assertEquals(
    bannedEmojisFromHistory([{ role: 'user', content: '😀' }]),
    [],
  );
});

// ── stripBannedEmojis ──
Deno.test('stripBannedEmojis: buang emoji terlarang + rapikan', () => {
  const s = stripBannedEmojis('halo 😢 dunia ❤️', ['😢']);
  assertEquals(s.includes('😢'), false);
  assertEquals(s.includes('❤️'), true);
  assertEquals(s.includes('  '), false, 'spasi ganda dirapikan');
});
Deno.test('stripBannedEmojis: daftar kosong → tidak berubah', () => {
  const t = 'halo 😢';
  assertEquals(stripBannedEmojis(t, []), t);
});

// ── historyTimeLabel / bulan / stripTimeLabel ──
Deno.test('bulan: indeks WIB valid + di luar rentang → kosong', () => {
  assertEquals(bulan(0), 'Jan');
  assertEquals(bulan(8), 'Sep');
  assertEquals(bulan(11), 'Des');
  assertEquals(bulan(99), '');
});
Deno.test('historyTimeLabel: tanggal invalid → kosong', () => {
  assertEquals(historyTimeLabel('bukan-tanggal'), '');
});
Deno.test('historyTimeLabel: hari ini → prefix [hari ini', () => {
  const now = new Date(Date.now() + 7 * 3600 * 1000);
  const y = now.getUTCFullYear();
  const m = String(now.getUTCMonth() + 1).padStart(2, '0');
  const d = String(now.getUTCDate()).padStart(2, '0');
  const label = historyTimeLabel(`${y}-${m}-${d}T03:00:00.000Z`);
  assertEquals(label.startsWith('[hari ini'), true);
});
Deno.test('stripTimeLabel: buang label, sisakan isi', () => {
  assertEquals(stripTimeLabel('[hari ini 14.30] halo'), 'halo');
  assertEquals(stripTimeLabel('[3 Sep 09.15] hai'), 'hai');
});

// ── parseImagePrompt / stripMoodMarker ──
Deno.test('parseImagePrompt: ambil prompt image dari marker mood', () => {
  const t = 'oke siap {"mood":"senang","image":"kucing di taman"}';
  assertEquals(parseImagePrompt(t), 'kucing di taman');
});
Deno.test('parseImagePrompt: tanpa marker → null', () => {
  assertEquals(parseImagePrompt('halo biasa'), null);
});
Deno.test('parseImagePrompt: JSON rusak → null (tidak throw)', () => {
  assertEquals(parseImagePrompt('{"mood": rusak'), null);
});
Deno.test('stripMoodMarker: buang marker dari balasan tampil', () => {
  assertEquals(stripMoodMarker('halo {"mood":"senang","image":"x"}'), 'halo');
});
Deno.test('stripMoodMarker: tidak merusak teks normal', () => {
  assertEquals(stripMoodMarker('halo dunia'), 'halo dunia');
});

// ── fluxFree ──
Deno.test('fluxFree: URL + prompt ter-encode + dimensi', () => {
  const u = fluxFree('kucing lucu', 42, 512, 768);
  assertEquals(u.startsWith('https://image.pollinations.ai/prompt/'), true);
  assertEquals(u.includes('kucing%20lucu'), true);
  assertEquals(u.includes('width=512'), true);
  assertEquals(u.includes('height=768'), true);
  assertEquals(u.includes('seed=42'), true);
});
