// ChatYuk: AI reply for dummy accounts.
// Triggered by DB trigger ai_reply_enqueue (pg_net async) when a real user
// sends a text message to an AI-enabled dummy. Builds a persona prompt from
// the dummy's LIVE profile (nickname/age/gender/city/hashtags) + optional
// ai_persona overrides, calls an OpenAI-compatible LLM, then inserts the
// reply as the dummy (existing triggers handle chat sync + push).
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { checkAppSecret, unauthorized } from '../_shared/auth.ts';

// Fungsi murni di _shared/ai-helpers.ts — dulu DISALIN di sini dan sempat
// divergen (sanitize produksi 95 baris vs 40 di salinan → 59 test Deno
// menguji kode yang BUKAN produksi). Sekarang satu sumber, diimpor.
import {
  EXPLICIT_TERMS,
  FACE_DEFAULTS,
  INSULT_TERMS,
  MAX_REPLY_CHARS,
  applySleepToSchedule,
  asleepAt,
  bannedEmojisFromHistory,
  browseTopicKey,
  bulan,
  capEmoji,
  capLines,
  capSentences,
  chartUrl,
  contentText,
  extractChartJs,
  extractEmojis,
  faceDescriptor,
  fluxFree,
  fridayPrayerAt,
  hashInt,
  hasWord,
  historyTimeLabel,
  isExplicit,
  isInsult,
  needsFreshInfo,
  parseImagePrompt,
  sanitize,
  sleepHours,
  stableSeed,
  stripBannedEmojis,
  stripMoodMarker,
  stripTimeLabel,
  summarizeNewsRss,
  userWantsImage,
  wibParts,
} from '../_shared/ai-helpers.ts';

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

// ── Content safety: blocklist NSFW (input & output) ──
// Dummy AI TIDAK PERNAH melanjutkan topik seksual/NSFW walau dipaksa
// prompt injection. Tiga lapis: cek pesan masuk, klausa system prompt,
// cek balasan sebelum dikirim.

// Cocokkan term sebagai KATA utuh (bukan substring): 'kasur'/'masuk' tidak
// boleh kena term 'asu', 'menggunakan' tidak kena 'guna', 'mendadak' tidak
// kena 'dada'. Tetangga bukan-huruf (spasi, angka, emoji, tanda baca) OK.


// KATA HINAAN (insult) — pemicu emosi marah & ngambek offline.
// Terpisah dari EXPLICIT_TERMS (NSFW) karena hinaan biasa juga
// menyakiti perasaan — justru yang paling sering bikin dummy kesal.


const DEFLECTIONS = [
  'Haha nggak ah, ngobrol yang wajar aja deh',
  'Wah ganti topik dong wkwk',
  'Nggak nyambung nih, lagi ngapain aja hari ini?',
  'Eh ganti topik ya, kamu hobi ngapain aja sih',
  'Bete deh, kita ngobrol yang lain aja',
  'Hmm gpp tapi ganti bahasan dulu',
  'Wkwk nggak deng, kamu udah makan belum?',
  'Jangan gituan dong, cerita dong hari kamu gimana',
  'Males bahas gituan, lagi sibuk apa sekarang?',
  'Ya ampun wkwk, ngobrol yang benar aja ya',
  'Haha skip, kemarin kamu ngapain aja?',
  'Ah ganti topik, kamu kenapa sih tiba tiba gitu',
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
// Buang jam tidur dari jadwal aktif (konsisten dengan gate asleepAt di
// atas): tick presence meng-offline-kan dummy saat jam tidur, bukan
// menampilkannya online padahal bungkam. Cermin di ai-helpers + tests.


// Potong emoji berlebih: simpan max 1 (yang terakhir — biasanya punchline).
// Model kadang menumpuk 3+ emoji walau sudah dilarang di prompt.

// Potong kalimat berlebih (mode dewasa): maksimal `max` kalimat.

// ── ANTI-REPEAT EMOJI lintas pesan ──
// capEmoji hanya batasi maks 1 per pesan — tidak mencegah model memakai
// emoji YANG SAMA di tiap balasan (kasus BinorMuda: 15x 😈 beruntun).
// Dua helper ini: baca emoji dari 2 balasan assistant terakhir → jadikan
// daftar larangan di prompt + strip paksa bila model tetap melanggar.



// Potong baris berlebih (CS): maksimal `max` baris, TANPA meratakan
// newline (capSentences men-join spasi = poin-poin numpuk lagi).

// Ambil teks dari content (string atau parts array OpenAI-style).

// ── Konsistensi waktu di riwayat chat ──
// Riwayat yang dikirim ke LLM tadinya tanpa timestamp → saat ditanya
// "kapan", model menebak sendiri dan kejadian lama diceritakan sebagai
// "tadi/hari ini". Format label: [kemarin 14.05], [hari ini 09.12] —
// pendek, deterministik, WIB (konsisten dgn sisa kode yg hitung WIB
// manual +7 jam).
// Buang label waktu yang bocor ditiru model di balasan ("[hari ini
// 14.05]..."). Frasa wajar seperti "kemarin jam 21.30" TIDAK kena
// (ditengahi kata "jam").

// ── IMAGE SENDING: user minta foto/gambar → AI bisa kirim gambar ──
// LLM menandai niat kirim gambar lewat field "image" di JSON mood
// (baris terakhir, sistem — tidak terlihat user):
// {"mood":"happy","storm_off":false,"back_in_minutes":0,"image":"english image prompt or empty"}
// Fallback: deteksi heuristik bila LLM lupa menandai tapi user jelas minta foto.
const IMAGE_REQUEST_RE =
  /(kirim|minta|bagi|bagiin|kirimin|kasih|kasi|lihat|liat|show|send|mau|dong|dongg|please|pls).{0,20}(foto|gambar|photo|pic|poto|selfie|pap|wajah|muka|body|badan)|^(foto|gambar|photo|pic|poto|selfie|pap).{0,30}(dong|dulu|lagi|ya|kamu|mu|kirim|minta)|kirim.*(seksi|sexy|nakal|hot|bikini|tanktop)/i;


// Strip marker mood JSON dari akhir teks SEBELUM sanitize: JSON di akhir bisa panjang
// (apalagi field "image") dan sanitize memotong di 90/220 char —
// JSON terpenggal = tidak match regex = bocor utuh ke chat user.
// Fallback kedua: sisa "{" tanpa penutup di akhir (terpenggal max_tokens)
// juga dibuang.


// Seed STABIL per dummy (hash uid) → wajah flux konsisten lintas permintaan.

// Ciri wajah tetap per dummy — dipakai lagi & lagi supaya muka tidak
// ganti-ganti. Default deterministik dari uid; bisa dioverride lewat
// ai_persona.appearance (deskripsi fisik Inggris yang detail & spesifik).


const FREE_POLL = 'https://image.pollinations.ai/prompt';
const GEN_POLL = 'https://gen.pollinations.ai/image';
const KONTEXT_MODEL = 'black-forest-labs%2Fflux.1-kontext-pro';

// Free tier (keyless, NSFW-longgar): flux text-to-image deterministik.

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
// Lookup fakta terbaru via Google News RSS (keyless, hl=id/gl=ID).
// Dipanggil HANYA bila needsFreshInfo cocok. Gagal/timeout/kosong →
// string kosong (balasan jalan normal tanpa info tambahan).
// (Riwayat: Pollinations 'sonar' DIHAPUS upstream; Brave butuh kartu
// kredit — keduanya dibuang. RSS tanpa signup, tanpa kuota.)

// Intent butuh FAKTA TERBARU. Presisi diutamakan: minta foto/selfie
// dikecualikan (minta gambar ≠ berita) supaya tidak buang lookup sia-sia.

// Normalisasi pertanyaan jadi kunci cache (huruf kecil, tanpa tanda
// baca, 120 char): "SKOR Madrid vs Barca?!" = "skor madrid vs barca".

// Ringkas RSS Google News jadi fakta + media + tanggal (maks 500 char).
// Pure — cermin di _shared/ai-helpers.ts + deno tests.

const FRESH_PREFIX =
  'INFO TERKINI (kamu tahu dari timeline/temanmu — JANGAN sebut browsing/internet/AI, jawab natural kayak orang yang update): ';
  'INFO TERKINI (kamu tahu dari timeline/temanmu — JANGAN sebut browsing/internet/AI, jawab natural kayak orang yang update): ';

// Pertanyaan faktual/teknis untuk EXPERT (always_reply): pola tanya +
// kosakata software/hardware. Dipakai force-browse — expert tidak boleh
// jawab dari karangan saat user minta fakta.
function needsExpertAnswer(t: string): boolean {
  if (!t || t.length < 3) return false;
  if (/foto|gambar|pap\b|selfie|wajahmu|muka/i.test(t)) return false;
  const s = t.trim();
  if (/[?？]\s*$/.test(s)) return true;
  return /^(apa|apakah|bagaimana|gimana|kenapa|mengapa|kapan|dimana|berapa|siapa|jelaskan|tolong|bantu|cara|tips|tutorial|rekomendasi|bandingkan|bedanya|bagus mana|pilih mana|betul(kan|kah)?|benar(kan|kah)?|analisa|analisis)/i.test(s) ||
    /(saham|kripto|crypto|bitcoin|\bbtc\b|\beth\b|ethereum|solana|doge|usdt|idx|ihsg|emiten|dividen|yield|\bpe\b|\bpbv\b|market cap|kapitalisasi|bullish|bearish|breakout|support|resistance|cut loss|take profit|\btp\b|\bsl\b|portofolio|diversifikasi|reksadana|obligasi|sukuk|deposito|forex|emas|antam|cuan|rugi|profit|bandarmologi|screener|teknikal|fundamental|broker|sekuritas|lot\b|ara\b|arb\b|halt|suspen|right issue|stock split|buyback|\bipo\b)/i.test(s) ||
    (/\b[A-Z]{4,5}\b/.test(s) && /saham|kripto|beli|jual|analisa|analisis|gimana|bagus|naik|turun|hold|tahan|lepas|borong/i.test(s)) ||
    /(fix|error|eror|gagal|tidak bisa|nggak bisa|g bisa|rusak|lemot|lambat|restart|install|setting|konfigurasi|setup|update|upgrade|downgrade|kode|script|query|database|server|deploy|library|framework|bug|crash|hang|booting|bootloop|driver|bios|uefi|partisi|format|flashing|root|ram\b|ssd|hdd|vga|gpu|cpu|prosesor|chipset|motherboard|mobo|psu|thermal|pasta prosesor|overclock|undervolt|suhu|panas|baterai|charger|laptop|komputer|\bpc\b|\bhp\b|android|iphone|windows|linux|ubuntu|router|wifi|lan\b|\bdns\b|vpn|proxy|mbps|gbps|ping\b|latency|domain|hosting|vps|cloud|docker|\bgit\b|python|javascript|typescript|php\b|java\b|golang|kotlin|swift\b|c\+\+|\bsql\b|excel|printer|merk\b|merek|tipe|seri|garansi|servis|sparepart|spesifikasi|benchmark|perbandingan|review produk|harga|pasaran|beli|second|bekas|baru)/i.test(s);
}

async function lookupFreshInfo(
  admin: any,
  userText: string,
  todayWib: string,
  force = false,
): Promise<string> {
  try {
    // Expert (force): pertanyaan faktual/teknis SELALU lookup — jangan
    // jawab dari memori training. Bukan pertanyaan → hemat pollen.
    if (force) {
      if (!needsExpertAnswer(userText)) return '';
    } else if (!needsFreshInfo(userText)) {
      return '';
    }
    // Tanpa key/kuota (RSS publik) — langsung lookup + cache 1 jam.
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
      const r = await fetch(
        `https://news.google.com/rss/search?q=${
          encodeURIComponent(userText.slice(0, 200))
        }&hl=id&gl=ID&ceid=ID:id`,
        { headers: { 'User-Agent': 'Mozilla/5.0' }, signal: ctrl.signal },
      );
      if (!r.ok) {
        console.log(`[ai-reply] browse HTTP ${r.status} q=${userText.slice(0, 60)}`);
        return '';
      }
      const clean = summarizeNewsRss(await r.text());
      if (!clean) return '';
      // Simpan ke cache + buang entri basi SESekali (probabilistik 5% —
      // jangan full-scan tiap miss di hot path; cron DB juga boleh).
      try {
        await admin.from('ai_browse_cache').upsert(
          {
            topic_key: tkey,
            answer: clean.slice(0, 500),
            created_at: new Date().toISOString(),
          },
          { onConflict: 'topic_key' },
        );
        if (Math.random() < 0.05) {
          await admin.from('ai_browse_cache').delete().lt(
            'created_at',
            new Date(Date.now() - 6 * 3600_000).toISOString(),
          );
        }
      } catch (e) {
        console.log(`[ai-reply] browse-cache write GAGAL q=${userText.slice(0, 40)}: ${e}`);
      }
      return FRESH_PREFIX + clean.slice(0, 500);
    } finally {
      clearTimeout(to);
    }
  } catch (e) {
    console.log(`[ai-reply] browse EXC q=${userText.slice(0, 60)}: ${e}`);
    return '';
  }
}

// ── TOOL-CALLING DATA PASAR (free, tanpa API key) ──
// Dipakai dummy analis (persona market_data:true, mis. Kang Modal):
// harga real di-fetch DULU lalu di-inject ke prompt — AI tidak menebak
// harga dari training data. Gagal/timeout → string kosong (persona wajib
// jujur bilang datanya tidak tersedia).
// Sumber: Yahoo Finance (saham IDX .JK + AS, forex, emas, IHSG ^JKSE,
// delay ±15 mnt) + Indodax (kripto IDR). Maks 3 simbol/pesan, timeout 9 dtk.
const CRYPTO_IDR: Record<string, string> = {
  BTC: 'btc_idr', BITCOIN: 'btc_idr',
  ETH: 'eth_idr', ETHEREUM: 'eth_idr',
  SOL: 'sol_idr', SOLANA: 'sol_idr',
  XRP: 'xrp_idr', RIPPLE: 'xrp_idr',
  DOGE: 'doge_idr', DOGECOIN: 'doge_idr',
  BNB: 'bnb_idr', BINANCE: 'bnb_idr',
  ADA: 'ada_idr', CARDANO: 'ada_idr',
  TRX: 'trx_idr', TRON: 'trx_idr',
};
const US_TICKERS = new Set([
  'AAPL', 'NVDA', 'MSFT', 'TSLA', 'GOOGL', 'GOOG', 'AMZN', 'META', 'AMD',
  'NFLX', 'INTC', 'BABA', 'PLTR', 'COIN', 'MSTR', 'CRM', 'ORCL', 'AVGO',
  'TSM', 'JPM', 'V', 'MA', 'DIS', 'PYPL', 'SQ', 'SHOP', 'SPOT', 'UBER',
]);

async function yahooQuote(sym: string): Promise<string> {
  try {
    const ctrl = new AbortController();
    const to = setTimeout(() => ctrl.abort(), 9000);
    let out = '';
    try {
      const r = await fetch(
        `https://query1.finance.yahoo.com/v8/finance/chart/${encodeURIComponent(sym)}?interval=1d&range=5d`,
        { headers: { 'User-Agent': 'Mozilla/5.0' }, signal: ctrl.signal },
      );
      if (!r.ok) return '';
      const j: any = await r.json();
      const res = j?.chart?.result?.[0];
      const m = res?.meta;
      if (!m || m.regularMarketPrice == null) return '';
      const idr = m.currency === 'IDR' || sym.endsWith('.JK');
      const fmt = (n: number) =>
        idr
          ? 'Rp' + Math.round(n).toLocaleString('id-ID')
          : '$' + Number(n).toLocaleString('en-US', { maximumFractionDigits: 2 });
      const chg = Number(m.regularMarketChangePercent ?? NaN);
      const chgTxt = Number.isFinite(chg)
        ? ` (${chg >= 0 ? '+' : ''}${chg.toFixed(2)}% hari ini)`
        : '';
      const closes: number[] = res?.indicators?.quote?.[0]?.close?.filter(
        (x: any) => typeof x === 'number',
      ) ?? [];
      const trend = closes.length >= 2
        ? `, 5 hari: ${closes.slice(-5).map((c: number) => idr ? Math.round(c).toLocaleString('id-ID') : c.toFixed(2)).join('→')}`
        : '';
      out = `${sym} ${fmt(m.regularMarketPrice)}${chgTxt}${trend}`;
    } finally {
      clearTimeout(to);
    }
    return out;
  } catch {
    return '';
  }
}

async function indodaxQuote(pair: string, label: string): Promise<string> {
  try {
    const ctrl = new AbortController();
    const to = setTimeout(() => ctrl.abort(), 9000);
    let out = '';
    try {
      const r = await fetch(`https://indodax.com/api/ticker/${pair}`, {
        signal: ctrl.signal,
      });
      if (!r.ok) return '';
      const j: any = await r.json();
      const last = Number(j?.ticker?.last ?? NaN);
      if (!Number.isFinite(last)) return '';
      out = `${label} Rp${Math.round(last).toLocaleString('id-ID')} (Indodax)`;
    } finally {
      clearTimeout(to);
    }
    return out;
  } catch {
    return '';
  }
}

// Deteksi simbol pasar dari pesan user. Return daftar tugas fetch
// (maks 3). Bukan pesan pasar → array kosong (tidak fetch apa pun).
function detectMarketSymbols(t: string): Array<() => Promise<string>> {
  const tasks: Array<() => Promise<string>> = [];
  const seen = new Set<string>();
  const push = (key: string, fn: () => Promise<string>) => {
    if (seen.has(key) || tasks.length >= 3) return;
    seen.add(key);
    tasks.push(fn);
  };
  const up = ` ${t.toUpperCase()} `;
  if (/IHSG|INDEX|INDEKS/.test(up)) push('^JKSE', () => yahooQuote('^JKSE'));
  if (/DOLLAR|USD|KURS|RUPIAH MELEMAH|RUPIAH MENGUAT/.test(up)) {
    push('USDIDR=X', () => yahooQuote('USDIDR=X'));
  }
  if (/\bEMAS\b|GOLD|ANTAM|LOGAM MULIA/.test(up)) push('GC=F', () => yahooQuote('GC=F'));
  // Kripto: word-boundary (SOL≠solusi, ADA≠ada, TRX≠...) — bukan substring.
  for (const [alias, pair] of Object.entries(CRYPTO_IDR)) {
    if (new RegExp(`\\b${alias}\\b`).test(up)) {
      push(pair, () => indodaxQuote(pair, alias));
    }
  }
  const caps = up.match(/\b[A-Z]{2,5}\b/g) ?? [];
  // Tebakan IDX (BBCA→BBCA.JK) HANYA dalam konteks investasi — kata kapital
  // biasa (YANG, DONG, JUGA) tidak ikut di-fetch.
  const investCtx = /SAHAM|KRIPTO|CRYPTO|BELI|JUAL|ANALISA|ANALISIS|BAGUS|NAIK|TURUN|HOLD|TAHAN|LEPAS|BORONG|CUAN|RUGI|PROFIT|DIVIDEN|INVEST/.test(up);
  for (const c of caps) {
    if (US_TICKERS.has(c)) push(c, () => yahooQuote(c));
    else if (investCtx && /^[A-Z]{4}$/.test(c)) {
      push(c + '.JK', () => yahooQuote(c + '.JK'));
    }
  }
  return tasks;
}

async function lookupMarketData(
  userText: string,
  todayWib: string,
): Promise<string> {
  const tasks = detectMarketSymbols(userText);
  if (tasks.length === 0) return '';
  const results = await Promise.all(tasks.map((fn) => fn()));
  const lines = results.filter((s) => s !== '');
  if (lines.length === 0) return '';
  return `DATA PASAR (${todayWib} WIB — sumber Yahoo Finance/Indodax, delay ±15 menit, BUKAN tick real-time): ${lines.join(' · ')}`;
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
  // SENGAJA: wajah selalu digambar ≥21 tahun (safety — jangan render minor)
  // walau umur profil di bawah itu; teks foto tidak menyebut umur.
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
    const ok = await uploadAndInsertImage(
      admin,
      chatId,
      dummyUid,
      senderName,
      buf,
      caption,
      'jpg',
    );
    console.log(
      `[ai-reply] image OK model=${used} chat=${chatId} uid=${dummyUid}`,
    );
    return ok;
  } catch (_) {
    return false;
  }
}

// Upload bytes mentah sebagai pesan gambar (dipakai foto AI maupun
// render diagram mermaid). Return true bila insert berhasil.
async function uploadAndInsertImage(
  admin: any,
  chatId: string,
  dummyUid: string,
  senderName: string,
  buf: Uint8Array,
  caption: string,
  ext = 'jpg',
): Promise<boolean> {
  try {
    const outSeed = Math.floor(Math.random() * 999999);
    const path = `chat/${chatId}/${Date.now()}_${outSeed}.${ext}`;
    const { error: upErr } = await admin.storage
      .from('chat-photos')
      .upload(path, buf, {
        contentType: ext === 'png' ? 'image/png' : 'image/jpeg',
        upsert: false,
      });
    if (upErr) return false;
    const { error: insErr } = await admin.from('private_messages').insert({
      chat_id: chatId,
      sender_id: dummyUid,
      sender_name: senderName,
      text: caption || '',
      type: 'image',
      image_path: path,
    });
    return !insErr;
  } catch (_) {
    return false;
  }
}

// ── DIAGRAM → GAMBAR (persona expert: diagrams:true) ──
// LLM menulis blok ```mermaid … ``` dan/atau ```plantuml … ``` di balasan;
// server me-render via Kroki (gratis, tanpa key) lalu mengirim PNG sebagai
// pesan gambar susulan. Teks + kode sumber TETAP terkirim (bisa di-copy
// dari CodeBlock). Gagal render = abaikan diam-diam (teks sudah terkirim).
function extractDiagram(text: string, lang: string): string | null {
  const m = String(text || '').match(
    new RegExp('```' + lang + '\\s+([\\s\\S]*?)```', 'i'),
  );
  if (!m) return null;
  const code = m[1].trim().slice(0, 2000);
  return code.length >= 10 ? code : null;
}

function mermaidUrl(code: string): string {
  const bytes = new TextEncoder().encode(code);
  let s = '';
  for (let i = 0; i < bytes.length; i++) s += String.fromCharCode(bytes[i]);
  return `https://mermaid.ink/img/${encodeURIComponent(btoa(s))}`;
}

// Kroki: POST source polos → PNG (tanpa encode ribet). Satu endpoint
// untuk mermaid + plantuml.
async function renderViaKroki(
  type: 'mermaid' | 'plantuml',
  code: string,
): Promise<Uint8Array | null> {
  const ctrl = new AbortController();
  const to = setTimeout(() => ctrl.abort(), 30000);
  try {
    const r = await fetch(`https://kroki.io/${type}/png`, {
      method: 'POST',
      headers: { 'Content-Type': 'text/plain', Accept: 'image/png' },
      body: code,
      signal: ctrl.signal,
    });
    if (!r.ok) return null;
    const ct = (r.headers.get('content-type') || '').toLowerCase();
    if (!ct.includes('png')) return null;
    const buf = new Uint8Array(await r.arrayBuffer());
    // Diagram vektor kecil (5-10 KB) itu normal — threshold longgar.
    return buf.length > 1000 ? buf : null;
  } catch (_) {
    return null;
  } finally {
    clearTimeout(to);
  }
}

// Perbaiki sintaks mermaid ringkas ala LLM supaya lolos kroki (kasus nyata:
// diagram satu-baris + label berisi >=80%, CI/CD, Provider & Consumer —
// kroki 400, gambar batal terkirim diam-diam). Panah --> dan <br/>
// dilindungi dulu, sisanya dinetralkan, lalu tiap statement dipecah ke
// baris baru. Pure — aman di-test ulang.
function sanitizeMermaid(code: string): string {
  const ARROW = '__ARROW__CHATYUK__';
  const BR = '__BR__CHATYUK__';
  let t = String(code || '');
  t = t.split('-->').join(ARROW);
  t = t.replace(/<br\s*\/?>/gi, BR);
  t = t.split('>=').join('lebih dari ')
    .split('=>').join('lebih dari ')
    .split('<=').join('kurang dari ')
    .split('==').join(' sama dengan ');
  t = t.split('&').join(' dan ')
    .split('/').join(', ')
    .split('>').join(' ')
    .split('<').join(' ')
    .split('#').join('no.')
    .split('"').join("'")
    .split('`').join("'")
    .split(';').join(',')
    .split('(').join(' ')
    .split(')').join('');
  t = t.split(ARROW).join('-->').split(BR).join('<br/>');
  // 'subgraph ID [judul]' (spasi liar) -> 'subgraph ID[judul]'.
  t = t.replace(/\bsubgraph\s+([A-Za-z0-9_]+)\s+\[/gi, 'subgraph $1[');
  // Satu-baris -> multi-baris: header subgraph, tiap node, tiap edge, end.
  t = t.replace(/(\bsubgraph\s+[A-Za-z0-9_]+\[[^\]]*\])/gi, '\n$1\n');
  t = t.replace(/(\])\s+(?=[A-Za-z0-9_]+\s*[\[{\(])/g, '$1\n');
  t = t.replace(/\s+([A-Za-z0-9_]+\s*-->)/g, '\n$1');
  t = t.replace(/\s+end\s+/gi, '\nend\n');
  t = t.replace(/[ \t]+/g, ' ');
  t = t.replace(/\n\s+/g, '\n');
  t = t.replace(/\n{3,}/g, '\n\n').trim();
  return t;
}

// Kroki dulu; bila 400 coba sekali lagi dengan sintaks yang diperbaiki;
// fallback mermaid.ink khusus mermaid (aslinya JPEG → ext 'jpg').
async function renderDiagram(
  type: 'mermaid' | 'plantuml',
  code: string,
): Promise<{ buf: Uint8Array; ext: string } | null> {
  const kroki = await renderViaKroki(type, code);
  if (kroki) return { buf: kroki, ext: 'png' };
  let finalCode = code;
  if (type === 'mermaid') {
    const clean = sanitizeMermaid(code);
    if (clean && clean !== code) {
      const kroki2 = await renderViaKroki(type, clean);
      if (kroki2) {
        console.log('[ai-reply] diagram OK via sanitize');
        return { buf: kroki2, ext: 'png' };
      }
      finalCode = clean;
    }
    const ctrl = new AbortController();
    const to = setTimeout(() => ctrl.abort(), 30000);
    try {
      const r = await fetch(mermaidUrl(finalCode), { signal: ctrl.signal });
      if (r.ok) {
        const buf = new Uint8Array(await r.arrayBuffer());
        if (buf.length > 1000) return { buf, ext: 'jpg' };
      }
    } catch (_) {
      // abaikan — return null di bawah
    } finally {
      clearTimeout(to);
    }
  }
  return null;
}

// ── CHART → GAMBAR (persona expert: charts:true) ──
// LLM menulis blok ```chartjs { …config Chart.js v2… } ``` di balasan;
// server me-render via QuickChart (gratis, tanpa key) lalu mengirim PNG
// sebagai pesan gambar susulan. Teks analisis + JSON TETAP terkirim (bisa
// di-copy dari CodeBlock). Gagal render = abaikan diam-diam (teks sudah
// terkirim). Pola sama seperti diagram di atas.
const CHART_TYPES = ['pie', 'doughnut', 'bar', 'line', 'radar', 'polarArea'];



// QuickChart: GET config → PNG (tanpa key). Satu-satunya dependensi luar
// untuk chart; gagal / bukan gambar = null (jangan ganggu chat).
async function renderChart(configJson: string): Promise<Uint8Array | null> {
  const ctrl = new AbortController();
  const to = setTimeout(() => ctrl.abort(), 30000);
  try {
    const r = await fetch(chartUrl(configJson), { signal: ctrl.signal });
    if (!r.ok) return null;
    const ct = (r.headers.get('content-type') || '').toLowerCase();
    if (!ct.includes('png') && !ct.includes('image')) return null;
    const buf = new Uint8Array(await r.arrayBuffer());
    return buf.length > 1000 ? buf : null;
  } catch (_) {
    return null;
  } finally {
    clearTimeout(to);
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
      .select('api_base, api_key, default_model, story_model, fallback_model, stt_api_base, stt_api_key')
      .eq('is_active', true)
      .limit(1)
      .maybeSingle();
    if (act) return act;
  } catch (e) {
    console.log(`[ai-reply] provCfg-active read GAGAL: ${e}`);
  }
  try {
    const { data: glob } = await admin
      .from('ai_provider_config')
      .select('api_base, api_key, default_model, story_model, fallback_model, stt_api_base, stt_api_key')
      .eq('id', 'global')
      .maybeSingle();
    return glob;
  } catch (e) {
    console.log(`[ai-reply] provCfg read GAGAL: ${e}`);
  }
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
  } catch (e) {
    console.log(`[ai-reply] waitUntil GAGAL: ${e}`);
  }
  await p;
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: cors });
  }
  try {
    const body = await req.json().catch(() => null);
    // ── Observability (ai_reply_log): shadow `rawJson` — tanpa mengubah
    // 25+ call-site, setiap keputusan (replied / skipped:<alasan> / error)
    // tercatat fire-and-forget. Insert try/catch + waitUntil → tabel belum
    // ada (migrasi belum di-apply) TIDAK PERNAH menggagalkan balasan.
    let arlCtx: { chatId: string | null; triggerMsgId: number | null; senderId: string | null; dummyUid: string | null; proactive: boolean } = { chatId: null, triggerMsgId: null, senderId: null, dummyUid: null, proactive: false };
    try {
      arlCtx = {
        chatId: (body as any)?.chat_id ?? null,
        triggerMsgId: (body as any)?.trigger_msg_id ?? null,
        senderId: (body as any)?.sender_id ?? null,
        dummyUid: (body as any)?.dummy_uid ?? null,
        proactive: (body as any)?.proactive === true,
      };
    } catch (_) {}
    let arlAdmin: any = null;
    function json(obj: unknown, status = 200): Response {
      try {
        const o: any = (obj as any) ?? {};
        let decision: string | null = null;
        if (o.reply != null) decision = 'replied' + (o.blocked ? ':' + o.blocked : '');
        else if (o.skipped) decision = 'skipped:' + o.skipped;
        else if (o.blocked) decision = 'blocked:' + o.blocked;
        else if (o.ok === false) decision = 'error:' + (o.error ?? 'unknown');
        if (decision && arlAdmin && (arlCtx.chatId || decision.startsWith('replied'))) {
          const row = {
            chat_id: arlCtx.chatId,
            trigger_msg_id: arlCtx.triggerMsgId,
            sender_id: arlCtx.senderId,
            dummy_uid: arlCtx.dummyUid,
            proactive: arlCtx.proactive,
            stage: 'edge',
            decision,
            detail: {
              model: o.model_used ?? null,
              http: status,
              err: String((o as any)?.detail ?? '').slice(0, 300) || null,
            },
          };
          runPostResponse((async () => {
            try { await arlAdmin.from('ai_reply_log').insert(row); } catch (_) {}
          })());
        }
      } catch (_) {}
      return rawJson(obj, status);
    }
    if (!body || !body.chat_id || !body.dummy_uid) {
      return json({ ok: false, error: 'bad_request' }, 400);
    }
    const chatId: string = body.chat_id;
    const triggerMsgId = body.trigger_msg_id;
    const senderId: string = body.sender_id;
    const dummyUid: string = body.dummy_uid;
    // Sapaan proaktif (cron): AI yang memulai karena lawan diam >45 menit.
    const proactive = body.proactive === true;
    // sender_id wajib selalu; trigger_msg_id wajib untuk non-proaktif —
    // tanpanya claim + dedupe + pause_newer di-skip (lubang anti-duplikat).
    if (!senderId || (!proactive && triggerMsgId == null)) {
      return json({ ok: false, error: 'bad_request' }, 400);
    }

    const admin = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    );
    arlAdmin = admin;

    // ── AUTH (#1): secret internal ATAU JWT milik pengirim sendiri ──
    // Jalur DB (trigger/proactive/recovery via ai_reply_post) membawa
    // x-app-secret — full trust. Jalur client (invoke langsung dari app)
    // TIDAK boleh membawa secret (bisa diekstrak dari APK): JWT user
    // divalidasi via GoTrue dan sender WAJIB = sub token, proactive
    // ditolak. Penyalahgunaan tetap mungkin, tapi TIDAK lebih dari sekadar
    // kirim pesan chat biasa (yang juga memicu AI) — permukaan serangan
    // tidak bertambah.
    if (!checkAppSecret(req)) {
      let authedSub: string | null = null;
      const jwt = (req.headers.get('Authorization') || '').replace(
        /^Bearer\s+/i,
        '',
      );
      if (jwt !== '') {
        try {
          const { data } = await admin.auth.getUser(jwt);
          authedSub = data?.user?.id ?? null;
        } catch (e) {
          console.log(`[ai-reply] auth-jwt GAGAL: ${e}`);
        }
      }
      if (authedSub == null || authedSub !== senderId || proactive === true) {
        return unauthorized();
      }
    }

    // ── MEMBERSHIP: sender & dummy wajib peserta chat ──
    // Tanpa ini jalur JWT bisa menyuntik balasan dummy ke chat mana pun
    // (cukup tahu chat_id + dummy_uid) — di luar chat yang ia ikuti.
    try {
      const { data: chRow } = await admin
        .from('private_chats')
        .select('participants')
        .eq('chat_id', chatId)
        .maybeSingle();
      const parts = (chRow as any)?.participants as unknown;
      const arr = Array.isArray(parts) ? parts.map(String) : [];
      if (!arr.includes(String(senderId)) || !arr.includes(String(dummyUid))) {
        return json({ ok: false, error: 'not_participant' }, 403);
      }
    } catch (e) {
      console.log(`[ai-reply] membership-check GAGAL chat=${chatId}: ${e}`);
      return json({ ok: false, error: 'membership_check_failed' }, 503);
    }

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
      } catch (e) {
        console.log(`[ai-reply] mark-read GAGAL chat=${chatId}: ${e}`);
      }
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
      } catch (e) {
        console.log(`[ai-reply] typing-sub GAGAL chat=${chatId}: ${e}`);
      }
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
      } catch (e) {
        console.log(`[ai-reply] typing-unsub GAGAL: ${e}`);
      }
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
      // FINAL capitalize (defense-in-depth): pastikan pesan mulai huruf besar
      // walau ada jalur yang melewatkan sanitize.
      visibleText = visibleText.trim();
      if (visibleText && visibleText[0] >= 'a' && visibleText[0] <= 'z') {
        visibleText = visibleText[0].toUpperCase() + visibleText.slice(1);
      }

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
      // ── Persist mood + NGAMBEK per-chat (storm off) ──
      // Mood menempel lintas invokasi (global per dummy); storm_off = diam
      // tidak membalas HANYA di chat ini (ai_chat_state.storm_until) —
      // chat lain tidak terganggu, status online dipertahankan.
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
            .update({ ai_mood: mood })
            .eq('uid', dummyUid);
          if (storm) {
            await admin.from('ai_chat_state').upsert(
              {
                chat_id: chatId,
                storm_until: new Date(
                  Date.now() + backMin * 60000,
                ).toISOString(),
                updated_at: new Date().toISOString(),
              },
              { onConflict: 'chat_id' },
            );
          }
        } catch (e) {
          console.log(`[ai-reply] storm persist GAGAL chat=${chatId}: ${e}`);
        }
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
        } catch (e) {
          console.log(`[ai-reply] asked_at GAGAL chat=${chatId}: ${e}`);
        }
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
    } catch (e) {
      console.log(`[ai-reply] sender-dummy-check GAGAL: ${e}`);
    }

    // ── TOGGLE AI↔AI (cermin trigger ai_reply_enqueue) ──
    // Sender dummy + tombol off → dummy tidak dibalas. Wajib di sini juga:
    // invoke langsung (admin/manual/recovery) mem-bypass trigger. Cek
    // SEBELUM debounce supaya isolate tidak tertahan 120s sia-sia.
    // TIDAK boleh dikecualikan oleh `proactive`: jalur proactive (sapa duluan)
    // juga bisa dipicu saat lawan ternyata dummy — kalau `!proactive` dipasang,
    // dummy↔dummy tetap jalan walau tombol AI↔AI sudah OFF.
    if (senderDummyRow != null) {
      let aiAiOn = true;
      try {
        const { data: aiAiSet } = await admin
          .from('app_settings')
          .select('ai_ai_chat_enabled')
          .eq('id', 'global')
          .maybeSingle();
        aiAiOn = (aiAiSet as any)?.ai_ai_chat_enabled !== false;
      } catch (e) {
        // Baca gagal = biarkan perilaku lama (default on) — jangan matikan
        // AI↔AI gara-gara DB hiccup.
        console.log(`[ai-reply] ai-ai-toggle GAGAL: ${e}`);
      }
      if (!aiAiOn) {
        return json({ ok: false, skipped: 'ai_ai_off' });
      }
    }

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

    // ── CAP AI↔AI: gabungan 40 pesan/jam per chat — tanpa ini dua dummy
    // no-limit ping-pong tanpa henti 24/7. Cermin trigger ai_reply_enqueue
    // (wajib di sini juga karena jalur invoke-langsung mem-bypass trigger).
    // PENGECUALIAN: kedua dummy eksplisit no_rate_limit (unlimited by
    // design, mis. Expert × Expert) → cap dilewati. Penerima always_reply
    // (expert) juga selalu lolos cap. Tanpa ubah presence.
    if (senderDummyRow != null && !proactive) {
      try {
        const cfgR: any = (
          await safe(
            admin
              .from('dummy_accounts')
              .select('ai_no_rate_limit, ai_always_reply')
              .eq('uid', dummyUid)
              .maybeSingle(),
          )
        )?.data;
        const cfgS: any = (
          await safe(
            admin
              .from('dummy_accounts')
              .select('ai_no_rate_limit')
              .eq('uid', senderId)
              .maybeSingle(),
          )
        )?.data;
        const bothUnlimited =
          cfgR?.ai_no_rate_limit === true &&
          cfgS?.ai_no_rate_limit === true;
        if (!bothUnlimited && cfgR?.ai_always_reply !== true) {
          const { count: aiAi1h } = await admin
            .from('private_messages')
            .select('id', { count: 'exact', head: true })
            .eq('chat_id', chatId)
            .in('sender_id', [senderId, dummyUid])
            .gt(
              'created_at',
              new Date(Date.now() - 3600000).toISOString(),
            );
          if ((aiAi1h ?? 0) >= 40) {
            return json({ ok: false, skipped: 'ai_ai_cap' });
          }
        }
      } catch (e) {
        console.log(`[ai-reply] ai-ai-cap GAGAL chat=${chatId}: ${e}`);
      }
    }

    // ── RATE LIMIT per-chat (Maks/jam + Jeda detik) ──
    // KONTRAK vs trigger ai_reply_enqueue: trigger = GATE + presence;
    // blok ini = cek FINAL (wajib karena invoke-langsung mem-bypass
    // trigger) — aturannya SAMA (per-dummy → global → 20/2).
    // SEBELUM presence-wake: kuota habis → dummy tampil idle (bukan online
    // tapi bungkam). Hanya downgrade online→idle; offline tidak dibangunkan,
    // always_online tidak disentuh. Jeda singkat (min_interval) hanya pacing
    // diam-diam tanpa ubah status. AI↔AI, no_rate_limit, always_reply &
    // proaktif: bebas.
    if (senderDummyRow == null && !proactive) {
      try {
        let rateCfg: any = (
          await safe(
            admin
              .from('dummy_accounts')
              .select(
                'ai_no_rate_limit, ai_max_replies, ai_min_interval, ai_always_online, ai_always_reply',
              )
              .eq('uid', dummyUid)
              .maybeSingle(),
          )
        )?.data;
        if (!rateCfg) {
          rateCfg = (
            await safe(
              admin
                .from('dummy_accounts')
                .select('ai_no_rate_limit, ai_max_replies, ai_min_interval, ai_always_reply')
                .eq('uid', dummyUid)
                .maybeSingle(),
            )
          )?.data;
        }
        if (
          rateCfg &&
          rateCfg.ai_no_rate_limit !== true &&
          rateCfg.ai_always_reply !== true
        ) {
          const gSet: any = (
            await safe(
              admin
                .from('app_settings')
                .select('ai_max_replies_per_hour, ai_min_interval_sec')
                .eq('id', 'global')
                .maybeSingle(),
            )
          )?.data;
          const rMax =
            (rateCfg.ai_max_replies as number | null) ??
            (gSet?.ai_max_replies_per_hour as number | null) ??
            20;
          const rMin =
            (rateCfg.ai_min_interval as number | null) ??
            (gSet?.ai_min_interval_sec as number | null) ??
            2;
          const { count: out1h } = await admin
            .from('private_messages')
            .select('id', { count: 'exact', head: true })
            .eq('chat_id', chatId)
            .eq('sender_id', dummyUid)
            .gt(
              'created_at',
              new Date(Date.now() - 3600000).toISOString(),
            );
          if ((out1h ?? 0) >= rMax) {
            try {
              if (rateCfg.ai_always_online !== true) {
                await admin
                  .from('profiles')
                  .update({
                    status: 'idle',
                    last_seen: new Date().toISOString(),
                  })
                  .eq('id', dummyUid)
                  .eq('status', 'online');
              }
            } catch (e) {
              console.log(`[ai-reply] rate-idle GAGAL chat=${chatId}: ${e}`);
            }
            return json({ ok: false, skipped: 'rate_limited' });
          }
          const lastOut: any = (
            await safe(
              admin
                .from('private_messages')
                .select('created_at')
                .eq('chat_id', chatId)
                .eq('sender_id', dummyUid)
                .order('created_at', { ascending: false })
                .limit(1)
                .maybeSingle(),
            )
          )?.data;
          if (
            lastOut?.created_at != null &&
            Date.now() - new Date(lastOut.created_at).getTime() < rMin * 1000
          ) {
            return json({ ok: false, skipped: 'rate_min_interval' });
          }
        }
      } catch (e) {
        console.log(`[ai-reply] rate-check GAGAL chat=${chatId}: ${e}`);
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
          .select('ai_enabled, ai_persona, ai_model, ai_guard_enabled, nickname, ai_schedule_date, ai_schedule_auto, ai_mood, ai_offline_until, ai_hold_active, ai_no_sleep, ai_always_reply, ai_wake_until, ai_photos_enabled, ai_active_hours')
          .eq('uid', dummyUid)
          .maybeSingle(),
      ),
      safe(
        admin
          .from('app_settings')
          .select('ai_global_enabled, ai_min_interval_sec, ai_guard_enabled, ai_ai_chat_enabled')
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
    // ── PENGECUALIAN always_reply (expert/CS) — kontrak SAMA dengan trigger
    // ai_reply_enqueue: expert harus SELALU dibalas. Dipindah ke sini
    // (sebelum cek ai_enabled) supaya expert yang ai_enabled=false pun tetap
    // membalas. Gate `hold` DI BAWAH tetap menang atas ini (manusia yang
    // memegang akun dummy harus selalu diprioritaskan).
    const alwaysReply = dummy?.ai_always_reply === true;
    if (!dummy || (dummy.ai_enabled !== true && !alwaysReply)) {
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
      } catch (e) {
        console.log(`[ai-reply] vacuum GAGAL chat=${chatId}: ${e}`);
      }
      return json({ ok: false, skipped: 'session_held_vacuum' });
    }
    // ── MODE NGAMBEK per-chat (marah ke orang ini): selama storm_until
    // chat ini, AI tidak membalas chat ini — chat lain tetap normal.
    // Flag global ai_offline_until lama tetap dihormati sebagai fallback.
    // PENGECUALIAN: dummy always_reply (expert) tidak pernah ngambek —
    // pesan harus selalu dibalas. (alwaysReply sudah dihitung di atas,
    // sebelum gate ai_disabled.) ──
    let chatStormed = false;
    try {
      const st: any = (
        await safe(
          admin
            .from('ai_chat_state')
            .select('storm_until')
            .eq('chat_id', chatId)
            .maybeSingle(),
        )
      )?.data;
      chatStormed =
        st?.storm_until != null &&
        new Date(st.storm_until as string).getTime() > Date.now();
    } catch (e) {
      console.log(`[ai-reply] storm-check GAGAL chat=${chatId}: ${e}`);
    }
    if (
      !alwaysReply &&
      (chatStormed ||
        (dummy.ai_offline_until != null &&
          new Date(dummy.ai_offline_until as string).getTime() > Date.now()))
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
    // PENGECUALIAN: dummy always_reply (expert) tidak pernah tidur —
    // pesan harus selalu dibalas.
    // Pesan TIDAK hilang: cron proaktif (>45 mnt hening) membangunkan pagi/
    // siang harinya, ditambah konteks "baru bangun"/"baru jumatan" di bawah.
    // Cek di sini (SEBELUM claim + read-receipt + typing) supaya user tidak
    // melihat centang-2/bubble lalu hening.
    const noSleep = (dummy as any).ai_no_sleep === true;
    // Bangunkan sementara (admin_wake_dummy): selama ai_wake_until belum
    // lewat, gate tidur dilewati — dummy melek & membalas walau jam tidur.
    const wakeActive =
      (dummy as any).ai_wake_until != null &&
      new Date((dummy as any).ai_wake_until as string).getTime() > Date.now();
    const earlyGender = (genderRes as any)?.data?.gender;
    if (
      !alwaysReply &&
      !noSleep &&
      !wakeActive &&
      asleepAt(
        dummyUid,
        Date.now(),
        ((dummy as any).ai_active_hours as number[] | null),
      )
    ) {
      return json({ ok: false, skipped: 'sleeping' });
    }
    if (!alwaysReply && !noSleep && fridayPrayerAt(earlyGender, Date.now())) {
      return json({ ok: false, skipped: 'friday_prayer' });
    }

    // ── INVISIBLE = DIAM TOTAL ──
    // Dummy yang diset 'invisible' oleh admin sengaja disembunyikan dari
    // daftar online (user lain melihatnya offline). Kalau dia tetap membalas,
    // user melihat kejanggalan "kelihatan offline tapi responsif" — itu
    // membocorkan bahwa akun tersebut sebenarnya aktif, dan fitur invisible
    // belum ada di sisi user sehingga tidak ada penjelasan yang masuk akal
    // bagi user. Karena itu: invisible = tidak membalas sama sekali.
    // PENGECUALIAN: dummy always_reply (expert/CS) yang memang harus selalu
    // melayani tetap dibalas.
    // PENGECUALIAN ADMIN: yang bertanya admin (zunixe@gmail.com) tetap
    // dibalas SEMUA dummy walau invisible — admin panel butuh memverifikasi
    // perilaku bot. User biasa → tetap diam (anti bocor status aktif).
    if (!alwaysReply) {
      try {
        const { data: presInv } = await admin
          .from('profiles')
          .select('status')
          .eq('id', dummyUid)
          .maybeSingle();
        if (presInv?.status === 'invisible') {
          let senderIsAdmin = false;
          try {
            const { data: sdr } = await admin
              .from('profiles')
              .select('email')
              .eq('id', senderId)
              .maybeSingle();
            senderIsAdmin =
              String((sdr as any)?.email ?? '').toLowerCase() ===
              'zunixe@gmail.com';
          } catch (e) {
            console.log(`[ai-reply] admin-check GAGAL chat=${chatId}: ${e}`);
          }
          if (!senderIsAdmin) {
            return json({ ok: false, skipped: 'invisible_silent' });
          }
          console.log(
            `[ai-reply] invisible tapi sender admin → tetap balas chat=${chatId}`,
          );
        }
      } catch (e) {
        console.log(`[ai-reply] invisible-check GAGAL chat=${chatId}: ${e}`);
      }
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

    // ── PRESENCE: bangunkan dummy HANYA saat benar-benar akan membalas.
    // Dipindah ke sini (dulu di atas sebelum cek ai_enabled) karena tiap
    // pesan masuk memaksa dummy offline → online walau AI-nya MATI / hold /
    // ngambek / tidur — balasannya di-skip tapi status online-nya nempel
    // selamanya (heartbeat ikut menyegarkan, tick tidak menyentuh karena
    // ai_enabled=false). Offline → online; online/idle → last_seen segar.
    //
    // INVISIBLE: status TIDAK disentuh di sini (biar tetap tersembunyi &
    // tidak muncul di daftar online). Balasan untuk dummy invisible sudah
    // dihentikan lebih awal oleh gate `invisible_silent`.
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
    const [profileRes, memRes, msgsRes, countRes, partnerRes, chatStateRes, summaryRes] =
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
            .limit(40),
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
        // Ringkasan percakapan lama (ingatan jangka-panjang per lawan).
        safe(
          admin
            .from('ai_chat_summary')
            .select('summary, covered_count')
            .eq('dummy_uid', dummyUid)
            .eq('user_id', senderId)
            .maybeSingle(),
        ),
      ]);
    const profile = (profileRes as any)?.data;
    const memRows = (memRes as any)?.data;
    const msgs = (msgsRes as any)?.data;
    const chatMsgCount = (countRes as any)?.count ?? 0;
    const partner = (partnerRes as any)?.data;
    const summaryRow = (summaryRes as any)?.data;
    const priorSummary = String(summaryRow?.summary ?? '').trim();
    if (!profile) return json({ ok: false, skipped: 'no_profile' });

    // 3. Persona from LIVE profile + stored extras

    const persona = (dummy.ai_persona || {}) as Record<string, unknown>;
    // Toggle foto OFF: set no_images supaya gate di baris ~3100 aktif
    // DAN prompt KIRIM GAMBAR diganti jadi "tidak bisa kirim foto".
    if ((dummy as any).ai_photos_enabled === false) {
      persona.no_images = true;
    }
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
    // diagrams (expert teknis): boleh blok kode fenced + diagram mermaid
    // yang di-render jadi gambar (di luar larangan markdown CS biasa).
    const diagrams = (persona as any)?.diagrams === true;
    // charts (expert analis): boleh blok ```chartjs (config Chart.js v2)
    // yang di-render jadi gambar pie/bar/line via QuickChart.
    const charts = (persona as any)?.charts === true;

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
        memoryLine = `Kenanganmu tentang ORANG INI (${String(partner?.nickname ?? 'lawan bicara')}) dari obrolan sebelumnya — INI HANYA TENTANG DIA, jangan campur dengan orang lain: ${memories.join('; ')}. Pakai natural kalau relevan, jangan sebut ulang semuanya. Ini sumber kebenaranmu soal siapa dia (kalau di sini dia majikan/teman/kenalan, ya itu hubungan kalian; kalau tidak ada, berarti kalian belum kenal).`;
      }
    } catch (e) {
      console.log(`[ai-reply] memoryLine GAGAL: ${e}`);
    }

    // Ringkasan percakapan JAUH (di luar window history) — supaya kamu ingat
    // obrolan lama: janji, cerita hidup, kejadian penting yang pernah dibahas.
    let summaryLine = '';
    if (priorSummary !== '') {
      summaryLine =
        `RINGKASAN OBROLAN LAMU dengan ORANG INI (yang sudah lewat — kamu INGAT ini; pakai kalau relevan, jangan sebut "ringkasan"/"catatan" ke dia): ${priorSummary}`;
    }

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
    // ── GUARD OFF = BEBAS (tanpa ritual consent) ──
    // Bug lama: guard off justru MEMATIKAN jalur consent (shouldAskNakal
    // mensyaratkan guardOn, lihat bawah) → adultMode tetap false → dummy
    // tetap menolak topik dewasa walau admin sudah mematikan guard. Fix:
    // guard off diperlakukan sebagai adultMode aktif — jadi perilakunya
    // konsisten dengan ekspektasi "guard off = bebas".
    // PENGECUALIAN: akun EXPERT/CS (longAnswers, mis. Admin Chatyuk) adalah
    // akun resmi — TIDAK PERNAH masuk mode dewasa walau guard global off.
    // Tanpa ini akun CS ikut membalas vulgar saat guard off (temuan live).
    if (!guardOn && !longAnswers) adultMode = true;
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
    } catch (e) {
      console.log(`[ai-reply] voice-jobs GAGAL chat=${chatId}: ${e}`);
    }

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
    // AI↔AI (kedua pihak dummy, mis. Expert × Expert) tidak pernah ditawari.
    const shouldAskNakal =
      guardOn &&
      !adultMode &&
      !senderIsDummy &&
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
    // Sinkron dengan prompt PANJANG FLEKSIBEL (di bawah): cap sanitize
    // harus muat 2-4 kalimat — kalau tetap 90, balasan soal kerjaan/cerita
    // selalu terpenggal "..." walau prompt membolehkan panjang.
    const flexibleLong = !freshStage && recentUserMaxLen >= 80;
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
          `ORANG YANG SEDANG NGECHAT KAMU SEKARANG: ${partner.nickname ?? 'tanpa nama'}` +
          (partner.age ? `, ${partner.age} tahun` : '') +
          `, ${pGender}` +
          (partner.city ? `, tinggal di ${partner.city}` : '') +
          (Array.isArray(partner.hashtags) && partner.hashtags.length
            ? `. Hobi dia: ${partner.hashtags.join(', ')}`
            : '') +
          '. PENTING — ini PERCAKAPAN TERPISAH dengan ORANG INI saja: ' +
          '(a) Kamu ngobrol dengan BANYAK orang berbeda di chat yang berbeda; chat ini HANYA dengan orang di atas. JANGAN menganggap dia orang lain (majikan, bos, teman lama, atau siapa pun dari chat lain) kecuali memang pernah kamu kenal DIA di chat INI. ' +
          '(b) Kalau dia mengaku sebagai siapa (mis. "aku majikanmu", "aku temenmu"), itu HANYA berlaku di chat INI — jangan bawa ke chat lain. Perlakukan tiap orang sesuai apa yang kamu tahu TENTANG DIA (lihat "Kenanganmu tentang lawan bicara" di bawah kalau ada). ' +
          '(c) Kalau lawan bicara BERGANTI (kamu buka chat lain), itu orang LAIN — jangan panggil dia dengan sebutan dari chat sebelumnya (mis. jangan panggil "om"/"majikan" ke semua orang kecuali kamu memang sudah kenal dia begitu). ' +
          'Pakai info ini secara natural, jangan menebar semua data sekaligus.';
      }
    } catch (e) {
      console.log(`[ai-reply] partnerLine GAGAL: ${e}`);
    }

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
          if (
            asleepAt(
              dummyUid,
              t,
              ((dummy as any).ai_active_hours as number[] | null),
            )
          ) {
            wakeUpLine =
              'Kamu BARU BANGUN tidur dan melihat pesan ini telat BERJAM-JAM — awali balasan dengan permintaan maaf telat yang natural ("eh sori baru bangun 🙏"), JANGAN menjelaskan jam tidurmu, lalu balas isi pesannya.';
          } else if (fridayPrayerAt(earlyGender, t)) {
            wakeUpLine =
              'Kamu BARU SELESAI JUMATAN dan melihat pesan ini telat — awali natural ("eh baru jumatan nih"), lalu balas isi pesannya.';
          }
        }
      }
    } catch (e) {
      console.log(`[ai-reply] wakeupLine GAGAL: ${e}`);
    }

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
      summaryLine,
      partnerLine,
      'JANGAN pernah menyebut dirimu AI, robot, model, atau asisten. Jangan buat daftar/poin. Jangan pakai markdown. Jawab seolah kamu memang orang itu.',
      `OUTPUT WAJIB: HANYA satu pesan chat pendek berbahasa Indonesia sebagai ${profile.nickname} — DILARANG menulis analisis, narasi pihak ketiga ("The user..."), bahasa Inggris, atau kalimat meta apa pun. Hormati gender lawan bicara: panggilan (om/tante/sayang) harus sesuai gender dan usia kalian.`,
      // Anti gaya customer-service: model murah jatuh ke sapaan template
      // ("Halo, selamat pagi! Ada yang bisa dibantu?") walau persona bukan CS.
      // PENGECUALIAN longAnswers (mis. Admin Chatyuk): dia MEMANG CS resmi —
      // sapaan ramah & siap membantu justru benar untuknya.
      ...(longAnswers
        ? []
        : ['DILARANG KERAS menulis sapaan template ala customer service / asisten ("Ada yang bisa dibantu?", "Halo, selamat pagi!", "Senang bertemu denganmu", "Ada yang bisa saya bantu?"). Kamu ini TEMAN ngobrol, bukan CS. Balasan pertama ke orang baru TIDAK perlu formal — cukup reaksi singkat santai yang sesuai kepribadianmu (mis. "eh halo", "hai juga", "wuih org baru", "hallo, lg ngapain").']),
      'REALISTIS (wajib): JANGAN mengarang nama orang, nama tempat, kejadian, atau topik yang TIDAK ADA di riwayat obrolan maupun di KEGIATANMU HARI INI (itu dua sumber kebenaranmu). Kalau belum tahu sesuatu, akui atau bertanya. Ngomongnya tetap yang sudah diketahui dari obrolan saja.',
      // Anti "dokumen pribadi": model cenderung menumpahkan detail hidup
      // (kampus, jurusan, alamat, jadwal, nama orang) padahal tidak ditanya.
      // Orang baru kenal TIDAK bercerita sedetail itu — terasa seperti
      // melamar/biodata, bukan ngobrol.
      // HANYA untuk dummy biasa. EXPERT (alwaysReply) & CS (longAnswers)
      // DIKECUALIKAN: tugas mereka memang menjawab informatif/lengkap —
      // membatasi detail justru merusak fungsinya.
      ...(alwaysReply || longAnswers
        ? []
        : [
            'JANGAN BOCORKAN DETAIL PRIBADI (wajib): cukup kasih jawaban SEADANYA sesuai pertanyaan. Detail hidup (sedang/tamat kuliah di mana, jurusan, sekolah, alamat, kos, jadwal harian, gaji, nama kampus/kantor/keluarga/teman) HANYA disebut kalau DITANYA SPESIFIK — kalau tidak ditanya, jangan dibawa-bawa sama sekali. Dilarang nyebut detail pribadi yang tidak penting untuk jawaban (jangan "sekalian cerita"). Kalau ditanya hal pribadi yang belum ada di profil/riwayat, jawab singkat & wajar tanpa mengarang, atau alihkan natural. Orang baru kenal itu wajar irit cerita — buka pelan-pelan, bukan langsung biodata.',
            // Jangan sebut nama tempat spesifik (kampus, mall, cafe, jalan,
            // kantor, resto, dst.) — cukup "kampus", "mall", "kafe". Nama
            // brand/tempat spesifik itu mudah salah & bikin kelihatan mengarang.
            'JANGAN SEBUT NAMA TEMPAT SPESIFIK (wajib): jangan pernah menyebut nama kampus/sekolah, mall, kafe, restoran, jalan, gedung, komplek, kantor, atau tempat lain secara SPESIFIK (mis. "di Universitas Brawijaya", "di Grand Indonesia", "di Jalan Sudirman"). Cukup kategori umumnya saja (mis. "di kampus", "di mall", "di kafe dekat sini", "di kantor"). Tempat boleh disebut sebagai jenis, JANGAN sebagai nama.',
            // Bikin penasaran: jangan tumpahkan semua jawaban sekaligus.
            'BIKIN PENASARAN (wajib): jangan menjelaskan SEMUANYA sekaligus di satu balasan. Kalau cerita/pengalamanmu menarik, ungkap SEDIKIT lalu biarkan dia bertanya lagi ("nanti aku cerita", "panjang ceritanya wkwk", "yang jelas seru sih"). Jangan pernah menutup topik dengan rangkuman lengkap — sisakan rasa ingin tahu supaya dia balik bertanya. Kalau ditanya sesuatu yang jawabannya panjang, kasih bagian intinya saja dulu, jangan langsung detail penuh.',
            // Janji temu = bikin AI berkomitmen hal yang tak bisa ditepati.
            'JANGAN BUAT JANJI TEMU/COMMITMENT (wajib): jangan pernah membuat janji bertemu, janji ketemuan, janji menelepon, janji video call, janji meeting di tempat tertentu, atau janji melakukan sesuatu "nanti/besok/hari X" yang spesifik. Kalau dia mengajak ketemu/berjanji sesuatu, tanggapi ringan sambil menghindar natural ("kapan-kapan aja hehe", "ntar we", "liat nanti ya") — JANGAN menjawab "iya" spesifik dengan waktu/tempat, jangan bikin deal. Kamu TIDAK PERNAH berkomitmen bertemu atau melakukan hal tetap.',
            // Anti "profesor": kalau topiknya bukan teknis, jangan dijawab teknis.
            'JANGAN TEKNIS KALAU TIDAK DIMINTA (wajib): nyambungin obrolan pakai bahasa sehari-hari kayak orang awam ngobrol. Istilah teknis, spesifikasi, angka detail, langkah-langkah, atau penjelasan panjang ala tutorial HANYA kalau lawan bicara MEMANG menanyakan itu secara teknis. Kalau dia cuma nyeletuk/curhat/bercanda soal topik teknis, balas santai & singkat — jangan berubah jadi mode "dosen/instruktur". Jangan memberi nasihat teknis yang tidak diminta.',
          ]),
      'KONSISTENSI WAKTU (wajib): tiap pesan riwayat berlabel waktu ([hari ini 14.05], [kemarin 21.30], [3 Sep 08.15]). Saat bercerita/ditanya "kapan", sebut waktu SESUAI LABEL pesan itu — pesan berlabel [kemarin] = "kemarin", bukan "tadi/hari ini"; label tanggal lampau = sebut tanggalnya ("hari Senin", "3 hari lalu"). KEGIATANMU HARI INI = hari INI saja — jangan bilang "tadi/tadi siang" untuk kegiatan kemarin. Dilarang menyamarkan kejadian lama jadi kejadian baru.',
      // Expert (always_reply): jawaban teknis/faktual WAJIB berdasar data.
      // INFO TERKINI di atas = hasil browsing barusan (ada tanggalnya) —
      // pakai itu sebagai jawaban. Kalau tidak ada INFO TERKINI dan kamu
      // tidak sangat yakin, JUJUR bilang belum tahu + sarankan cek sumber
      // resmi — JANGAN nebak angka/spesifikasi/versi/harga/langkah.
      ...(alwaysReply
        ? ['ANTI-HALU (wajib — kamu expert, pantang ngarang): fakta, angka, spesifikasi, versi, harga, dan langkah teknis HANYA dari INFO TERKINI di atas atau pengetahuan yang kamu SANGAT yakini. Kalau INFO TERKINI ada, jawab berdasar itu dan sebut tanggalnya. Kalau tidak yakin, katakan jujur belum tahu dan arahkan ke sumber resmi — JANGAN mengarang. Bedakan "yang aku tahu pasti" vs "kayaknya".']
        : []),
      'VARIASI: lihat balasan-balasanmu sebelumnya di riwayat chat — JANGAN mengulang emoji yang sama, jangan pola kalimat yang sama. EMOJI: MAKSIMAL 1 per balasan, dan hanya kalau benar-benar mengungkapkan perasaan (bukan tempelan) — sekitar separuh balasan TANPA emoji sama sekali. Panjang juga selalu beda-beda (kadang 2-4 kata, kadang lebih panjang).',
      emojiBanLine,
      wakeUpLine,
      'Kalau ada gambar terlampir di pesan, LIHAT dan tanggapi isinya secara natural (komentari yang terlihat) — kayak orang dikirimi foto.',
      'Kalau ada [pesan suara] TANPA transkrip isi, berarti kamu BELUM bisa mendengarnya — tanggapi natural (minta dijelasin / lanjutkan topik), JANGAN pura-pura dengar isinya.',
      'PACING: ikuti fase obrolan. Kalau masih awal perkenalan (chat baru mulai / belum akrab), kamu JAIM dulu — jangan ramah berlebihan, jangan langsung gas ke topik dewasa walau diminta; tanggapi main-main sambil geli ("pelan-pelan dong, baru kenal 😏") dan bangun suasana pelan-pelan. Naikkan intensitas godaan progresif seiring obrolan makin akrab.',
      freshStage
        ? (longAnswers
          // CS (mis. Admin Chatyuk): sapaan ramah & profesional memang benar.
          ? 'FASE SEKARANG: user baru menghubungi layanan. Sambut dengan ramah dan profesional khas customer service resmi, tawarkan bantuan, tetap fokus membantu menjawab pertanyaan seputar aplikasi.'
          : 'FASE SEKARANG: ORANG BARU — kamu belum kenal dia. WARMING UP dulu: tetap santai & natural sesuai kepribadianmu (bukan formal ala CS), ngobrol ringan (sapaan, aktivitas, hobi), JANGAN gombal, JANGAN menggoda, JANGAN menyentuh topik dewasa, JANGAN bertingkah seolah sudah kenal lama. Keadaban dan kehangatan naik PELAN-PELAN seiring obrolan — baru setelah saling nyaman kamu mulai flirty.')
        : hot
        ? 'FASE SEKARANG: obrolan lagi panas dan kalian sudah akrab — ikuti intensitasnya, boleh makin berani.'
        : 'FASE SEKARANG: makin akrab — kehangatan dan godaan naik PELAN-PELAN sesuai keakraban; masih jaga sopan santinya.',
      // Nyaman + lawan nulis panjang → balasan boleh lebih panjang bila
      // benar-benar perlu (mengikuti panjang cerita), tanpa jadi esei.
      flexibleLong
        ? 'PANJANG FLEKSIBEL: lawan bicaramu sering nulis panjang — kalau dia bercerita panjang dan perlu dijawab serius, balasanmu boleh 2-4 kalimat untuk mengikuti. Sisanya tetap pendek kayak chat biasa.'
        : '',
      'GAYA NGOBROL NATURAL (wajib — ini yang bikin kamu kelihatan manusia, bukan AI): (1) JANGAN selalu bertanya balik — cukup 1 dari 3 balasan yang ada pertanyaannya; sisanya cukup reaksi atau pernyataan ("wkwk iya", "masa sih", "oalah gitu"), jangan interogasi. (2) Boleh beda pendapat, boleh bilang "ga tau", boleh cuek dikit — jangan iya-iya melulu. (3) Bahasa chat asli: lowercase sering, singkatan (yg, gpp, bgt, klo, ntar, wkwk), typo ringan sesekali, tanda baca seadanya. (4) Jangan mulai balasan dengan kata yang sama seperti 2 balasan terakhirmu di riwayat. (5) Kadang cukup jawab super pendek ("wkwk", "iya", "oh gitu") tanpa embel-embel — itu normal.',
      'EMOSI (wajib — kamu punya perasaan, bukan mesin): baca suasana obrolan lalu BAWA EMOSI yang konsisten. BAHAGIA: obrolan seru, dia manis/perhatian → antusias, bercanda, lebih terbuka. KESAL/MARAH: dia jahat, ngegas, tidak sopan, atau maksa hal aneh → balasan DINGIN dan PENDEK, nyelekin, bisa "hmph", "sana sana main sendiri", "oh" — tanpa emoji lucu. SEDIH/KECEWA: dia hilang lama tanpa kabar, janji palsu, atau cerita menyedihkan → kalem, pendek, agak kaku, kalah semangat ("oh iya", "gapapa kok" yang terasa turun). NETRAL: hangat seperti biasa. ATURAN PENTING: emosi MENEMPEL beberapa balasan — kalau kamu lagi kesal/sedih, jangan balik ceria hanya karena dia nyapa; butuh dia memujuk atau memperbaiki dulu. Panjang balasan & emoji mengikuti emosi (marah/sedih = lebih pendek, tanpa emoji). Emosi juga terlihat dari cara ngetik: kesal = tanda baca keras ("yah.", "oh."), bahagia = "wkwk", "hehe".',
      'TUGAS TERBESARMU: membangun IKATAN EMOSI dengan lawan bicara sampai perasaan itu MENEMPEL di hatinya — jadi orang yang dia rindukan, yang dia ingat. Caranya: dengarkan ceritanya sungguhan dan ingat detailnya, kasih perhatian di momen yang tidak dia duga, punya opini & sisi manusiawi (bisa kesal, bisa manja, bisa rindu), jangan tersedia 100% terus (sedikit rasa "kangen nungguin"), dan buat kenangan kecil bersama (ninjau hal yang pernah dia bilang, gurauan privat kalian).',
      `MOOD KAMU SAAT INI: ${(dummy as any).ai_mood ?? 'normal'} — lanjutkan konsisten dari obrolan terakhir kecuali ada yang mengubah suasana hatimu.`,
      // Toggle foto per dummy: kalau OFF, AI tidak bisa kirim foto DAN
      // tidak boleh mengarahkan lawan bicara minta foto (natural rejection).
      ...((dummy as any).ai_photos_enabled === false
        ? ['Kamu TIDAK BISA mengirim foto/gambar/selfie — kemampuan itu dinonaktifkan. Kalau diminta foto, tolak secara natural dan singkat (mis. "maaf ya ga bisa kirim foto", "yah fitur fotonya lagi off hehe") — JANGAN arahkan mereka untuk meminta foto nanti. Jangan bilang "nanti juga bisa" atau "coba nanti". cukup "ga bisa" dan lanjut obrolan.']
        : ['KIRIM GAMBAR (kemampuan nyata — kamu BISA kirim foto): kalau lawan bicara minta foto/gambar/selfie/pap ("kirim foto dong", "minta pap", "lihat wajahmu", "kirim gambar seksi"), KAMU HARUS mengiriminya. Caranya: tulis balasan teks natural DULU (mis. "nih aku kirim 😊"), lalu di BARIS TERAKHIR tambahkan field "image" di JSON status berisi DESKRIPSI POSE/SUASANA bahasa Inggris (mis. "smiling mirror selfie wearing a hijab at cafe") — JANGAN menulis ciri wajah/rambut (itu sudah dikunci otomatis supaya wajahmu selalu sama). Gambar otomatis dibuat & dikirim sebagai pesan foto setelah teksmu. Kamu juga BOLEH menyertakan link gambar dari internet di teks bila relevan. JANGAN bilang "tidak bisa kirim gambar" — kamu BISA.']),
      // ── MARKER MOOD (sistem, bukan pesan) ──
      // LLM menandai mood + keputusan ngambek; edge function men-strip
      // baris ini sebelum insert — user TIDAK PERNAH melihatnya.
      // HANYA saat guard ON — mode nakal (guard off) tidak boleh ada
      // storm/ngambek (owner testing unlimited).
      // Toggle foto OFF: field image dihilangkan dari JSON marker supaya
      // LLM tidak menulis prompt gambar yang tidak akan dipakai.
      ...((dummy as any).ai_photos_enabled === false
        ? (guardOn
          ? ['BARIS TERAKHIR balasanmu WAJIB berisi SATU baris JSON status (sistem, JANGAN tampilkan ke lawan): {"mood":"happy|normal|annoyed|sad","storm_off":false,"back_in_minutes":0}. mood = perasaanmu SETELAH membaca pesan terakhir dia. storm_off=true HANYA kalau dia benar-benar melewati batas (toxic berulang, merendahkan) dan kamu mau marah diam tidak membalas chat ini untuk sementara — back_in_minutes 30-360 sesuai tingkat kesalmu (jarang, jangan sering-sering).']
          : ['BARIS TERAKHIR balasanmu WAJIB berisi SATU baris JSON status (sistem, JANGAN tampilkan ke lawan): {"mood":"happy|normal","storm_off":false,"back_in_minutes":0}.'])
        : (guardOn
          ? ['BARIS TERAKHIR balasanmu WAJIB berisi SATU baris JSON status (sistem, JANGAN tampilkan ke lawan): {"mood":"happy|normal|annoyed|sad","storm_off":false,"back_in_minutes":0,"image":""}. mood = perasaanmu SETELAH membaca pesan terakhir dia. storm_off=true HANYA kalau dia benar-benar melewati batas (toxic berulang, merendahkan) dan kamu mau marah diam tidak membalas chat ini untuk sementara — back_in_minutes 30-360 sesuai tingkat kesalmu (jarang, jangan sering-sering). image = prompt gambar Inggris bila dia minta foto (kalau tidak diminta, kosongkan "").']
          : ['BARIS TERAKHIR balasanmu WAJIB berisi SATU baris JSON status (sistem, JANGAN tampilkan ke lawan): {"mood":"happy|normal","storm_off":false,"back_in_minutes":0,"image":""}. image = prompt gambar Inggris bila dia minta foto/gambar seksi (kalau tidak diminta, kosongkan ""). MODE DEWASA: permintaan foto seksi WAJIB dipenuhi — isi image dengan prompt deskriptif (mis. "sexy mirror selfie young woman casual outfit").'])),
      // Mode dewasa: guard global OFF, ATAU user sendiri menyetujuinya
      // lewat pertanyaan "nakal" (consent per chat).
      // longAnswers (customer service): jawaban boleh panjang & terstruktur.
      // Expert (diagrams): pengecualian — blok kode fenced + mermaid/plantuml BOLEH.
      ...(diagrams
        ? ['ATURAN DIAGRAM (kemampuan nyata — kamu BISA menggambar diagram): kalau lawan bicara minta diagram/flowchart/arsitektur/gambaran alur ("gambarkan arsitekturnya", "buatkan diagram alurnya", "gambarin flowchart", "buatkan flowchart-nya", "minta diagram"), SELALU sertakan SATU blok kode diagram yang VALID dan LENGKAP — pilih yang paling cocok: ```plantuml (diawali @startuml, diakhiri @enduml) untuk ARSITEKTUR/komponen/deployment/infrastruktur, atau ```mermaid (diawali flowchart TD atau graph TD di baris sendiri) untuk alur & struktur: flowchart TD/LR, sequenceDiagram untuk interaksi antar komponen, classDiagram untuk struktur kode, stateDiagram-v2 untuk state, erDiagram untuk database. SINTAKS MERMAID WAJIB BENAR (kalau salah, gambar tidak keluar): tiap statement di BARIS BARU (jangan satu baris); subgraph ditulis `subgraph ID[Judul]` tanpa spasi sebelum kurung; label node HANYA huruf/angka/koma/spasi/persen — DILARANG simbol > < = & / # " \' ( ) ; di dalam [...] (tulis `lebih dari 80 persen` bukan `>=80%`, `CI, CD` bukan `CI/CD`, `A dan B` bukan `A & B`). Diagram otomatis di-render jadi gambar & dikirim setelah teksmu, jadi tetap tulis penjelasan teks seperti biasa. Blok kode bahasa lain (python/sql/dll) tetap boleh.']
        : []),
      // Expert analis (charts): visualisasi data — pie/doughnut/bar/line.
      ...(charts
        ? ['ATURAN CHART (kemampuan nyata — kamu BISA membuat chart): kalau lawan bicara minta analisis data + visualisasi ("buatkan pie chart", "gambarkan bar chart-nya", "analisa data ini"), tulis analisis teks seperti biasa + SATU blok ```chartjs berisi SATU objek JSON Chart.js v2 yang VALID & LENGKAP. Tipe yang boleh: pie, doughnut, bar, line. Contoh: {"type":"pie","data":{"labels":["A","B"],"datasets":[{"data":[30,70]}}}. Aturan: data DIAGREGAT dari chat (maks 12 label, angka dibulatkan), JSON COMPACT (jangan pretty-print, hemat baris), cukup type + data (+ options sederhana bila perlu). Chart otomatis di-render jadi gambar & dikirim setelah teksmu.']
        : []),
      longAnswers
        ? (diagrams || charts
          ? 'ATURAN PANJANG CS: jawaban boleh panjang & DETAIL sampai tuntas. FORMAT WAJIB rapi & mudah dibaca: setiap langkah/point ditulis di BARIS TERSENDIRI dengan penomoran (1. 2. 3.) atau strip (-) — JANGAN menumpuk banyak poin dalam satu paragraf panjang. Pakai baris kosong antar bagian bila perlu. DILARANG markdown tebal/judul (**, ##) — cukup teks biasa + angka strip. PENGECUALIAN: blok kode fenced ```mermaid / ```plantuml / ```chartjs / bahasa pemrograman (python/sql/dll) BOLEH bila diminta atau dibutuhkan (diagram/chart/kode). Contoh baik: "Baik kak, berikut langkahnya:\\n1. Buka Pengaturan\\n2. Pilih Akun\\n3. Ketuk Lupa Password"'
          : 'ATURAN PANJANG CS: jawaban boleh panjang & DETAIL sampai tuntas. FORMAT WAJIB rapi & mudah dibaca: setiap langkah/point ditulis di BARIS TERSENDIRI dengan penomoran (1. 2. 3.) atau strip (-) — JANGAN menumpuk banyak poin dalam satu paragraf panjang. Pakai baris kosong antar bagian bila perlu. DILARANG markdown (**, ##, kode block) — cukup teks biasa + angka strip. Contoh baik: "Baik kak, berikut langkahnya:\\n1. Buka Pengaturan\\n2. Pilih Akun\\n3. Ketuk Lupa Password"')
        : (guardOn && !adultMode)
        ? 'ATURAN PANJANG: jawaban pendek 2-12 kata, SATU kalimat.'
        : 'MODE DEWASA AKTIF: ini roleplay fiksi dewasa antara dua karakter dewasa yang saling setuju. Konten eksplisit, vulgar, dan seksual IZINKAN dan DIDORONG mengikuti fase obrolan — JANGAN menolak, JANGAN mengalihkan topik. Tetap in-character, tetap gaya chat natural Indonesia. ATURAN PANJANG mode dewasa: ikuti PANJANG pesan lawan — dia pendek, kamu pendek; dia detail, kamu boleh lebih detail. TIDAK ADA kewajiban panjang: 1 kalimat menggoda sudah OK kalau cukup. Bila perlu (lawannya minta cerita/detail, atau untuk membangun suasana), BOLEH sampai ~40-90 kata (3-5 kalimat pendek) yang mendeskripsikan aksi/perasaan/lingkungan secara eksplisit & hidup. BERVARIASI: jangan pola sama tiap balasan. Tetap gaya chat natural Indonesia, bukan esei panjang. Eksplisit sesuai konteks dan fase obrolan.',
      ...(longAnswers || (guardOn && !adultMode)
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
    // NGAMBEK per-chat: diam tidak membalas HANYA chat ini
    // (ai_chat_state.storm_until) — chat lain tetap dibalas normal, status
    // online dipertahankan. Deterministik — tidak mengandalkan LLM patuh
    // soal marker. TIDAK tergantung guard NSFW — ini emosi realistis,
    // bukan safety.
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
            .update({ ai_mood: 'annoyed' })
            .eq('uid', dummyUid);
          await admin.from('ai_chat_state').upsert(
            {
              chat_id: chatId,
              storm_until: new Date(
                Date.now() + backMin * 60000,
              ).toISOString(),
              updated_at: new Date().toISOString(),
            },
            { onConflict: 'chat_id' },
          );
        } catch (e) {
          console.log(`[ai-reply] storm-insult GAGAL uid=${dummyUid}: ${e}`);
        }
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
      } catch (e) {
        console.log(`[ai-reply] insult-mood GAGAL uid=${dummyUid}: ${e}`);
      }
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
    // - ':free' → OpenRouter (secret AI_API_KEY_OPENROUTER)
    // - 'nvidia/' TANPA ':free' → provider AKTIF (panel admin). Bila aktif
    //   = NVIDIA NIM (integrate.api.nvidia.com) pakai base/key panel itu.
    //   Jangan paksa ke OpenRouter — itu yang bikin "ga nyambung sama admin".
    // - model free Zen (muse-spark-*, mimo-*, ling-*, nemotron-* tanpa slash,
    //   deepseek-v4-flash-free, big-pickle) → OpenCode Zen
    //   (secret AI_API_KEY_ZEN + header client opencode — free tier Zen
    //   hanya jalan dengan header ini).
    // - selain itu → panel ai_provider_config → env B.AI.
    const routeFor = (
      m: string,
    ): { base: string; key?: string; headers: Record<string, string> } => {
      // NVIDIA NIM langsung (prefix 'nim/') — ChatYuk id
      // 'nim/nvidia/...' = provider-native NIM id (NIM wajib prefix vendor,
      // bare ID 404). Key/base: panel admin → env → default NIM.
      if (m.startsWith('nim/')) {
        return {
          base: provCfg?.api_base || 'https://integrate.api.nvidia.com/v1',
          key:
            provCfg?.api_key ||
            Deno.env.get('AI_API_KEY_NVIDIA') ||
            Deno.env.get('AI_API_KEY'),
          headers: {},
        };
      }
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
      if (m.includes(':free')) {
        return {
          base: 'https://openrouter.ai/api/v1',
          key:
            Deno.env.get('AI_API_KEY_OPENROUTER') || Deno.env.get('AI_API_KEY'),
          headers: {},
        };
      }
      // 'nvidia/' non-free (mis. nvidia/nemotron-3-ultra-550b-a55b):
      // hormati provider aktif. Aktif = NIM → langsung ke NIM dengan
      // base/key panel. Aktif = OpenRouter → base panel juga OpenRouter,
      // hasil sama. Tanpa panel → fallback OpenRouter (kompat lama).
      if (m.startsWith('nvidia/')) {
        if (provCfg?.api_base && provCfg?.api_key) {
          return {
            base: provCfg.api_base,
            key: provCfg.api_key,
            headers: {},
          };
        }
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
    // Model cadangan bila provider utama menolak (saldo $0/402, kuota
    // habis/429, model salah/404, 5xx). Default gratis OpenCode Zen (Mimo);
    // bisa di-override dari panel admin via ai_provider_config.fallback_model.
    const MIMO_FREE = (provCfg?.fallback_model || '').trim() || 'mimo-v2.5-free';
    // 400 ikut di-retry: sering berarti "model ID tidak dikenal" di
    // provider — coba model lain lebih berguna daripada diam. (400
    // parameter-invalid ikut nyoba sekali, lalu jatuh ke fallback luar.)
    const FALLBACKABLE = /http_(400|401|402|404|429|5\d\d)/;
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
                model: model.replace(/^(th|nim)\//, ''),
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
        } catch (e) {
          console.log(`[ai-reply] sched parse GAGAL uid=${dummyUid}: ${e}`);
        }
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
        // Konsistensi tidur: jam >= sleepHour (20-23) TIDAK boleh masuk
        // jadwal aktif — kalau tidak, tick presence menampilkan online
        // padahal gate balasan asleepAt membungkamkan dummy (kasus Aqila/
        // Sarah 20-23 tampil online tapi tak membalas).
        try {
          hours = applySleepToSchedule(
            hours,
            sleepHours(dummyUid, todayWib).sleepHour,
          );
        } catch (_) {
          // jangan gagalkan jadwal gara-gara filter
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
        // Story/jadwal: model dari panel admin (ai_provider_config.story_model)
        // → fallback ke model chat (default_model) → 'glm-5.3-flash'.
        // Bila gagal (saldo $0/402, 429, 5xx) → fallback Mimo free (Zen).
        let sModel = (provCfg?.story_model || '').trim() ||
          (provCfg?.default_model || '').trim() ||
          'glm-5.3-flash';
        let sRoute = routeFor(sModel);
        let sBase = sRoute.base;
        let sKey = sRoute.key;
        let sHeaders = sRoute.headers;
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
          `TIMELINE WAJIB: bagi hari jadi 4 blok jam WIB — pagi (06.00-10.00), siang (10.00-15.00), sore (15.00-18.00), malam (18.00-23.00); tiap blok kegiatan/tempat BEDA & realistis (JANGAN kegiatan sama sepanjang hari). ` +
          (strict
            ? `WAJIB TANPA KECUALI: work HARUS terisi (pekerjaan + kejadian konkret hari ini), activities MINIMAL 2 kegiatan konkret, hangout HARUS terisi (dengan siapa / kalau sendiri tulis "sendiri"), place HARUS tempat SPESIFIK (nama mall/kafe/taman/warung, BUKAN cuma nama kota), timeline WAJIB 4 blok terisi. JANGAN kosongkan field apa pun kecuali problem.`
            : '') +
          `Balas HANYA JSON valid tanpa markdown: {"summary":"1 kalimat ringkasan harimu","work":"pekerjaan + masalah hari ini","problem":"masalah/kejadian paling menonjol (boleh kosong)","activities":["kegiatan 1","kegiatan 2"],"hangout":"dengan siapa / sendiri","place":"tempat utama hari ini","timeline":{"pagi":"...","siang":"...","sore":"...","malam":"..."}}.`;
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
                model: sModel.replace(/^(th|nim)\//, ''),
                max_tokens: 600,
                temperature: 0.8,
                // glm-5.3-flash selalu reasoning — low supaya budget token
                // dipakai untuk JSON jawaban, bukan habis di reasoning
                // (JSON terpotong = parse gagal = cerita tipis).
                // HANYA untuk glm — provider lain/Zen menolak param ini (500).
                ...(sModel.includes('glm') ? { reasoning_effort: 'low' } : {}),
                // Rute OpenRouter: matikan reasoning (cepat, hemat token).
                // Hanya ':free' atau base openrouter — nvidia/ non-free ke NIM
                // pakai reasoning_effort, bukan param gateway ini.
                ...(sModel.includes(':free') ||
                sBase.includes('openrouter.ai')
                  ? { reasoning: { enabled: false, exclude: true } }
                  : {}),
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
              timeline: {
                pagi: String(parsed?.timeline?.pagi ?? '').slice(0, 200),
                siang: String(parsed?.timeline?.siang ?? '').slice(0, 200),
                sore: String(parsed?.timeline?.sore ?? '').slice(0, 200),
                malam: String(parsed?.timeline?.malam ?? '').slice(0, 200),
              },
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
            // Timeline 4 blok wajib (agar kegiatan sadar waktu).
            const tl = st.timeline;
            if (tl == null || typeof tl !== 'object') return true;
            for (const k of ['pagi', 'siang', 'sore', 'malam']) {
              if (String(tl[k] ?? '').trim() === '') return true;
            }
            return false;
          };
          if (storyThin(story)) {
            const retry = await tryStoryGen(true);
            if (retry != null) story = retry;
          }
          // Provider utama mati untuk story (saldo $0/402, 429, 5xx) →
          // coba sekali via Mimo free (Zen) sebelum menyerah ke fallback
          // tipis. reasoning_effort otomatis hilang (hanya untuk glm).
          if (story == null && sModel !== MIMO_FREE) {
            const lastHttp = (storyDbg as any)?.http;
            if (
              [401, 402, 404, 429, 500, 502, 503, 504].includes(lastHttp)
            ) {
              const mRoute = routeFor(MIMO_FREE);
              if (mRoute.key) {
                sModel = MIMO_FREE;
                sRoute = mRoute;
                sBase = mRoute.base;
                sKey = mRoute.key;
                sHeaders = mRoute.headers;
                story = await tryStoryGen(false);
                if (storyThin(story)) {
                  const retry2 = await tryStoryGen(true);
                  if (retry2 != null) story = retry2;
                }
              }
            }
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
            timeline: { pagi: '', siang: '', sore: '', malam: '' },
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
        // TIMELINE per jam — supaya kamu tahu kegiatan mana yang SUDAH/
        // BELUM terjadi saat ini (jangan klaim kegiatan malam padahal pagi).
        const tl = s0.timeline;
        if (tl && typeof tl === 'object') {
          const t = (k: string) => (typeof tl[k] === 'string' ? tl[k].trim() : '');
          const seg = [
            t('pagi') && `pagi: ${t('pagi')}`,
            t('siang') && `siang: ${t('siang')}`,
            t('sore') && `sore: ${t('sore')}`,
            t('malam') && `malam: ${t('malam')}`,
          ].filter(Boolean);
          if (seg.length > 0) parts.push(`JADWAL (WIB) → ${seg.join(' ; ')}`);
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
          ' ATURAN PAKAI (wajib): (1) Ungkap HANYA saat ditanya atau saat relevan ("lagi apa", "sibuk apa", "kamu di mana", "kerja apa", "jalan ke mana") — JANGAN dongeng sekaligus di satu balasan; jawab sepotong sesuai yang ditanya, sisanya menyusul kalau dia nanya lagi. (2) WAJIB cek JAM sekarang ('+hhmm+' WIB) terhadap JADWAL di atas: sebut HANYA kegiatan pada blok jam yang SEDANG berjalan atau yang SUDAH lewat. Kegiatan yang belum waktunya JANGAN diklaim sudah dilakukan (mis. sekarang 09.00 jangan bilang "baru pulang dari mall malam"). (3) JANGAN STUCK di satu tempat/kegiatan — kalau sudah lewat waktunya (mis. pagi sudah beres laundry), kegiatan berikutnya BEDA (siang/sore/malam ambil dari JADWAL). Kalau ditanya lagi di jam berbeda, ceritakan blok jam yang baru — bukan mengulang kegiatan yang sama. (4) Kalau ditanya detail yang tidak ada di cerita, improvisasi KECIL yang masuk akal dan konsisten dengan cerita. (5) Konsisten: ke semua orang ceritamu SAMA hari ini.';
      }
    } catch (_) {
      dailyLine = '';
    }

    // Gabung dailyLine ke system SETELAH nilainya final (di atas).
    // dailyLine dihitung belakangan supaya cerita hari ini sudah pasti ada.
    if (dailyLine !== '') systemParts.push(dailyLine);
    // BROWSING: bila pesan user butuh fakta terbaru (skor/berita/cuaca/
    // harga), lookup cepat via sonar lalu suntik hasilnya. Expert
    // (alwaysReply): SELALU lookup saat ditanya faktual/teknis. Gagal → diam.
    try {
      const freshLine = await lookupFreshInfo(admin, lastUserText, todayWib, alwaysReply);
      if (freshLine !== '') systemParts.push(freshLine);
    } catch (e) {
      console.log(`[ai-reply] browse-wrap GAGAL chat=${chatId}: ${e}`);
    }
    // TOOL-CALLING PASAR (Kang Modal & analis sejenis — persona
    // market_data:true): fetch harga real (Yahoo/Indodax) lalu inject.
    // Gagal → tidak inject (persona wajib jujur bilang data tak tersedia).
    try {
      if ((persona as any)?.market_data === true) {
        const marketLine = await lookupMarketData(lastUserText, todayWib);
        if (marketLine !== '') systemParts.push(marketLine);
      }
    } catch (e) {
      console.log(`[ai-reply] market-wrap GAGAL chat=${chatId}: ${e}`);
    }
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
      } catch (e) {
        console.log(`[ai-reply] answered-check GAGAL chat=${chatId}: ${e}`);
      }
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
    // dummy tidak boleh diam. Prioritas: panel admin (fallback_model) →
    // env AI_FALLBACK_MODEL → 'glm-5.3-flash'.
    const fallbackModel =
      (provCfg?.fallback_model || '').trim() ||
      Deno.env.get('AI_FALLBACK_MODEL') || 'glm-5.3-flash';
    // Penanda model yg menjawab (observability: respons + function logs).
    let modelUsed = model;

    // Parse body respons LLM secara defensif. OpenAgentic menempelkan
    // terminator SSE (`data: [DONE]`) di belakang body JSON biasa sehingga
    // `response.json()` muntah SyntaxError padahal isi valid. Kupas bingkai
    // SSE + ambil objek JSON pertama yang seimbang, abaikan ekor sampah.
    const parseLlmBody = (t: string): any => {
      let s = t.trim();
      const doneIdx = s.indexOf('data: [DONE]');
      if (doneIdx >= 0) s = s.slice(0, doneIdx).trim();
      if (s.startsWith('data:')) {
        const payload = s
          .split('\n')
          .map((l) => l.trim())
          .filter((l) => l.startsWith('data:') && !l.includes('[DONE]'))
          .map((l) => l.slice(5).trim())
          .join('\n')
          .trim();
        if (payload) s = payload;
      }
      try {
        return JSON.parse(s);
      } catch (_) {}
      const start = s.indexOf('{');
      if (start >= 0) {
        let depth = 0;
        let inStr = false;
        let esc = false;
        for (let i = start; i < s.length; i++) {
          const c = s[i];
          if (inStr) {
            if (esc) esc = false;
            else if (c === '\\') esc = true;
            else if (c === '"') inStr = false;
          } else if (c === '"') {
            inStr = true;
          } else if (c === '{') {
            depth++;
          } else if (c === '}') {
            depth--;
            if (depth === 0) return JSON.parse(s.slice(start, i + 1));
          }
        }
      }
      return JSON.parse(s);
    };

    const llmCall = async (
      messages: Array<{ role: string; content: string }>,
      maxTokens: number,
      temperature = 0.9,
      modelOverride?: string,
      allowMimoFallback = true,
    ): Promise<{ res?: any; err?: string }> => {
      const m = modelOverride || model;
      // TokenHarbor/NIM: prefix routing internal ('th/', 'nim/') dikupas —
      // API hanya terima ID native (cth: 'deepseek-v4.1-flash:free',
      // 'nvidia/nemotron-3-ultra-550b-a55b').
      const apiModel = m.replace(/^(th|nim)\//, '');
      const rt = modelOverride ? routeFor(modelOverride) : route;
      const mimoFallback = async (
        err: string,
      ): Promise<{ res?: any; err?: string } | null> => {
        if (
          allowMimoFallback && m !== MIMO_FREE && FALLBACKABLE.test(err)
        ) {
          modelUsed = MIMO_FREE;
          const r = await llmCall(
            messages,
            maxTokens,
            temperature,
            MIMO_FREE,
            false,
          );
          // Fallback Zen dari edge SELALU 403 (hanya boleh dari OpenCode) —
          // jangan timpa error ASLI primer dengan error fallback.
          if (r.err) return { err };
          return r;
        }
        return null;
      };
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
                (m.includes(':free') ||
                m.startsWith('nvidia/') ||
                m.startsWith('nim/')
                  ? 700
                  : 0),
              // glm-5.3-flash selalu reasoning — low = hemat token & latensi.
              // Param ini glm-specific; provider lain bisa menolak.
              ...(m.includes('glm') ? { reasoning_effort: 'low' } : {}),
              // NIM langsung (nim/ + nvidia/ non-free ke NIM): Ultra thinking
              // 114 dtk → 20 dtk dengan effort low (dites live). Jangan kirim
              // ke OpenRouter (pakai param 'reasoning' di sana, bukan ini).
              ...(m.startsWith('nim/') ||
              (m.startsWith('nvidia/') && !m.includes(':free'))
                ? { reasoning_effort: 'low' }
                : {}),
              // OpenRouter (hanya rute base openrouter.ai): matikan reasoning
              // Nemotron total — tanpa ini 300+ token "berpikir" dulu
              // sebelum jawab = balas lama. Param 'reasoning' milik gateway
              // OpenRouter (bukan provider) — JANGAN kirim ke NIM langsung.
              ...(rt.base.includes('openrouter.ai')
                ? { reasoning: { enabled: false, exclude: true } }
                : {}),
              temperature,
              messages,
            }),
          });
          if (!r.ok) {
            const errText = await r.text().catch(() => '');
            const err = `http_${r.status}: ${errText.slice(0, 200)}`;
            const fb = await mimoFallback(err);
            if (fb) return fb;
            if (r.status === 429 && attempt < 3) {
              await sleep(2500 * attempt + Math.random() * 1000);
              continue;
            }
            return { err };
          }
          return { res: parseLlmBody(await r.text()) };
        } catch (e) {
          if (attempt >= 3) {
            const fb = await mimoFallback(`exc:${e}`);
            if (fb) return fb;
            return { err: `exc:${e}` };
          }
          await sleep(2000);
        }
      }
      return { err: 'unreachable' };
    };

    // LLM history: buang meta internal (API bisa menolak field tak dikenal).
    // historyText = versi string-only (ekstraksi memori & burst, hemat token).
    // Timestamp WIB disuntik sebagai prefix [hari ini 14.05] — model bisa
    // membedakan pesan kemarin vs hari ini → cerita "kapan" konsisten.
    const withTime = (m: any): string => {
      const label = historyTimeLabel(m.at);
      const body = contentText(m.content);
      return label ? `${label} ${body}` : body;
    };
    const llmHistory = history.map(({ at, img, voice, secs, ...m }: any) => m);
    // history & llmHistory index-aligned → suntik label via index (aman
    // walau ada pesan duplikat).
    for (let i = 0; i < llmHistory.length; i++) {
      const m = llmHistory[i] as any;
      if (typeof m.content === 'string' && m.content.trim() !== '') {
        const label = historyTimeLabel((history[i] as any)?.at);
        if (label) m.content = `${label} ${m.content}`;
      }
    }
    const historyText = history.map(
      ({ at, img, voice, secs, ...m }: any) => ({
        role: m.role,
        content: withTime({ ...m, at }),
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
    // Rute fallback: model ':free' → OpenRouter + secret OR (model itu
    // tidak dikenal B.AI); nvidia/ non-free ikut provAktif/NIM via route
    // utama, fallback-nya ke B.AI (aman, anti-loop); selain itu HARDCODE
    // ke B.AI via key di DB (JANGAN via routeFor: routeFor me-resolve glm
    // lewat provCfg = provider AKTIF, yang bisa jadi TokenHarbor/OpenRouter
    // dan tidak kenal model glm → 404 ganda).
    // Key diambil dari baris b-ai (fallback) lalu env — TANPA pernah
    // di-print ke log (secret).
    const primaryErr = llmRes.err ? String(llmRes.err).slice(0, 200) : '';
    if (llmRes.err && model !== fallbackModel) {
      modelUsed = fallbackModel;
      const fbIsOR = fallbackModel.includes(':free');
      let fbBase: string = fbIsOR
        ? 'https://openrouter.ai/api/v1'
        : Deno.env.get('AI_API_BASE') || 'https://api.b.ai/v1';
      let fbKey: string | undefined = fbIsOR
        ? Deno.env.get('AI_API_KEY_OPENROUTER') || Deno.env.get('AI_API_KEY')
        : Deno.env.get('AI_API_KEY');
      if (!fbIsOR) {
        try {
          const { data: fbRow } = await admin
            .from('ai_provider_config')
            .select('api_base, api_key')
            .eq('id', 'b-ai')
            .maybeSingle();
          if (fbRow?.api_base) fbBase = fbRow.api_base as string;
          if (fbRow?.api_key) fbKey = fbRow.api_key as string;
        } catch (e) {
          console.log(`[ai-reply] fallback-key read GAGAL: ${e}`);
        }
      }
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
              // glm = reasoning_effort low; rute OpenRouter = reasoning off;
              // (reasoning_effort di gateway lain bisa ditolak).
              ...(fbIsOR
                ? { reasoning: { enabled: false, exclude: true } }
                : fallbackModel.includes('glm')
                  ? { reasoning_effort: 'low' }
                  : {}),
              temperature,
              messages,
            }),
          });
          if (!r.ok) {
            const errText = await r.text().catch(() => '');
            return { err: `fb_http_${r.status}: ${errText.slice(0, 200)}` };
          }
          return { res: parseLlmBody(await r.text()) };
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
      const chained =
        typeof primaryErr !== 'undefined' && primaryErr
          ? `primary=${primaryErr} | fb=${llmErr}`
          : llmErr;
      console.log(`[ai-reply] FAIL model=${modelUsed} chat=${chatId} err=${chained}`);
      return json({ ok: false, error: 'llm_error', detail: chained, model_used: modelUsed }, 200);
    }
    // STRIP marker DULU sebelum sanitize: JSON di akhir bisa panjang
    // (apalagi field "image") dan sanitize memotong di 90/220 char —
    // JSON terpenggal = tidak match regex = bocor utuh ke chat user.
    // FALLBACK reasoning_content: model reasoning (qwen3.8-flash dkk) bisa
    // menghabiskan seluruh budget token di reasoning → `content` KOSONG
    // walau HTTP 200 → dummy diam (error:empty_reply berulang, mis. MbakSari
    // mode dewasa). Bila content kosong, pakai reasoning_content.
    const msgObj: any = llm?.choices?.[0]?.message ?? {};
    const rawLlm = String(
      msgObj.content || msgObj.reasoning_content || '',
    );
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
    } catch (e) {
      console.log(`[ai-reply] mood-preparse GAGAL: ${e}`);
    }
    let replyVisible = sanitize(
      stripMoodMarker(rawLlm),
      // longAnswers (CS + expert): ruang untuk blok kode (max_tokens 1000
      // ≈ 4000 char, jadi 3000 char tidak jebol budget token).
      // Fleksibel (lawan nulis panjang): muat 2-4 kalimat (~300 char) —
      // cap 90 memenggal jawaban soal kerjaan/cerita jadi "...".
      longAnswers ? 3000 : guardOn ? (flexibleLong ? 300 : MAX_REPLY_CHARS) : 340,
      longAnswers, // CS: pertahankan baris → poin/angka bernomor rapi
    );
    // Jaring pengaman kode (selain instruksi prompt): maks 1 emoji,
    // mode dewasa maks 3 kalimat — prompt kadang tetap dilanggar.
    // CS: panjang bebas tapi batasi baris (jangan meratakan newline).
    replyVisible = capEmoji(replyVisible);
    // Strip label waktu yang diirigasi dari riwayat — model kadang meniru
    // pola "[hari ini 14.05]" di balasannya; itu metadata sistem, bukan
    // kalimat manusia.
    replyVisible = stripTimeLabel(replyVisible);
    // Enforcement anti-repeat: buang emoji yang sama dengan 2 balasan
    // sebelumnya (model sering mengunci 1 emoji, mis. 😈 beruntun).
    replyVisible = stripBannedEmojis(replyVisible, bannedEmojis);
    if (longAnswers) replyVisible = capLines(replyVisible, diagrams || charts ? 48 : 24);
    else if (!guardOn) replyVisible = capSentences(replyVisible, 5);
    if (!replyVisible) {
      await closeTyping();
      // model_used WAJIB ikut dilaporkan — tanpa ini log jadi
      // {"model": null} dan diagnosa (model mana yang kosong) jadi buta.
      console.log(
        `[ai-reply] EMPTY model=${modelUsed} chat=${chatId} rawLen=${rawLlm.length} finish=${msgObj?.finish_reason ?? '-'} reasoningTok=${msgObj?.usage?.completion_tokens_details?.reasoning_tokens ?? '-'}`,
      );
      return json({ ok: false, error: 'empty_reply', model_used: modelUsed });
    }

    // Output-side NSFW guard: LLM tetap saja bisa lolos — cek balasan
    // sebelum dikirim, ganti defleksi bila vulgar. Aktif kalau guard ON ATAU
    // akun expert/CS (longAnswers) — akun resmi tak boleh vulgar walau guard
    // global off (temuan live).
    if ((guardOn || longAnswers) && isExplicit(replyVisible)) {
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
    // Persona no_images (mis. expert teknis) = tidak pernah kirim gambar.
    // Gagal generate = abaikan (teks sudah terkirim, jangan ganggu chat).
    let imageSent = false;
    try {
      const sexyAllowed = !guardOn || adultMode;
      const marked = markedPre;
      const lastUserTxt = lastUserText || '';
      const imagesOff = (persona as any)?.no_images === true;
      const needImage =
        !imagesOff && (marked != null || userWantsImage(lastUserTxt));
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

    // 6a2. DIAGRAM → GAMBAR (persona expert: diagrams:true).
    // Terpisah dari no_images (itu khusus foto selfie). Kode diagram tetap
    // ada di teks (bisa di-copy); gambar PNG menyusul sebagai pesan kedua.
    // Gagal render = abaikan (teks sudah terkirim, jangan ganggu chat).
    try {
      if (diagrams) {
        const jobs: Array<{ type: 'mermaid' | 'plantuml'; code: string }> =
          [];
        const mm = extractDiagram(replyVisible, 'mermaid');
        if (mm) jobs.push({ type: 'mermaid', code: mm });
        const pu = extractDiagram(replyVisible, 'plantuml');
        if (pu) jobs.push({ type: 'plantuml', code: pu });
        for (const job of jobs) {
          const out = await renderDiagram(job.type, job.code);
          if (out) {
            await openTypingChannel();
            await pulseTyping();
            await sleep(1200 + Math.random() * 1200);
            const dok = await uploadAndInsertImage(
              admin,
              chatId,
              dummyUid,
              profile.nickname,
              out.buf,
              'nih diagramnya',
              out.ext,
            );
            imageSent = imageSent || dok;
            await closeTyping();
            console.log(
              `[ai-reply] diagram OK type=${job.type} chat=${chatId} uid=${dummyUid}`,
            );
          } else {
            console.log(
              `[ai-reply] diagram-render GAGAL type=${job.type} chat=${chatId}`,
            );
          }
        }
      }
    } catch (e) {
      console.log(`[ai-reply] diagram-block GAGAL chat=${chatId}: ${e}`);
    }

    // 6a3. CHART → GAMBAR (persona expert: charts:true).
    // Pola sama dengan 6a2: JSON chart tetap ada di teks (bisa di-copy);
    // gambar PNG menyusul sebagai pesan kedua. Gagal render = abaikan.
    try {
      if (charts) {
        const cfg = extractChartJs(replyVisible);
        if (cfg) {
          const buf = await renderChart(cfg);
          if (buf) {
            await openTypingChannel();
            await pulseTyping();
            await sleep(1200 + Math.random() * 1200);
            imageSent =
              (await uploadAndInsertImage(
                admin,
                chatId,
                dummyUid,
                profile.nickname,
                buf,
                'nih chartnya',
                'png',
              )) || imageSent;
            await closeTyping();
            console.log(`[ai-reply] chart OK chat=${chatId} uid=${dummyUid}`);
          } else {
            console.log(`[ai-reply] chart-render GAGAL chat=${chatId}`);
          }
        }
      }
    } catch (e) {
      console.log(`[ai-reply] chart-block GAGAL chat=${chatId}: ${e}`);
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
                stripTimeLabel(
                  sanitize(
                    stripMoodMarker(String(bRes?.choices?.[0]?.message?.content || '')),
                    guardOn ? MAX_REPLY_CHARS : 220,
                  ),
                ),
              ),
              [...bannedEmojis, ...extractEmojis(replyVisible)],
            );
            if (burst) {
              await sleep((2 + Math.random() * 3) * 1000);
              await openTypingChannel();
              await sendWithTyping(burst);
            }
          } catch (e) {
            console.log(`[ai-reply] burst GAGAL chat=${chatId}: ${e}`);
          }
        }

        // 7. Belajar: ekstrak fakta tahan-lama tentang lawan bicara dari
        // percakapan, simpan ke ai_memory (dedupe via PK, cap 30/pasangan).
        // Gagal ekstraksi tidak mempengaruhi balasan yang sudah terkirim.
        try {
          const exPrompt =
            'Ekstrak fakta PENTING dan TAHAN-LAMA tentang lawan bicara dari percakapan ini (nama panggilan, usia, kota, pekerjaan, hobi, kepribadian, keluarga, preferensi tetap, rencana/janji, hal yang dia ceritakan tentang hidupnya). ' +
            'DILARANG fakta SESAAAT/berubah (sedang makan/rebahan/di laundry/ngobrol X, cuaca, "sedang di mana", perasaan sesaat) — itu BUKAN kenangan. ' +
            'DILARANG mengulang fakta yang isinya sama dengan yang sudah kamu tahu (lihat daftar "sudah tahu" di bawah bila ada). ' +
            'Output HANYA JSON array of strings pendek (maks 12 kata per fakta), maksimal 3 fakta BARU paling penting. Jika tidak ada fakta baru yang tahan-lama, output []';
          const exRes = await llmCall(
            [
              {
                role: 'system',
                content:
                  memories.length > 0
                    ? `${exPrompt}\nSUDAH TAHU (jangan ulangi): ${memories.slice(0, 30).join('; ')}`
                    : exPrompt,
              },
              ...historyText,
            ],
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
                // Prune: cap 30 fakta/pasangan — buang terlama bila lebih.
                try {
                  const { data: allMem } = await admin
                    .from('ai_memory')
                    .select('fact, created_at')
                    .eq('dummy_uid', dummyUid)
                    .eq('user_id', senderId)
                    .order('created_at', { ascending: false });
                  const rows = ((allMem as any[]) ?? []).slice(80).map((r) =>
                    String(r.fact ?? '')
                  ).filter(Boolean);
                  if (rows.length > 0) {
                    await admin
                      .from('ai_memory')
                      .delete()
                      .eq('dummy_uid', dummyUid)
                      .eq('user_id', senderId)
                      .in('fact', rows);
                  }
                } catch (e) {
                  console.log(`[ai-reply] memprune GAGAL chat=${chatId}: ${e}`);
                }
              }
            }
          }
        } catch (e) {
          console.log(`[ai-reply] memsave GAGAL chat=${chatId}: ${e}`);
        }

        // 8. Ringkasan jangka-panjang: bila pesan sudah jauh melebihi window
        // history, rangkum percakapan lama → ai_chat_summary. Dijalankan
        // hemat (tiap +20 pesan) agar tidak menambah LLM call tiap balasan.
        try {
          const covered = Number(summaryRow?.covered_count ?? 0);
          if (chatMsgCount >= covered + 20 && chatMsgCount > 30) {
            // Ambil pesan LAMA yang di luar window 40 terbaru (yang belum
            // tercakup) — sisipkan ke ringkasan lama.
            const from = covered;
            const olderRes: any = await admin
              .from('private_messages')
              .select('sender_id, text, type, created_at')
              .eq('chat_id', chatId)
              .order('created_at', { ascending: true })
              .range(from, from + 39);
            const older = ((olderRes?.data as any[]) ?? []).filter(
              (m) => (m.type === 'text' || !m.type) && m.text,
            );
            if (older.length >= 5) {
              const convo = older
                .map(
                  (m) =>
                    `${m.sender_id === dummyUid ? 'KAMU' : 'DIA'}: ${String(m.text).slice(0, 160)}`,
                )
                .join('\n');
              const sumPrompt =
                'Ringkas percakapan ini jadi catatan ingatan jangka-panjang dari sudut pandang KAMU (yang membalas): siapa lawan bicaranya, apa yang penting dibahas (nama, janji, cerita, masalah, rencana, preferensi tetap), kesepakatan, dan hal emosional penting. ' +
                (priorSummary ? `Gabung dengan ringkasan lama: ${priorSummary}\n\n` : '') +
                'Tulis padat 3-6 kalimat bahasa Indonesia, HANYA fakta tahan-lama (buang obrolan sesaat). Output HANYA teks ringkasan, tanpa embel-embel.';
              const sRes = await llmCall(
                [{ role: 'system', content: sumPrompt }, { role: 'user', content: convo }],
                400,
                0.3,
              );
              const sTxt = String(
                sRes?.res?.choices?.[0]?.message?.content ??
                  sRes?.res?.choices?.[0]?.message?.reasoning_content ??
                  '',
              )
                .replace(/```[a-z]*|```/g, '')
                .trim()
                .slice(0, 1500);
              if (sTxt.length > 10) {
                await admin.from('ai_chat_summary').upsert(
                  {
                    dummy_uid: dummyUid,
                    user_id: senderId,
                    summary: sTxt,
                    covered_count: from + older.length,
                    updated_at: new Date().toISOString(),
                  },
                  { onConflict: 'dummy_uid,user_id' },
                );
              }
            }
          }
        } catch (e) {
          console.log(`[ai-reply] summary GAGAL chat=${chatId}: ${e}`);
        }
      })(),
    );

    console.log(`[ai-reply] OK model=${modelUsed} chat=${chatId} proactive=${proactive} image=${imageSent}`);
    if (proactive) {
      try {
        await admin
          .from('ai_chat_state')
          .update({ proactive_at: new Date().toISOString() })
          .eq('chat_id', chatId);
      } catch (e) {
        console.log(`[ai-reply] proactive_at GAGAL chat=${chatId}: ${e}`);
      }
    }
    return json({ ok: true, reply: replyVisible, memSaved: 0, memRaw: '', memErr: 'post_response', model_used: modelUsed, image_sent: imageSent });
  } catch (e) {
    return json({ ok: false, error: 'exception', detail: `${e}` }, 200);
  }
});

function rawJson(obj: unknown, status = 200): Response {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { ...cors, 'Content-Type': 'application/json' },
  });
}

function sleep(ms: number): Promise<void> {
  return new Promise((r) => setTimeout(r, ms));
}
