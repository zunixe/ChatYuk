// Lapis 3: test realtime konkuren — buka N websocket Supabase, subscribe
// channel seperti app. Titik terlemah plan Free (limit concurrent realtime).
//
// Pakai: node scripts/stress/realtime.mjs <url> <anonKey> <N> <holdDetik>
import { createClient } from '/tmp/stress/node_modules/@supabase/supabase-js/dist/index.mjs';

const [url, anon, nStr, holdStr] = process.argv.slice(2);
const N = parseInt(nStr, 10);
const HOLD = parseInt(holdStr, 10);

const clients = [];
let subscribed = 0;
const errors = [];
const authErrors = [];

const t0 = Date.now();
for (let i = 0; i < N; i++) {
  const sb = createClient(url, anon, {
    auth: { persistSession: false, autoRefreshToken: false },
    realtime: { params: { eventsPerSecond: 5 } },
  });
  clients.push(sb);
  const ch = sb.channel(`stress-rt-${i}-${Date.now()}`);
  ch.on('postgres_changes', { event: '*', schema: 'public', table: 'private_messages' }, () => {});
  ch.subscribe((status, err) => {
    if (status === 'SUBSCRIBED') subscribed++;
    else if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT') {
      errors.push(status);
      if (err) authErrors.push(String(err).slice(0, 120));
    }
  });
}

const deadline = Date.now() + HOLD * 1000;
while (Date.now() < deadline && subscribed < N) {
  await new Promise((r) => setTimeout(r, 250));
}
const elapsed = Date.now() - t0;

console.log(`  subscribe sukses : ${subscribed}/${N}`);
console.log(`  error            : ${errors.length}${errors.length ? ' (' + errors[0] + ')' : ''}`);
if (authErrors.length) console.log(`  detail           : ${authErrors[0]}`);
console.log(`  waktu settle     : ${elapsed}ms`);
console.log(`  status           : ${subscribed === N ? 'OK' : subscribed >= N * 0.9 ? 'DEGRADED' : 'GAGAL'}`);

for (const sb of clients) { try { await sb.removeAllChannels(); } catch {} }
await new Promise((r) => setTimeout(r, 800));
process.exit(0);
