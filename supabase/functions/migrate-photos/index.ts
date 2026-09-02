import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";
import { checkAppSecret, unauthorized } from "../_shared/auth.ts";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const bucket = "chat-photos";

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("Method not allowed", { status: 405 });
  // Auth: operasi massal service_role — hanya caller dengan APP_SHARED_SECRET.
  if (!checkAppSecret(req)) return unauthorized();
  const { limit = 100 } = await req.json().catch(() => ({}));
  const supabase = createClient(supabaseUrl, serviceKey);
  let migrated = 0;

  // Private messages
  const { data: privates, error: e1 } = await supabase
    .from("private_messages")
    .select("id, chat_id, image_data")
    .like("image_data", "data:%")
    .limit(limit);
  if (e1) return new Response(JSON.stringify({ error: e1.message }), { status: 500 });

  for (const row of privates ?? []) {
    try {
      const b64 = row.image_data.split(",")[1] ?? row.image_data;
      const bytes = Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
      const path = `chat/${row.chat_id}/${row.id}.jpg`;
      const { error: upErr } = await supabase.storage.from(bucket).upload(path, bytes, { contentType: "image/jpeg", upsert: true });
      if (upErr) continue;
      await supabase.from("private_messages").update({ image_path: path, image_data: "" }).eq("id", row.id);
      migrated++;
    } catch (_) {}
  }

  // Room messages
  const { data: rooms } = await supabase.from("messages").select("id, room_id, image_data").like("image_data", "data:%").limit(limit);
  for (const row of rooms ?? []) {
    try {
      const b64 = row.image_data.split(",")[1] ?? row.image_data;
      const bytes = Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
      const path = `chat/room_${row.room_id}/${row.id}.jpg`;
      const { error: upErr } = await supabase.storage.from(bucket).upload(path, bytes, { contentType: "image/jpeg", upsert: true });
      if (upErr) continue;
      await supabase.from("messages").update({ image_path: path, image_data: "" }).eq("id", row.id);
      migrated++;
    } catch (_) {}
  }

  return new Response(JSON.stringify({ migrated }), { headers: { "Content-Type": "application/json" } });
});
