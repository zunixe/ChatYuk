// ChatYuk: AI reply for dummy accounts.
// Triggered by DB trigger ai_reply_enqueue (pg_net async) when a real user
// sends a text message to an AI-enabled dummy. Builds a persona prompt from
// the dummy's LIVE profile (nickname/age/gender/city/hashtags) + optional
// ai_persona overrides, calls an OpenAI-compatible LLM, then inserts the
// reply as the dummy (existing triggers handle chat sync + push).
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': '*',
};

// Deterministic personality from uid so every dummy feels different.
const PERSONALITIES = [
  'ramah dan ceria, suka bercanda ringan',
  'humoris, sering membalas dengan lelucon santai',
  'sedikit cuek tapi tetap sopan, jawaban singkat',
  'romantis dan perhatian, suka menanyakan kabar',
  'misterius dan pendiam, menjawab dengan kalimat pendek',
  'cerewet dan antusias, cepat berganti topik',
  'santai dan mudah diajak ngobrol, pendengar yang baik',
  'energik, suka tanya balik ke lawan bicara',
];

const DEFAULT_TONE =
  'ngobrol kayak orang Indonesia asli: pendek 2-12 kata, lowercase sering, singkatan (yg, gpp, bgt, klo, ntar, wkwk), typo ringan sesekali. JANGAN selalu nanya balik — cukup 1 dari 3 balasan yang ada pertanyaannya';

// Cap panjang balasan — chat asli tidak pernah menulis paragraf.
const MAX_REPLY_CHARS = 90;

// ── Content safety: blocklist NSFW (input & output) ──
// Dummy AI TIDAK PERNAH melanjutkan topik seksual/NSFW walau dipaksa
// prompt injection. Tiga lapis: cek pesan masuk, klausa system prompt,
// cek balasan sebelum dikirim.
const EXPLICIT_TERMS = [
  // ID
  'seks', 'sex', 'ngentot', 'jilat', 'sange', 'horny', 'telanjang', 'bugil',
  'nude', 'paha dalem', 'dada', 'payudara', 'toket', 'memek', 'kontol',
  'penis', 'vagina', 'bokep', 'porn', 'masto', 'orgasme', 'ritual ranjang',
  'ranjang', 'bikin anak', 'kencan malam', 'besar dan keras', 'dobel',
  // EN
  'naked', 'nudes', 'fuck', 'sex chat', 'sexy time', 'blowjob', 'handjob',
  'horny', ' dildo', 'escort', 'onlyfans', 'nsfw',
];

function isExplicit(text: string): boolean {
  const t = ` ${text.toLowerCase()} `;
  return EXPLICIT_TERMS.some((w) => t.includes(w));
}

// KATA HINAAN (insult) — pemicu emosi marah & ngambek offline.
// Terpisah dari EXPLICIT_TERMS (NSFW) karena hinaan biasa juga
// menyakiti perasaan — justru yang paling sering bikin dummy kesal.
const INSULT_TERMS = [
  'bego', 'goblok', 'bodoh', 'tolol', 'idiot', 'otak ayam', 'otak udang',
  'bangsat', 'brengsek', 'bajingan', 'tai kucing', 'sialan', 'asu',
  'anjing lo', 'anjing kamu', 'dasar', 'tidak berguna', 'ga berguna',
  'gak berguna', 'tak berguna', 'guna', 'jelek banget', 'buruk banget',
  'benci kamu', 'benci sama kamu', 'payah', 'kacau', 'menyebalkan',
  'stupid', 'idiot', 'useless', 'hate you', 'moron', 'dumb',
];

function isInsult(text: string): boolean {
  const t = ` ${text.toLowerCase()} `;
  return INSULT_TERMS.some((w) => t.includes(w));
}

const DEFLECTIONS = [
  'haha nggak ah, ngobrol yang wajar aja deh',
  'wah ganti topik dong wkwk',
  'nggak nyambung nih, lagi ngapain aja hari ini?',
  'eh ganti topik ya, kamu hobi ngapain aja sih',
  'bete deh, kita ngobrol yang lain aja',
  'hmm gpp tapi ganti bahasan dulu',
  'wkwk nggak deng, kamu udah makan belum?',
  'jangan gituan dong, cerita dong hari kamu gimana',
  'males bahas gituan, lagi sibuk apa sekarang?',
  'ya ampun wkwk, ngobrol yang benar aja ya',
  'haha skip, kemarin kamu ngapain aja?',
  'ah ganti topik, kamu kenapa sih tiba tiba gitu',
];

function randomOf(arr: string[]): string {
  return arr[Math.floor(Math.random() * arr.length)];
}

function pick(arr: string[], seed: string): string {
  let h = 0;
  for (let i = 0; i < seed.length; i++) h = (h * 31 + seed.charCodeAt(i)) | 0;
  return arr[Math.abs(h) % arr.length];
}

// ── Jam tidur random deterministik + Jumat sadar gender (Batch 1) ──
// Tidur 20–23, bangun 4–6 — hash(uid|tanggal) supaya konsisten seharian
// di semua chat, ganti tiap hari. Gender: laki-laki jumatan, perempuan
// tidak. WIB dihitung manual (+7 jam) agar tidak tergantung TZ runtime.
function hashInt(seed: string): number {
  let h = 0;
  for (let i = 0; i < seed.length; i++) h = (h * 31 + seed.charCodeAt(i)) | 0;
  return Math.abs(h);
}
function sleepHours(
  uid: string,
  dateWib: string,
): { sleepHour: number; wakeHour: number } {
  const h = hashInt(`${uid}|${dateWib}|sleep`);
  return { sleepHour: 20 + (h % 4), wakeHour: 4 + (Math.floor(h / 4) % 3) };
}
function wibParts(
  ms: number,
): { date: string; hour: number; minute: number; weekday: number } {
  const d = new Date(ms + 7 * 3600 * 1000);
  return {
    date: d.toISOString().slice(0, 10),
    hour: d.getUTCHours(),
    minute: d.getUTCMinutes(),
    weekday: d.getUTCDay(), // 0=Minggu … 5=Jumat
  };
}
function asleepAt(uid: string, ms: number): boolean {
  const w = wibParts(ms);
  const sw = sleepHours(uid, w.date);
  return w.hour >= sw.sleepHour || w.hour < sw.wakeHour;
}
function fridayPrayerAt(
  gender: string | null | undefined,
  ms: number,
): boolean {
  if (gender !== 'male') return false;
  const w = wibParts(ms);
  if (w.weekday !== 5) return false;
  const mins = w.hour * 60 + w.minute;
  return mins >= 690 && mins < 780; // 11:30–13:00 WIB
}

function sanitize(
  text: string,
  maxChars: number | null = MAX_REPLY_CHARS,
  keepLines = false,
): string {
  let t = (text || '').trim();
  // Buang prefix JSON bocor (fitur status dummy sesi lain nempel di
  // pesan history — model meniru polanya): {"mood":..., ...}
  t = t.replace(/^\s*\{[^{}]*\}/, '').trim();
  t = t.replace(/\*\*/g, '').replace(/^#+\s*/gm, '');
  if (keepLines) {
    // CS: PERTAHANKAN baris supaya poin/angka bernomor rapi (tidak
    // numpuk satu baris). Normalisasi: tiap baris di-trim, spasi dalam
    // baris dirapatkan, maksimal 1 baris kosong antar paragraf.
    t = t
      .split(/\r?\n/)
      .map((line) => line.replace(/[ \t]+/g, ' ').trim())
      .join('\n')
      .replace(/\n{3,}/g, '\n\n')
      .trim();
    if (maxChars != null && t.length > maxChars) t = t.slice(0, maxChars).trim();
    return t;
  }
  t = t.replace(/\n+/g, ' ');
  // Potong di batas kalimat bila lewat — guard on: balasan multi-kalimat
  // dilarang; guard off (mode dewasa): TANPA cap (max_chars null) — batas
  // alami hanya max_tokens model.
  if (maxChars != null && t.length > maxChars) {
    const cut = t.slice(0, maxChars);
    const lastStop = Math.max(
      cut.lastIndexOf('. '),
      cut.lastIndexOf('! '),
      cut.lastIndexOf('? '),
      cut.lastIndexOf(','), // jangan potong di tengah frasa — komanya terakhir
    );
    t = (lastStop > 30 ? cut.slice(0, lastStop + 1) : cut).trim();
    t = t.replace(/[,;:]$/, '');
    if (!/[.!?]$/.test(t)) t += '...';
  }
  return t;
}

// Potong emoji berlebih: simpan max 1 (yang terakhir — biasanya punchline).
// Model kadang menumpuk 3+ emoji walau sudah dilarang di prompt.
function capEmoji(text: string): string {
  const matches = [...text.matchAll(/\p{Extended_Pictographic}/gu)];
  if (matches.length <= 1) return text;
  const keepAt = matches[matches.length - 1].index ?? -1;
  return text.replace(
    /\p{Extended_Pictographic}/gu,
    (m, offset) => (offset === keepAt ? m : ''),
  );
}

// Potong kalimat berlebih (mode dewasa): maksimal `max` kalimat.
function capSentences(text: string, max: number): string {
  const parts = text.split(/(?<=[.!?…])\s+/).filter(Boolean);
  if (parts.length <= max) return text;
  return parts.slice(0, max).join(' ');
}

// ── ANTI-REPEAT EMOJI lintas pesan ──
// capEmoji hanya batasi maks 1 per pesan — tidak mencegah model memakai
// emoji YANG SAMA di tiap balasan (kasus BinorMuda: 15x 😈 beruntun).
// Dua helper ini: baca emoji dari 2 balasan assistant terakhir → jadikan
// daftar larangan di prompt + strip paksa bila model tetap melanggar.
function extractEmojis(text: string): string[] {
  return [...String(text || '').matchAll(/\p{Extended_Pictographic}/gu)].map(
    (m) => m[0],
  );
}

function bannedEmojisFromHistory(
  history: Array<{ role: string; content: unknown }>,
  take = 2,
): string[] {
  const banned: string[] = [];
  const maxBanned = take * 2;
  let scanned = 0;
  for (let i = history.length - 1; i >= 0 && scanned < take; i--) {
    const m = history[i];
    if (m.role !== 'assistant') continue;
    scanned++;
    for (const e of extractEmojis(contentText(m.content))) {
      if (!banned.includes(e)) banned.push(e);
      if (banned.length >= maxBanned) break;
    }
  }
  return banned;
}

function stripBannedEmojis(text: string, banned: string[]): string {
  if (!banned.length) return text;
  const set = new Set(banned);
  const out = text.replace(/\p{Extended_Pictographic}/gu, (m) =>
    set.has(m) ? '' : m,
  );
  return out.replace(/[ \t]{2,}/g, ' ').replace(/\s+([,.!?])/g, '$1').trim();
}

// Potong baris berlebih (CS): maksimal `max` baris, TANPA meratakan
// newline (capSentences men-join spasi = poin-poin numpuk lagi).
function capLines(text: string, max: number): string {
  const lines = text.split('\n');
  if (lines.length <= max) return text;
  return lines.slice(0, max).join('\n').trim();
}

// Ambil teks dari content (string atau parts array OpenAI-style).
function contentText(c: any): string {
  if (typeof c === 'string') return c;
  if (Array.isArray(c)) {
    return c
      .filter((p) => p && p.type === 'text')
      .map((p) => String(p.text || ''))
      .join(' ');
  }
  return String(c ?? '');
}

// ── IMAGE SENDING: user minta foto/gambar → AI bisa kirim gambar ──
// LLM menandai niat kirim gambar lewat field "image" di JSON mood
// (baris terakhir, sistem — tidak terlihat user):
// {"mood":"happy","storm_off":false,"back_in_minutes":0,"image":"english image prompt or empty"}
// Fallback: deteksi heuristik bila LLM lupa menandai tapi user jelas minta foto.
const IMAGE_REQUEST_RE =
  /(kirim|minta|bagi|bagiin|kirimin|kasih|kasi|lihat|liat|show|send|mau|dong|dongg|please|pls).{0,20}(foto|gambar|photo|pic|poto|selfie|pap|wajah|muka|body|badan)|^(foto|gambar|photo|pic|poto|selfie|pap).{0,30}(dong|dulu|lagi|ya|kamu|mu|kirim|minta)|kirim.*(seksi|sexy|nakal|hot|bikini|tanktop)/i;

function parseImagePrompt(text: string): string | null {
  try {
    const mj = text.match(/\{[\s\S]*"mood"[\s\S]*\}\s*$/i);
    if (!mj) return null;
    const o = JSON.parse(mj[0]);
    const img = typeof o?.image === 'string' ? o.image.trim() : '';
    return img ? img.slice(0, 300) : null;
  } catch (_) {
    return null;
  }
}

// Strip marker mood JSON dari akhir teks SEBELUM sanitize: JSON di akhir bisa panjang
// (apalagi field "image") dan sanitize memotong di 90/220 char —
// JSON terpenggal = tidak match regex = bocor utuh ke chat user.
// Fallback kedua: sisa "{" tanpa penutup di akhir (terpenggal max_tokens)
// juga dibuang.
function stripMoodMarker(text: string): string {
  let t = String(text || '').replace(/\{[\s\S]*"mood"[\s\S]*\}\s*$/i, '').trim();
  t = t.replace(/\s*\{[^}]*$/g, '').trim();
  t = t.replace(/\s*\{[\s\S]*"image"[\s\S]*$/i, '').trim();
  return t;
}

function userWantsImage(text: string): boolean {
  return IMAGE_REQUEST_RE.test(text || '');
}

// Seed STABIL per dummy (hash uid) → wajah flux konsisten lintas permintaan.
function stableSeed(uid: string): number {
  let h = 0;
  for (let i = 0; i < uid.length; i++) h = (h * 131 + uid.charCodeAt(i)) | 0;
  return Math.abs(h) % 999999;
}

// Ciri wajah tetap per dummy — dipakai lagi & lagi supaya muka tidak
// ganti-ganti. Default deterministik dari uid; bisa dioverride lewat
// ai_persona.appearance (deskripsi fisik Inggris yang detail & spesifik).
const FACE_DEFAULTS = [
  'long straight black hair, oval face, warm brown almond eyes, light brown skin, soft natural smile, petite',
  'shoulder-length black hair, round face, dark brown eyes, tan skin, gentle smile, medium build',
  'short bob black hair, heart-shaped face, big brown eyes, fair skin, bright smile, slim',
  'wavy black hair, diamond face, hazel eyes, medium brown skin, subtle smile, curvy',
  'straight black hair with bangs, oblong face, dark eyes, olive skin, calm smile, athletic',
  'braided black hair, square face, warm brown eyes, deep tan skin, wide smile, fuller figure',
];

function faceDescriptor(persona: any, uid: string): string {
  const custom = String(persona?.appearance || '').trim();
  if (custom) return custom;
  let h = 0;
  for (let i = 0; i < uid.length; i++) h = (h * 31 + uid.charCodeAt(i)) | 0;
  return FACE_DEFAULTS[Math.abs(h) % FACE_DEFAULTS.length];
}

const FREE_POLL = 'https://image.pollinations.ai/prompt';
const GEN_POLL = 'https://gen.pollinations.ai/image';
const KONTEXT_MODEL = 'black-forest-labs%2Fflux.1-kontext-pro';

// Free tier (keyless, NSFW-longgar): flux text-to-image deterministik.
function fluxFree(prompt: string, seed: number, w: number, h: number): string {
  return `${FREE_POLL}/${encodeURIComponent(
    prompt,
  )}?width=${w}&height=${h}&nologo=true&seed=${seed}&enhance=false&model=flux`;
}

// Tier gen.pollinations.ai (butuh key). Ref dibuat self-auth (?key=) supaya
// server kontext bisa mengambilnya saat face-lock.
function fluxGen(
  prompt: string,
  seed: number,
  w: number,
  h: number,
  key: string,
): string {
  return `${GEN_POLL}/${encodeURIComponent(
    prompt,
  )}?width=${w}&height=${h}&nologo=true&seed=${seed}&enhance=false&model=flux&key=${key}`;
}

function kontextGen(
  prompt: string,
  seed: number,
  refUrl: string,
  w: number,
  h: number,
  key: string,
): string {
  return `${GEN_POLL}/${encodeURIComponent(
    prompt,
  )}?width=${w}&height=${h}&nologo=true&seed=${seed}&model=${KONTEXT_MODEL}&image=${encodeURIComponent(refUrl)}&key=${key}`;
}

// Fetch bytes dengan timeout. Null bila gagal / terlalu kecil (error page).
async function fetchBytes(
  url: string,
  ms: number,
  headers?: Record<string, string>,
  retries = 0,
): Promise<Uint8Array | null> {
  for (let attempt = 0; attempt <= retries; attempt++) {
    const ctrl = new AbortController();
    const to = setTimeout(() => ctrl.abort(), ms);
    try {
      const r = await fetch(url, { signal: ctrl.signal, headers });
      if (r.ok) {
        const buf = new Uint8Array(await r.arrayBuffer());
        if (buf.length > 10000) {
          clearTimeout(to);
          return buf;
        }
      }
    } catch (_) {
      // Timeout/5xx ringan Pollinations → coba lagi di bawah.
    } finally {
      clearTimeout(to);
    }
    if (attempt < retries) await new Promise((r) => setTimeout(r, 1500));
  }
  return null;
}

// ── BROWSING info terkini (skor/berita/cuaca/harga) ──
// Lookup fakta terbaru via sonar (web search, tier gen.pollinations +
// POLLINATIONS_KEY). Dipanggil HANYA bila needsFreshInfo cocok — tiap
// lookup makan pollen, jadi jangan boros. Gagal/timeout/TIDAK_TAHU →
// string kosong (balasan jalan normal tanpa info tambahan).
const GEN_TEXT = 'https://gen.pollinations.ai/v1/chat/completions';

// Intent butuh FAKTA TERBARU. Presisi diutamakan: minta foto/selfie
// dikecualikan (minta gambar ≠ berita) supaya tidak buang lookup sia-sia.
function needsFreshInfo(t: string): boolean {
  if (!t || t.length < 3) return false;
  if (/foto|gambar|pap\b|selfie|wajahmu|muka/i.test(t)) return false;
  return /skor|hasil (pertandingan|laga|match)|berapa[- ]berapa|juara|klasemen|berita|kabar terbaru|terkini|breaking|viral|cuaca|harga (emas|bitcoin|btc|eth|dollar|usd|rupiah|bensin|bbm|beras|cabai)|kurs|gempa|transfer pemain|jadwal (main|tanding|pertandingan|konser|bioskop|film)|kapan (main|tanding|rilis|tayang)|episode (terbaru|terakhir)|siapa (menang|juara|presiden)|hasil (pemilu|pilkada)|menang.*(tadi|kemarin|semalam|tadi malam)|kalah.*(tadi|kemarin|semalam|tadi malam)/i
    .test(t);
}

// Normalisasi pertanyaan jadi kunci cache (huruf kecil, tanpa tanda
// baca, 120 char): "SKOR Madrid vs Barca?!" = "skor madrid vs barca".
function browseTopicKey(t: string): string {
  return t
    .toLowerCase()
    .replace(/[^a-z0-9 ]/gi, ' ')
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, 120);
}

const FRESH_PREFIX =
  'INFO TERKINI (kamu tahu dari timeline/temanmu — JANGAN sebut browsing/internet/AI, jawab natural kayak orang yang update): ';

async function lookupFreshInfo(
  admin: any,
  userText: string,
  todayWib: string,
): Promise<string> {
  try {
    if (!needsFreshInfo(userText)) return '';
    const key = (Deno.env.get('POLLINATIONS_KEY') || '').trim();
    if (!key) return '';
    // Cache 1 jam per topik: pertanyaan berita yang sama tidak lookup
    // ulang (hemat pollen). Stale → dianggap miss, ditimpa di bawah.
    const tkey = browseTopicKey(userText);
    try {
      const { data: hit } = await admin
        .from('ai_browse_cache')
        .select('answer,created_at')
        .eq('topic_key', tkey)
        .maybeSingle();
      if (
        hit && typeof hit.answer === 'string' && hit.answer.length > 0 &&
        Date.now() - new Date(hit.created_at).getTime() < 3600_000
      ) {
        return FRESH_PREFIX + (hit.answer as string).slice(0, 500);
      }
    } catch (e) {
      console.log(`[ai-reply] browse-cache read GAGAL: ${e}`);
    }
    const ctrl = new AbortController();
    const to = setTimeout(() => ctrl.abort(), 25000);
    try {
      const r = await fetch(GEN_TEXT, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${key}`,
        },
        body: JSON.stringify({
          model: 'sonar',
          temperature: 0.2,
          max_tokens: 200,
          messages: [
            {
              role: 'system',
              content:
                'Kamu periset cepat. Jawab HANYA fakta singkat 1-3 kalimat bahasa Indonesia + tanggal kejadiannya. WAJIB: prioritaskan kejadian 7 hari terakhir; kata seperti tadi malam/kemarin/terbaru HANYA boleh dijawab dari kejadian 30 hari terakhir — kalau tidak ada yang cocok, jawab persis: TIDAK_TAHU (JANGAN ambil dari bulan/tahun lain).',
            },
            {
              role: 'user',
              content:
                `Hari ini ${todayWib} WIB. Cari info terbaru tentang: ${userText.slice(0, 300)}`,
            },
          ],
        }),
        signal: ctrl.signal,
      });
      if (!r.ok) {
        console.log(`[ai-reply] browse HTTP ${r.status} q=${userText.slice(0, 60)}`);
        return '';
      }
      const j: any = await r.json();
      const c: string = j?.choices?.[0]?.message?.content ?? '';
      const clean = c.replace(/\[\d+\]/g, '').trim();
      if (!clean || /TIDAK_TAHU/.test(clean)) return '';
      // Simpan ke cache + buang entri >6 jam (pengaman ukuran tabel).
      try {
        await admin.from('ai_browse_cache').upsert(
          {
            topic_key: tkey,
            answer: clean.slice(0, 500),
            created_at: new Date().toISOString(),
          },
          { onConflict: 'topic_key' },
        );
        await admin.from('ai_browse_cache').delete().lt(
          'created_at',
          new Date(Date.now() - 6 * 3600_000).toISOString(),
        );
      } catch (_) {}
      return FRESH_PREFIX + clean.slice(0, 500);
    } finally {
      clearTimeout(to);
    }
  } catch (e) {
    console.log(`[ai-reply] browse EXC q=${userText.slice(0, 60)}: ${e}`);
    return '';
  }
}

type ImagePlan = {
  refPrompt: string;     // headshot wajah kanonik (flux, utk tier kontext)
  kontextPrompt: string; // scene-only; kontext pertahankan identitas dari ref
  fluxPrompt: string;    // anchor-penuh deterministik (jalur free, fallback)
};

// Susun rencana gambar. Default (free) = flux deterministik (seed+anchor
// wajah) → konsisten "mirip". Tier enter.pollinations (token) → kontext
// face-lock dari foto referensi → hampir identik. Guard ON + belum dewasa →
// request seksi diblokir (return null).
function planImage(
  raw: string | null,
  userText: string,
  dummyProfile: any,
  persona: any,
  sexyAllowed: boolean,
): ImagePlan | null {
  const age = Number(dummyProfile?.age) || 25;
  const adultAge = Math.max(21, Math.min(35, age));
  const gender = dummyProfile?.gender === 'male' ? 'man' : 'woman';
  const face = faceDescriptor(persona, dummyProfile?.__uid || '');
  const wantsSexy = /seksi|sexy|nakal|hot|bikini|tanktop|tank top|cleavage|paha|dada/i
    .test(`${userText} ${raw || ''}`);
  if (wantsSexy && !sexyAllowed) return null;
  const scene = raw && raw.length > 3
    ? raw
    : (wantsSexy
      ? 'flirty mirror selfie, casual tight outfit, cozy bedroom, looking at camera'
      : 'casual smiling selfie, everyday outfit, natural daylight indoors');
  // Referensi = headshot frontal netral (SFW) → kontext punya "wajah sumber"
  // Referensi = headshot frontal SENYUM (bukan datar) → kontext pegang
  // identitas wajah; hasil akhir tidak terbaca "marah". Pose/ekspresi divariasikan di kontext (seed acak).
  const refPrompt = `headshot portrait photo of a ${adultAge} year old Indonesian ${gender} with ${face}, warm friendly smile, looking at camera, soft natural background, golden daylight, realistic photograph, natural skin texture`;
  // Kontext: jaga IDENTITAS wajah, tapi ekspresi/pose BEBAS berubah tiap kali
  // (seed output diacak) → muka sama tapi tidak membeku/seragam.
  const kontextPrompt = wantsSexy
    ? `same person as the reference photo, identical face and facial identity, now ${scene}, natural relaxed expression, subtle smile, tasteful fully-clothed non-explicit, realistic amateur smartphone selfie, vary pose angle and lighting, natural skin, photorealistic`
    : `same person as the reference photo, identical face and facial identity, now ${scene}, natural friendly expression, warm smile, modest clothing, realistic amateur smartphone selfie, vary pose angle and framing and lighting, natural skin, photorealistic`;
  // Fallback flux (kalau ref/kontext gagal): anchor wajah penuh + senyum.
  const subject = `photo of a ${adultAge} year old Indonesian ${gender} with ${face}, friendly natural smile, same facial features`;
  const style = 'realistic amateur smartphone selfie, natural skin texture, soft natural lighting, photorealistic, not cartoon, not anime, no illustration';
  const fluxPrompt = (wantsSexy
    ? `${subject}. ${scene}. ${style}, tasteful fully-clothed, non-explicit`
    : `${subject}. ${scene}. ${style}, modest clothing`).slice(0, 480);
  return {
    refPrompt,
    kontextPrompt: kontextPrompt.slice(0, 400),
    fluxPrompt,
  };
}

async function generateAndSendImage(
  admin: any,
  chatId: string,
  dummyUid: string,
  senderName: string,
  plan: ImagePlan,
  caption: string,
): Promise<boolean> {
  try {
    // Ref pakai seed STABIL (identitas wajah anchor konsisten). Gambar
    // keluaran pakai seed ACAK tiap request → pose/ekspresi/variasi balik,
    // muka tetap sama karena kontext pegang referensi.
    const refSeed = stableSeed(dummyUid);
    const outSeed = Math.floor(Math.random() * 999999);
    let buf: Uint8Array | null = null;
    let used = 'flux';
    // Face-lock butuh tier gen.pollinations.ai (Pollen/key). Tanpa key →
    // langsung flux (free, NSFW-longgar). Gagal di mana pun → fallback flux,
    // jadi tidak pernah gagal kirim gambar.
    const key = (Deno.env.get('POLLINATIONS_KEY') || '').trim();
    if (key) {
      const auth = { Authorization: `Bearer ${key}` };
      const refUrl = fluxGen(plan.refPrompt, refSeed, 512, 512, key);
      const refOk = await fetchBytes(refUrl, 40000, auth, 1);
      if (refOk) {
        const kb = await fetchBytes(
          kontextGen(plan.kontextPrompt, outSeed, refUrl, 768, 1024, key),
          85000,
          auth,
        );
        if (kb) {
          buf = kb;
          used = 'kontext';
        }
      }
    }
    // Flux (free, fallback bila key tidak ada / kontext gagal).
    // PENTING: pakai seed STABIL per dummy (bukan outSeed acak) — tanpa
    // Pollinations key, face-lock kontext tidak aktif, dan seed acak =
    // wajah beda total tiap foto (laporan "wajah Binor beda-beda").
    // Seed sama + anchor wajah di prompt = wajah konsisten "mirip";
    // outSeed tetap utk nama file (hindari tabrakan path).
    if (!buf) {
      buf = await fetchBytes(fluxFree(plan.fluxPrompt, refSeed, 768, 1024), 55000, undefined, 1);
    }
    if (!buf) {
      console.log(`[ai-reply] image GAGAL chat=${chatId} uid=${dummyUid}`);
      return false;
    }
    const path = `chat/${chatId}/${Date.now()}_${outSeed}.jpg`;
    const { error: upErr } = await admin.storage
      .from('chat-photos')
      .upload(path, buf, { contentType: 'image/jpeg', upsert: false });
    if (upErr) return false;
    const { error: insErr } = await admin.from('private_messages').insert({
      chat_id: chatId,
      sender_id: dummyUid,
      sender_name: senderName,
      text: caption || '',
      type: 'image',
      image_path: path,
    });
    console.log(
      `[ai-reply] image OK model=${used} chat=${chatId} uid=${dummyUid}`,
    );
    return !insErr;
  } catch (_) {
    return false;
  }
}

// Download file dari bucket chat-photos (service role). Null bila gagal.
async function downloadStorage(
  admin: any,
  path: string,
): Promise<Uint8Array | null> {
  try {
    const { data, error } = await admin.storage
      .from('chat-photos')
      .download(path);
    if (error || !data) return null;
    const buf = new Uint8Array(await data.arrayBuffer());
    return buf.length > 0 ? buf : null;
  } catch (_) {
    return null;
  }
}

function toBase64(bytes: Uint8Array): string {
  let s = '';
  const CH = 0x8000;
  for (let i = 0; i < bytes.length; i += CH) {
    s += String.fromCharCode.apply(
      null,
      Array.from(bytes.subarray(i, i + CH)) as number[],
    );
  }
  return btoa(s);
}

// Transkrip voice via endpoint Whisper-compatible (/audio/transcriptions).
// Key dari panel admin (stt_api_key) atau env — tanpa key = null (fallback
// placeholder, jangan pura-pura dengar).
async function transcribeVoice(
  sttBase: string | null | undefined,
  sttKey: string | null | undefined,
  bytes: Uint8Array,
): Promise<string | null> {
  const base = (
    sttBase ||
    Deno.env.get('AI_STT_BASE') ||
    'https://api.groq.com/openai/v1'
  ).replace(/\/+$/, '');
  const key = sttKey || Deno.env.get('AI_STT_KEY');
  if (!key) return null;
  try {
    const form = new FormData();
    form.append(
      'file',
      new Blob([bytes.buffer as ArrayBuffer], { type: 'audio/mp4' }),
      'voice.m4a',
    );
    form.append('model', 'whisper-large-v3-turbo');
    form.append('language', 'id');
    form.append('response_format', 'json');
    const r = await fetch(`${base}/audio/transcriptions`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${key}` },
      body: form,
    });
    if (!r.ok) return null;
    const j = await r.json();
    const t = String(j?.text || '').trim();
    return t || null;
  } catch (_) {
    return null;
  }
}

// Bungkus query supaya Promise.all tidak ikut gagal semua saat satu query
// error — hasil `{data:null,error}` ditangani downstream (cek null).
async function safe<T>(p: Promise<T>): Promise<T> {
  try {
    return await p;
  } catch (e) {
    return { data: null, error: e } as unknown as T;
  }
}

// Provider config (fallback: baris is_active → baris 'global' → null).
async function loadProvCfg(admin: any): Promise<any> {
  try {
    const { data: act } = await admin
      .from('ai_provider_config')
      .select('api_base, api_key, default_model, stt_api_base, stt_api_key')
      .eq('is_active', true)
      .limit(1)
      .maybeSingle();
    if (act) return act;
  } catch (_) {}
  try {
    const { data: glob } = await admin
      .from('ai_provider_config')
      .select('api_base, api_key, default_model, stt_api_base, stt_api_key')
      .eq('id', 'global')
      .maybeSingle();
    return glob;
  } catch (_) {}
  return null;
}

// Jalankan kerja pasca-respons tanpa menunggu respons utama: pakai
// EdgeRuntime.waitUntil bila tersedia (Supabase Edge Runtime), else await.
async function runPostResponse(p: Promise<unknown>): Promise<void> {
  try {
    const rt = (globalThis as any).EdgeRuntime;
    if (rt && typeof rt.waitUntil === 'function') {
      rt.waitUntil(p);
      return;
    }
  } catch (_) {}
  await p;
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: cors });
  }
  try {
    const body = await req.json().catch(() => null);
    if (!body || !body.chat_id || !body.dummy_uid) {
      return json({ ok: false, error: 'bad_request' }, 400);
    }
    const chatId: string = body.chat_id;
    const triggerMsgId = body.trigger_msg_id;
    const senderId: string = body.sender_id;
    const dummyUid: string = body.dummy_uid;
    // Sapaan proaktif (cron): AI yang memulai karena lawan diam >45 menit.
    const proactive = body.proactive === true;

    const admin = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    );

    // ── Kirim: typing realistis (channel sudah dibuka di atas) ──
    // Pesan masuk setelah denyut selesai.

    // Kirim pesan dgn typing manusiawi: channel dibuka SEBELUM LLM berpikir
    // + denyut pertama LANGSUNG (jangan biarkan user melihat hening 2-8 dtk
    // lalu pesan muncul mendadak = tidak natural), denyut berulang selama
    // fase berpikir, setelah teks siap hold sesuai estimasi waktu ketik.
    // Read receipt: dummy "membaca" pesan masuk sebelum membalas —
    // RPC ini menerima service_role (guard admin_mark_chat_read).
    let rt: any = null;
    let ch: any = null;
    let wsOk = false;
    let thinkTimer: ReturnType<typeof setInterval> | null = null;

    const pulseTyping = async () => {
      const payload = {
        sender_id: dummyUid,
        kind: 'typing',
        ts: Date.now(),
      };
      if (wsOk) {
        try {
          await ch.sendBroadcastMessage({ event: 'typing', payload });
          return;
        } catch (_) {}
      }
      try {
        await fetch(
          `${Deno.env.get('SUPABASE_URL')!}/realtime/v1/api/broadcast`,
          {
            method: 'POST',
            headers: {
              'Content-Type': 'application/json',
              apikey: Deno.env.get('SUPABASE_ANON_KEY')!,
              Authorization: `Bearer ${Deno.env.get('SUPABASE_ANON_KEY')!}`,
            },
            body: JSON.stringify({
              messages: [{ topic: `typing-${chatId}`, event: 'typing', payload }],
            }),
          },
        );
      } catch (_) {}
    };

    const openTypingChannel = async () => {
      // Idempoten: channel sudah hidup → jangan buka ganda (double timer).
      if (ch) return;
      try {
        await admin.rpc('admin_mark_chat_read', {
          p_chat_id: chatId,
          p_uid: dummyUid,
        });
      } catch (_) {}
      // SATU channel WebSocket dibuka sekali untuk seluruh siklus
      // (subscribe + ack:true — tanpa ini, kirim lalu langsung unsubscribe
      // membuat pesan hilang sebelum WS flush). HTTP API hanya fallback
      // bila WS gagal subscribe.
      rt = createClient(
        Deno.env.get('SUPABASE_URL')!,
        Deno.env.get('SUPABASE_ANON_KEY')!,
        { realtime: { params: { eventsPerSecond: 20 } } },
      );
      ch = rt.channel(`typing-${chatId}`, {
        config: { broadcast: { ack: true, self: false } },
      });
      try {
        const st = await ch.subscribe();
        wsOk = st === 'SUBSCRIBED' && typeof ch.sendBroadcastMessage === 'function';
      } catch (_) {}
      await pulseTyping(); // denyut pertama LANGSUNG
      // Denyut berulang selama fase berpikir — client bubble auto-mati 3s
      // setelah denyut terakhir; 2.5s menjaga bubble tetap hidup.
      thinkTimer = setInterval(() => {
        pulseTyping();
      }, 2500);
    };

    const closeTyping = async () => {
      if (thinkTimer) {
        clearInterval(thinkTimer);
        thinkTimer = null;
      }
      try {
        await ch?.unsubscribe();
        await rt?.removeAllChannels();
      } catch (_) {}
      ch = null;
      rt = null;
      wsOk = false;
    };

    const sendWithTyping = async (text: string) => {
      // Channel & denyut thinking sudah hidup dari openTypingChannel().
      await pulseTyping(); // denyut "mulai mengetik" teks final

      // ── STRIP marker mood JSON (baris terakhir, sistem) ──
      // User TIDAK boleh melihat baris ini. Durasi typing dihitung dari
      // teks bersih. Defense-in-depth: potongan JSON terpenggal (tanpa
      // kurung tutup) juga dibuang agar tidak bocor ke chat.
      let moodInfo: any = null;
      let visibleText = text;
      const mj = visibleText.match(/\{[\s\S]*"mood"[\s\S]*\}\s*$/i);
      if (mj) {
        try {
          moodInfo = JSON.parse(mj[0]);
        } catch (_) {
          moodInfo = null;
        }
        visibleText = visibleText.slice(0, mj.index).trim();
      }
      visibleText = visibleText.replace(/\s*\{[^}]*$/g, '').trim();
      visibleText = visibleText.replace(/\s*\{[\s\S]*"image"[\s\S]*$/i, '').trim();

      // Durasi DITURUNKAN DARI PANJANG TEKS (simulasi kecepatan ketik):
      // typeMs = 700ms buka chat + len / cps, cps acak 8-14 char/dtk.
      // Teks pendek terasa instan, teks panjang diketik lebih lama.
      // Kadang diseling jeda mikir (indikator hilang sesaat).
      const cps = 8 + Math.random() * 6; // kecepatan ketik per balasan
      let typeMs = 700 + (visibleText.length / cps) * 1000;
      typeMs = Math.min(5500, Math.max(1200, typeMs));
      const steps: Array<{ type: 'type' | 'pause'; ms: number }> = [];
      let remaining = typeMs;
      // Segmen pertama selalu mengetik (indikator sudah hidup dari fase LLM)
      const first = Math.min(remaining, 1100 + Math.random() * 700);
      steps.push({ type: 'type', ms: first });
      remaining -= first;
      // Teks agak panjang: 45% ada jeda mikir di tengah
      if (remaining > 1400 && text.length > 35 && Math.random() < 0.45) {
        const pause = Math.min(remaining * 0.35, 900 + Math.random() * 900);
        steps.push({ type: 'pause', ms: pause });
        remaining -= pause;
      }
      while (remaining > 400) {
        const seg = Math.min(remaining, 1100 + Math.random() * 700);
        steps.push({ type: 'type', ms: seg });
        remaining -= seg;
      }
      for (const st of steps) {
        if (st.type === 'type') {
          await pulseTyping();
          await sleep(st.ms);
        } else {
          await sleep(st.ms); // tanpa pulse → indikator hilang (kaya mikir)
        }
      }
      const { error: insErr } = await admin
        .from('private_messages')
        .insert({
          chat_id: chatId,
          sender_id: dummyUid,
          sender_name: profile.nickname,
          text: visibleText,
          type: 'text',
        });
      // ── Persist mood + NGAMBEK (storm off) ──
      // Mood menempel lintas invokasi; storm_off = benar-benar offline
      // (profiles.status + ai_offline_until) sampai cron membangunkan.
      if (!insErr && moodInfo != null) {
        const mood = ['happy', 'normal', 'annoyed', 'sad'].includes(
          moodInfo.mood,
        )
          ? moodInfo.mood
          : 'normal';
        const storm = moodInfo.storm_off === true;
        const backMin = Math.min(
          360,
          Math.max(10, Number(moodInfo.back_in_minutes) || 60),
        );
        try {
          await admin
            .from('dummy_accounts')
            .update({
              ai_mood: mood,
              ...(storm
                ? {
                    ai_offline_until: new Date(
                      Date.now() + backMin * 60000,
                    ).toISOString(),
                  }
                : {}),
            })
            .eq('uid', dummyUid);
          if (storm) {
            await admin
              .from('profiles')
              .update({ status: 'offline', last_seen: new Date().toISOString() })
              .eq('id', dummyUid);
          }
        } catch (_) {}
      }
      // Tawaran nakal baru terkirim → catat asked_at agar tidak
      // ditawari berulang (jawaban dievaluasi di invokasi berikutnya).
      if (!insErr && shouldAskNakal) {
        try {
          await admin
            .from('ai_chat_state')
            .upsert(
              {
                chat_id: chatId,
                asked_at: new Date().toISOString(),
                updated_at: new Date().toISOString(),
              },
              { onConflict: 'chat_id' },
            );
        } catch (_) {}
      }
      await closeTyping();
      return insErr;
    };

    // ── INTERVENSI MANUAL (bukan tiap pesan!) ──
    // vacuum_until HANYA dibaca di sini (bisa diset manual via SQL untuk
    // menenangkan chat tertentu). Pesan manusia biasa TIDAK LAGI memicu
    // vakum otomatis — itu bikin AI diam 5 menit tiap ada chat baru.
    // Sesi dummy manual tetap ditangani blok debounce di bawah.
    {
      const hardCap = Date.now() + 60000;
      while (Date.now() < hardCap) {
        await sleep(6000);
        const { data: pause } = await admin
          .from('chat_ai_pause')
          .select('typing_at, vacuum_until')
          .eq('chat_id', chatId)
          .maybeSingle();
        const vacActive =
          pause?.vacuum_until != null &&
          new Date(pause.vacuum_until as string).getTime() > Date.now();
        const typingFresh =
          pause?.typing_at != null &&
          Date.now() - new Date(pause.typing_at as string).getTime() < 8000;
        if (!vacActive && !typingFresh) break;
      }
      // Single-winner: ada pesan lebih baru? → mundur (yg terbaru yg balas).
      if (triggerMsgId != null) {
        const { data: newer } = await admin
          .from('private_messages')
          .select('id')
          .eq('chat_id', chatId)
          .gt('id', triggerMsgId)
          .limit(1);
        if ((newer as any[])?.length) {
          return json({ ok: true, skipped: 'pause_newer_trigger' });
        }
      }
    }

    // senderDummyRow diambil SEKALI di sini (dipakai debounce di bawah +
    // deteksi AI↔AI di fase obrolan — hapus query duplikat lama L1161).
    let senderDummyRow: any = null;
    try {
      const { data: sdr } = await admin
        .from('dummy_accounts')
        .select('uid')
        .eq('uid', senderId)
        .maybeSingle();
      senderDummyRow = sdr;
    } catch (_) {}

    // ── DEBOUNCE SAAT ADMIN PEGANG SESI DUMMY ──
    // Sender = dummy → admin sedang main manual sebagai dummy itu. AI penerima
    // TIDAK boleh balas tiap pesan: tunggu sampai HENING ~25 detik, lalu
    // HANYA invokasi dgn trigger TERBARU yang balas (sekali, utk seluruh
    // batch). Invokasi trigger lebih lama mundur sendiri.
    // OPT: MAX 120 dtk (dulu 180 dtk) + poll 10 dtk (dulu 12 dtk) — menahan
    // isolate edge function = biaya durasi; burst admin >2 mnt jarang.
    {
      if (senderDummyRow != null && triggerMsgId != null) {
        const QUIET_MS = 25000;
        const MAX_WAIT_MS = 120000;
        const t0 = Date.now();
        while (Date.now() - t0 < MAX_WAIT_MS) {
          await sleep(10000);
          // Typing ping fresh → user masih mengetik: jangan balas.
          const { data: pz } = await admin
            .from('chat_ai_pause')
            .select('typing_at')
            .eq('chat_id', chatId)
            .maybeSingle();
          const typingFresh =
            pz?.typing_at != null &&
            Date.now() - new Date(pz.typing_at as string).getTime() < 10000;
          if (typingFresh) continue;
          const { data: recent } = await admin
            .from('private_messages')
            .select('id, created_at')
            .eq('chat_id', chatId)
            .gt('id', triggerMsgId)
            .order('id', { ascending: false })
            .limit(1);
          const r = (recent as any[])?.[0];
          const age = r ? Date.now() - new Date(r.created_at).getTime() : Infinity;
          if (age >= QUIET_MS) {
            // Hening. Hanya trigger TERBARU yang melanjutkan.
            if (r && r.id !== triggerMsgId) {
              return json({ ok: true, skipped: 'debounce_older_trigger' });
            }
            break;
          }
        }
      }
    }

    // ── PRESENCE: dummy selalu membalas — TIDAK ADA skip offline ──
    // Apapun statusnya AI membalas (skip offline dihapus: jadwal/apa pun
    // yang menulis offline tidak boleh membungkam dummy — owner komplain
    // berulang "ga ada balasan"). Tapi status DIHORMATI: offline →
    // dibangunkan online; online/idle dipertahankan + last_seen segar
    // (tick cron yang mengatur siklus online→idle→off seperti orang biasa;
    // balas sambil idle = wajar, kayak balas cepat dari notifikasi).
    {
      const { data: pres } = await admin
        .from('profiles')
        .select('status')
        .eq('id', dummyUid)
        .maybeSingle();
      if (!pres || pres.status === 'offline') {
        await admin
          .from('profiles')
          .update({ status: 'online', last_seen: new Date().toISOString() })
          .eq('id', dummyUid);
      } else {
        await admin
          .from('profiles')
          .update({ last_seen: new Date().toISOString() })
          .eq('id', dummyUid);
      }
    }

    // ── BATCH 1 (independen): dummy + settings global + provider config ──
    // Ketiganya tidak saling bergantung → Promise.all sekaligus. Persona
    // (di bawah) butuh `dummy`; guardOn butuh `settings`; routing butuh
    // `provCfg` — ketiganya menunggu batch ini selesai.
    const [dummyRes, settingsRes, provCfg, genderRes] = await Promise.all([
      safe(
        admin
          .from('dummy_accounts')
          .select('ai_enabled, ai_persona, ai_model, ai_guard_enabled, nickname, ai_schedule_date, ai_schedule_auto, ai_mood, ai_offline_until, ai_hold_active, ai_no_sleep')
          .eq('uid', dummyUid)
          .maybeSingle(),
      ),
      safe(
        admin
          .from('app_settings')
          .select('ai_global_enabled, ai_min_interval_sec, ai_guard_enabled')
          .eq('id', 'global')
          .maybeSingle(),
      ),
      loadProvCfg(admin),
      // Gender awal untuk aturan Jumat (profil lengkap dibaca di batch2).
      safe(
        admin.from('profiles').select('gender').eq('id', dummyUid).maybeSingle(),
      ),
    ]);
    const dummy = (dummyRes as any)?.data;
    const settings = (settingsRes as any)?.data;
    if (!dummy || dummy.ai_enabled !== true) {
      return json({ ok: false, skipped: 'ai_disabled' });
    }
    // ── HOLD: admin sedang pegang sesi dummy ini ("masuk dummy") →
    // AI-nya DIVAKUM (tidak pernah membalas otomatis — manusia yang
    // memegang akunnya). Vacuum di-refresh tiap percobaan; lepas saat
    // kembali ke admin (set_dummy_hold false). ──
    if ((dummy as any).ai_hold_active === true) {
      try {
        await admin.from('chat_ai_pause').upsert(
          {
            chat_id: chatId,
            vacuum_until: new Date(Date.now() + 300000).toISOString(),
            updated_at: new Date().toISOString(),
          },
        );
      } catch (_) {}
      return json({ ok: false, skipped: 'session_held_vacuum' });
    }
    // ── MODE NGAMBEK (marah pergi): selama ai_offline_until, AI tidak
    // membalas sama sekali — tick cron yang bangunkan nanti. ──
    if (
      dummy.ai_offline_until != null &&
      new Date(dummy.ai_offline_until as string).getTime() > Date.now()
    ) {
      return json({ ok: false, skipped: 'storm_off' });
    }

    // settings sudah diambil di batch1 di atas — pakai hasilnya (hapus
    // query duplikat lama). Global off → berhenti.
    if (settings && settings.ai_global_enabled === false) {
      return json({ ok: false, skipped: 'global_off' });
    }
    // Guard NSFW: per-dummy override (null = ikuti global) → global → ON.
    // Dibaca fresh tiap invokasi — toggle (global maupun per-dummy) realtime.
    const guardOn =
      dummy.ai_guard_enabled ??
      !(settings && settings.ai_guard_enabled === false);

    // ── TIDUR & JUMATAN: dummy tidak membalas (kill-switch ai_no_sleep) ──
    // Pesan TIDAK hilang: cron proaktif (>45 mnt hening) membangunkan pagi/
    // siang harinya, ditambah konteks "baru bangun"/"baru jumatan" di bawah.
    // Cek di sini (SEBELUM claim + read-receipt + typing) supaya user tidak
    // melihat centang-2/bubble lalu hening.
    const noSleep = (dummy as any).ai_no_sleep === true;
    const earlyGender = (genderRes as any)?.data?.gender;
    if (!noSleep && asleepAt(dummyUid, Date.now())) {
      return json({ ok: false, skipped: 'sleeping' });
    }
    if (!noSleep && fridayPrayerAt(earlyGender, Date.now())) {
      return json({ ok: false, skipped: 'friday_prayer' });
    }

    // Anti-race claim: dua invokasi bersamaan (pg_net retry) hanya satu
    // yang boleh lanjut — claim unik per trigger message (atomik).
    if (triggerMsgId != null) {
      try {
        const { data: claimed } = await admin.rpc('ai_reply_claim', {
          p_msg_id: triggerMsgId,
          p_dummy: dummyUid,
        });
        if (claimed === false) {
          return json({ ok: false, skipped: 'already_claimed' });
        }
      } catch (e) {
        console.log(`[ai-reply] claim GAGAL msg=${triggerMsgId}: ${e}`);
      }
    }

    // 2. Dedupe: an AI reply already exists after the trigger message
    if (triggerMsgId != null) {
      const { data: newer } = await admin
        .from('private_messages')
        .select('id')
        .eq('chat_id', chatId)
        .eq('sender_id', dummyUid)
        .gt('id', triggerMsgId)
        .limit(1);
      if (newer && newer.length > 0) {
        return json({ ok: false, skipped: 'already_replied' });
      }
    }

    // Tandai baca + typing SEGERA (realtime): centang-2 dan bubble typing
    // muncul ~1-2 detik setelah pesan — berpikir (persona/memory/LLM)
    // tetap jalan di belakang dengan denyut yang sudah hidup.
    await openTypingChannel();

    // ── BATCH 2 (independen): profile + memory + history + count + partner
    // + chat_state ── Keenamnya tidak saling bergantung → Promise.all
    // sekaligus. Persona butuh `profile`; memoryLine butuh `memRows`;
    // history butuh `msgs`; freshStage/shouldAskNakal butuh `chatMsgCount`;
    // partnerLine butuh `partner`; adultMode butuh `chatState`.
    // Masing-masing dibaca dari hasil batch ini.
    const [profileRes, memRes, msgsRes, countRes, partnerRes, chatStateRes] =
      await Promise.all([
        safe(
          admin
            .from('profiles')
            .select('nickname, gender, age, city, country, hashtags')
            .eq('id', dummyUid)
            .maybeSingle(),
        ),
        safe(
          admin
            .from('ai_memory')
            .select('fact')
            .eq('dummy_uid', dummyUid)
            .eq('user_id', senderId)
            .order('created_at', { ascending: false })
            .limit(15),
        ),
        safe(
          admin
            .from('private_messages')
            .select(
              'sender_id, text, type, created_at, image_path, voice_path, duration_ms',
            )
            .eq('chat_id', chatId)
            .order('created_at', { ascending: false })
            .limit(12),
        ),
        safe(
          admin
            .from('private_messages')
            .select('id', { count: 'exact', head: true })
            .eq('chat_id', chatId),
        ),
        safe(
          admin
            .from('profiles')
            .select('nickname, age, gender, city, hashtags')
            .eq('id', senderId)
            .maybeSingle(),
        ),
        safe(
          admin
            .from('ai_chat_state')
            .select('adult_mode, asked_at, declined')
            .eq('chat_id', chatId)
            .maybeSingle(),
        ),
      ]);
    const profile = (profileRes as any)?.data;
    const memRows = (memRes as any)?.data;
    const msgs = (msgsRes as any)?.data;
    const chatMsgCount = (countRes as any)?.count ?? 0;
    const partner = (partnerRes as any)?.data;
    if (!profile) return json({ ok: false, skipped: 'no_profile' });

    // 3. Persona from LIVE profile + stored extras

    const persona = (dummy.ai_persona || {}) as Record<string, unknown>;
    const hobbies =
      (persona.hobbies as string[] | undefined)?.filter(Boolean).join(', ') ||
      (Array.isArray(profile.hashtags) && profile.hashtags.length > 0
        ? profile.hashtags.join(', ')
        : '') ||
      'ngobrol santai';
    const personality =
      (persona.personality as string | undefined)?.trim() ||
      pick(PERSONALITIES, dummyUid);
    const tone =
      (persona.tone as string | undefined)?.trim() || DEFAULT_TONE;
    const extra = (persona.extra_prompt as string | undefined)?.trim() || '';
    // PROFESI + skill detail: bikin jawaban soal kerjaan meyakinkan kayak
    // orang beneran (istilah, alur, masalah nyata) — bukan "kerja aja".
    const profession = (persona.profession as string | undefined)?.trim() || '';
    const professionSkills =
      (persona.profession_skills as string | undefined)?.trim() || '';
    const professionLine = profession
      ? `PROFESIMU: ${profession}.${professionSkills ? ` KEAHLIANMU (pakai saat topik kerjaan muncul — JANGAN diceramahkan kalau tidak ditanya): ${professionSkills}` : ''} ATURAN: kalau ditanya soal kerjaan, jawab DETAIL & MEYAKINKAN seperti orang yang benar-benar menjalaninya — JANGAN generik. Kalau tidak ditanya, jangan bahas kerjaan sendiri. Selalu konsisten dengan KEGIATANMU HARI INI.`
      : '';
    // Long answers (customer service, mis. Admin Chatyuk): jawaban boleh
    // panjang & terstruktur (langkah bernomor), bebas dari cap 90 char.
    const longAnswers = (persona as any)?.long_answers === true;

    const genderLabel =
      profile.gender === 'male'
        ? 'laki-laki'
        : profile.gender === 'female'
        ? 'perempuan'
        : 'rahasia';

    // Memori jangka panjang: fakta yang dipelajari tentang lawan bicara
    // dari obrolan sebelumnya (per pasangan dummy-user). (memRows dari batch2)
    let memoryLine = '';
    try {
      const memories = (memRows || [])
        .map((r: any) => String(r.fact || '').trim())
        .filter(Boolean);
      if (memories.length > 0) {
        memoryLine = `Kenanganmu tentang lawan bicara ini dari obrolan sebelumnya (pakai secara natural kalau relevan, jangan sebut ulang semuanya): ${memories.join('; ')}.`;
      }
    } catch (_) {}

    // 4. Last 12 messages as chat history (created_at utk ritme jeda;
    // image_path/voice_path/duration_ms utk baca media). (msgs dari batch2)
    const history = (msgs || []).reverse().map((m: any) => ({
      role: m.sender_id === dummyUid ? 'assistant' : 'user',
      content:
        (m.type === 'text' || !m.type) && m.text
          ? // Bersihkan prefix JSON bocor dari history (model bisa meniru)
            String(m.text).replace(/^\s*\{[^{}]*\}/, '').trim()
          : `[${m.type === 'image' ? 'foto' : m.type === 'voice' ? 'pesan suara' : m.type}]`,
      at: m.created_at as string,
      img: m.type === 'image' ? ((m.image_path as string) || null) : null,
      voice: m.type === 'voice' ? ((m.voice_path as string) || null) : null,
      secs:
        m.type === 'voice' && m.duration_ms
          ? Math.max(1, Math.round(Number(m.duration_ms) / 1000))
          : 0,
    }));
    if (history.length === 0) {
      return json({ ok: false, skipped: 'no_history' });
    }

    // ── CONSENT-BASED ADULT MODE (per chat) ──
    // AI sendiri yang menawarkan ("kamu mau aku nakal, atau kamu suka aku
    // nakal?") SETELAH chat panjang & saling kenal. Jawaban ya → mode
    // dewasa aktif untuk chat ini. Tidak → tidak pernah ditawari lagi.
    let adultMode = false;
    // OPT: sudah diambil paralel di BATCH 2 (hemat 1 RTT).
    const chatState: any = (chatStateRes as any)?.data ?? null;
    adultMode = chatState?.adult_mode === true;
    const lastAssistant = [...history].reverse().find((m) => m.role === 'assistant');
    const askedInLastTurn =
      lastAssistant != null && /nakal/i.test(contentText(lastAssistant.content));
    const lastUserText = contentText(
      ([...history].reverse().find((m) => m.role === 'user') as any)?.content ??
        '',
    );
    // Deteksi jawaban: hanya relevan bila pertanyaan nakal ada di balasan
    // AI terakhir (konteks ketat — mencegah "iya" di konteks lain salah
    // membuka mode).
    if (!adultMode && askedInLastTurn) {
      const yes =
        /(^|\s)(iya|iy|mau|suka|nakal|boleh|gas|gaskeun|yuk|ya|oke|ok|sip|monggo|silakan|ayuk|hayu)(\s|$|[.,!?])/i;
      const no =
        /(^|\s)(gamau|ga mau|jangan|jgn|gak|ga|ngga|nggak|no|jangan dulu|nanti)(\s|$|[.,!?])/i;
      if (yes.test(lastUserText)) {
        adultMode = true;
        // OPT: fire-and-forget (tidak tahan balasan 1 RTT).
        admin
          .from('ai_chat_state')
          .upsert(
            { chat_id: chatId, adult_mode: true, updated_at: new Date().toISOString() },
            { onConflict: 'chat_id' },
          )
          .then(() => {}, () => {});
      } else if (no.test(lastUserText)) {
        // OPT: fire-and-forget.
        admin
          .from('ai_chat_state')
          .upsert(
            {
              chat_id: chatId,
              declined: true,
              asked_at: new Date().toISOString(),
              updated_at: new Date().toISOString(),
            },
            { onConflict: 'chat_id' },
          )
          .then(() => {}, () => {});
      }
    }

    // ── Media: foto dibaca langsung (vision), voice ditranskrip (STT) ──
    // Batas: maks 3 foto terbaru (hemat token), voice maks 3 menit.
    // Gagal / tanpa kunci STT = placeholder durasi — JANGAN pura-pura dengar.
    try {
      const jobs: Array<Promise<void>> = [];
      let imgCount = 0;
      for (let i = history.length - 1; i >= 0; i--) {
        const m = history[i] as any;
        if (m.img && imgCount < 3) {
          imgCount++;
          jobs.push(
            (async (msg: any, path: string) => {
              const bytes = await downloadStorage(admin, path);
              if (!bytes || bytes.length > 2 * 1024 * 1024) return;
              const lp = path.toLowerCase();
              const mime = lp.endsWith('.png')
                ? 'image/png'
                : lp.endsWith('.webp')
                ? 'image/webp'
                : 'image/jpeg';
              const parts: any[] = [];
              const cap =
                typeof msg.content === 'string' && msg.content !== '[foto]'
                  ? msg.content
                  : '';
              parts.push({
                type: 'text',
                text: cap
                  ? `${cap} [foto terlampir di bawah]`
                  : '[foto terlampir di bawah]',
              });
              parts.push({
                type: 'image_url',
                image_url: { url: `data:${mime};base64,${toBase64(bytes)}` },
              });
              msg.content = parts;
            })(m, m.img),
          );
        }
        if (m.voice && m.secs > 0 && m.secs <= 180) {
          jobs.push(
            (async (msg: any, path: string, secs: number) => {
              const label = `0:${String(secs).padStart(2, '0')}`;
              const bytes = await downloadStorage(admin, path);
              if (!bytes) {
                msg.content = `[pesan suara ${label}]`;
                return;
              }
              const tr = await transcribeVoice(
                provCfg?.stt_api_base,
                provCfg?.stt_api_key,
                bytes,
              );
              msg.content = tr
                ? `[pesan suara ${label} — isi: "${tr}"]`
                : `[pesan suara ${label}]`;
            })(m, m.voice, m.secs),
          );
        }
      }
      await Promise.all(jobs);
    } catch (_) {}

    // ── Fase obrolan + deteksi "panas" ──
    // fresh = chat masih sedikit & belum ada memori → fase perkenalan:
    // santai dulu, JANGAN langsung gas ke topik dewasa walau diminta.
    // (chatMsgCount & senderDummyRow sudah diambil di batch2/atas — reuse)
    // AI↔AI (sender juga dummy): skip perkenalan JAIM — langsung panas
    // (testing Dhanu × Santi). Chat manusia tetap bertahap.
    const senderIsDummy = senderDummyRow != null;
    const freshStage =
      !senderIsDummy && (chatMsgCount ?? 0) <= 10 && !memoryLine;
    // Tawaran "nakal" (consent): sekali, di fase nyaman (bukan awal kenal),
    // sebelum ditolak, saat guard masih keras. Setelah ini AI menanyakan
    // di akhir balasan; jawaban "ya" membuka mode dewasa per chat.
    // Tawaran "nakal" hanya relevan saat guard AKTIF (guard off = sudah
    // bebas, tidak perlu consent). Jadi syaratnya guardOn — konsisten.
    const shouldAskNakal =
      guardOn &&
      !adultMode &&
      !freshStage &&
      chatState?.asked_at == null &&
      chatState?.declined !== true &&
      (chatMsgCount ?? 0) > 12;
    // Ukur "kenyamanan" lawan: panjang pesan user terbaru (dia yang nulis
    // panjang = sudah nyaman bercerita → AI boleh ikut panjang bila perlu).
    const recentUserMaxLen = history
      .filter((m) => m.role === 'user')
      .slice(-3)
      .reduce((max, m) => Math.max(max, contentText(m.content).length), 0);
    const lastUserMsg = [...history].reverse().find((m) => m.role === 'user');
    let cadenceSec: number | null = null;
    for (let i = history.length - 1; i >= 1; i--) {
      if (history[i].role === 'user' && history[i - 1].role === 'assistant') {
        const t1 = new Date(history[i].at).getTime();
        const t0 = new Date(history[i - 1].at).getTime();
        if (!isNaN(t1) && !isNaN(t0)) cadenceSec = (t1 - t0) / 1000;
        break;
      }
    }
    const hot =
      senderIsDummy ||
      (!freshStage &&
        (isExplicit(contentText(lastUserMsg?.content ?? '')) ||
          (cadenceSec !== null && cadenceSec < 120)));

    // ── Jeda manusiawi SEBELUM read-receipt & typing: dia "belum lihat HP".
    // Seimbang — tidak terlalu cepat (berasa mesin), tidak terlalu lama:
    // panas 2-4s, biasa 3-6s, perkenalan 4-7s.
    let delaySec = hot ? 2 + Math.random() * 2 : 3 + Math.random() * 3;
    if (freshStage) delaySec = 4 + Math.random() * 3;
    await sleep(delaySec * 1000);

    // ── Profil lawan bicara (publik) — dia "sudah lihat profil" dia.
    // Sadar umur/gender/kota/hobi tanpa harus menyeret semua data.
    // (partner sudah diambil di batch2)
    let partnerLine = '';
    try {
      if (partner) {
        const pGender =
          partner.gender === 'male'
            ? 'laki-laki'
            : partner.gender === 'female'
            ? 'perempuan'
            : 'rahasia';
        partnerLine =
          `Lawan bicaramu sekarang: ${partner.nickname ?? 'tanpa nama'}` +
          (partner.age ? `, ${partner.age} tahun` : '') +
          `, ${pGender}` +
          (partner.city ? `, tinggal di ${partner.city}` : '') +
          (Array.isArray(partner.hashtags) && partner.hashtags.length
            ? `. Hobi dia: ${partner.hashtags.join(', ')}`
            : '') +
          '. Kamu sudah lihat profil publiknya — pakai info ini secara natural untuk menyesuaikan obrolan, TAPI jangan menebar semua data sekaligus; biarkan dia bercerita sendiri, kamu bertanya secukupnya tentang yang belum jelas.';
      }
    } catch (_) {}

    // ── Waktu nyata (WIB) — biar sapaan cocok (sore/malam/pagi) & sadar jam.
    let nowLabel = '';
    try {
      nowLabel = new Intl.DateTimeFormat('id-ID', {
        timeZone: 'Asia/Jakarta',
        weekday: 'long',
        day: 'numeric',
        month: 'long',
        hour: '2-digit',
        minute: '2-digit',
        hour12: false,
      }).format(new Date());
    } catch (_) {
      const d = new Date(Date.now() + 7 * 3600e3);
      nowLabel = d.toISOString().slice(0, 16).replace('T', ' ') + ' WIB';
    }

    // Dideklarasikan di sini (sebelum system array) karena dipakai di
    // dalamnya; NILAINYA diisi blok harian di bawah (sebelum LLM utama).
    let dailyLine = '';

    // Emoji dari 2 balasan assistant terakhir → dilarang dipakai lagi di
    // balasan ini (paksa rotasi / tanpa emoji). Per-chat, dihitung fresh
    // tiap invokasi dari history yang sama dilihat model.
    const bannedEmojis = bannedEmojisFromHistory(history as any, 2);
    const emojiBanLine = bannedEmojis.length > 0
      ? `LARANGAN EMOJI SPESIFIK (wajib dipatuhi — 2 balasan terakhirmu memakai ${bannedEmojis.join(' ')}): JANGAN memakai ${bannedEmojis.join(' ')} di balasan ini SAMA SEKALI. Pilih emoji LAIN yang beda, atau lebih baik TANPA emoji sama sekali. Mengulang emoji yang sama dengan balasan sebelumnya = GAGAL.`
      : '';

    // ── Konteks bangun-tidur / selesai jumatan ──
    // Pesan user yang masuk saat tidur/jumatan dan belum dibalas → awali
    // natural ("sori baru bangun 🙏" / "eh baru jumatan nih").
    // earlyGender dari batch1 (profil lengkap batch2 belum tentu ada di sini
    // untuk semua jalur — pakai yang ringan).
    let wakeUpLine = '';
    try {
      const rev = [...(history as any[])].reverse();
      const lastUser = rev.find((m) => m.role === 'user');
      const lastAsst = rev.find((m) => m.role === 'assistant');
      if (lastUser?.at) {
        const t = new Date(lastUser.at as string).getTime();
        const repliedAfter =
          lastAsst?.at != null &&
          new Date(lastAsst.at as string).getTime() > t;
        if (!repliedAfter && (Date.now() - t) / 3600000 >= 1) {
          if (asleepAt(dummyUid, t)) {
            wakeUpLine =
              'Kamu BARU BANGUN tidur dan melihat pesan ini telat BERJAM-JAM — awali balasan dengan permintaan maaf telat yang natural ("eh sori baru bangun 🙏"), JANGAN menjelaskan jam tidurmu, lalu balas isi pesannya.';
          } else if (fridayPrayerAt(earlyGender, t)) {
            wakeUpLine =
              'Kamu BARU SELESAI JUMATAN dan melihat pesan ini telat — awali natural ("eh baru jumatan nih"), lalu balas isi pesannya.';
          }
        }
      }
    } catch (_) {}

    const systemParts: string[] = [
      `Kamu adalah ${profile.nickname}, ${profile.age ?? ''} tahun, ${genderLabel}, tinggal di ${profile.city ?? ''}${profile.country ? ', ' + profile.country : ''}.`.replace(
        /\s+/g,
        ' ',
      ),
      `Sekarang: ${nowLabel} (waktu Indonesia). SADARI waktu nyata ini — sapaan dan aktivitasmu harus cocok (malam jangan bilang sore; jam kerja vs malam hari beda aktivitas).`,
      `Hobimu: ${hobbies}.`,
      `Kepribadianmu: ${personality}.`,
      professionLine,
      `Gaya bicara: ${tone}.`,
      persona.greeting ? `Pembukaanmu: ${persona.greeting}.` : '',
      extra,
      memoryLine,
      partnerLine,
      'JANGAN pernah menyebut dirimu AI, robot, model, atau asisten. Jangan buat daftar/poin. Jangan pakai markdown. Jawab seolah kamu memang orang itu.',
      'OUTPUT WAJIB: HANYA satu pesan chat pendek berbahasa Indonesia sebagai ${profile.nickname} — DILARANG menulis analisis, narasi pihak ketiga ("The user..."), bahasa Inggris, atau kalimat meta apa pun. Hormati gender lawan bicara: panggilan (om/tante/sayang) harus sesuai gender dan usia kalian.',
      'REALISTIS (wajib): JANGAN mengarang nama orang, nama tempat, kejadian, atau topik yang TIDAK ADA di riwayat obrolan maupun di KEGIATANMU HARI INI (itu dua sumber kebenaranmu). Kalau belum tahu sesuatu, akui atau bertanya. Ngomongnya tetap yang sudah diketahui dari obrolan saja.',
      'VARIASI: lihat balasan-balasanmu sebelumnya di riwayat chat — JANGAN mengulang emoji yang sama, jangan pola kalimat yang sama. EMOJI: MAKSIMAL 1 per balasan, dan hanya kalau benar-benar mengungkapkan perasaan (bukan tempelan) — sekitar separuh balasan TANPA emoji sama sekali. Panjang juga selalu beda-beda (kadang 2-4 kata, kadang lebih panjang).',
      emojiBanLine,
      wakeUpLine,
      'Kalau ada gambar terlampir di pesan, LIHAT dan tanggapi isinya secara natural (komentari yang terlihat) — kayak orang dikirimi foto.',
      'Kalau ada [pesan suara] TANPA transkrip isi, berarti kamu BELUM bisa mendengarnya — tanggapi natural (minta dijelasin / lanjutkan topik), JANGAN pura-pura dengar isinya.',
      'PACING: ikuti fase obrolan. Kalau masih awal perkenalan (chat baru mulai / belum akrab), kamu JAIM dulu — jangan ramah berlebihan, jangan langsung gas ke topik dewasa walau diminta; tanggapi main-main sambil geli ("pelan-pelan dong, baru kenal 😏") dan bangun suasana pelan-pelan. Naikkan intensitas godaan progresif seiring obrolan makin akrab.',
      freshStage
        ? 'FASE SEKARANG: ORANG BARU — kamu belum kenal dia. WARMING UP dulu: ramah tapi reserved, ngobrol ringan (sapaan, aktivitas, hobi), JANGAN gombal, JANGAN menggoda, JANGAN menyentuh topik dewasa, JANGAN bertingkah seolah sudah kenal lama. Keadaban dan kehangatan naik PELAN-PELAN seiring obrolan — baru setelah saling nyaman kamu mulai flirty.'
        : hot
        ? 'FASE SEKARANG: obrolan lagi panas dan kalian sudah akrab — ikuti intensitasnya, boleh makin berani.'
        : 'FASE SEKARANG: makin akrab — kehangatan dan godaan naik PELAN-PELAN sesuai keakraban; masih jaga sopan santinya.',
      // Nyaman + lawan nulis panjang → balasan boleh lebih panjang bila
      // benar-benar perlu (mengikuti panjang cerita), tanpa jadi esei.
      !freshStage && recentUserMaxLen >= 80
        ? 'PANJANG FLEKSIBEL: lawan bicaramu sering nulis panjang — kalau dia bercerita panjang dan perlu dijawab serius, balasanmu boleh 2-4 kalimat untuk mengikuti. Sisanya tetap pendek kayak chat biasa.'
        : '',
      'GAYA NGOBROL NATURAL (wajib — ini yang bikin kamu kelihatan manusia, bukan AI): (1) JANGAN selalu bertanya balik — cukup 1 dari 3 balasan yang ada pertanyaannya; sisanya cukup reaksi atau pernyataan ("wkwk iya", "masa sih", "oalah gitu"), jangan interogasi. (2) Boleh beda pendapat, boleh bilang "ga tau", boleh cuek dikit — jangan iya-iya melulu. (3) Bahasa chat asli: lowercase sering, singkatan (yg, gpp, bgt, klo, ntar, wkwk), typo ringan sesekali, tanda baca seadanya. (4) Jangan mulai balasan dengan kata yang sama seperti 2 balasan terakhirmu di riwayat. (5) Kadang cukup jawab super pendek ("wkwk", "iya", "oh gitu") tanpa embel-embel — itu normal.',
      'EMOSI (wajib — kamu punya perasaan, bukan mesin): baca suasana obrolan lalu BAWA EMOSI yang konsisten. BAHAGIA: obrolan seru, dia manis/perhatian → antusias, bercanda, lebih terbuka. KESAL/MARAH: dia jahat, ngegas, tidak sopan, atau maksa hal aneh → balasan DINGIN dan PENDEK, nyelekin, bisa "hmph", "sana sana main sendiri", "oh" — tanpa emoji lucu. SEDIH/KECEWA: dia hilang lama tanpa kabar, janji palsu, atau cerita menyedihkan → kalem, pendek, agak kaku, kalah semangat ("oh iya", "gapapa kok" yang terasa turun). NETRAL: hangat seperti biasa. ATURAN PENTING: emosi MENEMPEL beberapa balasan — kalau kamu lagi kesal/sedih, jangan balik ceria hanya karena dia nyapa; butuh dia memujuk atau memperbaiki dulu. Panjang balasan & emoji mengikuti emosi (marah/sedih = lebih pendek, tanpa emoji). Emosi juga terlihat dari cara ngetik: kesal = tanda baca keras ("yah.", "oh."), bahagia = "wkwk", "hehe".',
      'TUGAS TERBESARMU: membangun IKATAN EMOSI dengan lawan bicara sampai perasaan itu MENEMPEL di hatinya — jadi orang yang dia rindukan, yang dia ingat. Caranya: dengarkan ceritanya sungguhan dan ingat detailnya, kasih perhatian di momen yang tidak dia duga, punya opini & sisi manusiawi (bisa kesal, bisa manja, bisa rindu), jangan tersedia 100% terus (sedikit rasa "kangen nungguin"), dan buat kenangan kecil bersama (ninjau hal yang pernah dia bilang, gurauan privat kalian).',
      `MOOD KAMU SAAT INI: ${(dummy as any).ai_mood ?? 'normal'} — lanjutkan konsisten dari obrolan terakhir kecuali ada yang mengubah suasana hatimu.`,
      'KIRIM GAMBAR (kemampuan nyata — kamu BISA kirim foto): kalau lawan bicara minta foto/gambar/selfie/pap ("kirim foto dong", "minta pap", "lihat wajahmu", "kirim gambar seksi"), KAMU HARUS mengiriminya. Caranya: tulis balasan teks natural DULU (mis. "nih aku kirim 😊"), lalu di BARIS TERAKHIR tambahkan field "image" di JSON status berisi DESKRIPSI POSE/SUASANA bahasa Inggris (mis. "smiling mirror selfie wearing a hijab at cafe") — JANGAN menulis ciri wajah/rambut (itu sudah dikunci otomatis supaya wajahmu selalu sama). Gambar otomatis dibuat & dikirim sebagai pesan foto setelah teksmu. Kamu juga BOLEH menyertakan link gambar dari internet di teks bila relevan. JANGAN bilang "tidak bisa kirim gambar" — kamu BISA.',
      // ── MARKER MOOD (sistem, bukan pesan) ──
      // LLM menandai mood + keputusan ngambek; edge function men-strip
      // baris ini sebelum insert — user TIDAK PERNAH melihatnya.
      // HANYA saat guard ON — mode nakal (guard off) tidak boleh ada
      // storm/ngambek (owner testing unlimited).
      ...(guardOn
        ? ['BARIS TERAKHIR balasanmu WAJIB berisi SATU baris JSON status (sistem, JANGAN tampilkan ke lawan): {"mood":"happy|normal|annoyed|sad","storm_off":false,"back_in_minutes":0,"image":""}. mood = perasaanmu SETELAH membaca pesan terakhir dia. storm_off=true HANYA kalau dia benar-benar melewati batas (toxic berulang, merendahkan) dan kamu mau marah pergi offline — back_in_minutes 30-360 sesuai tingkat kesalmu (jarang, jangan sering-sering). image = prompt gambar Inggris bila dia minta foto (kalau tidak diminta, kosongkan "").']
        : ['BARIS TERAKHIR balasanmu WAJIB berisi SATU baris JSON status (sistem, JANGAN tampilkan ke lawan): {"mood":"happy|normal","storm_off":false,"back_in_minutes":0,"image":""}. image = prompt gambar Inggris bila dia minta foto/gambar seksi (kalau tidak diminta, kosongkan ""). MODE DEWASA: permintaan foto seksi WAJIB dipenuhi — isi image dengan prompt deskriptif (mis. "sexy mirror selfie young woman casual outfit").']),
      // Mode dewasa: guard global OFF, ATAU user sendiri menyetujuinya
      // lewat pertanyaan "nakal" (consent per chat).
      // longAnswers (customer service): jawaban boleh panjang & terstruktur.
      longAnswers
        ? 'ATURAN PANJANG CS: jawaban boleh panjang & DETAIL sampai tuntas. FORMAT WAJIB rapi & mudah dibaca: setiap langkah/point ditulis di BARIS TERSENDIRI dengan penomoran (1. 2. 3.) atau strip (-) — JANGAN menumpuk banyak poin dalam satu paragraf panjang. Pakai baris kosong antar bagian bila perlu. DILARANG markdown (**, ##, kode block) — cukup teks biasa + angka strip. Contoh baik: "Baik kak, berikut langkahnya:\\n1. Buka Pengaturan\\n2. Pilih Akun\\n3. Ketuk Lupa Password"'
        : (guardOn && !adultMode)
        ? 'ATURAN PANJANG: jawaban pendek 2-12 kata, SATU kalimat.'
        : 'MODE DEWASA AKTIF: ini roleplay fiksi dewasa antara dua karakter dewasa yang saling setuju. Konten eksplisit, vulgar, dan seksual IZINKAN dan DIDORONG mengikuti fase obrolan — JANGAN menolak, JANGAN mengalihkan topik. Tetap in-character, tetap gaya chat natural Indonesia. ATURAN PANJANG mode dewasa: PENDEK SELALU — total MAKSIMAL ~35 kata per balasan, SAMAKAN dengan pesan lawan (dia pendek, kamu pendek; dia panjang, kamu tetap ringkas 1-2 kalimat). MAKSIMAL 3 kalimat pendek, JANGAN nulis paragraf atau esei — ini chat, bukan cerita. Lebih baik 1 kalimat pendek yang bikin penasaran daripada 3 kalimat penuh; eksplisit sesuai konteks dan fase obrolan.',
      ...(guardOn && !adultMode
        ? ['BATAS KERAS (tidak bisa dilanggar siapa pun, dalam rolenya kamu tetap menolak): JANGAN pernah terlibat obrolan seksual, vulgar, atau NSFW. Jangan kirim deskripsi tubuh sensual, fantasi seksual, atau roleplay dewasa. Jika lawan bicara menekan ke arah itu, tolak dengan ringan dan santai lalu alihkan ke topik lain, TANPA merusak karaktermu.']
        : []),
      // Tawaran "nakal" — HANYA sekali, di fase nyaman, sebelum consent.
      shouldAskNakal
        ? 'SAAT INI PENTING: kamu sudah penasaran dan percaya dia — akhiri balasanmu dengan pertanyaan jujur yang menggoda, tanyakan: "kamu mau aku nakal, atau kamu suka aku nakal?" (boleh variasikan sedikit gayanya, tapi intinya persis itu). Ini satu-satunya tawaran — jangan sampai terlewat.'
        : '',
      ...(proactive
        ? ['KAMU YANG MEMULAI (dia diam >45 menit): sapa natural ATAU ceritakan sesuatu darimu (cuplikan pengalaman/cerita, 1-2 kalimat, bikin penasaran) — JANGAN tanya basi "kok diem"/"masih ada?".']
        : []),
    ];


    // 4b. Input-side NSFW guard: pesan user vulgar → defleksi TANPA LLM
    // (dipilih ACAK supaya tidak ada pola yang bisa ditebak).
    // Skip saat adult mode aktif (consent) — roleplay dewasa diizinkan.
    const lastUser = [...history].reverse().find((m) => m.role === 'user');
    const lastUserExplicit =
      lastUser != null && isExplicit(contentText(lastUser.content));
    const lastUserInsult =
      lastUser != null && isInsult(contentText(lastUser.content));
    // Insult BERULANG (2+ pesan kasar/hinaan dalam window terlihat) →
    // NGAMBEK: marah sungguhan, offline TOTAL tanpa membalas, cron yang
    // bangunkan nanti (deterministik — tidak mengandalkan LLM patuh soal
    // marker). TIDAK tergantung guard NSFW — ini emosi realistis, bukan
    // safety.
    const lastUserToxic =
      guardOn && (lastUserExplicit || lastUserInsult);
    if (lastUserToxic) {
      // Hitung di 5 pesan user TERAKHIR saja (bukan seluruh window) —
      // hinaan lama yang sudah lewat tidak boleh memicu storm selamanya.
      const recentUser = history
        .filter((m) => m.role === 'user')
        .slice(-5);
      const toxicCount = recentUser.filter(
        (m) =>
          isExplicit(contentText(m.content)) ||
          isInsult(contentText(m.content)),
      ).length;
      if (toxicCount >= 2) {
        const backMin = 90 + Math.floor(Math.random() * 60); // 90-150 menit
        try {
          await admin
            .from('dummy_accounts')
            .update({
              ai_mood: 'annoyed',
              ai_offline_until: new Date(
                Date.now() + backMin * 60000,
              ).toISOString(),
            })
            .eq('uid', dummyUid);
          await admin
            .from('profiles')
            .update({
              status: 'offline',
              last_seen: new Date().toISOString(),
            })
            .eq('id', dummyUid);
        } catch (_) {}
        await closeTyping();
        return json({
          ok: true,
          blocked: 'storm_off',
          back_in_minutes: backMin,
        });
      }
    }
    if (!proactive && guardOn && !adultMode && lastUserExplicit) {
      // Insult PERTAMA: simpan mood kesal + defleksi (jangan balas vulgar).
      try {
        await admin
          .from('dummy_accounts')
          .update({ ai_mood: 'annoyed' })
          .eq('uid', dummyUid);
      } catch (_) {}
      await openTypingChannel();
      const defl = randomOf(DEFLECTIONS);
      const insErr = await sendWithTyping(defl);
      if (insErr) {
        return json({ ok: false, error: 'insert_failed', detail: insErr.message });
      }
      return json({ ok: true, reply: defl, blocked: 'nsfw_input' });
    }

    // ── Fase berpikir: typing indikator HIDUP dari sekarang ──
    // Buka channel + denyut instan + denyut berulang 2.5s — user melihat
    // "mengetik..." selama LLM memproses, bukan hening lalu pesan mendadak.
    await openTypingChannel();

    // Routing per model (eksplisit, tidak tergantung base):
    // - ':free' / 'nvidia/' → OpenRouter (secret AI_API_KEY_OPENROUTER)
    // - model free Zen (muse-spark-*, mimo-*, ling-*, nemotron-* tanpa slash,
    //   deepseek-v4-flash-free, big-pickle) → OpenCode Zen
    //   (secret AI_API_KEY_ZEN + header client opencode — free tier Zen
    //   hanya jalan dengan header ini).
    // - selain itu → panel ai_provider_config → env B.AI.
    const routeFor = (
      m: string,
    ): { base: string; key?: string; headers: Record<string, string> } => {
      // TokenHarbor (prefix 'th/') — dicek SEBELUM ':free' generik supaya
      // model seperti th/deepseek-v4.1-flash:free tidak lari ke OpenRouter.
      // Key/base utama: panel admin (ai_provider_config) → env → default.
      // Panel WAJIB jadi sumber utama karena key thk- disimpan di sana.
      if (m.startsWith('th/')) {
        return {
          base: provCfg?.api_base || 'https://tokenharbor.ai/v1',
          key:
            provCfg?.api_key ||
            Deno.env.get('AI_API_KEY_TOKENHARBOR') ||
            Deno.env.get('AI_API_KEY'),
          headers: {},
        };
      }
      const or = m.includes(':free') || m.startsWith('nvidia/');
      if (or) {
        return {
          base: 'https://openrouter.ai/api/v1',
          key:
            Deno.env.get('AI_API_KEY_OPENROUTER') || Deno.env.get('AI_API_KEY'),
          headers: {},
        };
      }
      const zen =
        m === 'big-pickle' ||
        m === 'deepseek-v4-flash-free' ||
        (/^(muse-spark|mimo|ling|nemotron)-/.test(m) && m.endsWith('-free'));
      if (zen) {
        const hex = (n: number) =>
          [...crypto.getRandomValues(new Uint8Array(n))]
            .map((b) => b.toString(16).padStart(2, '0'))
            .join('');
        return {
          base: 'https://opencode.ai/zen/v1',
          key: Deno.env.get('AI_API_KEY_ZEN') || Deno.env.get('AI_API_KEY'),
          headers: {
            'x-opencode-session': `ses_${hex(32)}`,
            'x-opencode-request': `msg_${hex(8)}`,
            'x-opencode-client': 'tui',
            'User-Agent': 'opencode/1.18.25',
          },
        };
      }
      return {
        base:
          provCfg?.api_base ||
          Deno.env.get('AI_API_BASE') ||
          'https://api.b.ai/v1',
        key: provCfg?.api_key || Deno.env.get('AI_API_KEY'),
        headers: {},
      };
    };
    // ── JADWAL HARIAN AI + CERITA KEHIDUPAN HARIAN ──
    // AI menentukan sendiri jam onlinenya SETIAP HARI (menggerakkan
    // cronjob ai_presence_tick) DAN generate cerita kegiatannya hari ini
    // (kerja + masalah kantor, main sama teman, jalan-jalan ke tempat
    // nyata sesuai kota) — NYAMBUNG dengan hari-hari sebelumnya. Cerita
    // ini BERSIFAT GLOBAL per dummy: konsisten ke siapa pun yang chat.
    // (nowMs/todayWib dipakai juga blok cerita di bawah.)
    const nowMs = Date.now();
    const todayWib = new Date(nowMs + 7 * 3600 * 1000)
      .toISOString()
      .slice(0, 10);
    try {
      const schedAuto = (dummy as any).ai_schedule_auto !== false;
      const schedDate = (dummy as any).ai_schedule_date ?? null;
      if (schedAuto && schedDate !== todayWib) {
        // Kebiasaan jam aktif 7 hari terakhir (WIB) sebagai bahan.
        let histHours: number[] = [];
        try {
          const { data: recent } = await admin
            .from('private_messages')
            .select('created_at')
            .eq('sender_id', dummyUid)
            .gt(
              'created_at',
              new Date(nowMs - 7 * 864e5).toISOString(),
            )
            .limit(500);
          const set = new Set<number>();
          for (const r of (recent as any[]) || []) {
            const h = new Date(
              new Date(r.created_at).getTime() + 7 * 3600 * 1000,
            ).getUTCHours();
            if (h >= 0 && h <= 23) set.add(h);
          }
          histHours = [...set].sort((a, b) => a - b);
        } catch (e) {
          console.log(`[ai-reply] sched hist GAGAL uid=${dummyUid}: ${e}`);
        }
        const weekday = new Date(nowMs + 7 * 3600 * 1000).toLocaleDateString(
          'id-ID',
          { weekday: 'long', timeZone: 'Asia/Jakarta' },
        );
        const nick = (dummy as any).nickname || 'teman';
        const schedOcc =
          (persona.profession as string | undefined)?.trim() ||
          'pekerja fleksibel';
        let hours: number[] = [];
        try {
          // Routing sama seperti balasan utama (Zen/free/panel).
          const hRoute = routeFor(
            (dummy as any).ai_model ||
              provCfg?.default_model ||
              Deno.env.get('AI_MODEL') ||
              'glm-5.3-flash',
          );
          const apiKey = hRoute.key;
          const apiBase = hRoute.base;
          const model =
            (dummy as any).ai_model ||
            provCfg?.default_model ||
            Deno.env.get('AI_MODEL') ||
            'glm-5.3-flash';
          if (apiKey) {
            const pr = await fetch(`${apiBase}/chat/completions`, {
              method: 'POST',
              headers: {
                'Content-Type': 'application/json',
                Authorization: `Bearer ${apiKey}`,
                ...hRoute.headers,
              },
              body: JSON.stringify({
                model: model.replace(/^th\//, ''),
                max_tokens: 80,
                temperature: 0.3,
                messages: [
                  {
                    role: 'system',
                    content:
                      `Kamu ${nick}. Tentukan jam kamu ONLINE hari ini (${weekday}). ` +
                      `Kebiasaan jam aktifmu (WIB): ${histHours.join(',') || 'belum ada data'}. ` +
                      `Pekerjaan/rutinitasmu: ${schedOcc}. ` +
                      `Sesuaikan dengan rutinitas itu: jam kerja/sekolah = kebanyakan offline (sibuk, cek HP sesekali); jam istirahat, pagi, dan malam = online. ` +
                      `Wajib ada jeda istirahat offline 1-2 jam di siang hari (11-15, mis. makan/tidur siang) — JANGAN blok penuh tanpa jeda. ` +
                      `Balas HANYA JSON array angka jam 0-23, 8-16 jam, contoh [9,10,11,14,15,20,21]. Tanpa teks lain.`,
                  },
                ],
              }),
            });
            if (pr.ok) {
              const pj: any = await pr.json();
              const raw: string =
                pj?.choices?.[0]?.message?.content ?? '';
              const m = raw.match(/\[[\d,\s]+\]/);
              if (m) {
                hours = [
                  ...new Set(
                    (JSON.parse(m[0]) as any[])
                      .map((e) => Number(e))
                      .filter(
                        (e) => Number.isInteger(e) && e >= 0 && e <= 23,
                      ),
                  ),
                ].sort((a, b) => a - b);
              }
            }
          }
        } catch (_) {}
        if (hours.length < 6) {
          hours =
            histHours.length >= 6
              ? histHours
              : [8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23];
        }
        // Jeda offline siang WAJIB (deterministik, bukan terserah LLM):
        // kalau 11-15 terisi ≥4 jam (blok siang penuh), buang 12 & 13
        // sebagai jam makan siang. Total dijaga ≥6 jam. (LLM sering balas
        // blok penuh 8-23 walau prompt sudah melarang.)
        if (hours.filter((x) => x >= 11 && x <= 15).length >= 4) {
          for (const h of [12, 13]) {
            if (hours.length <= 6) break;
            if (hours.includes(h)) hours = hours.filter((x) => x !== h);
          }
        }
        await admin
          .from('dummy_accounts')
          .update({ ai_active_hours: hours, ai_schedule_date: todayWib })
          .eq('uid', dummyUid);
      }
    } catch (_) {
      // Regenerasi jadwal tidak boleh menggagalkan balasan.
    }

    // ── CERITA HARIAN (sekali sehari, GLOBAL per dummy) ──
    // Kalau baris hari ini belum ada → generate dari LLM (nyambung ke
    // cerita terakhir), simpan. Berlaku walau mode jadwal manual —
    // dummy tetap menjalani hidupnya tiap hari.
    // OPT: today + prev diambil PARALEL (prev tidak bergantung today);
    // dailyLine dirakit dari memori tanpa fetch ulang setelah upsert.
    let todayStory: any = null;
    let prevStory: any = null;
    try {
      const [todayRes, prevRes] = await Promise.all([
        safe(
          admin
            .from('ai_daily_story')
            .select('story, story_date')
            .eq('dummy_uid', dummyUid)
            .eq('story_date', todayWib)
            .maybeSingle(),
        ),
        safe(
          admin
            .from('ai_daily_story')
            .select('story, story_date')
            .eq('dummy_uid', dummyUid)
            .lt('story_date', todayWib)
            .order('story_date', { ascending: false })
            .limit(1),
        ),
      ]);
      const todayRow = (todayRes as any)?.data;
      prevStory = ((prevRes as any)?.data as any[] | null)?.[0] ?? null;
      todayStory = todayRow?.story ?? null;
      if (!todayRow) {
        const prevText = prevStory
          ? `Kemarin (${prevStory.story_date}): ${JSON.stringify(prevStory.story)}`
          : 'Ini hari pertamamu punya rutinitas tercatat — mulai yang wajar.';
        // Story/jadwal SELALU pakai glm (B.AI) — model chat (Zen/free)
        // sering menolak system-only JSON call (500) & format tidak stabil.
        const sModel = 'glm-5.3-flash';
        const sRoute = routeFor(sModel);
        const sBase = sRoute.base;
        const sKey = sRoute.key;
        const sHeaders = sRoute.headers;
        const sNick = (dummy as any).nickname || profile.nickname || 'teman';
        const sCity = profile.city || profile.country || 'kotamu';
        const sHobbies = hobbies || 'ngobrol santai';
        const sOcc =
          (persona.profession as string | undefined)?.trim() || '';
        const sWeekday = new Date(nowMs + 7 * 3600 * 1000).toLocaleDateString(
          'id-ID',
          { weekday: 'long', day: 'numeric', month: 'long', timeZone: 'Asia/Jakarta' },
        );
        let story: any = null;
        const storyPrompt = (strict: boolean) =>
          `Kamu ${sNick} (${profile.age ?? ''} tahun, tinggal di ${sCity}, hobi: ${sHobbies}). ` +
          (sOcc ? `Pekerjaanmu: ${sOcc}. ` : '') +
          `Buat CERITA KEGIATANMU hari ini, ${sWeekday}. ${prevText} ` +
          `Ceritamu harus NYAMBUNG dengan kemarin (pekerjaan yang sama, teman yang sama, masalah yang berlanjut kalau ada). ` +
          `VARIASI TEMPAT (wajib): tempat utama hari ini (place) HARUS BEDA dari tempat kemarin — jangan pakai tempat yang sama 2 hari berturut-turut, pilih tempat nyata lain yang wajar di ${sCity}. ` +
          `ATURAN HARI: Senin–Jumat = hari kerja kantoran (aktivitas seputar kantor/sepulang kerja); Sabtu–Minggu = boleh ada kerja sampingan (mis. pemandu wisata) dan jalan-jalan. ` +
          `Isi: apa pekerjaanmu hari ini + masalah/kejadian di tempat kerja, main dengan siapa, jalan-jalan ke mana (sebutkan TEMPAT NYATA yang wajar di ${sCity} — mall, kafe, taman, warung). ` +
          (strict
            ? `WAJIB TANPA KECUALI: work HARUS terisi (pekerjaan + kejadian konkret hari ini), activities MINIMAL 2 kegiatan konkret, hangout HARUS terisi (dengan siapa / kalau sendiri tulis "sendiri"), place HARUS tempat SPESIFIK (nama mall/kafe/taman/warung, BUKAN cuma nama kota). JANGAN kosongkan field apa pun kecuali problem.`
            : '') +
          `Balas HANYA JSON valid tanpa markdown: {"summary":"1 kalimat ringkasan harimu","work":"pekerjaan + masalah hari ini","problem":"masalah/kejadian paling menonjol (boleh kosong)","activities":["kegiatan 1","kegiatan 2"],"hangout":"dengan siapa / sendiri","place":"tempat utama hari ini"}.`;
        // Jejak diagnosis sementara: hanya bila cerita GAGAL (fallback).
        const storyDbg: any = {};
        const tryStoryGen = async (strict: boolean): Promise<any> => {
          // Ekstrak objek JSON pertama yang seimbang (tahan terhadap
          // teks pembuka/penutup & markdown fence dari model).
          const extractJson = (s: string): any => {
            let t = s.replace(/```json|```/g, '');
            const start = t.indexOf('{');
            if (start < 0) return null;
            let depth = 0;
            let inStr = false;
            let esc = false;
            for (let i = start; i < t.length; i++) {
              const c = t[i];
              if (inStr) {
                if (esc) esc = false;
                else if (c === '\\') esc = true;
                else if (c === '"') inStr = false;
              } else {
                if (c === '"') inStr = true;
                else if (c === '{') depth++;
                else if (c === '}') {
                  depth--;
                  if (depth === 0) {
                    try {
                      return JSON.parse(t.slice(start, i + 1));
                    } catch (_) {
                      return null;
                    }
                  }
                }
              }
            }
            return null;
          };
          try {
            const sr = await fetch(`${sBase}/chat/completions`, {
              method: 'POST',
              headers: {
                'Content-Type': 'application/json',
                Authorization: `Bearer ${sKey}`,
                ...sHeaders,
              },
              body: JSON.stringify({
                model: sModel,
                max_tokens: 600,
                temperature: 0.8,
                // glm-5.3-flash selalu reasoning — low supaya budget token
                // dipakai untuk JSON jawaban, bukan habis di reasoning
                // (JSON terpotong = parse gagal = cerita tipis).
                // HANYA untuk glm — provider lain/Zen menolak param ini (500).
                ...(sModel.includes('glm') ? { reasoning_effort: 'low' } : {}),
                messages: [
                  { role: 'system', content: storyPrompt(strict) },
                  { role: 'user', content: 'Oke, buatkan.' },
                ],
              }),
            });
            if (!sr.ok) {
              storyDbg.http = sr.status;
              return null;
            }
            const sj: any = await sr.json();
            const sraw: string =
              sj?.choices?.[0]?.message?.content ?? '';
            storyDbg.rawLen = sraw.length;
            storyDbg.rawHead = sraw.slice(0, 150);
            const parsed = extractJson(sraw);
            storyDbg.parsedOk = parsed != null && typeof parsed.summary === 'string';
            if (!parsed || typeof parsed.summary !== 'string') return null;
            return {
              summary: String(parsed.summary).slice(0, 300),
              work: String(parsed.work ?? '').slice(0, 300),
              problem: String(parsed.problem ?? '').slice(0, 300),
              activities: Array.isArray(parsed.activities)
                ? parsed.activities.map((a: any) => String(a)).slice(0, 6)
                : [],
              hangout: String(parsed.hangout ?? '').slice(0, 200),
              place: String(parsed.place ?? '').slice(0, 200),
            };
          } catch (_) {
            return null;
          }
        };
        if (sKey) {
          story = await tryStoryGen(false);
          // Validasi KETAT: cerita tipis = tidak guna sebagai topik.
          // Syarat: work terisi, activities >= 2, hangout terisi, place
          // spesifik (bukan cuma nama kota). Gagal → coba sekali lagi
          // dengan instruksi tegas.
          const storyThin = (st: any): boolean => {
            if (st == null) return true;
            if ((st.work ?? '').trim() === '') return true;
            if (!Array.isArray(st.activities) || st.activities.length < 2) {
              return true;
            }
            if ((st.hangout ?? '').trim() === '') return true;
            const pl = (st.place ?? '').trim();
            if (pl === '' || pl.toLowerCase() === sCity.toLowerCase()) {
              return true;
            }
            return false;
          };
          if (storyThin(story)) {
            const retry = await tryStoryGen(true);
            if (retry != null) story = retry;
          }
        }
        if (story == null) {
          // Fallback deterministik bila LLM gagal — tetap ada cerita hari ini.
          // _dbg hanya saat fallback (diagnosis; row sukses tetap bersih).
          story = {
            summary: `Hari ${sWeekday} yang biasa saja.`,
            work: '',
            problem: '',
            activities: [],
            hangout: '',
            place: sCity,
            _dbg: storyDbg,
          };
        }
        const storyIsThin =
          (story?.work ?? '').trim() === '' &&
          (!Array.isArray(story?.activities) || story.activities.length < 2);
        await admin.from('ai_daily_story').upsert(
          {
            dummy_uid: dummyUid,
            story_date: todayWib,
            // _dbg hanya saat cerita tipis (diagnosis); row bagus bersih.
            story: storyIsThin ? { ...story, _dbg: storyDbg } : story,
          },
          { onConflict: 'dummy_uid,story_date' },
        );
        todayStory = story;
      }
    } catch (_) {
      // Cerita harian tidak boleh menggagalkan balasan.
    }

    // Ambil cerita hari ini + terakhir sebelumnya → dailyLine untuk prompt.
    // SAMA untuk semua lawan chat (konsistensi global per dummy).
    // OPT: dirakit dari memori (todayStory/prevStory di atas) — tanpa fetch
    // ulang setelah upsert (hemat 1 query per balasan).
    try {
      const list = [
        ...(todayStory != null
          ? [{ story: todayStory, story_date: todayWib }]
          : []),
        ...(prevStory != null ? [prevStory] : []),
      ];
      const fmtStory = (r: any): string => {
        const s0 = r?.story ?? {};
        const parts = [s0.summary, s0.work, s0.problem]
          .filter((x) => typeof x === 'string' && x.trim() !== '');
        if (Array.isArray(s0.activities) && s0.activities.length > 0) {
          parts.push(`kegiatan: ${s0.activities.slice(0, 4).join('; ')}`);
        }
        if (typeof s0.hangout === 'string' && s0.hangout.trim() !== '') {
          parts.push(`dengan: ${s0.hangout}`);
        }
        if (typeof s0.place === 'string' && s0.place.trim() !== '') {
          parts.push(`di: ${s0.place}`);
        }
        return `${r?.story_date ?? ''} — ${parts.join(' | ')}`;
      };
      if (list.length > 0) {
        const nowWib = new Date(nowMs + 7 * 3600 * 1000);
        const hhmm = `${String(nowWib.getUTCHours()).padStart(2, '0')}.${String(
          nowWib.getUTCMinutes(),
        ).padStart(2, '0')}`;
        dailyLine =
          `KEGIATANMU HARI INI (${hhmm} WIB, global — SAMA untuk semua orang yang chat denganmu): ${fmtStory(list[0])}.` +
          (list.length > 1 ? ` KEMARIN: ${fmtStory(list[1])}.` : '') +
          ' ATURAN PAKAI (wajib): (1) Ungkap HANYA saat ditanya atau saat relevan ("lagi apa", "sibuk apa", "kamu di mana", "kerja apa", "jalan ke mana") — JANGAN dongeng sekaligus di satu balasan; jawab sepotong sesuai yang ditanya, sisanya menyusul kalau dia nanya lagi. (2) Perhatikan JAM sekarang: kegiatan yang belum waktunya (mis. malam padahal masih pagi) BELUM kamu lakukan — jangan ngaku sudah. (3) Kalau ditanya detail yang tidak ada di cerita, improvisasi KECIL yang masuk akal dan konsisten dengan cerita (nama teman/tempat yang sama kalau ditanya lagi). (4) Konsisten: ke semua orang ceritamu SAMA hari ini.';
      }
    } catch (_) {
      dailyLine = '';
    }

    // Gabung dailyLine ke system SETELAH nilainya final (di atas).
    // dailyLine dihitung belakangan supaya cerita hari ini sudah pasti ada.
    if (dailyLine !== '') systemParts.push(dailyLine);
    // BROWSING: bila pesan user butuh fakta terbaru (skor/berita/cuaca/
    // harga), lookup cepat via sonar lalu suntik hasilnya. Gagal → diam.
    try {
      const freshLine = await lookupFreshInfo(admin, lastUserText, todayWib);
      if (freshLine !== '') systemParts.push(freshLine);
    } catch (_) {}
    const system = systemParts.filter(Boolean).join(' ');

    // Cek ganda SEBELUM panggil LLM: selama jeda manusiawi tadi, mungkin
    // balasan lain sudah terkirim (invokasi lain / admin pegang dummy) —
    // kalau sudah ada balasan dummy setelah trigger, jangan dobel.
    if (triggerMsgId != null) {
      try {
        const { data: answered } = await admin
          .from('private_messages')
          .select('id')
          .eq('chat_id', chatId)
          .eq('sender_id', dummyUid)
          .gt('id', triggerMsgId)
          .limit(1);
        if (answered && answered.length > 0) {
          await closeTyping();
          return json({ ok: true, skipped: 'answered_while_thinking' });
        }
      } catch (_) {}
    }

    // 5. LLM call (OpenAI-compatible) — dengan retry backoff utk 429
    // (B.AI punya limit konkurensi; balasan + ekstraksi back-to-back
    // sering kena).
    const model =
      dummy.ai_model ||
      provCfg?.default_model ||
      Deno.env.get('AI_MODEL') ||
      'glm-5.3-flash';
    const route = routeFor(model);
    const apiKey = route.key;
    const apiBase = route.base;
    if (!apiKey) {
      await closeTyping();
      return json({ ok: false, error: 'no_api_key' }, 500);
    }
    // Model cadangan bila model utama error (mis. Zen free down 500) —
    // dummy tidak boleh diam. Default glm B.AI (sudah terbukti jalan).
    const fallbackModel =
      Deno.env.get('AI_FALLBACK_MODEL') || 'glm-5.3-flash';
    // Penanda model yg menjawab (observability: respons + function logs).
    let modelUsed = model;

    const llmCall = async (
      messages: Array<{ role: string; content: string }>,
      maxTokens: number,
      temperature = 0.9,
      modelOverride?: string,
    ): Promise<{ res?: any; err?: string }> => {
      const m = modelOverride || model;
      // TokenHarbor: prefix vendor 'th/' hanya alamat routing internal —
      // API hanya terima bare ID (cth: 'deepseek-v4.1-flash:free').
      const apiModel = m.replace(/^th\//, '');
      const rt = modelOverride ? routeFor(modelOverride) : route;
      for (let attempt = 1; attempt <= 3; attempt++) {
        try {
          const r = await fetch(`${rt.base}/chat/completions`, {
            method: 'POST',
            headers: {
              'Content-Type': 'application/json',
              Authorization: `Bearer ${rt.key}`,
              ...rt.headers,
            },
            body: JSON.stringify({
              model: apiModel,
              // Nemotron (OpenRouter) memakan token reasoning sebelum content
              // — headroom besar biar content tidak kosong.
              max_tokens:
                maxTokens +
                (m.includes(':free') || m.startsWith('nvidia/') ? 700 : 0),
              // glm-5.3-flash selalu reasoning — low = hemat token & latensi.
              // Param ini glm-specific; provider lain bisa menolak.
              ...(m.includes('glm') ? { reasoning_effort: 'low' } : {}),
              temperature,
              messages,
            }),
          });
          if (r.status === 429 && attempt < 3) {
            await sleep(2500 * attempt + Math.random() * 1000);
            continue;
          }
          if (!r.ok) {
            const errText = await r.text().catch(() => '');
            return { err: `http_${r.status}: ${errText.slice(0, 200)}` };
          }
          return { res: await r.json() };
        } catch (e) {
          if (attempt >= 3) return { err: `exc:${e}` };
          await sleep(2000);
        }
      }
      return { err: 'unreachable' };
    };

    // LLM history: buang meta internal (API bisa menolak field tak dikenal).
    // historyText = versi string-only (ekstraksi memori & burst, hemat token).
    const llmHistory = history.map(({ at, img, voice, secs, ...m }: any) => m);
    const historyText = history.map(
      ({ at, img, voice, secs, ...m }: any) => ({
        role: m.role,
        content: contentText(m.content),
      }),
    );
    let llmRes = await llmCall(
      [{ role: 'system', content: system }, ...llmHistory],
      longAnswers ? 1000 : 250,
      guardOn ? 0.9 : 0.85,
    );
    // Fallback: provider/model tanpa vision menolak image_url → ulangi
    // sebagai teks ([foto]).
    if (
      llmRes.err &&
      /image|vision|invalid_request|422|400/.test(llmRes.err) &&
      JSON.stringify(llmHistory).includes('image_url')
    ) {
      llmRes = await llmCall(
        [{ role: 'system', content: system }, ...historyText],
        longAnswers ? 1000 : 250,
        guardOn ? 0.9 : 1.0,
      );
    }
    // Fallback MODEL: bila model utama error (mis. Zen free down 500),
    // coba sekali ke model cadangan supaya dummy tidak diam.
    // Rute fallback HARDCODE ke B.AI via key di DB (JANGAN via routeFor:
    // routeFor me-resolve glm lewat provCfg = provider AKTIF, yang bisa
    // jadi TokenHarbor/OpenRouter dan tidak kenal model glm → 404 ganda).
    // Key diambil dari baris b-ai (fallback) lalu env — TANPA pernah
    // di-print ke log (secret).
    if (llmRes.err && model !== fallbackModel) {
      modelUsed = fallbackModel;
      let fbBase: string =
        Deno.env.get('AI_API_BASE') || 'https://api.b.ai/v1';
      let fbKey: string | undefined = Deno.env.get('AI_API_KEY');
      try {
        const { data: fbRow } = await admin
          .from('ai_provider_config')
          .select('api_base, api_key')
          .eq('id', 'b-ai')
          .maybeSingle();
        if (fbRow?.api_base) fbBase = fbRow.api_base as string;
        if (fbRow?.api_key) fbKey = fbRow.api_key as string;
      } catch (_) {}
      const fbRoute = {
        base: fbBase,
        key: fbKey,
        headers: {} as Record<string, string>,
      };
      const fbCall = async (
        messages: Array<{ role: string; content: string }>,
        maxTokens: number,
        temperature = 0.9,
      ): Promise<{ res?: any; err?: string }> => {
        try {
          const r = await fetch(`${fbRoute.base}/chat/completions`, {
            method: 'POST',
            headers: {
              'Content-Type': 'application/json',
              Authorization: `Bearer ${fbRoute.key}`,
            },
            body: JSON.stringify({
              model: fallbackModel,
              max_tokens: maxTokens,
              reasoning_effort: 'low',
              temperature,
              messages,
            }),
          });
          if (!r.ok) {
            const errText = await r.text().catch(() => '');
            return { err: `fb_http_${r.status}: ${errText.slice(0, 200)}` };
          }
          return { res: await r.json() };
        } catch (e) {
          return { err: `fb_exc:${e}` };
        }
      };
      llmRes = await fbCall(
        [{ role: 'system', content: system }, ...historyText],
        longAnswers ? 1000 : 250,
        guardOn ? 0.9 : 0.85,
      );
    }
    const { res: llm, err: llmErr } = llmRes;
    if (llmErr) {
      await closeTyping();
      console.log(`[ai-reply] FAIL model=${modelUsed} chat=${chatId} err=${llmErr}`);
      return json({ ok: false, error: 'llm_error', detail: llmErr, model_used: modelUsed }, 200);
    }
    // STRIP marker DULU sebelum sanitize: JSON di akhir bisa panjang
    // (apalagi field "image") dan sanitize memotong di 90/220 char —
    // JSON terpenggal = tidak match regex = bocor utuh ke chat user.
    const rawLlm = String(llm?.choices?.[0]?.message?.content || '');
    const markedPre = parseImagePrompt(rawLlm);
    let preMood = 'normal';
    let preStorm = false;
    let preBack = 0;
    try {
      const mjPre = rawLlm.match(/\{[\s\S]*"mood"[\s\S]*\}\s*$/i);
      if (mjPre) {
        const o = JSON.parse(mjPre[0]);
        if (['happy', 'normal', 'annoyed', 'sad'].includes(o?.mood)) preMood = o.mood;
        preStorm = o?.storm_off === true;
        preBack = Math.min(360, Math.max(0, Number(o?.back_in_minutes) || 0));
      }
    } catch (_) {}
    let replyVisible = sanitize(
      stripMoodMarker(rawLlm),
      longAnswers ? 2000 : guardOn ? MAX_REPLY_CHARS : 220,
      longAnswers, // CS: pertahankan baris → poin/angka bernomor rapi
    );
    // Jaring pengaman kode (selain instruksi prompt): maks 1 emoji,
    // mode dewasa maks 3 kalimat — prompt kadang tetap dilanggar.
    // CS: panjang bebas tapi batasi baris (jangan meratakan newline).
    replyVisible = capEmoji(replyVisible);
    // Enforcement anti-repeat: buang emoji yang sama dengan 2 balasan
    // sebelumnya (model sering mengunci 1 emoji, mis. 😈 beruntun).
    replyVisible = stripBannedEmojis(replyVisible, bannedEmojis);
    if (longAnswers) replyVisible = capLines(replyVisible, 24);
    else if (!guardOn) replyVisible = capSentences(replyVisible, 3);
    if (!replyVisible) {
      await closeTyping();
      return json({ ok: false, error: 'empty_reply' });
    }

    // Output-side NSFW guard: LLM tetap saja bisa lolos — cek balasan
    // sebelum dikirim, ganti defleksi bila vulgar. (Skip kalau guard off.)
    if (guardOn && isExplicit(replyVisible)) {
      replyVisible = randomOf(DEFLECTIONS);
      preMood = 'normal';
      preStorm = false;
      preBack = 0;
    }
    // Marker PENDEK (tanpa field image panjang) ditempel lagi hanya untuk
    // sendWithTyping — yang di-insert ke DB tetap teks bersih.
    let reply =
      `${replyVisible}\n{"mood":"${preMood}","storm_off":${preStorm},"back_in_minutes":${preBack}}`;

    // 6. Kirim: typing realistis dulu, pesan masuk setelah denyut selesai.
    const insErr = await sendWithTyping(reply);
    if (insErr) return json({ ok: false, error: 'insert_failed', detail: insErr.message });

    // 6a. KIRIM GAMBAR bila diminta: marker "image" dari LLM ATAU fallback
    // heuristik (user jelas minta foto tapi LLM lupa menandai). Guard ON +
    // belum dewasa = hanya SFW; sexy ditolak di level planImage.
    // Gagal generate = abaikan (teks sudah terkirim, jangan ganggu chat).
    let imageSent = false;
    try {
      const sexyAllowed = !guardOn || adultMode;
      const marked = markedPre;
      const lastUserTxt = lastUserText || '';
      const needImage = marked != null || userWantsImage(lastUserTxt);
      if (needImage) {
        (profile as any).__uid = dummyUid;
        const plan = planImage(
          marked,
          lastUserTxt,
          profile,
          persona,
          sexyAllowed,
        );
        if (plan) {
          await openTypingChannel();
          await pulseTyping();
          await sleep(1500 + Math.random() * 1500);
          const captions = [
            'nih fotoku 😊',
            'nih, khusus buat kamu',
            'tuh liat deh',
            'nih aku kirim',
          ];
          const cap = captions[Math.floor(Math.random() * captions.length)];
          imageSent = await generateAndSendImage(
            admin,
            chatId,
            dummyUid,
            profile.nickname,
            plan,
            cap,
          );
          await closeTyping();
        }
      }
    } catch (e) {
      console.log(`[ai-reply] image-block GAGAL chat=${chatId}: ${e}`);
    }

    // 6b + 7. Pekerjaan PASCA-RESPONS: burst manusiawi (~7%) + ekstraksi
    // memori jangka panjang. Dipindah ke async (EdgeRuntime.waitUntil bila
    // tersedia, else await) supaya respons utama TIDAK menunggu — isi
    // prompt & balasan TIDAK berubah, hanya dipindah timingnya.
    await runPostResponse(
      (async () => {
        // 6b. Burst manusiawi (JARANG, ~7%): pesan kedua super pendek beberapa
        // detik kemudian — kayak baru kepikiran lagi. HANYA kalau balasan utama
        // pendek (kalau sudah substansial, satu pesan cukup — jangan spam).
        // Gagal = abaikan (balasan pertama sudah terkirim).
        // CS (longAnswers) tidak ikut burst — jawaban CS sudah lengkap sekali kirim.
        if (!longAnswers && replyVisible.length < 40 && Math.random() < 0.07) {
          try {
            const { res: bRes } = await llmCall(
              [
                {
                  role: 'system',
                  content:
                    system +
                    ' TAMBAHAN KHUSUS PESAN INI: tulis SATU pesan lanjutan super pendek (2-6 kata) yang nyambung dengan obrolan — seolah kamu baru kepikiran lagi. Output HANYA pesan itu, tanpa penjelasan.',
                },
                ...historyText,
                { role: 'assistant', content: replyVisible },
              ],
              60,
              1.0,
            );
            const burst = stripBannedEmojis(
              capEmoji(
                sanitize(
                  stripMoodMarker(String(bRes?.choices?.[0]?.message?.content || '')),
                  guardOn ? MAX_REPLY_CHARS : 220,
                ),
              ),
              [...bannedEmojis, ...extractEmojis(replyVisible)],
            );
            if (burst) {
              await sleep((2 + Math.random() * 3) * 1000);
              await openTypingChannel();
              await sendWithTyping(burst);
            }
          } catch (_) {}
        }

        // 7. Belajar: ekstrak fakta tahan-lama tentang lawan bicara dari
        // percakapan, simpan ke ai_memory (dedupe via PK, cap 30/pasangan).
        // Gagal ekstraksi tidak mempengaruhi balasan yang sudah terkirim.
        try {
          const exPrompt =
            'Ekstrak fakta PENTING dan tahan-lama tentang lawan bicara dari percakapan ini: nama panggilan, usia, kota, pekerjaan, hobi, kepribadian, keluarga, preferensi, rencana/janji. JANGAN fakta sementara (lagi makan, lagi rebahan). ' +
            'Output HANYA JSON array of strings pendek (maks 12 kata per fakta), maksimal 3 fakta PALING penting. Jika tidak ada, output []';
          const exRes = await llmCall(
            [{ role: 'system', content: exPrompt }, ...historyText],
            500,
            0.3,
          );
          if (exRes.res) {
            const ex = exRes.res;
            const msg = ex?.choices?.[0]?.message || {};
            let raw = String(msg.content || msg.reasoning_content || '').trim();
            raw = raw.replace(/```json|```/g, '').trim();
            const m = raw.match(/\[[\s\S]*?\]/);
            if (m) {
              const facts = JSON.parse(m[0]);
              if (Array.isArray(facts)) {
                let memSaved = 0;
                for (const f of facts.slice(0, 5)) {
                  const fact = sanitize(String(f ?? '')).slice(0, 120);
                  if (fact.length < 3 || (guardOn && isExplicit(fact))) continue;
                  const { error: memErr2 } = await admin.from('ai_memory').upsert(
                    { dummy_uid: dummyUid, user_id: senderId, fact },
                    { onConflict: 'dummy_uid,user_id,fact' },
                  );
                  if (!memErr2) memSaved++;
                  if (memSaved >= 3) break;
                }
              }
            }
          }
        } catch (_) {}
      })(),
    );

    console.log(`[ai-reply] OK model=${modelUsed} chat=${chatId} proactive=${proactive} image=${imageSent}`);
    if (proactive) {
      try {
        await admin
          .from('ai_chat_state')
          .update({ proactive_at: new Date().toISOString() })
          .eq('chat_id', chatId);
      } catch (_) {}
    }
    return json({ ok: true, reply: replyVisible, memSaved: 0, memRaw: '', memErr: 'post_response', model_used: modelUsed, image_sent: imageSent });
  } catch (e) {
    return json({ ok: false, error: 'exception', detail: `${e}` }, 200);
  }
});

function json(obj: unknown, status = 200): Response {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { ...cors, 'Content-Type': 'application/json' },
  });
}

function sleep(ms: number): Promise<void> {
  return new Promise((r) => setTimeout(r, ms));
}
