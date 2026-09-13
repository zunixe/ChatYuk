// Pure helper murni ai-reply — bisa diuji via Deno tanpa edge runtime.
// Source: supabase/functions/ai-reply/index.ts (extracted 2026-09-13).

export const MAX_REPLY_CHARS = 90;

export const EXPLICIT_TERMS = [
  'seks', 'sex', 'ngentot', 'jilat', 'sange', 'horny', 'telanjang', 'bugil',
  'nude', 'paha dalem', 'dada', 'payudara', 'toket', 'memek', 'kontol',
  'penis', 'vagina', 'bokep', 'porn', 'masto', 'orgasme', 'ritual ranjang',
  'masturbasi', 'onani', 'colmek', 'coli', 'setubuh', 'bercinta', 'birahi',
  'esek', 'esek-esek', 'hack', 'cheat', 'crack', 'exploit', 'nudes',
  'sexting', 'nsfw', 'xxx', 'hentai', 'onlyfans', 'fap', 'cum', 'creampie',
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

export function asleepAt(uid: string, ms: number): boolean {
  const w = wibParts(ms);
  const sw = sleepHours(uid, w.date);
  return w.hour >= sw.sleepHour || w.hour < sw.wakeHour;
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

export function isExplicit(text: string): boolean {
  if (!text) return false;
  const t = text.toLowerCase();
  return EXPLICIT_TERMS.some((term) => t.includes(term));
}

export function sanitize(text: string, maxChars: number | null = MAX_REPLY_CHARS): string {
  let t = (text || '').trim();
  t = t.replace(/^\s*\{[^{}]*\}/, '').trim();
  if (maxChars !== null && t.length > maxChars) t = t.slice(0, maxChars);
  const lines = t.split('\n').filter((l) => l.trim());
  return lines.length > 1 ? lines[lines.length - 1].trim() : t;
}

export const IMAGE_REQUEST_RE = /\b(kirim|kasi|kasih|tolong|send|share)\b.*\b(foto|gambar|photo|image|selfie|pict|picture)\b|\b(selfie|selfi)\b|\bphoto\b/i;

export function isImageRequest(text: string): boolean {
  return IMAGE_REQUEST_RE.test(text || '');
}

export function needsFreshInfo(t: string): boolean {
  if (!t || t.length < 3) return false;
  if (/foto|gambar|pap\b|selfie|wajahmu|muka/i.test(t)) return false;
  return /skor|hasil (pertandingan|laga|match)|berapa[- ]berapa|juara|klasemen|berita|kabar terbaru|terkini|breaking|viral|cuaca|harga (emas|bitcoin|btc|eth|dollar|usd|rupiah|bensin|bbm|beras|cabai)|kurs|gempa|transfer pemain|jadwal (main|tanding|pertandingan|konser|bioskop|film)|kapan (main|tanding|rilis|tayang)|episode (terbaru|terakhir)|siapa (menang|juara|presiden)|hasil (pemilu|pilkada)|menang.*(tadi|kemarin|semalam|tadi malam)|kalah.*(tadi|kemarin|semalam|tadi malam)/i
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
