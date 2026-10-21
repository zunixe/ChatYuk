# Instabox — Sandbox VM untuk ChatYuk

Dokumen ini menyimpan kredensial akses ke mesin instabox dan catatan setup Supabase lokal.

## Koneksi

```bash
ssh -p 2222 ibssh_pkaewaqds244ilfseabkwddeeu@api.instabox.sh
```

| Field | Value |
|---|---|
| Host | `api.instabox.sh` |
| Port | `2222` |
| User | `ibssh_pkaewaqds244ilfseabkwddeeu` |
| Host key check | `-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null` |

One-liner non-interaktif:

```bash
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -p 2222 ibssh_pkaewaqds244ilfseabkwddeeu@api.instabox.sh "<cmd>"
```

> Catatan: saat pertama connect tanpa `StrictHostKeyChecking=no` muncul `Host key verification failed`.
> Gunakan opsi di atas, atau tambahkan host key-nya permanen ke `~/.ssh/known_hosts`.

## Spesifikasi Mesin

- Hostname internal: `instabox-myagent`
- Kernel: Linux 6.18.54-instabox (x86_64)
- 4 vCPU, 8192 MiB RAM, root disk 16 GiB, `/data` 20 GiB
- Home: `/data/home` — Workspace: `/data/workspace`
- Outbound internet OK; **tidak ada port yang reachable dari internet**
- Disk `root` dan `/data` survive saat stop; snapshot hanya menyimpan root disk (kecuali `/data` root-only)

Tools terpasang: `docker` 29.8.2, `docker compose` v5.6.0, `node` v22.23.3, `npm` 10.9.9, `git`, `python3`, `tar`
Belum ada: `supabase` CLI, `psql`, `bun`, `deno`, `rsync`

## Setup Supabase Lokal (ChatYuk)

Target: jalankan Supabase lokal di instabox dari folder `chatyuk/supabase`.

### 1. Upload folder supabase

Dari lokal (macOS):

```bash
cd ~/Documents/chatyuk
tar --exclude='.temp' --exclude='node_modules' -czf /tmp/chatyuk-supabase.tar.gz supabase

ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 2222 \
    ibssh_pkaewaqds244ilfseabkwddeeu@api.instabox.sh \
    "mkdir -p /data/workspace/chatyuk && tar -xzf - -C /data/workspace/chatyuk" \
    < /tmp/chatyuk-supabase.tar.gz
```

### 2. Install Supabase CLI di instabox

```bash
npm install -g supabase
supabase --version
docker info >/dev/null && echo "docker ok"
```

### 3. Jalankan

```bash
cd /data/workspace/chatyuk/supabase
supabase start
```

`.temp/linked-project.json` di-exclude, jadi project cloud (ref `fohcucyyejdryryoxitm`) tidak ikut ter-link —
aman untuk menjalankan stack lokal tanpa menyentuh project cloud.

### 4. Akses (SSH tunnel dari laptop)

Tidak ada port publik. Akses dari lokal via SSH tunnel:

```bash
ssh -N -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 2222 \
    -L 54321:localhost:54321 -L 54322:localhost:54322 -L 54323:localhost:54323 \
    ibssh_pkaewaqds244ilfseabkwddeeu@api.instabox.sh
```

- API: `http://localhost:54321`
- Postgres: `postgresql://postgres:postgres@localhost:54322/postgres`
- Studio: `http://localhost:54323`
- Mailpit (email lokal): `http://localhost:54324`

---

## Status: BERJALAN ✅

`supabase start` sukses penuh di instabox pada 2026-10-20.

| Item | Hasil |
|---|---|
| Migrasi teraplikasi | **471** (tercatat di `supabase_migrations.schema_migrations`) |
| Tabel `public` | 79 |
| Container | 12 service up (db, rest, auth, storage, realtime, studio, kong, vector, analytics, pg_meta, inbucket, edge_runtime) |
| Smoke test | `GET /rest/v1/profiles` → HTTP 200; Studio → HTTP 307 (redirect normal) |

Verifikasi cepat dari dalam instabox:

```bash
ssh -p 2222 ibssh_pkaewaqds244ilfseabkwddeeu@api.instabox.sh \
  "cd /data/workspace/chatyuk/supabase && supabase status"
```

### 5. Buka Studio di browser instabox (dilihat dari tab Computer)

Studio hanya listen di `127.0.0.1` di dalam VM. Cara melihatnya tanpa tunnel:
buka Chromium di desktop instabox (display `:1`) — desktop itu tampil di
dashboard instabox, tab **Computer**.

```bash
ssh -p 2222 ibssh_pkaewaqds244ilfseabkwddeeu@api.instabox.sh \
  'DISPLAY=:1 nohup chromium http://127.0.0.1:54323/project/rest >/tmp/chromium.log 2>&1 & sleep 4; echo ok'
```

> Browser apapun yang Playwright/Puppeteer launch dari shell baru di instabox
> otomatis tampil di desktop `:1` (lihat `MACHINE.md`). atoms:
>
> - Router Studio: `http://127.0.0.1:54323/project/default/...`
>   (`database/schemas` = Schema Visualizer, `database/tables` = Tabel, dll.)
> - Supabase local punya 2 identitas project di Studio: `default` (raw) dan
>   `ChatYuk` — keduanya menunjuk DB yang sama.
>
> Alternatif dari laptop sendiri: SSH tunnel (langkah 4 di atas) lalu buka
> `http://localhost:54323` di browser lokal.

`scrot` tersedia untuk verifikasi visual:

```bash
ssh -p 2222 ibssh_...@api.instabox.sh 'DISPLAY=:1 scrot /tmp/studio.png'
scp -P 2222 ibssh_...@api.instabox.sh:/tmp/studio.png .
```

---

## Status: ONLINE via ngrok (URL STABIL) ✅

Supabase lokal di instabox diakses dari internet lewat outbound tunnel
(instabox tidak punya inbound port, CLI `instabox-port` tidak ada di template ini).

| Item | Nilai |
|---|---|
| **URL publik** | **`https://defense-subtract-untrimmed.ngrok-free.dev`** (tetap/permanen) |
| Di-expose | **Hanya port API** `127.0.0.1:54321` — REST, GraphQL, Auth, Realtime (websocket), Edge Functions, Storage |
| TIDAK di-expose | Studio (54323), Postgres (54322), Mailpit — tetap internal |
| API key (publishable) | `sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH` |
| Secret key | JANGAN dipakai dari publik: `sb_secret_***REDACTED***` (lokal saja) |
| Agent | ngrok v3.39.11, `/usr/local/bin/ngrok`, config `/root/.config/ngrok/ngrok.yml` |
| Service | `ngrok.service` (systemd, **enabled** → auto-start tiap VM hidup) |
| Dev domain | `defense-subtract-untrimmed.ngrok-free.dev` (free plan, 1 domain/akun) |

Test cepat dari mana saja:

```bash
curl "https://defense-subtract-untrimmed.ngrok-free.dev/rest/v1/profiles?select=id,nickname&limit=2" \
  -H "apikey: sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH"
# → [{"id":"...0001","nickname":"Budi"},...]
```

Untuk Flutter/app: `SUPABASE_URL=https://defense-subtract-untrimmed.ngrok-free.dev`
+ publishable key di atas. Realtime websocket ikut jalan (`wss://.../realtime/v1`).

### Kelola ngrok

```bash
# status & log
ssh ... 'systemctl status ngrok; sudo journalctl -u ngrok -n 50 --no-pager'
# restart
ssh ... 'sudo systemctl restart ngrok'
# inspect request (UI ngrok lokal, hanya via SSH tunnel)
ssh -L 4040:127.0.0.1:4040 ...   # lalu buka http://127.0.0.1:4040
```

### Catatan free plan ngrok

- **Interstitial warning**: request dari browser (User-Agent browser) bisa dapat
  halaman peringatan ngrok. Request API/SDK (curl, Dart, postgrest-js) umumnya lolos.
  Kalau kena: kirim header `ngrok-skip-browser-warning: true`.
- Kuota & rate-limit bulanan kecil — cukup untuk testing/demo, **bukan produksi**.
- Kalau perlu produksi: named Cloudflare Tunnel (`chatyuk-local`, sudah dibuat di akun
  CF `e928846d08255f70b48ba2dc0310424e`, token di `/etc/cloudflared/token`, service
  `cloudflared.service` **disabled**) — tinggal butuh domain/zone di CF lalu tambah
  Public Hostname → `http://localhost:54321`.

### Kenapa sempat mati (insiden 2026-10-20)

VM instabox pernah di-**stop dari kontrol plane instabox** (bukan crash di dalam OS):
- SSH menjawab `administratively prohibited: machine ... is waking up` — istilah platform.
- `last -x shutdown/reboot` dan `journalctl -b -1` kosong → OS tidak pernah shutdown sendiri.
- MACHINE.md: *"A stop ends every process"* → Supabase + tunnel + Chromium semuanya mati.
- Pemicu paling mungkin: auto-stop VM idle oleh instabox, atau stop manual dari dashboard.

Yang bertahan hanya disk. Setelah mesin hidup lagi (buka dashboard → tunggu wake):
1. Containers Supabase restart otomatis (restart policy docker) — verifikasi `supabase status`.
2. `ngrok.service` auto-start (systemd enabled) → **URL tetap sama**, tidak perlu aksi.

### Catatan penting lokal-vs-cloud

- Cron job lokal (`chatyuk-outbox-worker`, send-push, dst.) di migrations masih
  menunjuk **URL cloud** `fohcucyyejdryryoxitm.supabase.co/functions/v1/...` —
  jadi di DB lokal, cron-nya memanggil edge functions cloud, bukan yang di runtime lokal.
- Anonymous signup + email confirmation dinonaktifkan di config — akun yang dibuat
  lewat URL publik ini langsung aktif. Bukan kondisi produksi (cloud berbeda perilaku).
- Tidak ada secret custom (`app_shared_secret` = NULL di lokal) → fungsi yang
  pakai `x-app-secret` ke edge functions lokal akan gagal auth sampai diisi.

---

## Konfigurasi `config.toml`

Sumber kebenaran: `supabase/config.toml` (project_id = **ChatYuk**). Ringkasan nilai
penting yang menentukan perilaku stack lokal:

### Port & service

| Service | Port | Catatan |
|---|---|---|
| API (Kong) | **54321** | REST `/rest/v1`, GraphQL, Edge Functions `/functions/v1`, S3 `/storage/v1/s3` |
| Postgres | **54322** | `postgresql://postgres:postgres@127.0.0.1:54322/postgres` |
| Shadow DB (db diff) | 54320 | dipakai `supabase db diff/reset` |
| Studio | **54323** | UI |
| Mailpit | 54324 | inbox email lokal (test SMTP) |
| Analytics | 54327 | backend `postgres` |
| Edge inspector | 8083 | Chrome DevTools debug Deno functions |
| Pooler | 54329 | **disabled** |
| API TLS | — | **disabled** (HTTP saja) |

### Database

| Setting | Nilai |
|---|---|
| `major_version` | **17** (harus sama dengan PG versi cloud — cek `SHOW server_version;`) |
| `migrations.enabled` | true; `schema_paths = []` (default folder `migrations/`) |
| `db.seed.enabled` | true; seed `./seed.sql` |
| `api.max_rows` | 1000 |
| `api.schemas` | `public`, `graphql_public`; `extra_search_path = public, extensions` |
| `auto_expose_new_tables` | unset → entitas baru **tidak** auto-expose (default baru, legacy removed 2026-10-30) |

### Auth & realtime

| Setting | Nilai |
|---|---|
| `site_url` | `http://127.0.0.1:3000` |
| `jwt_expiry` | 3600 (1 jam) |
| `enable_signup` / `enable_anonymous_sign_ins` | true / **true** (app ChatYuk pakai anonymous dulu) |
| email confirmations | **false** (tanpa verifikasi, sesuai app) |
| minimum_password_length | 6 |
| rate limit email_sent | 2/jam (hati-hati saat test email loop) |
| `realtime` | enabled (IPv4 default) |

### Edge Functions — matriks `verify_jwt`

| Function | verify_jwt | Kenapa |
|---|---|---|
| `topup-webhook` | **false** | dipanggil Midtrans langsung (tanpa JWT user) |
| `r` | **false** | redirect referral dari browser publik |
| `ai-reply` | **false** | dipanggil pg_net trigger; auth internal |
| `ai-daily-life` | **false** | dipanggil pg_cron + `x-app-secret` |
| `send-push` | **false** | dipanggil DB trigger via net.http_post — tanpa ini push gagal 401 diam-diam |
| `email-worker` / `email-webhook` | **false** | cron + `x-app-secret` (Resend) |
| `email-track` / `email-unsubscribe` | **false** | dibuka dari email client |
| `telegram-webhook` | **false** | auth via `x-telegram-bot-api-secret-token` |
| `sticker-gc` | **false** | cron/service + APP_SHARED_SECRET |
| `topup-create`, `play-topup-verify`, `welcome-bonus`, `telegram-verify` | true | dipanggil client authenticated |

### Storage & experimental

| Setting | Nilai |
|---|---|
| `storage.file_size_limit` | 50MiB |
| `storage.s3_protocol` | enabled (klien S3 bisa connect) |
| `storage.vector` | enabled (10 buckets / 5 indexes max) |
| `edge_runtime.policy` | `per_worker` (hot reload), `deno_version = 2` |
| `experimental.pgdelta` | enabled (engine schema diff untuk `db diff/pull`) |
| `orioledb / s3_*` | unset (fitur experimental tidak aktif) |

> Peringatan `section [inbucket] is deprecated` di log start = normal; v3 nanti
> ganti ke `[local_smtp]`.

---

## Drift Skema yang Diperbaiki

Fresh-deploy (`supabase start` / `db reset`) **gagal** sebelum perbaikan karena 4 migrasi
mereferensikan objek yang hanya ada di DB cloud (dibuat manual via Dashboard/Management API),
tidak pernah dibuat migration. Detail lengkap ada di header masing-masing file.

### 1. `20260928120000_revoke_anon_internal_functions.sql`

`revoke execute on function public.get_data_sizes()` → `function does not exist`.

9 fungsi direferensikan tapi tidak punya definisi di migrations:
`admin_test, check_email_exists, get_data_sizes, get_last_messages, get_message_counts,
get_table_sizes, increment_unread, rls_auto_enable, room_online_counts`
(+ signature yang berubah: `admin_contact_delete(uuid)`, `ai_reply_post(...)`, dst — total 23 statement).

**Fix:** tiap statement dibungkus guard lookup `pg_proc` + `pg_get_function_identity_arguments`.
Kalau fungsi ada → statement dijalankan; kalau tidak → skip.

> Catatan: `to_regprocedure('...'::regprocedure)` **tidak bisa dipakai** — ia melempar error
> 42883 saat tipe argumen tidak dikenal, bukan return NULL. Harus lewat `pg_proc`.

### 2. `20260928130000_set_function_search_path.sql`

`alter function ... set search_path` gagal untuk fungsi yang sama. **Fix:** guard identik (11 statement).

### 3. `20260928200000_stagger_cron_schedules.sql`

`cron.alter_job(27, ...)` → `Job 27 does not exist`. Job ID (9, 14, 20, 27) adalah artefak cloud.

**Fix:** cari ID lewat nama job, bukan angka hardcoded:

```sql
select cron.alter_job(jobid, schedule := '*/2 * * * *')
  from cron.job where jobname = 'chatyuk-outbox-worker';
```

> Kolomnya **`jobid`**, bukan `id`.

### 4. `20260915000000_backfill_schema_drift.sql` (file baru)

Tiga objek cloud yang tidak ada di migrations:

| Objek | Definisi (dari cloud) | Dipakai oleh |
|---|---|---|
| `room_members.broadcast_granted` | `boolean not null default false` | `20261005150000_room_members_gender.sql`, `private_room_service.dart` |
| `app_settings.app_shared_secret` | `text` (NULL — isi manual) | ~29 migrasi (`x-app-secret` header) |
| `debug_notify_log` | tabel: `id integer identity pk, msg text, created_at timestamptz` | tidak dipakai kode; telemetri |

Semua idempotent (`if not exists`), aman dijalankan berulang dan aman di cloud.

> **Penting:** timestamp harus **sebelum** `20261005150000` karena migrasi itu butuh
> kolom `broadcast_granted`. Nama `20260915...` sengaja dipilih agar urutannya benar.

> `app_shared_secret` **tidak diberi default** di repo (rahasia). Untuk lokal bisa diisi:
> ```sql
> update public.app_settings set app_shared_secret = '<secret>' where id = 'global';
> ```

---

## Drift Lain (diketahui, belum diperbaiki)

| Item | Keterangan |
|---|---|
| Fungsi `revoke_broadcast` | Dipanggil `private_room_service.dart` tapi **tidak pernah didefinisikan** di migrations |
| `profiles.has_password` | Ada di migrations, **tidak ada di cloud** — cloud kemungkinan di-drop manual |
| `messages/private_messages.replied_to_meta` | Migrasi `20261020120000_reply_meta.sql` belum di-apply ke cloud |
| `app_settings.bonus_*` | 19 kolom ada di migrations, tidak ada di cloud (kemungkinan di-drop saat konsolidasi `unified_yukcoin`) |

## Cara Dump Skema Cloud (referensi)

Dipakai untuk memverifikasi drift di atas:

```bash
TOKEN=$(grep '^SUPABASE_ACCESS_TOKEN=' .env | cut -d= -f2-)
curl -s -X POST "https://api.supabase.com/v1/projects/fohcucyyejdryryoxitm/database/query" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"query":"select table_name, column_name, data_type, is_nullable, column_default \
       from information_schema.columns where table_schema='"'"'public'"'"' order by 1,2"}'
```

Untuk membandingkan: ekstrak DDL (`create table` + `add column`) dari `migrations/`,
jalankan di Postgres bersih (perlu stub `auth.users`, `storage.objects`, `auth.uid()`),
lalu diff kolomnya terhadap hasil dump cloud.

> Jangan pakai parser regex sederhana — terbukti menghasilkan false positive masif
> (60–105 kolom palsu) karena `drop column`, FK ke `auth.users`, dan format multi-baris.

---

## ChatYuk Web (deploy lokal)

Web SPA ada di `~/Documents/chatyuk-web` (repo terpisah). Build statis disajikan
Caddy di `:8080`; Caddy juga mem-proxy API Supabase ke Kong supaya web dan API
satu origin. Ngrok meneruskan ke Caddy (bukan langsung ke Kong).

| Komponen | Path / nilai |
|---|---|
| Build SPA | `/data/workspace/chatyuk-web/dist` |
| Caddyfile | `/data/workspace/chatyuk-web/deploy/Caddyfile` |
| Service Caddy | `chatyuk-web.service` (port 8080) |
| Service ngrok | `ngrok.service` → `127.0.0.1:8080` |
| URL publik | `https://defense-subtract-untrimmed.ngrok-free.dev` |
| Runtime config | `dist/runtime-config.js` (no-cache) |

Deploy ulang setelah build lokal:

```bash
cd ~/Documents/chatyuk-web
npm run build
ssh -p 2222 ibssh_pkaewaqds244ilfseabkwddeeu@api.instabox.sh \
  'rm -rf /data/workspace/chatyuk-web/dist'
tar czf - dist | ssh -p 2222 ibssh_pkaewaqds244ilfseabkwddeeu@api.instabox.sh \
  'tar xzf - -C /data/workspace/chatyuk-web'
ssh -p 2222 ibssh_pkaewaqds244ilfseabkwddeeu@api.instabox.sh \
  'sudo systemctl reload chatyuk-web'
```

Catatan:

- Ngrok free menampilkan halaman peringatan sekali per browser. Setelah
  **Visit Site**, cookie ngrok membuat aset/gambar termuat normal. XHR/fetch
  melewatinya lewat header `ngrok-skip-browser-warning`.
- Ganti backend web tanpa rebuild: edit `dist/runtime-config.js` (atau
  `public/runtime-config.js` sebelum build), lalu reload.
- `presence_for` diperbaiki oleh migrasi
  `20261020150000_fix_presence_for_invisible_uid.sql` (kolom
  `invisible_admin_uid` bertipe `text`, bukan `uuid`).

---

## Isi Folder `supabase/`

| Path | Keterangan |
|---|---|
| `migrations/` | 473 file migrasi SQL (+ `20260915000000_backfill_schema_drift.sql` = perbaikan drift) |
| `functions/` | 26 edge functions (Deno), termasuk `_shared/` |
| `tests/` | 28 file SQL test |
| `snapshots/` | 68K snapshot |
| `config.toml` | Konfigurasi project (`project_id = "ChatYuk"`) |
| `*.sql` (root) | SQL lepas / fix manual (baseline lama) |
| `.temp/` | Metadata Supabase CLI — **tidak di-copy** ke instabox |

### Sinkronisasi web ↔ mobile

Web dan aplikasi Flutter memakai database, trigger, dan Realtime yang sama:

- `chat_id` privat = dua uid yang di-sort, dipisah `_`.
- Keduanya insert ke `private_messages`; trigger `handle_new_private_message`
  mengisi `last_message`, `unread_counts`, `message_count`, dan
  `last_sender_id` di `private_chats`.
- Web mendengar `postgres_changes` untuk pesan, chat, dan reaksi; typing lewat
  broadcast `typing-<chatId>` yang sama dengan mobile.
- `hidden_by` dihormati. Kirim dari web meng-unhide chat; chat dengan
  `message_count = 0` tidak tampil di daftar.
- Presence web menulis `profiles.status`/`last_seen`; read receipt memakai
  `mark_chat_read`.

Uji dua arah 2026-10-20 berhasil: web → klien Supabase kedua (realtime id 7),
klien kedua → web (id 8), unread bertambah, dan `last_read_at` web terbaca
dari klien lain.
