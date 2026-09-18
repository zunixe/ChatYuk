// Stress test ChatYuk — lapis HTTP/API (PostgREST + RPC).
// ai-reply SENGAJA dikecualikan (biaya token LLM).
//
// Jalankan:
//   k6 run --env MODE=load  scripts/stress/k6_api.js
//   k6 run --env MODE=spike scripts/stress/k6_api.js
//   k6 run --env MODE=soak  scripts/stress/k6_api.js
//
// Env wajib: SUPABASE_URL, ANON_KEY. Token user dibuat otomatis dari
// akun stress_* (lihat setup()).
import http from 'k6/http';
import { check, sleep } from 'k6';
import { Trend, Rate, Counter } from 'k6/metrics';

const URL = __ENV.SUPABASE_URL || 'https://fohcucyyejdryryoxitm.supabase.co';
const ANON = __ENV.ANON_KEY;
const MODE = __ENV.MODE || 'load';
const ACCOUNTS = parseInt(__ENV.ACCOUNTS || '50', 10);

const rpcTrend = new Trend('chatyuk_rpc_ms', true);
const errRate = new Rate('chatyuk_errors');
const rpcCalls = new Counter('chatyuk_rpc_calls');

const SCENARIOS = {
  load: {
    stages: [
      { duration: '30s', target: 50 },
      { duration: '1m', target: 100 },
      { duration: '30s', target: 200 },
      { duration: '30s', target: 0 },
    ],
  },
  spike: {
    stages: [
      { duration: '10s', target: 10 },
      { duration: '10s', target: 200 }, // lompatan
      { duration: '30s', target: 200 },
      { duration: '10s', target: 0 },
    ],
  },
  soak: {
    stages: [
      { duration: '30s', target: 50 },
      { duration: '15m', target: 50 },
      { duration: '30s', target: 0 },
    ],
  },
};

export const options = {
  scenarios: { [MODE]: { executor: 'ramping-vus', stages: SCENARIOS[MODE].stages, gracefulStop: '10s' } },
  thresholds: {
    http_req_failed: ['rate<0.02'],
    chatyuk_rpc_ms: ['p(95)<1000'],
  },
  summaryTrendStats: ['avg', 'min', 'med', 'p(90)', 'p(95)', 'max'],
};

// Ambil token untuk semua akun stress_* (login sekali per VU di setup).
export function setup() {
  const tokens = [];
  const key = __ENV.SERVICE_KEY;
  for (let i = 1; i <= ACCOUNTS; i++) {
    const email = `stress_${String(i).padStart(4, '0')}@stress.local`;
    const res = http.post(`${URL}/auth/v1/token?grant_type=password`, JSON.stringify({
      email, password: 'StressTest123!',
    }), { headers: { apikey: key, 'Content-Type': 'application/json' }, timeout: '15s' });
    try {
      const j = res.json();
      if (j && j.access_token) tokens.push(j.access_token);
    } catch (e) { /* lewatkan */ }
  }
  console.log(`setup: ${tokens.length}/${ACCOUNTS} token didapat`);
  return { tokens };
}

function hdr(token) {
  return {
    apikey: ANON,
    Authorization: `Bearer ${token}`,
    'Content-Type': 'application/json',
    Prefer: 'return=minimal',
  };
}

export default function (data) {
  if (!data.tokens.length) return;
  const token = data.tokens[(__VU + __ITER) % data.tokens.length];
  const h = hdr(token);

  // Campuran beban realistis saat app dibuka:
  const rpcs = [
    ['story_tray', {}],
    ['get_online_users', { p_limit: 100 }],
    ['list_posts', { p_scope: 'all', p_limit: 30 }],
    ['timeline_pricing', {}],
  ];
  const [fn, body] = rpcs[Math.floor(Math.random() * rpcs.length)];

  const res = http.post(`${URL}/rest/v1/rpc/${fn}`, JSON.stringify(body), {
    headers: h, timeout: '30s', tags: { name: fn },
  });
  rpcCalls.add(1);
  rpcTrend.add(res.timings.duration);
  const ok = check(res, { [`${fn} 2xx`]: (r) => r.status >= 200 && r.status < 300 });
  errRate.add(!ok);

  sleep(Math.random() * 2 + 0.5);
}
