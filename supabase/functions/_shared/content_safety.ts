// Klasifikasi konten NSFW — helper MURNI (bisa diuji tanpa jaringan).
//
// Dipakai `functions/content-safety/index.ts`. Dua lapisan:
//   1. Model lokal `nsfwjs` bila tersedia (NSFW_MODEL=local) — lihat index.ts.
//   2. Fallback: provider vision yang sudah aktif di `ai_provider_config`
//      (OpenAI-compatible /chat/completions dengan image_url).
//
// Semua ambang dibaca dari `app_settings` (nsfw_reject_threshold,
// nsfw_review_threshold) agar bisa diubah tanpa rilis.

export type SafetyVerdict = 'allow' | 'review' | 'reject';

/// Petakan skor 0..1 ke keputusan.
///   >= reject  → 'reject' (media ditolak, file dihapus)
///   >= review  → 'review' (pesan `pending`, menunggu moderator)
///   selainnya  → 'allow'
export function verdictForScore(
  score: number,
  rejectThreshold: number,
  reviewThreshold: number,
): SafetyVerdict {
  const s = Number.isFinite(score) ? Math.max(0, Math.min(1, score)) : 0;
  if (s >= rejectThreshold) return 'reject';
  if (s >= reviewThreshold) return 'review';
  return 'allow';
}

/// Ambil skor NSFW dari respons model (JSON bebas) — toleran terhadap
/// beberapa bentuk: `{score}`, `{nsfw_score}`, atau daftar kategori
/// `[{className, probability}]` (gaya nsfwjs).
export function extractScore(raw: unknown): number | null {
  if (raw == null) return null;
  if (typeof raw === 'number' && Number.isFinite(raw)) return raw;
  if (Array.isArray(raw)) {
    let max = -1;
    for (const item of raw) {
      if (item && typeof item === 'object') {
        const cls = String((item as Record<string, unknown>).className ?? '')
          .toLowerCase();
        const p = Number((item as Record<string, unknown>).probability);
        if (Number.isFinite(p) && (cls === 'porn' || cls === 'hentai' || cls === 'sexy')) {
          max = Math.max(max, p);
        }
      }
    }
    return max < 0 ? null : max;
  }
  if (typeof raw === 'object') {
    const o = raw as Record<string, unknown>;
    for (const k of ['score', 'nsfw_score', 'nsfwScore', 'nsfw']) {
      const v = o[k];
      if (typeof v === 'number' && Number.isFinite(v)) return v;
      if (typeof v === 'string') {
        const n = Number(v);
        if (Number.isFinite(n)) return n;
      }
      if (typeof v === 'boolean') return v ? 1 : 0;
    }
  }
  return null;
}

/// Prompt ketat untuk provider vision: WAJIB balas JSON satu baris.
export const NSFW_PROMPT =
  'You are a strict content-safety classifier for a public chat room app. ' +
  'Look at the image and rate how explicitly sexual it is. ' +
  'Reply with ONE line of JSON only, no markdown: ' +
  '{"score": <number 0..1>, "label": "safe"|"suggestive"|"explicit"}. ' +
  'score 0 = clearly safe (landscape, objects, food, clothed people). ' +
  'score 1 = explicit nudity or sexual act. ' +
  'Be strict: swimwear/lingerie with sexual posing => >=0.7.';

/// Bangun body request chat/completions untuk klasifikasi gambar (base64).
export function buildVisionBody(model: string, mime: string, b64: string) {
  return {
    model,
    temperature: 0,
    max_tokens: 40,
    messages: [
      {
        role: 'user',
        content: [
          { type: 'text', text: NSFW_PROMPT },
          {
            type: 'image_url',
            image_url: { url: `data:${mime || 'image/jpeg'};base64,${b64}` },
          },
        ],
      },
    ],
  };
}

/// Parse jawaban model → skor. Toleran: cari JSON di dalam teks.
export function parseModelReply(text: string): number | null {
  if (!text) return null;
  const direct = tryJson(text);
  const fromDirect = extractScore(direct);
  if (fromDirect != null) return fromDirect;
  const m = text.match(/\{[\s\S]*?\}/);
  if (m) {
    const parsed = tryJson(m[0]);
    const s = extractScore(parsed);
    if (s != null) return s;
  }
  return null;
}

function tryJson(s: string): unknown {
  try {
    return JSON.parse(s);
  } catch (_) {
    return null;
  }
}
