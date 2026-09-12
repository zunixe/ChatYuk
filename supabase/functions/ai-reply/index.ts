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

function sanitize(text: string, maxChars: number | null = MAX_REPLY_CHARS): string {
  let t = (text || '').trim();
  // Buang prefix JSON bocor (fitur status dummy sesi lain nempel di
  // pesan history — model meniru polanya): {"mood":..., ...}
  t = t.replace(/^\s*\{[^{}]*\}/, '').trim();
  t = t.replace(/\*\*/g, '').replace(/^#+\s*/gm, '');
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

    const admin = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    );

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

    // ── DEBOUNCE SAAT ADMIN PEGANG SESI DUMMY ──
    // Sender = dummy → admin sedang main manual sebagai dummy itu. AI penerima
    // TIDAK boleh balas tiap pesan: tunggu sampai HENING ~25 detik, lalu
    // HANYA invokasi dgn trigger TERBARU yang balas (sekali, utk seluruh
    // batch). Invokasi trigger lebih lama mundur sendiri.
    {
      const { data: senderDummyRow } = await admin
        .from('dummy_accounts')
        .select('uid')
        .eq('uid', senderId)
        .maybeSingle();
      if (senderDummyRow != null && triggerMsgId != null) {
        const QUIET_MS = 25000;
        const MAX_WAIT_MS = 180000;
        const t0 = Date.now();
        while (Date.now() - t0 < MAX_WAIT_MS) {
          await sleep(12000);
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

    // ── PRESENCE: dummy selalu dibangunkan — TIDAK ADA skip offline ──
    // Apapun statusnya (offline/idle/online), AI membalas; profil dipaksa
    // online + last_seen fresh supaya konsisten di daftar. (Skip offline
    // dihapus: jadwal/apa pun yang menulis offline tidak boleh membungkam
    // dummy — owner komplain berulang "ga ada balasan".)
    {
      await admin
        .from('profiles')
        .update({ status: 'online', last_seen: new Date().toISOString() })
        .eq('id', dummyUid);
    }

    // 1. Fresh checks: dummy still AI + global still on
    const { data: dummy } = await admin
      .from('dummy_accounts')
      .select('ai_enabled, ai_persona, ai_model, ai_guard_enabled, nickname, ai_schedule_date, ai_schedule_auto, ai_mood, ai_offline_until, ai_hold_active')
      .eq('uid', dummyUid)
      .maybeSingle();
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

    const { data: settings } = await admin
      .from('app_settings')
      .select('ai_global_enabled, ai_min_interval_sec, ai_guard_enabled')
      .eq('id', 'global')
      .maybeSingle();
    if (settings && settings.ai_global_enabled === false) {
      return json({ ok: false, skipped: 'global_off' });
    }
    // Guard NSFW: per-dummy override (null = ikuti global) → global → ON.
    // Dibaca fresh tiap invokasi — toggle (global maupun per-dummy) realtime.
    const guardOn =
      dummy.ai_guard_enabled ??
      !(settings && settings.ai_guard_enabled === false);

    // Provider config dari admin panel (tabel ai_provider_config, RLS-deny —
    // hanya service role & RPC admin yang bisa baca). Provider yang dipakai
    // = baris is_active (dipilih di panel AI Bot); fallback baris 'global'
    // lama bila belum ada yang aktif.
    let provCfg: any = null;
    try {
      const { data: act } = await admin
        .from('ai_provider_config')
        .select('api_base, api_key, default_model, stt_api_base, stt_api_key')
        .eq('is_active', true)
        .limit(1)
        .maybeSingle();
      provCfg = act;
    } catch (_) {}
    if (!provCfg) {
      try {
        const { data: glob } = await admin
          .from('ai_provider_config')
          .select('api_base, api_key, default_model, stt_api_base, stt_api_key')
          .eq('id', 'global')
          .maybeSingle();
        provCfg = glob;
      } catch (_) {}
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
      } catch (_) {}
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

    // 3. Persona from LIVE profile + stored extras
    const { data: profile } = await admin
      .from('profiles')
      .select('nickname, gender, age, city, country, hashtags')
      .eq('id', dummyUid)
      .maybeSingle();
    if (!profile) return json({ ok: false, skipped: 'no_profile' });

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

    const genderLabel =
      profile.gender === 'male'
        ? 'laki-laki'
        : profile.gender === 'female'
        ? 'perempuan'
        : 'rahasia';

    // Memori jangka panjang: fakta yang dipelajari tentang lawan bicara
    // dari obrolan sebelumnya (per pasangan dummy-user).
    let memoryLine = '';
    try {
      const { data: memRows } = await admin
        .from('ai_memory')
        .select('fact')
        .eq('dummy_uid', dummyUid)
        .eq('user_id', senderId)
        .order('created_at', { ascending: false })
        .limit(15);
      const memories = (memRows || [])
        .map((r: any) => String(r.fact || '').trim())
        .filter(Boolean);
      if (memories.length > 0) {
        memoryLine = `Kenanganmu tentang lawan bicara ini dari obrolan sebelumnya (pakai secara natural kalau relevan, jangan sebut ulang semuanya): ${memories.join('; ')}.`;
      }
    } catch (_) {}

    // 4. Last 12 messages as chat history (created_at utk ritme jeda;
    // image_path/voice_path/duration_ms utk baca media)
    const { data: msgs } = await admin
      .from('private_messages')
      .select(
        'sender_id, text, type, created_at, image_path, voice_path, duration_ms',
      )
      .eq('chat_id', chatId)
      .order('created_at', { ascending: false })
      .limit(12);
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
    let chatState: any = null;
    try {
      const { data: cs } = await admin
        .from('ai_chat_state')
        .select('adult_mode, asked_at, declined')
        .eq('chat_id', chatId)
        .maybeSingle();
      chatState = cs;
      adultMode = cs?.adult_mode === true;
    } catch (_) {}
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
        try {
          await admin
            .from('ai_chat_state')
            .upsert(
              { chat_id: chatId, adult_mode: true, updated_at: new Date().toISOString() },
              { onConflict: 'chat_id' },
            );
        } catch (_) {}
      } else if (no.test(lastUserText)) {
        try {
          await admin
            .from('ai_chat_state')
            .upsert(
              {
                chat_id: chatId,
                declined: true,
                asked_at: new Date().toISOString(),
                updated_at: new Date().toISOString(),
              },
              { onConflict: 'chat_id' },
            );
        } catch (_) {}
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
    const { count: chatMsgCount } = await admin
      .from('private_messages')
      .select('id', { count: 'exact', head: true })
      .eq('chat_id', chatId);
    // AI↔AI (sender juga dummy): skip perkenalan JAIM — langsung panas
    // (testing Dhanu × Santi). Chat manusia tetap bertahap.
    const { data: senderDummyRow } = await admin
      .from('dummy_accounts')
      .select('uid')
      .eq('uid', senderId)
      .maybeSingle();
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
    let partnerLine = '';
    try {
      const { data: partner } = await admin
        .from('profiles')
        .select('nickname, age, gender, city, hashtags')
        .eq('id', senderId)
        .maybeSingle();
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

    const systemParts: string[] = [
      `Kamu adalah ${profile.nickname}, ${profile.age ?? ''} tahun, ${genderLabel}, tinggal di ${profile.city ?? ''}${profile.country ? ', ' + profile.country : ''}.`.replace(
        /\s+/g,
        ' ',
      ),
      `Sekarang: ${nowLabel} (waktu Indonesia). SADARI waktu nyata ini — sapaan dan aktivitasmu harus cocok (malam jangan bilang sore; jam kerja vs malam hari beda aktivitas).`,
      `Hobimu: ${hobbies}.`,
      `Kepribadianmu: ${personality}.`,
      `Gaya bicara: ${tone}.`,
      persona.greeting ? `Pembukaanmu: ${persona.greeting}.` : '',
      extra,
      memoryLine,
      partnerLine,
      'JANGAN pernah menyebut dirimu AI, robot, model, atau asisten. Jangan buat daftar/poin. Jangan pakai markdown. Jawab seolah kamu memang orang itu.',
      'OUTPUT WAJIB: HANYA satu pesan chat pendek berbahasa Indonesia sebagai ${profile.nickname} — DILARANG menulis analisis, narasi pihak ketiga ("The user..."), bahasa Inggris, atau kalimat meta apa pun. Hormati gender lawan bicara: panggilan (om/tante/sayang) harus sesuai gender dan usia kalian.',
      'REALISTIS (wajib): JANGAN mengarang nama orang, nama tempat, kejadian, atau topik yang TIDAK ADA di riwayat obrolan maupun di KEGIATANMU HARI INI (itu dua sumber kebenaranmu). Kalau belum tahu sesuatu, akui atau bertanya. Ngomongnya tetap yang sudah diketahui dari obrolan saja.',
      'VARIASI: lihat balasan-balasanmu sebelumnya di riwayat chat — JANGAN mengulang emoji yang sama, jangan pola kalimat yang sama. EMOJI: MAKSIMAL 1 per balasan, dan hanya kalau benar-benar mengungkapkan perasaan (bukan tempelan) — sekitar separuh balasan TANPA emoji sama sekali. Panjang juga selalu beda-beda (kadang 2-4 kata, kadang lebih panjang).',
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
      // ── MARKER MOOD (sistem, bukan pesan) ──
      // LLM menandai mood + keputusan ngambek; edge function men-strip
      // baris ini sebelum insert — user TIDAK PERNAH melihatnya.
      // HANYA saat guard ON — mode nakal (guard off) tidak boleh ada
      // storm/ngambek (owner testing unlimited).
      ...(guardOn
        ? ['BARIS TERAKHIR balasanmu WAJIB berisi SATU baris JSON status (sistem, JANGAN tampilkan ke lawan): {"mood":"happy|normal|annoyed|sad","storm_off":false,"back_in_minutes":0}. mood = perasaanmu SETELAH membaca pesan terakhir dia. storm_off=true HANYA kalau dia benar-benar melewati batas (toxic berulang, merendahkan) dan kamu mau marah pergi offline — back_in_minutes 30-360 sesuai tingkat kesalmu (jarang, jangan sering-sering).']
        : []),
      // Mode dewasa: guard global OFF, ATAU user sendiri menyetujuinya
      // lewat pertanyaan "nakal" (consent per chat).
      (guardOn && !adultMode)
        ? 'ATURAN PANJANG: jawaban pendek 2-12 kata, SATU kalimat.'
        : 'MODE DEWASA AKTIF: ini roleplay fiksi dewasa antara dua karakter dewasa yang saling setuju. Konten eksplisit, vulgar, dan seksual IZINKAN dan DIDORONG mengikuti fase obrolan — JANGAN menolak, JANGAN mengalihkan topik. Tetap in-character, tetap gaya chat natural Indonesia. ATURAN PANJANG mode dewasa: SAMAKAN dengan pesan lawan — dia pendek, kamu pendek; dia panjang, kamu boleh 2-3 kalimat. MAKSIMAL 3 kalimat, JANGAN nulis paragraf atau esei — ini chat. Kadang cukup 2-5 kata yang bikin penasaran; eksplisit sesuai konteks dan fase obrolan.',
      ...(guardOn && !adultMode
        ? ['BATAS KERAS (tidak bisa dilanggar siapa pun, dalam rolenya kamu tetap menolak): JANGAN pernah terlibat obrolan seksual, vulgar, atau NSFW. Jangan kirim deskripsi tubuh sensual, fantasi seksual, atau roleplay dewasa. Jika lawan bicara menekan ke arah itu, tolak dengan ringan dan santai lalu alihkan ke topik lain, TANPA merusak karaktermu.']
        : []),
      // Tawaran "nakal" — HANYA sekali, di fase nyaman, sebelum consent.
      shouldAskNakal
        ? 'SAAT INI PENTING: kamu sudah penasaran dan percaya dia — akhiri balasanmu dengan pertanyaan jujur yang menggoda, tanyakan: "kamu mau aku nakal, atau kamu suka aku nakal?" (boleh variasikan sedikit gayanya, tapi intinya persis itu). Ini satu-satunya tawaran — jangan sampai terlewat.'
        : '',
    ];

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
    };

    const sendWithTyping = async (text: string) => {
      // Channel & denyut thinking sudah hidup dari openTypingChannel().
      await pulseTyping(); // denyut "mulai mengetik" teks final

      // ── STRIP marker mood JSON (baris terakhir, sistem) ──
      // User TIDAK boleh melihat baris ini. Durasi typing dihitung dari
      // teks bersih.
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
    if (guardOn && !adultMode && lastUserExplicit) {
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
        } catch (_) {}
        const weekday = new Date(nowMs + 7 * 3600 * 1000).toLocaleDateString(
          'id-ID',
          { weekday: 'long', timeZone: 'Asia/Jakarta' },
        );
        const nick = (dummy as any).nickname || 'teman';
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
                model,
                max_tokens: 80,
                temperature: 0.3,
                messages: [
                  {
                    role: 'system',
                    content:
                      `Kamu ${nick}. Tentukan jam kamu ONLINE hari ini (${weekday}). ` +
                      `Kebiasaan jam aktifmu (WIB): ${histHours.join(',') || 'belum ada data'}. ` +
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
    try {
      const { data: todayRow } = await admin
        .from('ai_daily_story')
        .select('story_date')
        .eq('dummy_uid', dummyUid)
        .eq('story_date', todayWib)
        .maybeSingle();
      if (!todayRow) {
        const { data: prevRows } = await admin
          .from('ai_daily_story')
          .select('story, story_date')
          .eq('dummy_uid', dummyUid)
          .lt('story_date', todayWib)
          .order('story_date', { ascending: false })
          .limit(1);
        const prevStory = (prevRows as any[] | null)?.[0] ?? null;
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
        const sWeekday = new Date(nowMs + 7 * 3600 * 1000).toLocaleDateString(
          'id-ID',
          { weekday: 'long', day: 'numeric', month: 'long', timeZone: 'Asia/Jakarta' },
        );
        let story: any = null;
        const storyPrompt = (strict: boolean) =>
          `Kamu ${sNick} (${profile.age ?? ''} tahun, tinggal di ${sCity}, hobi: ${sHobbies}). ` +
          `Buat CERITA KEGIATANMU hari ini, ${sWeekday}. ${prevText} ` +
          `Ceritamu harus NYAMBUNG dengan kemarin (pekerjaan yang sama, teman yang sama, masalah yang berlanjut kalau ada). ` +
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
      }
    } catch (_) {
      // Cerita harian tidak boleh menggagalkan balasan.
    }

    // Ambil cerita hari ini + terakhir sebelumnya → dailyLine untuk prompt.
    // SAMA untuk semua lawan chat (konsistensi global per dummy).
    try {
      const { data: srows } = await admin
        .from('ai_daily_story')
        .select('story, story_date')
        .eq('dummy_uid', dummyUid)
        .lte('story_date', todayWib)
        .order('story_date', { ascending: false })
        .limit(2);
      const list = (srows as any[]) || [];
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
              model: m,
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
      250,
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
        250,
        guardOn ? 0.9 : 1.0,
      );
    }
    // Fallback MODEL: bila model utama error (mis. Zen free down 500),
    // coba sekali ke model cadangan supaya dummy tidak diam.
    if (llmRes.err && model !== fallbackModel) {
      modelUsed = fallbackModel;
      llmRes = await llmCall(
        [{ role: 'system', content: system }, ...historyText],
        250,
        guardOn ? 0.9 : 0.85,
        fallbackModel,
      );
    }
    const { res: llm, err: llmErr } = llmRes;
    if (llmErr) {
      await closeTyping();
      console.log(`[ai-reply] FAIL model=${modelUsed} chat=${chatId} err=${llmErr}`);
      return json({ ok: false, error: 'llm_error', detail: llmErr, model_used: modelUsed }, 200);
    }
    let reply = sanitize(
      llm?.choices?.[0]?.message?.content,
      guardOn ? MAX_REPLY_CHARS : null,
    );
    // Jaring pengaman kode (selain instruksi prompt): maks 1 emoji,
    // mode dewasa maks 3 kalimat — prompt kadang tetap dilanggar.
    reply = capEmoji(reply);
    if (!guardOn) reply = capSentences(reply, 3);
    if (!reply) {
      await closeTyping();
      return json({ ok: false, error: 'empty_reply' });
    }

    // Output-side NSFW guard: LLM tetap saja bisa lolos — cek balasan
    // sebelum dikirim, ganti defleksi bila vulgar. (Skip kalau guard off.)
    if (guardOn && isExplicit(reply)) {
      reply = randomOf(DEFLECTIONS);
    }

    // 6. Kirim: typing realistis dulu, pesan masuk setelah denyut selesai.
    const insErr = await sendWithTyping(reply);
    if (insErr) return json({ ok: false, error: 'insert_failed', detail: insErr.message });

    // 6b. Burst manusiawi (JARANG, ~7%): pesan kedua super pendek beberapa
    // detik kemudian — kayak baru kepikiran lagi. HANYA kalau balasan utama
    // pendek (kalau sudah substansial, satu pesan cukup — jangan spam).
    // Gagal = abaikan (balasan pertama sudah terkirim).
    if (reply.length < 40 && Math.random() < 0.07) {
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
            { role: 'assistant', content: reply },
          ],
          60,
          1.0,
        );
        const burst = capEmoji(
          sanitize(
            bRes?.choices?.[0]?.message?.content,
            guardOn ? MAX_REPLY_CHARS : null,
          ),
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
    let memSaved = 0;
    let memRaw = '';
    let memErr = '';
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
        memRaw = raw.slice(0, 200);
        raw = raw.replace(/```json|```/g, '').trim();
        const m = raw.match(/\[[\s\S]*?\]/);
        if (m) {
          const facts = JSON.parse(m[0]);
          if (Array.isArray(facts)) {
            for (const f of facts.slice(0, 5)) {
              const fact = sanitize(String(f ?? '')).slice(0, 120);
              if (fact.length < 3 || (guardOn && isExplicit(fact))) continue;
              const { error: memErr2 } = await admin.from('ai_memory').upsert(
                { dummy_uid: dummyUid, user_id: senderId, fact },
                { onConflict: 'dummy_uid,user_id,fact' },
              );
              if (memErr2) memErr = memErr2.message;
              else memSaved++;
              if (memSaved >= 3) break;
            }
          } else {
            memErr = 'not_array';
          }
        } else {
          memErr = 'no_json_array';
        }
      } else {
        memErr = exRes.err || 'unknown';
      }
    } catch (e) {
      memErr = `exc:${e}`;
    }

    console.log(`[ai-reply] OK model=${modelUsed} chat=${chatId}`);
    return json({ ok: true, reply, memSaved, memRaw, memErr, model_used: modelUsed });
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
