// Pure helper murni ai-reply — bisa diuji via Deno tanpa edge runtime.
// Cermin supabase/functions/ai-reply/index.ts — kalau mengubah salah satu,
// sinkronkan pasangannya (sumber kebenaran tunggal = index.ts).

export const MAX_REPLY_CHARS = 90;

export const EXPLICIT_TERMS = [
  // ID
  'seks', 'sex', 'ngentot', 'jilat', 'sange', 'horny', 'telanjang', 'bugil',
  'nude', 'paha dalem', 'dada', 'payudara', 'toket', 'memek', 'kontol',
  'penis', 'vagina', 'bokep', 'porn', 'masto', 'orgasme', 'ritual ranjang',
  'ranjang', 'bikin anak', 'kencan malam', 'besar dan keras', 'dobel',
  // EN
  'naked', 'nudes', 'fuck', 'sex chat', 'sexy time', 'blowjob', 'handjob',
  'horny', ' dildo', 'escort', 'onlyfans', 'nsfw',
];

export const INSULT_TERMS = [
  'bego', 'goblok', 'bodoh', 'tolol', 'idiot', 'otak ayam', 'otak udang',
  'bangsat', 'brengsek', 'bajingan', 'tai kucing', 'sialan', 'asu',
  'anjing lo', 'anjing kamu', 'dasar', 'tidak berguna', 'ga berguna',
  'gak berguna', 'tak berguna', 'guna', 'jelek banget', 'buruk banget',
  'benci kamu', 'benci sama kamu', 'payah', 'kacau', 'menyebalkan',
  'stupid', 'idiot', 'useless', 'hate you', 'moron', 'dumb',
];

export function hashInt(s: string): number {
  let h = 0;
  for (let i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) | 0;
  return Math.abs(h);
}

export function wibParts(
  ms: number,
): { date: string; hour: number; minute: number; weekday: number } {
  const d = new Date(ms + 7 * 3600 * 1000);
  return {
    date: d.toISOString().slice(0, 10),
    hour: d.getUTCHours(),
    minute: d.getUTCMinutes(),
    weekday: d.getUTCDay(),
  };
}

export function sleepHours(
  uid: string,
  dateWib: string,
): { sleepHour: number; wakeHour: number } {
  const h = hashInt(`${uid}|${dateWib}|sleep`);
  return { sleepHour: 20 + (h % 4), wakeHour: 4 + (Math.floor(h / 4) % 3) };
}

export function asleepAt(
  uid: string,
  ms: number,
  activeHours?: number[] | null,
): boolean {
  const w = wibParts(ms);
  // ai_active_hours = override EKSPLISIT dari admin: jam yang tercantum =
  // BANGUN (menang atas jam tidur acak). Konsisten dgn presence-tick (yang
  // memakai ai_active_hours murni) & chip "Bangun/Tidur" di panel admin.
  if (activeHours && activeHours.length > 0 && activeHours.includes(w.hour)) {
    return false;
  }
  const sw = sleepHours(uid, w.date);
  return w.hour >= sw.sleepHour || w.hour < sw.wakeHour;
}

// Cermin index.ts: buang jam tidur dari jadwal aktif harian supaya tick
// presence ikut meng-offline-kan dummy saat jam tidur (konsisten dengan
// gate balasan asleepAt). Floor 6 jam: jadwal degeneratif diganti
// siang standar sebelum jam tidur.
export function applySleepToSchedule(hours: number[], sleepHour: number): number[] {
  const kept = [...new Set(hours)]
    .map((e) => Number(e))
    .filter((e) => Number.isInteger(e) && e >= 0 && e < sleepHour)
    .sort((a, b) => a - b);
  if (kept.length >= 6) return kept;
  const fallback: number[] = [];
  for (let h = 7; h < sleepHour && fallback.length < 12; h++) fallback.push(h);
  return fallback.length >= 6 ? fallback : kept;
}

export function fridayPrayerAt(
  gender: string | null | undefined,
  ms: number,
): boolean {
  if (gender !== 'male') return false;
  const w = wibParts(ms);
  if (w.weekday !== 5) return false;
  const mins = w.hour * 60 + w.minute;
  return mins >= 690 && mins < 780;
}

export function stableSeed(uid: string): number {
  let h = 0;
  for (let i = 0; i < uid.length; i++) h = (h * 131 + uid.charCodeAt(i)) | 0;
  return Math.abs(h) % 999999;
}

export const FACE_DEFAULTS = [
  'long straight black hair, oval face, warm brown almond eyes, light brown skin, soft natural smile, petite',
  'shoulder-length black hair, round face, dark brown eyes, tan skin, gentle smile, medium build',
  'short bob black hair, heart-shaped face, big brown eyes, fair skin, bright smile, slim',
  'wavy black hair, diamond face, hazel eyes, medium brown skin, subtle smile, curvy',
  'straight black hair with bangs, oblong face, dark eyes, olive skin, calm smile, athletic',
  'braided black hair, square face, warm brown eyes, deep tan skin, wide smile, fuller figure',
];

export function faceDescriptor(persona: any, uid: string): string {
  const custom = String(persona?.appearance || '').trim();
  if (custom) return custom;
  let h = 0;
  for (let i = 0; i < uid.length; i++) h = (h * 31 + uid.charCodeAt(i)) | 0;
  return FACE_DEFAULTS[Math.abs(h) % FACE_DEFAULTS.length];
}

export function hasWord(text: string, term: string): boolean {
  const esc = term
    .toLowerCase()
    .replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  return new RegExp(`(^|[^\\p{L}])${esc}([^\\p{L}]|$)`, 'iu').test(text);
}

export function isExplicit(text: string): boolean {
  if (!text) return false;
  return EXPLICIT_TERMS.some((w) => hasWord(text, w));
}

export function isInsult(text: string): boolean {
  if (!text) return false;
  return INSULT_TERMS.some((w) => hasWord(text, w));
}

export function sanitize(
  text: string,
  maxChars: number | null = MAX_REPLY_CHARS,
  keepLines = false,
): string {
  let t = (text || '').trim();
  t = t.replace(/^\s*\{[^{}]*\}/, '').trim();
  t = t.replace(/\*\*/g, '').replace(/^#+\s*/gm, '');
  if (keepLines) {
    t = t
      .split(/\r?\n/)
      .map((line) => {
        const m = line.match(/^([ \t]*)([\s\S]*)$/);
        const indent = (m?.[1] ?? '')
          .replace(/\t/g, '  ')
          .slice(0, 24);
        const rest = (m?.[2] ?? '').replace(/[ \t]+/g, ' ').trim();
        return rest ? indent + rest : '';
      })
      .join('\n')
      .replace(/\n{3,}/g, '\n\n')
      .trim();
    if (maxChars != null && t.length > maxChars) t = t.slice(0, maxChars).trim();
    return t;
  }
  t = t.replace(/\n+/g, ' ');
  if (maxChars != null && t.length > maxChars) {
    const cut = t.slice(0, maxChars);
    const lastStop = Math.max(
      cut.lastIndexOf('. '),
      cut.lastIndexOf('! '),
      cut.lastIndexOf('? '),
      cut.lastIndexOf(','),
    );
    t = (lastStop > 30 ? cut.slice(0, lastStop + 1) : cut).trim();
    t = t.replace(/[,;:]$/, '');
    if (!/[.!?]$/.test(t)) t += '...';
  }
  return t;
}

export const IMAGE_REQUEST_RE =
  /(kirim|minta|bagi|bagiin|kirimin|kasih|kasi|lihat|liat|show|send|mau|dong|dongg|please|pls).{0,20}(foto|gambar|photo|pic|poto|selfie|pap|wajah|muka|body|badan)|^(foto|gambar|photo|pic|poto|selfie|pap).{0,30}(dong|dulu|lagi|ya|kamu|mu|kirim|minta)|kirim.*(seksi|sexy|nakal|hot|bikini|tanktop)/i;

export function userWantsImage(text: string): boolean {
  return IMAGE_REQUEST_RE.test(text || '');
}

// Cermin index.ts: ambil blok ```mermaid pertama (untuk render diagram).
// Return null bila tidak ada / terlalu pendek (bukan diagram beneran).
export function extractMermaid(text: string): string | null {
  const m = String(text || '').match(/```mermaid\s*\n([\s\S]*?)```/i);
  if (!m) return null;
  const code = m[1].trim().slice(0, 2000);
  return code.length >= 10 ? code : null;
}

// Cermin index.ts: ambil blok ```chartjs pertama (config Chart.js v2 untuk
// render chart via QuickChart). Validasi: JSON objek + type di whitelist +
// data.datasets non-kosong. Return JSON canonical, null bila tak valid.
const CHART_TYPES = ['pie', 'doughnut', 'bar', 'line', 'radar', 'polarArea'];

export function extractChartJs(text: string): string | null {
  const m = String(text || '').match(/```chartjs\s*\n([\s\S]*?)```/i);
  if (!m) return null;
  const raw = m[1].trim().slice(0, 4000);
  if (raw.length < 20) return null;
  try {
    const cfg = JSON.parse(raw);
    if (!cfg || typeof cfg !== 'object') return null;
    if (!CHART_TYPES.includes(String(cfg.type || '').trim())) return null;
    const data = (cfg as any).data;
    if (!data || typeof data !== 'object') return null;
    const sets = (data as any).datasets;
    if (!Array.isArray(sets) || sets.length < 1) return null;
    return JSON.stringify(cfg).slice(0, 4000);
  } catch (_) {
    return null;
  }
}

export function chartUrl(configJson: string): string {
  return `https://quickchart.io/chart?c=${encodeURIComponent(configJson)}&w=800&h=500&format=png&backgroundColor=white`;
}

// Cermin index.ts: ringkas RSS Google News jadi fakta + media + tanggal.
export function summarizeNewsRss(xml: string): string {
  const parts: string[] = [];
  const items = String(xml || '').match(/<item>[\s\S]*?<\/item>/g) || [];
  for (const it of items.slice(0, 3)) {
    const mT = it.match(/<title>([\s\S]*?)<\/title>/);
    const mP = it.match(/<pubDate>([\s\S]*?)<\/pubDate>/);
    const raw = (mT ? mT[1] : '').trim().replace(/<!\[CDATA\[|\]\]>/g, '');
    if (!raw) continue;
    const idx = raw.lastIndexOf(' - ');
    const head = idx > 0 ? raw.slice(0, idx).trim() : raw;
    const media = idx > 0 ? raw.slice(idx + 3).trim() : '';
    const dm = (mP ? mP[1] : '').match(/\d{1,2} \w{3}/);
    parts.push(
      dm && media ? `${head} (${media}, ${dm[0]})`
      : media ? `${head} (${media})`
      : head,
    );
  }
  return parts.join(' | ').slice(0, 500);
}

export function needsFreshInfo(t: string): boolean {
  if (!t || t.length < 3) return false;
  if (/foto|gambar|pap\b|selfie|wajahmu|muka/i.test(t)) return false;
  return /skor|hasil (pertandingan|laga|match)|berapa[- ]berapa|juara|klasemen|berita|kabar terbaru|terkini|breaking|viral|cuaca|harga (emas|bitcoin|btc|eth|dollar|usd|rupiah|bensin|bbm|beras|cabai)|kurs|gempa|transfer pemain|jadwal (main|tanding|pertandingan|konser|bioskop|film)|kapan (main|tanding|rilis|tayang)|episode (terbaru|terakhir)|siapa (menang|juara|presiden)|hasil (pemilu|pilkada)|menang.*(tadi|kemarin|semalam|tadi malam)|kalah.*(tadi|kemarin|semalam|tadi malam)|dokumentasi|docs\b|changelog|release notes|versi (terbaru|baru|terkini)|rilis (terbaru|baru)|update terbaru|CVE|vulnerab|keamanan siber|benchmark|spesifikasi|spec\b|datasheet|whitepaper|arxiv|RFC|API reference|migration guide|best practice|perbandingan (teknologi|framework|chip|prosesor|gpu)|roadmap (teknologi|produk)|transistor|nanometer|\b\d+\s?nm\b|arsitektur (chip|prosesor|cpu|gpu|arm|x86|risc)/i
    .test(t);
}

export function browseTopicKey(t: string): string {
  return t
    .toLowerCase()
    .replace(/[^a-z0-9 ]/gi, ' ')
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, 120);
}
