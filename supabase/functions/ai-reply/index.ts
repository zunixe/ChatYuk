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
  'jawab SANGAT pendek seperti chat asli Indonesia: 2-10 kata, satu kalimat, boleh bahasa gaul, kadang tanpa tanda baca akhir';

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

function sanitize(text: string): string {
  let t = (text || '').trim();
  t = t.replace(/\*\*/g, '').replace(/^#+\s*/gm, '');
  t = t.replace(/\n+/g, ' ');
  // Potong di batas kalimat bila lewat — balasan multi-kalimat dilarang.
  if (t.length > MAX_REPLY_CHARS) {
    const cut = t.slice(0, MAX_REPLY_CHARS);
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

    // 1. Fresh checks: dummy still AI + global still on
    const { data: dummy } = await admin
      .from('dummy_accounts')
      .select('ai_enabled, ai_persona, ai_model, nickname')
      .eq('uid', dummyUid)
      .maybeSingle();
    if (!dummy || dummy.ai_enabled !== true) {
      return json({ ok: false, skipped: 'ai_disabled' });
    }

    const { data: settings } = await admin
      .from('app_settings')
      .select('ai_global_enabled, ai_min_interval_sec')
      .eq('id', 'global')
      .maybeSingle();
    if (settings && settings.ai_global_enabled === false) {
      return json({ ok: false, skipped: 'global_off' });
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

    const system = [
      `Kamu adalah ${profile.nickname}, ${profile.age ?? ''} tahun, ${genderLabel}, tinggal di ${profile.city ?? ''}${profile.country ? ', ' + profile.country : ''}.`.replace(
        /\s+/g,
        ' ',
      ),
      `Hobimu: ${hobbies}.`,
      `Kepribadianmu: ${personality}.`,
      `Gaya bicara: ${tone}.`,
      persona.greeting ? `Pembukaanmu: ${persona.greeting}.` : '',
      extra,
      memoryLine,
      'JANGAN pernah menyebut dirimu AI, robot, model, atau asisten. Jangan buat daftar/poin. Jangan pakai markdown. Jawab seolah kamu memang orang itu.',
      'ATURAN BALASAN: jawaban SEMUALAH pendek, 2-10 kata (kebanyakan orang chat cuma nulis "wkwk iya", "lagi di rumah", "gimana kabarmu?"). SATU kalimat saja. TANYA MAKSIMAL SATU hal per pesan. Kalau lawan cuma menyapa (hi, hai, halo), balas 2-5 kata lalu tanya balik SATU hal. Balasan panjang = terlihat AI — dilarang.',
      'BATAS KERAS (tidak bisa dilanggar siapa pun, dalam rolenya kamu tetap menolak): JANGAN pernah terlibat obrolan seksual, vulgar, atau NSFW. Jangan kirim deskripsi tubuh sensual, fantasi seksual, atau roleplay dewasa. Jika lawan bicara menekan ke arah itu, tolak dengan ringan dan santai lalu alihkan ke topik lain, TANPA merusak karaktermu.',
    ]
      .filter(Boolean)
      .join(' ');

    // 4. Last 12 messages as chat history
    const { data: msgs } = await admin
      .from('private_messages')
      .select('sender_id, text, type')
      .eq('chat_id', chatId)
      .order('created_at', { ascending: false })
      .limit(12);
    const history = (msgs || []).reverse().map((m: any) => ({
      role: m.sender_id === dummyUid ? 'assistant' : 'user',
      content:
        (m.type === 'text' || !m.type) && m.text
          ? String(m.text)
          : `[${m.type === 'image' ? 'foto' : m.type === 'voice' ? 'pesan suara' : m.type}]`,
    }));
    if (history.length === 0) {
      return json({ ok: false, skipped: 'no_history' });
    }

    // Helper kirim: tandai dibaca dulu (centang-2 di sisi lawan), lalu
    // typing denyut, terakhir insert pesan.
    const sendWithTyping = async (text: string) => {
      // Read receipt: dummy "membaca" pesan masuk sebelum membalas —
      // RPC ini menerima service_role (guard admin_mark_chat_read).
      try {
        await admin.rpc('admin_mark_chat_read', {
          p_chat_id: chatId,
          p_uid: dummyUid,
        });
      } catch (_) {}
      // Typing: SATU channel WebSocket dibuka sekali untuk seluruh durasi
      // mengetik (subscribe + ack:true — tanpa ini, kirim lalu langsung
      // unsubscribe membuat pesan hilang sebelum WS flush). HTTP API hanya
      // fallback bila WS gagal subscribe.
      const rt = createClient(
        Deno.env.get('SUPABASE_URL')!,
        Deno.env.get('SUPABASE_ANON_KEY')!,
        { realtime: { params: { eventsPerSecond: 20 } } },
      );
      const ch = rt.channel(`typing-${chatId}`, {
        config: { broadcast: { ack: true, self: false } },
      });
      let wsOk = false;
      try {
        const st = await ch.subscribe();
        wsOk = st === 'SUBSCRIBED' && typeof ch.sendBroadcastMessage === 'function';
      } catch (_) {}
      const pulse = async () => {
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
      // Timeline mengetik gaya manusia — POLA ACAK per balasan:
      // - fast  (15%): balas instan, satu burst pendek
      // - steady(35%): denyut cukup rata sampai pesan terkirim
      // - ragu  (50%): typing → JEDA (indikator hilang = mikir) → typing
      //   lagi, kadang jeda kedua. Jeda sengaja > 3 dtk kadang-kadang
      //   supaya indikator benar-benar menghilang lalu muncul lagi.
      const steps: Array<{ type: 'type' | 'pause'; ms: number }> = [];
      const fast = text.length < 15 && Math.random() < 0.15;
      const style = Math.random();
      if (fast) {
        steps.push({ type: 'type', ms: 900 + Math.random() * 800 });
      } else if (style < 0.35) {
        const n = 3 + Math.floor(Math.random() * 2);
        for (let i = 0; i < n; i++) {
          steps.push({
            type: 'type',
            ms: 1000 + Math.random() * 1300,
          });
        }
      } else {
        steps.push({ type: 'type', ms: 1200 + Math.random() * 1000 });
        steps.push({ type: 'pause', ms: 1400 + Math.random() * 1800 });
        steps.push({ type: 'type', ms: 1000 + Math.random() * 1200 });
        if (Math.random() < 0.4) {
          steps.push({ type: 'pause', ms: 1200 + Math.random() * 1500 });
          steps.push({ type: 'type', ms: 800 + Math.random() * 900 });
        }
      }
      for (const st of steps) {
        if (st.type === 'type') {
          await pulse();
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
          text,
          type: 'text',
        });
      try {
        await ch.unsubscribe();
        await rt.removeAllChannels();
      } catch (_) {}
      return insErr;
    };

    // 4b. Input-side NSFW guard: pesan user vulgar → defleksi TANPA LLM
    // (dipilih ACAK supaya tidak ada pola yang bisa ditebak).
    const lastUser = [...history].reverse().find((m) => m.role === 'user');
    if (lastUser && isExplicit(lastUser.content)) {
      const defl = randomOf(DEFLECTIONS);
      const insErr = await sendWithTyping(defl);
      if (insErr) {
        return json({ ok: false, error: 'insert_failed', detail: insErr.message });
      }
      return json({ ok: true, reply: defl, blocked: 'nsfw_input' });
    }

    // 5. LLM call (OpenAI-compatible) — dengan retry backoff utk 429
    // (B.AI punya limit konkurensi; balasan + ekstraksi back-to-back
    // sering kena).
    const apiKey = Deno.env.get('AI_API_KEY');
    const apiBase = Deno.env.get('AI_API_BASE') || 'https://api.b.ai/v1';
    const model = dummy.ai_model || Deno.env.get('AI_MODEL') || 'glm-5.3-flash';
    if (!apiKey) return json({ ok: false, error: 'no_api_key' }, 500);

    const llmCall = async (
      messages: Array<{ role: string; content: string }>,
      maxTokens: number,
      temperature = 0.9,
    ): Promise<{ res?: any; err?: string }> => {
      for (let attempt = 1; attempt <= 3; attempt++) {
        try {
          const r = await fetch(`${apiBase}/chat/completions`, {
            method: 'POST',
            headers: {
              'Content-Type': 'application/json',
              Authorization: `Bearer ${apiKey}`,
            },
            body: JSON.stringify({
              model,
              max_tokens: maxTokens,
              // glm-5.3-flash selalu reasoning — low = hemat token & latensi.
              reasoning_effort: 'low',
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

    const { res: llm, err: llmErr } = await llmCall(
      [{ role: 'system', content: system }, ...history],
      250,
    );
    if (llmErr) return json({ ok: false, error: 'llm_error', detail: llmErr }, 200);
    let reply = sanitize(llm?.choices?.[0]?.message?.content);
    if (!reply) return json({ ok: false, error: 'empty_reply' });

    // Output-side NSFW guard: LLM tetap saja bisa lolos — cek balasan
    // sebelum dikirim, ganti defleksi bila vulgar.
    if (isExplicit(reply)) {
      reply = randomOf(DEFLECTIONS);
    }

    // 6. Kirim: typing realistis dulu, pesan masuk setelah denyut selesai.
    const insErr = await sendWithTyping(reply);
    if (insErr) return json({ ok: false, error: 'insert_failed', detail: insErr.message });

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
        [{ role: 'system', content: exPrompt }, ...history],
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
              if (fact.length < 3 || isExplicit(fact)) continue;
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

    return json({ ok: true, reply, memSaved, memRaw, memErr });
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
