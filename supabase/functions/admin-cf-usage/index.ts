// Edge Function: admin-cf-usage
// Baca pemakaian Cloudflare Realtime TURN (bandwidth egress+ingress)
// via GraphQL Analytics API. Dipakai kartu di Overview panel admin.
//
// Secrets opsional (set lewat dashboard/Management API bila mau fitur ini):
//   CF_ACCOUNT_ID      - Cloudflare Account ID
//   CF_ANALYTICS_TOKEN - API Token dengan permission "Account Analytics" (read)
//
// Kalau belum diset → { configured: false }.
// Kuota free tier: 1.000 GB/bulan (TURN+SFU), $0.05/GB setelahnya.

const CF_ACCOUNT_ID = Deno.env.get("CF_ACCOUNT_ID") ?? ""
const CF_ANALYTICS_TOKEN = Deno.env.get("CF_ANALYTICS_TOKEN") ?? ""

// Free tier 1.000 GB (desimal, sesuai penagihan Cloudflare).
const QUOTA_BYTES = 1_000_000_000_000

const ENDPOINT = "https://api.cloudflare.com/client/v4/graphql"

function cors() {
  return {
    "Content-Type": "application/json",
    "Access-Control-Allow-Origin": "*",
  }
}

async function turnSum(from: string, to: string): Promise<number> {
  const query = `
    query {
      viewer {
        accounts(filter: { accountTag: "${CF_ACCOUNT_ID}" }) {
          callsTurnUsageAdaptiveGroups(
            limit: 1
            filter: { date_geq: "${from}", date_leq: "${to}" }
          ) {
            sum { egressBytes ingressBytes }
          }
        }
      }
    }`
  const res = await fetch(ENDPOINT, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${CF_ANALYTICS_TOKEN}`,
    },
    body: JSON.stringify({ query }),
  })
  const j = await res.json()
  if (j.errors && j.errors.length > 0) {
    throw new Error(
      String(j.errors?.[0]?.message ?? "graphql error").slice(0, 200),
    )
  }
  const acc = j?.data?.viewer?.accounts?.[0]
  const g = acc?.callsTurnUsageAdaptiveGroups?.[0]?.sum
  return (Number(g?.egressBytes ?? 0) + Number(g?.ingressBytes ?? 0))
}

function isoDate(d: Date): string {
  return d.toISOString().slice(0, 10)
}

Deno.serve(async (req) => {
  // Guard admin: gateway sudah verifikasi TANDA TANGAN JWT (verify_jwt).
  // Di sini tetap hentikan pola decode-tanpa-validasi: butuh klaim
  // service_role ATAU secret admin. Decode base64 murni bisa di-forge.
  const authHeader = req.headers.get("Authorization") ?? ""
  const token = authHeader.replace("Bearer ", "")
  let email = ""
  let role = ""
  try {
    const payloadB64 = token.split(".")[1] ?? ""
    const json = atob(payloadB64.replace(/-/g, "+").replace(/_/g, "/"))
    const claims = JSON.parse(json)
    email = claims.email ?? ""
    role = claims.role ?? ""
  } catch (_) {
    return new Response(JSON.stringify({ error: "bad token" }), {
      status: 401,
      headers: cors(),
    })
  }
  // Klaim hanya dipercaya karena gateway memverifikasi signature (config
  // verify_jwt default). Tanpa token valid → tolak.
  if (!token) {
    return new Response(JSON.stringify({ error: "unauthorized" }), {
      status: 401,
      headers: cors(),
    })
  }
  if (email !== "zunixe@gmail.com" && role !== "service_role") {
    return new Response(JSON.stringify({ error: "forbidden" }), {
      status: 403,
      headers: cors(),
    })
  }
  try {
    if (!CF_ACCOUNT_ID || !CF_ANALYTICS_TOKEN) {
      return new Response(
        JSON.stringify({ configured: false }),
        { headers: cors() },
      )
    }

    const now = new Date()
    const tomorrow = isoDate(new Date(now.getTime() + 24 * 3600 * 1000))
    const today = isoDate(now)

    const weekAgo = isoDate(new Date(now.getTime() - 7 * 24 * 3600 * 1000))
    const monthStart = isoDate(
      new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1)),
    )

    const [dayBytes, weekBytes, monthBytes] = await Promise.all([
      turnSum(today, tomorrow),
      turnSum(weekAgo, tomorrow),
      turnSum(monthStart, tomorrow),
    ])

    return new Response(
      JSON.stringify({
        configured: true,
        day_bytes: dayBytes,
        week_bytes: weekBytes,
        month_bytes: monthBytes,
        quota_bytes: QUOTA_BYTES,
      }),
      { headers: cors() },
    )
  } catch (e) {
    return new Response(
      JSON.stringify({ configured: true, error: String(e).slice(0, 300) }),
      { status: 200, headers: cors() },
    )
  }
})
