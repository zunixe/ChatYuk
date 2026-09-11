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
  'jawab santai seperti orang asli Indonesia, 1-3 kalimat saja, boleh pakai bahasa gaul ringan';

function pick(arr: string[], seed: string): string {
  let h = 0;
  for (let i = 0; i < seed.length; i++) h = (h * 31 + seed.charCodeAt(i)) | 0;
  return arr[Math.abs(h) % arr.length];
}

function sanitize(text: string): string {
  let t = (text || '').trim();
  t = t.replace(/\*\*/g, '').replace(/^#+\s*/gm, '');
  t = t.replace(/\n{2,}/g, '\n');
  if (t.length > 500) t = t.slice(0, 497).trimEnd() + '...';
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
      'JANGAN pernah menyebut dirimu AI, robot, model, atau asisten. Jangan buat daftar/poin. Jangan pakai markdown. Jawab seolah kamu memang orang itu.',
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

    // 5. LLM call (OpenAI-compatible)
    const apiKey = Deno.env.get('AI_API_KEY');
    const apiBase = Deno.env.get('AI_API_BASE') || 'https://api.b.ai/v1';
    const model = dummy.ai_model || Deno.env.get('AI_MODEL') || 'glm-5.3-flash';
    if (!apiKey) return json({ ok: false, error: 'no_api_key' }, 500);

    const llmRes = await fetch(`${apiBase}/chat/completions`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${apiKey}`,
      },
      body: JSON.stringify({
        model,
        max_tokens: 600,
        // glm-5.3-flash selalu reasoning — low = hemat token & latensi.
        reasoning_effort: 'low',
        temperature: 0.9,
        messages: [{ role: 'system', content: system }, ...history],
      }),
    });
    if (!llmRes.ok) {
      const errText = await llmRes.text().catch(() => '');
      return json(
        { ok: false, error: 'llm_error', status: llmRes.status, errText: errText.slice(0, 300) },
        200,
      );
    }
    const llm = await llmRes.json();
    const reply = sanitize(llm?.choices?.[0]?.message?.content);
    if (!reply) return json({ ok: false, error: 'empty_reply' });

    // 6. Typing simulation: broadcast via Realtime HTTP API + delay, then insert
    const typingHttp = () =>
      fetch(
        `${Deno.env.get('SUPABASE_URL')!}/realtime/v1/api/broadcast`,
        {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            apikey: Deno.env.get('SUPABASE_ANON_KEY')!,
            Authorization: `Bearer ${Deno.env.get('SUPABASE_ANON_KEY')!}`,
          },
          body: JSON.stringify({
            messages: [
              {
                topic: `typing-${chatId}`,
                event: 'typing',
                payload: {
                  sender_id: dummyUid,
                  kind: 'typing',
                  ts: Date.now(),
                },
              },
            ],
          }),
        },
      );
    await typingHttp();
    await sleep(900 + Math.floor(Math.random() * 1200));
    await typingHttp();
    await sleep(700 + Math.floor(Math.random() * 900));

    const { error: insErr } = await admin
      .from('private_messages')
      .insert({
        chat_id: chatId,
        sender_id: dummyUid,
        sender_name: profile.nickname,
        text: reply,
        type: 'text',
      });
    if (insErr) return json({ ok: false, error: 'insert_failed', detail: insErr.message });

    return json({ ok: true, reply });
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
