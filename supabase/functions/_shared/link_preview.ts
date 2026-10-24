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

// ── SSRF guard (REVIEW_2026-10-24 SEC-03) ───────────────────────────────────
// Sebelumnya: validasi hanya `^https?://` + panjang, redirect diikuti bebas.
// Akibatnya user login bisa menyuruh server fetch URL internal
// (169.254.169.254 metadata, host privat, redirect ke IP privat) lalu membaca
// og:*/<title> hasilnya — server jadi proxy pemindai jaringan internal.
//
// Guard ini menolak: hostname internal, IP literal privat/loopback/link-local,
// dan hasil resolusi DNS yang mengarah ke rentang privat. Redirect diikuti
// MANUAL maksimal [MAX_REDIRECTS] hop dengan validasi ulang tiap hop.
const MAX_REDIRECTS = 3;

function isPrivateIpv4(ip: string): boolean {
  const m = ip.match(/^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/);
  if (!m) return false;
  const a = Number(m[1]), b = Number(m[2]);
  if (a === 0 || a === 10 || a === 127) return true;
  if (a === 169 && b === 254) return true;            // link-local + cloud metadata
  if (a === 172 && b >= 16 && b <= 31) return true;   // privat
  if (a === 192 && b === 168) return true;            // privat
  if (a === 100 && b >= 64 && b <= 127) return true;  // CGNAT
  if (a >= 224) return true;                          // multicast/reserved
  return false;
}

export function isBlockedIp(ip: string): boolean {
  const l = ip.trim().toLowerCase().replace(/^\[|\]$/g, '');
  if (isPrivateIpv4(l)) return true;
  if (l === '::1' || l === '::') return true;
  if (l.startsWith('fc') || l.startsWith('fd')) return true;  // unique local
  if (l.startsWith('fe80')) return true;                      // link-local
  if (l.startsWith('::ffff:')) return isBlockedIp(l.slice(7)); // IPv4-mapped
  return false;
}

const BLOCKED_HOSTS = new Set([
  'localhost', 'localhost.localdomain', 'metadata', 'metadata.google.internal',
  'instance-data', 'kubernetes', 'kubernetes.default',
]);

export function isBlockedHostname(host: string): boolean {
  const h = host.trim().toLowerCase().replace(/\.$/, '');
  if (!h) return true;
  if (BLOCKED_HOSTS.has(h)) return true;
  if (h.endsWith('.localhost') || h.endsWith('.internal') || h.endsWith('.local')) return true;
  // IP literal (v4) atau IPv6 dalam bracket.
  if (isPrivateIpv4(h)) return true;
  if (h.includes(':') && isBlockedIp(h)) return true;
  return false;
}

/// Resolve DNS dan tolak bila ADA record yang mengarah ke IP privat.
/// Bila resolver tidak tersedia, tetap izinkan (fail-open) — guard hostname
/// literal di atas sudah menutup kasus paling umum, dan runtime Deno Deploy
/// tidak berada di jaringan privat pengguna.
async function resolvesToPrivate(host: string): Promise<boolean> {
  try {
    const deno = (globalThis as unknown as {
      Deno?: { resolveDns?: (n: string, t: string) => Promise<string[]> };
    }).Deno;
    if (!deno?.resolveDns) return false;
    const [v4, v6] = await Promise.all([
      deno.resolveDns(host, 'A').catch(() => [] as string[]),
      deno.resolveDns(host, 'AAAA').catch(() => [] as string[]),
    ]);
    return [...v4, ...v6].some((ip) => isBlockedIp(ip));
  } catch (_) {
    return false;
  }
}

/// Validasi URL tujuan fetch: skema, hostname, dan hasil DNS.
export async function assertSafeUrl(raw: string): Promise<URL | null> {
  let u: URL;
  try {
    u = new URL(raw);
  } catch (_) {
    return null;
  }
  if (u.protocol !== 'http:' && u.protocol !== 'https:') return null;
  if (u.username || u.password) return null; // kredensial di URL = mencurigakan
  if (isBlockedHostname(u.hostname)) return null;
  if (await resolvesToPrivate(u.hostname)) return null;
  return u;
}

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
    // SSRF: validasi URL awal (hostname + DNS privat).
    if (!(await assertSafeUrl(url))) {
      _cache.set(url, { at: Date.now(), val: null });
      return null;
    }
    const ctrl = new AbortController();
    const t = setTimeout(() => ctrl.abort(), timeoutMs);
    // Redirect diikuti MANUAL: tiap hop divalidasi ulang, maks MAX_REDIRECTS.
    // `redirect: 'follow'` dulu bisa dibelokkan ke IP privat/metadata.
    let target = url;
    let res: Response | null = null;
    for (let hop = 0; hop <= MAX_REDIRECTS; hop++) {
      res = await fetch(target, {
        redirect: 'manual',
        signal: ctrl.signal,
        headers: { 'User-Agent': UA, 'Accept-Language': 'en-US,en;q=0.9,id;q=0.8' },
      });
      const isRedirect = res.status >= 300 && res.status < 400;
      if (!isRedirect) break;
      const loc = res.headers.get('location');
      if (!loc) break;
      let next: URL;
      try {
        next = new URL(loc, target);
      } catch (_) {
        res = null;
        break;
      }
      if (!(await assertSafeUrl(next.toString()))) {
        res = null;
        break;
      }
      target = next.toString();
      if (hop === MAX_REDIRECTS) {
        res = null; // terlalu banyak redirect
      }
    }
    clearTimeout(t);
    if (res && res.ok) {
      // Batasi ke HTML saja (cegah menarik biner besar / JSON internal).
      const ct = (res.headers.get('content-type') || '').toLowerCase();
      if (ct && !ct.includes('text/html') && !ct.includes('application/xhtml')) {
        _cache.set(url, { at: Date.now(), val: null });
        return null;
      }
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
