// Supabase Edge Function: ai-daily-life
// Cron 05:00 WIB → pre-generate cerita harian untuk SEMUA dummy AI-enabled
// yang belum punya baris hari ini. Dummy yang tidak pernah di-chat tetap
// punya kehidupan hari itu (tidak menunggu trigger chat pertama).
// Auth: header x-app-secret (APP_SHARED_SECRET) — dipanggil pg_cron.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { checkAppSecret, unauthorized } from '../_shared/auth.ts';

function json(obj: unknown, status = 200): Response {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

function extractJson(s: string): any {
  const t = s.replace(/```json|```/g, '');
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
}

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') {
    return json({ error: 'method_not_allowed' }, 405);
  }
  if (!checkAppSecret(req)) return unauthorized();
  try {
    const admin = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    );
    const nowMs = Date.now();
    const todayWib = new Date(nowMs + 7 * 3600 * 1000)
      .toISOString()
      .slice(0, 10);

    // Provider aktif (sama seperti ai-reply) — story SELALU pakai glm.
    let provCfg: any = null;
    try {
      const { data: act } = await admin
        .from('ai_provider_config')
        .select('api_base, api_key, default_model')
        .eq('is_active', true)
        .limit(1)
        .maybeSingle();
      provCfg = act;
    } catch (_) {}
    const sBase =
      provCfg?.api_base ||
      Deno.env.get('AI_API_BASE') ||
      'https://api.b.ai/v1';
    const sKey = provCfg?.api_key || Deno.env.get('AI_API_KEY');
    if (!sKey) return json({ ok: false, error: 'no_api_key' }, 500);

    // Dummy AI-enabled yang belum punya cerita hari ini.
    const { data: dummies } = await admin
      .from('dummy_accounts')
      .select('uid, ai_model')
      .eq('ai_enabled', true);
    const generated: string[] = [];
    const skipped: string[] = [];
    const failed: string[] = [];
    for (const d of (dummies as any[]) || []) {
      const uid = d.uid as string;
      try {
        const { data: todayRow } = await admin
          .from('ai_daily_story')
          .select('story_date')
          .eq('dummy_uid', uid)
          .eq('story_date', todayWib)
          .maybeSingle();
        if (todayRow) {
          skipped.push(uid);
          continue;
        }
        // Profil + cerita terakhir (kontinuitas).
        const { data: profile } = await admin
          .from('profiles')
          .select('nickname, age, city, country, hashtags')
          .eq('id', uid)
          .maybeSingle();
        const { data: prevRows } = await admin
          .from('ai_daily_story')
          .select('story, story_date')
          .eq('dummy_uid', uid)
          .lt('story_date', todayWib)
          .order('story_date', { ascending: false })
          .limit(1);
        const prevStory = (prevRows as any[] | null)?.[0] ?? null;
        const prevText = prevStory
          ? `Kemarin (${prevStory.story_date}): ${JSON.stringify(prevStory.story)}`
          : 'Ini hari pertamamu punya rutinitas tercatat — mulai yang wajar.';
        const nick = (profile as any)?.nickname ?? 'teman';
        const city =
          (profile as any)?.city || (profile as any)?.country || 'kotamu';
        const tags = Array.isArray((profile as any)?.hashtags)
          ? ((profile as any).hashtags as string[]).join(', ')
          : '';
        const hobbies = tags || 'ngobrol santai';
        const weekday = new Date(nowMs + 7 * 3600 * 1000).toLocaleDateString(
          'id-ID',
          {
            weekday: 'long',
            day: 'numeric',
            month: 'long',
            timeZone: 'Asia/Jakarta',
          },
        );
        const storyPrompt =
          `Kamu ${nick} (${(profile as any)?.age ?? ''} tahun, tinggal di ${city}, hobi: ${hobbies}). ` +
          `Buat CERITA KEGIATANMU hari ini, ${weekday}. ${prevText} ` +
          `Ceritamu harus NYAMBUNG dengan kemarin (pekerjaan yang sama, teman yang sama, masalah yang berlanjut kalau ada). ` +
          `Isi: apa pekerjaanmu hari ini + masalah/kejadian di tempat kerja, main dengan siapa, jalan-jalan ke mana (sebutkan TEMPAT NYATA yang wajar di ${city} — mall, kafe, taman, warung). ` +
          `Balas HANYA JSON valid tanpa markdown: {"summary":"1 kalimat ringkasan harimu","work":"pekerjaan + masalah hari ini","problem":"masalah/kejadian paling menonjol (boleh kosong)","activities":["kegiatan 1","kegiatan 2"],"hangout":"dengan siapa / sendiri","place":"tempat utama hari ini"}.`;
        const sr = await fetch(`${sBase}/chat/completions`, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            Authorization: `Bearer ${sKey}`,
          },
          body: JSON.stringify({
            model: 'glm-5.3-flash',
            max_tokens: 600,
            temperature: 0.8,
            reasoning_effort: 'low',
            messages: [
              { role: 'system', content: storyPrompt },
              { role: 'user', content: 'Oke, buatkan.' },
            ],
          }),
        });
        if (!sr.ok) {
          failed.push(uid);
          continue;
        }
        const sj: any = await sr.json();
        const parsed = extractJson(
          sj?.choices?.[0]?.message?.content ?? '',
        );
        if (!parsed || typeof parsed.summary !== 'string') {
          failed.push(uid);
          continue;
        }
        const story = {
          summary: String(parsed.summary).slice(0, 300),
          work: String(parsed.work ?? '').slice(0, 300),
          problem: String(parsed.problem ?? '').slice(0, 300),
          activities: Array.isArray(parsed.activities)
            ? parsed.activities.map((a: any) => String(a)).slice(0, 6)
            : [],
          hangout: String(parsed.hangout ?? '').slice(0, 200),
          place: String(parsed.place ?? '').slice(0, 200),
        };
        await admin.from('ai_daily_story').upsert(
          { dummy_uid: uid, story_date: todayWib, story },
          { onConflict: 'dummy_uid,story_date' },
        );
        generated.push(uid);
      } catch (_) {
        failed.push(uid);
      }
    }
    return json({ ok: true, date: todayWib, generated, skipped, failed });
  } catch (e) {
    return json({ ok: false, error: String(e) }, 500);
  }
});
