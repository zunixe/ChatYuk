// ChatYuk: link preview (og:* metadata) — SERVER-SIDE fetch (mirip Telegram
// messages.getWebPage). Kenapa di server: (a) IP server lebih lolos anti-bot
// (TikTok/Shopee) daripada device, (b) hasil konsisten lintas device, (c) tak
// membocorkan IP user ke situs tujuan.
//
// Auth: verify_jwt Supabase (default gateway) — dipanggil klien yang login.
// Input : POST { url } — hanya http(s), panjang dibatasi (anti-SSRF sederhana).
// Output: { ok, title, description, image, siteName }

const MAX_URL_LEN = 2048;
const FETCH_TIMEOUT_MS = 8000;
const MAX_HTML_BYTES = 512 * 1024; // cukup utk <head>; jangan unduh halaman penuh

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

/// Parse og:* / <title> dari HTML (paritas LinkPreviewService.parseHtml Dart).
export function parsePreview(
  url: string,
  html: string,
): { title: string; description: string; image: string; siteName: string } {
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

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') return json({ error: 'method' }, 405);

  let url = '';
  try {
    const body = await req.json();
    url = (body?.url ?? '').toString().trim();
  } catch (_) {
    return json({ error: 'bad json' }, 400);
  }
  if (!url || url.length > MAX_URL_LEN || !/^https?:\/\//i.test(url)) {
    return json({ error: 'bad url' }, 400);
  }

  try {
    const ctrl = new AbortController();
    const t = setTimeout(() => ctrl.abort(), FETCH_TIMEOUT_MS);
    const res = await fetch(url, {
      redirect: 'follow',
      signal: ctrl.signal,
      headers: {
        // UA browser: banyak situs (YouTube/TikTok) blokir UA non-browser.
        'User-Agent':
          'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Mobile Safari/537.36',
        'Accept-Language': 'en-US,en;q=0.9,id;q=0.8',
      },
    });
    clearTimeout(t);
    if (!res.ok) return json({ ok: false, error: `status ${res.status}` });

    // Batasi ukuran (jangan baca seluruh halaman besar): potong di MAX_HTML_BYTES.
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
      html += dec.decode();
    } else {
      html = await res.text();
    }

    const p = parsePreview(url, html);
    return json({ ok: true, ...p });
  } catch (e) {
    return json({ ok: false, error: `${e}` });
  }
});
