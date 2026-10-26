// ChatYuk: klasifikasi konten NSFW untuk MEDIA di room publik.
//
// Kenapa di server: klien tidak boleh jadi penentu (bisa dimodifikasi), dan
// model/ambang harus bisa diubah tanpa rilis.
//
// Auth: verify_jwt Supabase (default gateway) — hanya user login.
// Input : POST { storage_path, mime? }  (path di bucket `chat-photos`)
// Output: { ok, verdict: 'allow'|'review'|'reject', score, thresholds }
//
// Alur keputusan (ambang dari app_settings):
//   score >= nsfw_reject_threshold (0.75) → reject (klien hapus file)
//   score >= nsfw_review_threshold (0.50) → review (pesan `pending`, moderator)
//   selainnya                             → allow
//
// Sumber klasifikasi: provider vision aktif di `ai_provider_config`
// (OpenAI-compatible /chat/completions). Bila tidak ada provider / gagal →
// { ok:false, verdict:'allow' } (fail-open) supaya user sah tidak terblokir
// karena gangguan layanan; trust gate + laporan tetap berjalan.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import {
  buildVisionBody,
  parseModelReply,
  verdictForScore,
} from '../_shared/content_safety.ts';

const BUCKET = 'chat-photos';
const MODEL_TIMEOUT_MS = 12000;

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

function mimeFromPath(path: string): string {
  const p = path.toLowerCase();
  if (p.endsWith('.png')) return 'image/png';
  if (p.endsWith('.webp')) return 'image/webp';
  if (p.endsWith('.gif')) return 'image/gif';
  return 'image/jpeg';
}

function toBase64(bytes: Uint8Array): string {
  let bin = '';
  const chunk = 0x8000;
  for (let i = 0; i < bytes.length; i += chunk) {
    bin += String.fromCharCode(...bytes.subarray(i, i + chunk));
  }
  return btoa(bin);
}

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') return json({ error: 'method' }, 405);

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch (_) {
    return json({ error: 'bad_json' }, 400);
  }

  const storagePath = String(body.storage_path ?? '').trim();
  if (!storagePath) return json({ error: 'storage_path_required' }, 400);

  const admin = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    { auth: { persistSession: false } },
  );

  // Ambang dari app_settings (bisa diubah admin tanpa rilis).
  let rejectThreshold = 0.75;
  let reviewThreshold = 0.50;
  try {
    const { data } = await admin
      .from('app_settings')
      .select('nsfw_reject_threshold, nsfw_review_threshold')
      .eq('id', 'global')
      .maybeSingle();
    if (data) {
      const r = Number(data.nsfw_reject_threshold);
      const v = Number(data.nsfw_review_threshold);
      if (Number.isFinite(r)) rejectThreshold = r;
      if (Number.isFinite(v)) reviewThreshold = v;
    }
  } catch (_) {}

  // Unduh media (service role — RLS storage tidak menghalangi).
  let bytes: Uint8Array | null = null;
  try {
    const { data, error } = await admin.storage.from(BUCKET).download(storagePath);
    if (error || !data) {
      return json({ ok: false, error: 'download_failed', verdict: 'allow' });
    }
    bytes = new Uint8Array(await data.arrayBuffer());
  } catch (_) {
    return json({ ok: false, error: 'download_failed', verdict: 'allow' });
  }
  if (!bytes || bytes.length === 0) {
    return json({ ok: false, error: 'empty', verdict: 'allow' });
  }
  // Batas aman: klasifikasi gambar > 6 MB boros; poster video jauh lebih kecil.
  if (bytes.length > 6 * 1024 * 1024) {
    return json({ ok: true, verdict: 'review', score: null,
      reason: 'too_large', thresholds: { rejectThreshold, reviewThreshold } });
  }

  // Provider vision aktif.
  let apiBase = '';
  let apiKey = '';
  let model = '';
  try {
    const { data } = await admin
      .from('ai_provider_config')
      .select('api_base, api_key, default_model, is_active')
      .eq('is_active', true)
      .limit(1)
      .maybeSingle();
    if (data) {
      apiBase = String(data.api_base ?? '');
      apiKey = String(data.api_key ?? '');
      model = String(data.default_model ?? '');
    }
  } catch (_) {}

  if (!apiBase || !apiKey || !model) {
    return json({ ok: false, error: 'no_provider', verdict: 'allow',
      thresholds: { rejectThreshold, reviewThreshold } });
  }

  const mime = String(body.mime ?? '') || mimeFromPath(storagePath);
  let score: number | null = null;
  try {
    const ctrl = new AbortController();
    const t = setTimeout(() => ctrl.abort(), MODEL_TIMEOUT_MS);
    const res = await fetch(`${apiBase.replace(/\/+$/, '')}/chat/completions`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${apiKey}`,
      },
      body: JSON.stringify(buildVisionBody(model, mime, toBase64(bytes))),
      signal: ctrl.signal,
    });
    clearTimeout(t);
    if (res.ok) {
      const j = await res.json();
      const text = j?.choices?.[0]?.message?.content ?? '';
      score = parseModelReply(typeof text === 'string' ? text : '');
    }
  } catch (_) {
    score = null;
  }

  if (score == null) {
    // Model tidak memberi skor → jangan blokir; catat untuk audit.
    try {
      await admin.from('admin_alerts').insert({
        kind: 'nsfw_unscored',
        severity: 'low',
        message: 'Klasifikasi NSFW gagal (fail-open)',
        detail: { storage_path: storagePath },
      });
    } catch (_) {}
    return json({ ok: false, error: 'no_score', verdict: 'allow',
      thresholds: { rejectThreshold, reviewThreshold } });
  }

  const verdict = verdictForScore(score, rejectThreshold, reviewThreshold);
  if (verdict !== 'allow') {
    try {
      await admin.from('admin_alerts').insert({
        kind: 'nsfw_flag',
        severity: verdict === 'reject' ? 'high' : 'medium',
        message: `Media terindikasi NSFW (${verdict}, score=${score.toFixed(2)})`,
        detail: { storage_path: storagePath, score, verdict },
      });
    } catch (_) {}
  }

  return json({
    ok: true,
    verdict,
    score,
    thresholds: { rejectThreshold, reviewThreshold },
  });
});
