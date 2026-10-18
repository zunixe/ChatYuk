// Parser OG + fetch ringkas — SATU sumber untuk:
//  - link-preview (preview di app)
//  - send-push (notifikasi pesan berisi link: judul/deskripsi + gambar)
// Paritas dengan `LinkPreviewService.parseHtml` di Dart.

export type PreviewData = {
  title: string;
  description: string;
  image: string;
  siteName: string;
};

export const MAX_URL_LEN = 2048;
export const MAX_HTML_BYTES = 512 * 1024;
const UA =
  'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Mobile Safari/537.36';

/// Parse og:* / <title> dari HTML.
export function parsePreview(url: string, html: string): PreviewData {
  const metaProp = (prop: string): string => {
    const r1 = new RegExp(
      `<meta[^>]+property=["']${prop}["'][^>]+content=["']([^"']+)["']`,
      'i',
    );
    const m1 = html.match(r1);
    if (m1) return m1[1].trim();
    const r2 = new RegExp(
      `<meta[^>]+content=["']([^"']+)["'][^>]+property=["']${prop}["']`,
      'i',
    );
    const m2 = html.match(r2);
    return m2 ? m2[1].trim() : '';
  };
  const metaName = (name: string): string => {
    const r = new RegExp(
      `<meta[^>]+name=["']${name}["'][^>]+content=["']([^"']+)["']`,
      'i',
    );
    return html.match(r)?.[1]?.trim() ?? '';
  };
  let host = url;
  try {
    host = new URL(url).host;
  } catch (_) { /* biarkan url apa adanya */ }
  let title = metaProp('og:title');
  if (!title) title = html.match(/<title[^>]*>([^<]+)<\/title>/i)?.[1]?.trim() ?? '';
  if (!title) title = host;
  const description = metaProp('og:description') || metaName('description');
  const image = metaProp('og:image');
  const siteName = metaProp('og:site_name') || host;
  return { title, description, image, siteName };
}

/// URL pertama di teks (sama seperti `_urlRegex` klien), tanda baca penutup
/// dibuang. Kosong bila tidak ada / terlalu panjang.
export function extractFirstUrl(text: string): string {
  const m = (text ?? '').match(/https?:\/\/[^\s<>"']+/i);
  if (!m) return '';
  let u = m[0];
  const tail = '.,!?;:)]}\'"';
  while (u.length > 0 && tail.includes(u[u.length - 1])) u = u.slice(0, -1);
  if (!u || u.length > MAX_URL_LEN) return '';
  return u;
}

// Cache kecil per-isolate: link yang sama dikirim berulang tidak fetch ulang.
const CACHE_TTL_MS = 10 * 60 * 1000;
const CACHE_MAX = 200;
const _cache = new Map<string, { at: number; val: PreviewData | null }>();

/// Fetch metadata dengan timeout ketat (dipakai jalur push: jangan menahan
/// notifikasi lama). null bila gagal/terlalu lambat.
export async function fetchPreview(
  url: string,
  timeoutMs = 1500,
): Promise<PreviewData | null> {
  if (!url || !/^https?:\/\//i.test(url) || url.length > MAX_URL_LEN) return null;
  const hit = _cache.get(url);
  if (hit && Date.now() - hit.at < CACHE_TTL_MS) return hit.val;
  let val: PreviewData | null = null;
  try {
    const ctrl = new AbortController();
    const t = setTimeout(() => ctrl.abort(), timeoutMs);
    const res = await fetch(url, {
      redirect: 'follow',
      signal: ctrl.signal,
      headers: { 'User-Agent': UA, 'Accept-Language': 'en-US,en;q=0.9,id;q=0.8' },
    });
    clearTimeout(t);
    if (res.ok) {
      const reader = res.body?.getReader();
      let html = '';
      if (reader) {
        const dec = new TextDecoder();
        let total = 0;
        while (true) {
          const { done, value } = await reader.read();
          if (done) break;
          total += value.length;
          html += dec.decode(value, { stream: true });
          if (total >= MAX_HTML_BYTES) break;
        }
      }
      if (html) val = parsePreview(url, html);
    }
  } catch (_) {
    val = null;
  }
  if (_cache.size >= CACHE_MAX) _cache.clear();
  _cache.set(url, { at: Date.now(), val });
  return val;
}

/// oEmbed (judul + thumbnail resmi) untuk situs yang memblokir fetch HTML
/// dari IP server: YouTube & TikTok. Dipakai sebagai FALLBACK.
async function fetchOEmbed(
  url: string,
  timeoutMs = 1200,
): Promise<PreviewData | null> {
  const u = url.toLowerCase();
  let endpoint = '';
  if (u.includes('youtube.com') || u.includes('youtu.be')) {
    endpoint = `https://www.youtube.com/oembed?format=json&url=${
      encodeURIComponent(url)
    }`;
  } else if (u.includes('tiktok.com')) {
    endpoint = `https://www.tiktok.com/oembed?url=${encodeURIComponent(url)}`;
  } else {
    return null;
  }
  try {
    const ctrl = new AbortController();
    const t = setTimeout(() => ctrl.abort(), timeoutMs);
    const res = await fetch(endpoint, {
      signal: ctrl.signal,
      headers: { 'User-Agent': UA, 'Accept': 'application/json' },
    });
    clearTimeout(t);
    if (!res.ok) return null;
    const j = await res.json();
    const title = `${j?.title ?? ''}`.trim();
    const image = `${j?.thumbnail_url ?? ''}`.trim();
    if (!title && !image) return null;
    let host = url;
    try {
      host = new URL(url).host;
    } catch (_) { /* biarkan */ }
    return {
      title,
      description: `${j?.author_name ?? ''}`.trim(),
      image,
      siteName: `${j?.provider_name ?? host}`.trim() || host,
    };
  } catch (_) {
    return null;
  }
}

/// Fetch metadata dengan fallback oEmbed. Dipakai jalur PUSH (notifikasi):
/// link YouTube/TikTok tetap dapat judul + gambar walau HTML-nya diblok.
///
/// Hasil fetch HTML disebut "lemah" bila tanpa gambar ATAU judulnya cuma nama
/// situs/host (kasus YouTube: title "YouTube", image "") → oEmbed dipakai.
export async function fetchPreviewWithFallback(
  url: string,
  timeoutMs = 1500,
): Promise<PreviewData | null> {
  const direct = await fetchPreview(url, timeoutMs);
  if (_isRich(direct)) return direct;
  const oe = await fetchOEmbed(url);
  if (!oe) return direct;
  return {
    title: _betterTitle(direct?.title, oe.title, direct?.siteName),
    description: direct?.description || oe.description,
    image: direct?.image || oe.image,
    siteName: oe.siteName || direct?.siteName || '',
  };
}

function _isRich(p: PreviewData | null): boolean {
  if (!p) return false;
  if (!p.image) return false;
  const t = p.title.trim().toLowerCase();
  const host = p.siteName.trim().toLowerCase();
  return t.length > 0 && t !== host && t !== 'youtube';
}

function _betterTitle(a?: string, b?: string, avoid?: string): string {
  const A = (a ?? '').trim();
  const B = (b ?? '').trim();
  const weak =
    A.length === 0 ||
    A.toLowerCase() === (avoid ?? '').trim().toLowerCase() ||
    A.toLowerCase() === 'youtube';
  return weak ? (B || A) : A;
}
