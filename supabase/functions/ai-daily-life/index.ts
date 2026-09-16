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
          const slice = t.slice(start, i + 1);
          try {
            return JSON.parse(slice);
          } catch (_) {
            // Repair ringan: trailing comma sebelum } / ] (khas output
            // Mimo/Zen yang hampir-valid) lalu coba sekali lagi.
            try {
              return JSON.parse(
                slice.replace(/,\s*([}\]])/g, '$1'),
              );
            } catch (_) {
              return null;
            }
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
        .select('api_base, api_key, default_model, story_model, fallback_model')
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
    // Model story = ai_provider_config.story_model → default_model →
    // 'glm-5.3-flash'. Ganti model cukup lewat panel admin, tanpa redeploy.
    const sModel =
      (provCfg?.story_model || '').trim() ||
      (provCfg?.default_model || '').trim() ||
      'glm-5.3-flash';

    // Cadangan gratis (OpenCode Zen, Mimo) bila provider utama menolak
    // (saldo $0/402, 429, 5xx). Bisa di-override dari panel admin via
    // ai_provider_config.fallback_model.
    const MIMO_FREE = (provCfg?.fallback_model || '').trim() || 'mimo-v2.5-free';
    const zenRoute = (): { base: string; key?: string; headers: Record<string, string> } => {
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
    };
    // Dummy AI-enabled yang belum punya cerita hari ini.
    // HANYA dummy biasa (kind='regular') yang punya story harian — akun
    // expert (CS/Admin Chatyuk) tidak perlu story. Kolom `kind` ada sejak
    // migrasi 20260914110000; fallback 'regular' bila null.
    const { data: dummies } = await admin
      .from('dummy_accounts')
      .select('uid, ai_model, kind')
      .eq('ai_enabled', true)
      .eq('kind', 'regular');
    const generated: string[] = [];
    const skipped: string[] = [];
    const failed: string[] = [];
    // Alasan gagal per-dummy (observability: 402/429/500/parse) — dibersihkan
    // saat dummy tsb sukses di pass berikutnya.
    const failWhy: Record<string, string> = {};
    // Sink per-pass untuk retry multi-pass (di bawah).
    let failSink: string[] = failed;

    // Proses SATU dummy (cek hari ini + profil + prev, lalu LLM + upsert).
    // Dipanggil worker pool di bawah. Format output JSON story TIDAK berubah.
    // OPT: ketiga query independen (prev tidak butuh hasil cek today —
    // hanya butuh keputusannya) → Promise.all sekaligus, hemat 1 RTT.
    const processDummy = async (uid: string): Promise<void> => {
      const [todayRes, profileRes, prevRes, dummyRes] = await Promise.all([
        admin
          .from('ai_daily_story')
          .select('story_date')
          .eq('dummy_uid', uid)
          .eq('story_date', todayWib)
          .maybeSingle(),
        admin
          .from('profiles')
          .select('nickname, age, city, country, hashtags')
          .eq('id', uid)
          .maybeSingle(),
        admin
          .from('ai_daily_story')
          .select('story, story_date')
          .eq('dummy_uid', uid)
          .lt('story_date', todayWib)
          .order('story_date', { ascending: false })
          .limit(1),
        admin
          .from('dummy_accounts')
          .select('ai_persona')
          .eq('uid', uid)
          .maybeSingle(),
      ]);
      const todayRow = (todayRes as any)?.data;
      if (todayRow) {
        skipped.push(uid);
        delete failWhy[uid];
        return;
      }
      const profile = (profileRes as any)?.data;
      const prevStory =
        (((prevRes as any)?.data as any[] | null)?.[0]) ?? null;
      const prevText = prevStory
        ? `Kemarin (${prevStory.story_date}): ${JSON.stringify(prevStory.story)}`
        : 'Ini hari pertamamu punya rutinitas tercatat — mulai yang wajar.';
      const nick = profile?.nickname ?? 'teman';
      const city = profile?.city || profile?.country || 'kotamu';
      const tags = Array.isArray(profile?.hashtags)
        ? (profile.hashtags as string[]).join(', ')
        : '';
      const hobbies = tags || 'ngobrol santai';
      const persona = ((dummyRes as any)?.data as any)?.ai_persona as any;
      // Profesi: field profession WAJIB jadi sumber utama. Fallback ke
      // personality/extra_prompt supaya dummy yang profession-nya belum
      // diisi tetap punya konteks pekerjaan (dulu kosong → model mengarang
      // "kerja kantoran" untuk semua orang, mis. MbakSari yang ART).
      const occ =
        persona?.profession?.toString()?.trim() ||
        persona?.personality?.toString()?.trim() ||
        persona?.extra_prompt?.toString()?.trim() ||
        '';
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
        `Kamu ${nick} (${profile?.age ?? ''} tahun, tinggal di ${city}, hobi: ${hobbies}). ` +
        (occ ? `Pekerjaanmu: ${occ}. ` : '') +
        `Buat CERITA KEGIATANMU hari ini, ${weekday}. ${prevText} ` +
        `Ceritamu harus NYAMBUNG dengan kemarin (pekerjaan yang sama, teman yang sama, masalah yang berlanjut kalau ada). ` +
        `VARIASI TEMPAT (wajib): tempat utama hari ini (place) HARUS BEDA dari tempat kemarin — jangan pakai tempat yang sama 2 hari berturut-turut, pilih tempat nyata lain yang wajar di ${city}. ` +
        `AKTIVITAS HARUS SESUAI PEKERJAANMU — JANGAN paksa kerja kantoran kalau pekerjaanmu bukan kantoran (mis. asisten rumah tangga ya kerja di rumah; pedagang ya jualan; mahasiswa ya kuliah; freelancer ya kerja dari mana saja). Kalau tidak punya pekerjaan tetap, isi "work" dengan kegiatan produktif nyata (kuliah, bantu usaha, kerja sampingan, urus rumah). ` +
        `Isi: apa yang kamu kerjakan hari ini + masalah/kejadian seputar itu, main dengan siapa, jalan-jalan ke mana (sebutkan TEMPAT NYATA yang wajar di ${city} — mall, kafe, taman, warung). ` +
        `TIMELINE WAJIB (ini kunci biar kamu sadar waktu): bagi harimu jadi 4 blok jam WIB — pagi (06.00-10.00), siang (10.00-15.00), sore (15.00-18.00), malam (18.00-23.00). Tiap blok HARUS kegiatan/tempat BEDA dan realistis sesuai pekerjaanmu (ART ya beres-beres/masak/belanja; pedagang ya jualan; mahasiswa ya kuliah). JANGAN taruh kegiatan yang sama di semua blok (mis. "di laundry" terus sepanjang hari = SALAH). Tempat boleh sama antar blok kalau memang wajar (mis. kerja di rumah), TAPI kegiatannya harus beda. ` +
        `Balas HANYA JSON valid tanpa markdown: {"summary":"1 kalimat ringkasan harimu","work":"pekerjaan + masalah hari ini","problem":"masalah/kejadian paling menonjol (boleh kosong)","activities":["kegiatan 1","kegiatan 2"],"hangout":"dengan siapa / sendiri","place":"tempat utama hari ini","timeline":{"pagi":"kegiatan+tempat 06.00-10.00","siang":"kegiatan+tempat 10.00-15.00","sore":"kegiatan+tempat 15.00-18.00","malam":"kegiatan+tempat 18.00-23.00"}}.`;
      // Generate cerita: primer (glm) → fallback Mimo free (Zen) saat primer
      // menolak (402/429/5xx) ATAU hasil primer tipis/gagal-parse (kasus
      // Dhanu: Mimo 200 tapi JSON tidak valid). Gagal parse/tipis → ulangi
      // sekali dengan instruksi tegas (pola sama seperti ai-reply strict).
      const strictSuffix =
        `WAJIB TANPA KECUALI: work HARUS terisi (pekerjaan + kejadian konkret hari ini), activities MINIMAL 2 kegiatan konkret, hangout HARUS terisi (dengan siapa / kalau sendiri tulis "sendiri"), place HARUS tempat SPESIFIK (nama mall/kafe/taman/warung, BUKAN cuma nama kota), timeline WAJIB ada 4 blok (pagi/siang/sore/malam) dengan kegiatan BEDA tiap blok. JANGAN kosongkan field apa pun kecuali problem.`;
      type GenRes = {
        parsed: any;
        http: number | null;
        via: string;
        rawLen: number;
        rawHead: string;
      };
      const rawOf = (j: any): string => {
        const m = j?.choices?.[0]?.message;
        const c = m?.content;
        if (typeof c === 'string' && c.length > 0) return c;
        // Zen/Mimo kadang menaruh teks di reasoning_content saat content
        // kosong — pakai sebagai cadangan sebelum menyerah.
        const rc = (m as any)?.reasoning_content;
        if (typeof rc === 'string' && rc.length > 0) return rc;
        return '';
      };
      const callPrimary = async (strict: boolean): Promise<GenRes> => {
        const prompt = strict ? `${storyPrompt} ${strictSuffix}` : storyPrompt;
        try {
          const r = await fetch(`${sBase}/chat/completions`, {
            method: 'POST',
            headers: {
              'Content-Type': 'application/json',
              Authorization: `Bearer ${sKey}`,
            },
            body: JSON.stringify({
              model: sModel,
              max_tokens: 600,
              temperature: 0.8,
              // Base OpenRouter (provider aktif): matikan reasoning Nemotron
              // (cepat + hemat token). Base lain: reasoning_effort low (glm).
              ...(sBase.includes('openrouter.ai')
                ? { reasoning: { enabled: false, exclude: true } }
                : { reasoning_effort: 'low' }),
              messages: [
                { role: 'system', content: prompt },
                { role: 'user', content: 'Oke, buatkan.' },
              ],
            }),
          });
          if (!r.ok) return { parsed: null, http: r.status, via: 'th', rawLen: 0, rawHead: '' };
          const j: any = await r.json().catch(() => null);
          const raw = rawOf(j);
          return { parsed: extractJson(raw), http: r.status, via: 'th', rawLen: raw.length, rawHead: raw.slice(0, 120) };
        } catch (_) {
          return { parsed: null, http: null, via: 'exc', rawLen: 0, rawHead: '' };
        }
      };
      const callMimo = async (strict: boolean): Promise<GenRes | null> => {
        try {
          const zr = zenRoute();
          if (!zr.key) return null;
          const prompt = strict ? `${storyPrompt} ${strictSuffix}` : storyPrompt;
          const mr = await fetch(`${zr.base}/chat/completions`, {
            method: 'POST',
            headers: {
              'Content-Type': 'application/json',
              Authorization: `Bearer ${zr.key}`,
              ...zr.headers,
            },
            body: JSON.stringify({
              model: MIMO_FREE,
              // Headroom: Mimo/Zen bisa menghabiskan token untuk reasoning
              // sebelum content — budget kecil = JSON terpotong = parse gagal.
              max_tokens: 1000,
              temperature: 0.8,
              messages: [
                { role: 'system', content: prompt },
                { role: 'user', content: 'Oke, buatkan.' },
              ],
            }),
          });
          if (!mr.ok) return { parsed: null, http: mr.status, via: 'mimo', rawLen: 0, rawHead: '' };
          const mj: any = await mr.json().catch(() => null);
          const raw = rawOf(mj);
          return { parsed: extractJson(raw), http: mr.status, via: 'mimo', rawLen: raw.length, rawHead: raw.slice(0, 120) };
        } catch (_) {
          return { parsed: null, http: null, via: 'exc', rawLen: 0, rawHead: '' };
        }
      };
      // Validasi KETAT (sama seperti storyThin ai-reply): cerita tipis =
      // tidak guna sebagai topik. summary saja tidak cukup (kasus Dhanu).
      const storyThin = (p: any): boolean => {
        if (p == null || typeof p.summary !== 'string') return true;
        if (String((p as any).work ?? '').trim() === '') return true;
        if (!Array.isArray((p as any).activities) || (p as any).activities.length < 2) return true;
        if (String((p as any).hangout ?? '').trim() === '') return true;
        const pl = String((p as any).place ?? '').trim();
        if (pl === '' || pl.toLowerCase() === city.toLowerCase()) return true;
        // Timeline 4 blok (pagi/siang/sore/malam) wajib & tiap blok terisi.
        const tl: any = (p as any).timeline;
        if (tl == null || typeof tl !== 'object') return true;
        for (const k of ['pagi', 'siang', 'sore', 'malam']) {
          if (String(tl[k] ?? '').trim() === '') return true;
        }
        return false;
      };
      let g = await callPrimary(false);
      if (storyThin(g.parsed)) {
        const gStrict = await callPrimary(true);
        if (!storyThin(gStrict.parsed)) g = gStrict;
        else {
          // Primer tipis/gagal (termasuk 200-parse-null) → coba Mimo,
          // bukan cuma saat primer HTTP-error. Lalu strict sekali lagi.
          const m1 = await callMimo(false);
          const m2 = storyThin(m1?.parsed) ? await callMimo(true) : null;
          const best = [gStrict, m1, m2].find((x) => x && !storyThin(x?.parsed));
          if (best) g = best;
          else {
            const tail = [gStrict, m1, m2]
              .filter(Boolean)
              .map((x) => `${(x as GenRes).via}:${(x as GenRes).http}:len${(x as GenRes).rawLen}:${((x as GenRes).rawHead || '').replace(/\s+/g, ' ').slice(0, 60)}`)
              .join(' | ');
            failWhy[uid] = `thin(${g.via}:${g.http}+${tail})`;
          }
        }
      }
      const parsed = storyThin(g.parsed) ? null : g.parsed;
      if (!parsed) {
        failSink.push(uid);
        return;
      }
      // Bersihkan mojibake/karakter rusak dari output model (mis. nama tempat
      // "Warung Kopi Kemen�?��??"). Penyebab: byte UTF-8 valid tapi ter-decode
      // salah — muncul U+FFFD, byte kontrol, juga A0 (non-breaking space dari
      // decode UTF-8 ganda). Rapikan spasi setelah pembersihan.
      const clean = (s: unknown): string =>
        String(s ?? '')
          .replace(/\uFFFD/g, '')            // replacement char
          .replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F]/g, '') // kontrol
          .replace(/\u00A0/g, ' ')           // nbsp
          .replace(/[ \t]{2,}/g, ' ')        // spasi ganda
          .replace(/\s+([.,!?])/g, '$1')     // spasi sebelum tanda baca
          .trim();
      const tlRaw: any = (parsed as any).timeline ?? {};
      const story = {
        summary: clean(parsed.summary).slice(0, 300),
        work: clean(parsed.work).slice(0, 300),
        problem: clean(parsed.problem).slice(0, 300),
        activities: Array.isArray(parsed.activities)
          ? parsed.activities.map((a: any) => clean(a)).slice(0, 6)
          : [],
        hangout: clean(parsed.hangout).slice(0, 200),
        place: clean(parsed.place).slice(0, 200),
        // Timeline 4 blok jam WIB — dipakai ai-reply agar kegiatan sesuai JAM.
        timeline: {
          pagi: clean(tlRaw.pagi).slice(0, 200),
          siang: clean(tlRaw.siang).slice(0, 200),
          sore: clean(tlRaw.sore).slice(0, 200),
          malam: clean(tlRaw.malam).slice(0, 200),
        },
      };
      await admin.from('ai_daily_story').upsert(
        { dummy_uid: uid, story_date: todayWib, story },
        { onConflict: 'dummy_uid,story_date' },
      );
      generated.push(uid);
      delete failWhy[uid];
    };

    // Worker pool paralel terbatas (5 concurrent) — hindari membuka ratusan
    // koneksi LLM sekaligus tapi tetap jauh lebih cepat dari serial.
    // Retry multi-pass (maks 3 pass): yang gagal di-pass awal dicoba lagi
    // sampai terisi — "coba lagi sampe terisi storynya tiap orang".
    const CONCURRENCY = 5;
    let pending: string[] = [...((dummies as any[]) || [])].map((d) => d.uid as string);
    for (let pass = 0; pass < 3 && pending.length > 0; pass++) {
      if (pass > 0) await new Promise((r) => setTimeout(r, 15000));
      const queue = pending;
      pending = [];
      failSink = [];
      const workers = Array.from(
        { length: Math.min(CONCURRENCY, queue.length) },
        async () => {
          while (queue.length > 0) {
            const uid = queue.shift()!;
            try {
              await processDummy(uid);
            } catch (_) {
              failSink.push(uid);
            }
          }
        },
      );
      await Promise.all(workers);
      pending = [...failSink];
    }
    failed.push(...pending);

    return json({ ok: true, date: todayWib, generated, skipped, failed, failedWhy: failWhy });
  } catch (e) {
    return json({ ok: false, error: String(e) }, 500);
  }
});
