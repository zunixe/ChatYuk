import { assertEquals } from 'https://deno.land/std/assert/mod.ts';
import {
  buildVisionBody,
  extractScore,
  parseModelReply,
  verdictForScore,
} from './content_safety.ts';

// Keputusan moderasi media (permintaan user 2026-10-26):
//  >= 0.75 reject · >= 0.50 review (menunggu moderator) · sisanya allow.

Deno.test('verdictForScore: ambang default 0.50 / 0.75', () => {
  assertEquals(verdictForScore(0.0, 0.75, 0.5), 'allow');
  assertEquals(verdictForScore(0.49, 0.75, 0.5), 'allow');
  assertEquals(verdictForScore(0.5, 0.75, 0.5), 'review');
  assertEquals(verdictForScore(0.74, 0.75, 0.5), 'review');
  assertEquals(verdictForScore(0.75, 0.75, 0.5), 'reject');
  assertEquals(verdictForScore(1, 0.75, 0.5), 'reject');
});

Deno.test('verdictForScore: nilai aneh di-clamp / aman', () => {
  assertEquals(verdictForScore(Number.NaN, 0.75, 0.5), 'allow');
  assertEquals(verdictForScore(-5, 0.75, 0.5), 'allow');
  assertEquals(verdictForScore(9, 0.75, 0.5), 'reject');
});

Deno.test('extractScore: bentuk skor umum', () => {
  assertEquals(extractScore({ score: 0.8 }), 0.8);
  assertEquals(extractScore({ nsfw_score: '0.6' }), 0.6);
  assertEquals(extractScore({ nsfw: true }), 1);
  assertEquals(extractScore({ nsfw: false }), 0);
  assertEquals(extractScore(0.42), 0.42);
  assertEquals(extractScore({}), null);
});

Deno.test('extractScore: daftar kategori gaya nsfwjs (ambil maks porn/hentai/sexy)', () => {
  const preds = [
    { className: 'Neutral', probability: 0.05 },
    { className: 'Porn', probability: 0.82 },
    { className: 'Hentai', probability: 0.4 },
    { className: 'Sexy', probability: 0.3 },
    { className: 'Drawing', probability: 0.01 },
  ];
  assertEquals(extractScore(preds), 0.82);
  assertEquals(
    extractScore([{ className: 'Neutral', probability: 0.99 }]),
    null,
  );
});

Deno.test('parseModelReply: JSON langsung & JSON di dalam teks', () => {
  assertEquals(parseModelReply('{"score":0.9,"label":"explicit"}'), 0.9);
  assertEquals(
    parseModelReply('Hasil: {"score": 0.55} semoga membantu'),
    0.55,
  );
  assertEquals(parseModelReply('tidak bisa dinilai'), null);
  assertEquals(parseModelReply(''), null);
});

Deno.test('buildVisionBody: menyertakan prompt + image_url data URI', () => {
  const b = buildVisionBody('m', 'image/png', 'AAA');
  const content = b.messages[0].content as unknown[];
  assertEquals(b.model, 'm');
  assertEquals(b.temperature, 0);
  assertEquals(content.length, 2);
  const img = content[1] as { type: string; image_url: { url: string } };
  assertEquals(img.type, 'image_url');
  assertEquals(img.image_url.url, 'data:image/png;base64,AAA');
});
