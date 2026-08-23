import { serve } from "https://deno.land/std@0.168.0/http/server.ts"

const TURN_TOKEN_ID = "TURN_TOKEN_ID_REDACTED"
const TURN_API_TOKEN = "TURN_API_TOKEN_REDACTED"

serve(async (_req) => {
  try {
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
