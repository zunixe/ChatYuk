import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { checkAppSecret, unauthorized } from "../_shared/auth.ts"

// Kredensial Cloudflare Realtime TURN dibaca dari Edge Function Secrets
// (TURN_TOKEN_ID, TURN_API_TOKEN) — jangan hardcode di sini.
const TURN_TOKEN_ID = Deno.env.get("TURN_TOKEN_ID") ?? ""
const TURN_API_TOKEN = Deno.env.get("TURN_API_TOKEN") ?? ""

serve(async (req) => {
  // Auth: generate kredensial TURN berbiaya (TTL 24 jam) — hanya caller
  // dengan APP_SHARED_SECRET (client app membawa secret yang sama).
  if (!checkAppSecret(req)) return unauthorized()
  try {
    if (!TURN_TOKEN_ID || !TURN_API_TOKEN) {
      return new Response(JSON.stringify({ error: "TURN secrets not configured" }), { status: 500 })
    }
    const resp = await fetch(
      `https://rtc.live.cloudflare.com/v1/turn/keys/${TURN_TOKEN_ID}/credentials/generate`,
      {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${TURN_API_TOKEN}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ ttl: 86400 }),
      }
    )
    const data = await resp.json()
    return new Response(JSON.stringify(data), {
      headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" },
    })
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), { status: 500 })
  }
})
