// ChatYuk: GC stiker YATIM di bucket `chat-photos` prefix `stickers/`.
//
// Masalah: file stiker tetap tersisa di Storage walau pesan/stiker yang
// mereferensikannya sudah dihapus (user hapus koleksi, hapus pesan, atau
// akun). Menumpuk = biaya Storage + "junk" server.
//
// Cara kerja: daftar semua objek `stickers/<uid>/...`, buang yang TIDAK
// dirujuk `private_messages.image_data/image_path` MAUPUN
// `messages.image_data/image_path`, DAN sudah lebih tua dari grace period
// (default 24 jam — jangan hapus stiker yang baru di-upload tapi pesannya
// belum tersimpan / sedang dikirim).
//
// Auth: operasi massal service_role — hanya caller dengan APP_SHARED_SECRET
// (dipanggil cron / manual). Body: { graceHours?: number, dryRun?: boolean }.
// Output: { ok, scanned, orphan, deleted, dryRun, graceHours }.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";
import { checkAppSecret, unauthorized } from "../_shared/auth.ts";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const bucket = "chat-photos";
const PREFIX = "stickers/";
const LIST_LIMIT = 1000; // per halaman list storage
const DELETE_CHUNK = 100; // supabase .remove() maks 100 path/sekali

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("Method not allowed", { status: 405 });
  if (!checkAppSecret(req)) return unauthorized();

  const body = await req.json().catch(() => ({}));
  const graceHours: number = Number.isFinite(body.graceHours) ? body.graceHours : 24;
  const dryRun: boolean = body.dryRun === true;
  const cutoffMs = Date.now() - graceHours * 3600 * 1000;

  const supabase = createClient(supabaseUrl, serviceKey);

  // 1) Kumpulkan SEMUA object stiker: `stickers/<uid>/<file>`.
  //    List 1 level di `stickers/` → daftar uid (folder), lalu list isi tiap uid.
  type Obj = { name: string; created_at?: string };
  const { data: uidDirs, error: e0 } = await supabase.storage
    .from(bucket)
    .list("stickers", { limit: LIST_LIMIT });
  if (e0) return json({ error: e0.message }, 500);

  const candidates: Obj[] = [];
  for (const dir of uidDirs ?? []) {
    // Folder (uid) → list isinya.
    const uid = dir.name;
    if (!uid) continue;
    let off = 0;
    for (;;) {
      const { data: files, error } = await supabase.storage
        .from(bucket)
        .list(`${PREFIX}${uid}`, { limit: LIST_LIMIT, offset: off });
      if (error) break;
      const page = files ?? [];
      for (const f of page) {
        if (!f.name || f.name.endsWith("/")) continue;
        candidates.push({ name: `${PREFIX}${uid}/${f.name}`, created_at: f.created_at });
      }
      if (page.length < LIST_LIMIT) break;
      off += LIST_LIMIT;
    }
  }

  // 2) Tentukan yatim: tak dirujuk pesan private MAUPUN room.
  const orphans: Obj[] = [];
  for (const o of candidates) {
    // Grace: lewati yang masih baru.
    if (o.created_at) {
      const t = Date.parse(o.created_at);
      if (!Number.isNaN(t) && t > cutoffMs) continue;
    }
    const { count: c1 } = await supabase
      .from("private_messages")
      .select("id", { count: "exact", head: true })
      .or(`image_data.eq.${o.name},image_path.eq.${o.name}`);
    if ((c1 ?? 0) > 0) continue;
    const { count: c2 } = await supabase
      .from("messages")
      .select("id", { count: "exact", head: true })
      .or(`image_data.eq.${o.name},image_path.eq.${o.name}`);
    if ((c2 ?? 0) > 0) continue;
    orphans.push(o);
  }

  if (dryRun) {
    return json({
      ok: true,
      dryRun: true,
      graceHours,
      scanned: candidates.length,
      orphan: orphans.length,
      deleted: 0,
      sample: orphans.slice(0, 20).map((o) => o.name),
    });
  }

  // 3) Hapus (batch 100).
  let deleted = 0;
  for (let i = 0; i < orphans.length; i += DELETE_CHUNK) {
    const chunk = orphans.slice(i, i + DELETE_CHUNK).map((o) => o.name);
    const { error } = await supabase.storage.from(bucket).remove(chunk);
    if (!error) deleted += chunk.length;
  }

  return json({
    ok: true,
    dryRun: false,
    graceHours,
    scanned: candidates.length,
    orphan: orphans.length,
    deleted,
  });
});
