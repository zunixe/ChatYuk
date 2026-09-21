## 0. ⛔ LARANGAN — jangan pakai akun user asli untuk test

**JANGAN pernah mengirim/menyisipkan pesan dengan `sender_id` milik user
asli** (SQL, Management API, `net.http_post`, atau skrip) untuk memicu balasan
AI. Pesan itu muncul seolah dari user asli → **disangka scam / akun dibajak**.

Cara benar memicu balasan AI saat debug:
1. Pakai uid **dummy** sebagai `sender_id` (dummy→dummy), ATAU
2. Pakai akun test khusus milik dev yang terdaftar sebagai dummy.
3. Butuh `always_reply=true` untuk uji deterministik? Pakai dummy biasa yang
   memang untuk test — **jangan** pakai uid user asli, dan **jangan** mengubah
   flag dummy milik user (kembalikan setelah selesai).
4. Bersihkan tuntas: `private_messages`, `ai_reply_log`, `ai_reply_claims`,
   kembalikan `private_chats.last_message`/`last_message_at` ke pesan asli.
5. Cache lokal HP (`chatyuk_messages_v1.db`) **TIDAK** ikut terhapus saat baris
   server dihapus — history user masih menampilkan pesan tsb.

# Runbook: Dummy AI Tidak Membalas

Sumber kebenaran: `supabase/functions/ai-reply/index.ts`,
`supabase/migrations/20260913130000_ai_callback_auth.sql`,
`20260913140000_ai_watchdog_and_helpers.sql`,
`20260914060000_ai_reply_log_fix.sql`,
`lib/widgets/private_chat_message.dart:726-740`.

## 1. Arti centang (bukan tebakan)

- Centang-1 abu = terkirim ke server, **belum dibaca lawan** (`isRead=false`).
- Centang-2 biru = lawan sudah buka chat (`markAsRead` jalan saat screen dibuka,
  `lib/screens/private_chat_screen.dart:305`).
- Centang-1 bukan bug HP. Cek adb dulu: HP normal kalau `adb devices` = `device`.

## 2. Alur balasan (reaktif)

`private_messages INSERT` → trigger `ai_reply_enqueue()` →
helper `ai_reply_post()` (pakai `x-app-secret` dari `ai_internal_config`) →
edge function `ai-reply` → insert balasan sebagai dummy.

Proaktif (cron `ai-proactive-10m`, tiap 10 menit): hening >45 mnt (manusia)
atau >10 mnt (AI↔AI), cooldown 3 jam / 30 mnt, syarat pesan terakhir dari
manusia dan `ai_hold_active=false`.

## 3. Cara query DB (WAJIB pakai ini, jangan mengira-ngira)

Token ada di `.env` (gitignored). **Jangan pernah print token / secret
penuh ke output.** Powershell (Windows):

```powershell
$env:SUPABASE_ACCESS_TOKEN = ((Get-Content .env | Where-Object { $_ -match '^SUPABASE_ACCESS_TOKEN\s*=' }) -replace '^[^=]*=\s*','').Trim().Trim('"').Trim("'")
supabase db query --linked "<SQL>"
```

Catatan: perintah pertama bisa lama (±1 mnt, "Initialising login role").
Kalau hang >3 mnt, ulangi sekali.

## 4. SQL siap pakai (read-only, secret disensor)

```sql
-- 4a. Global kill switch (harus true)
select id, ai_global_enabled from app_settings where id='global';

-- 4b. Secret internal (fail-closed: kalau callback_secret kosong,
-- SEMUA dummy diam total). Jangan select value penuh!
select key, (value<>'') as filled, length(value) as len
from ai_internal_config where key in ('callback_secret','ai_reply_url');

-- 4c. Provider LLM aktif (harus ada 1 row is_active=true)
select default_model, is_active from ai_provider_config;

-- 4d. Cron proaktif (harus ada & active)
select jobname, schedule, active from cron.job where jobname like 'ai-%';

-- 4e. Flag per dummy (ganti nickname)
select nickname, ai_enabled, coalesce(ai_hold_active,false) as hold,
  ai_no_rate_limit, ai_always_reply, ai_no_sleep,
  ai_offline_until, ai_wake_until
from dummy_accounts where nickname ilike '%BinorMuda%';

-- 4f. Ngambek per-chat (storm_until > now = AI diam di chat itu)
select chat_id, proactive_at, storm_until, updated_at from ai_chat_state
where chat_id = '<CHAT_ID>';

-- 4g. Claim nyangkut = trigger jalan tapi function mati/gagal
select trigger_msg_id, dummy_uid, claimed_at from ai_reply_claims
order by claimed_at desc limit 10;

-- 4h. Pesan terakhir di chat (siapa pengirim terakhir, kapan)
select id, sender_id, left(coalesce(text,''),40) as text, type, created_at
from private_messages where chat_id = '<CHAT_ID>'
order by id desc limit 5;

-- 4i. Cari chat_id dari nickname dummy (butuh uid dummy dari 4e)
select chat_id, participants from private_chats
where participants @> array['<DUMMY_UID>'::uuid] limit 20;
```

## 5. Kode skip edge function (`ai-reply` return `skipped`)

**Urutan prioritas flag (kontrak — jangan diubah tanpa update trigger + edge):**

```
hold > invisible > always_reply / ai_enabled > wake > storm > global > sleep/jumatan > rate
```

- `hold` (admin pegang dummy) selalu MENANG — bahkan atas `always_reply`.
- `always_reply` MENEMBUS `ai_enabled=false`, `sleep`, `friday_prayer`, `storm`, dan rate/cap.
- `ai_active_hours` bersifat KOSMETIK (tampilan presence) — TIDAK menghentikan balasan.

| skip | Arti | Cek |
|---|---|---|
| `ai_disabled` | toggle AI dummy mati. **Pengecualian `ai_always_reply` (expert/CS): flag ini MENEMBUS ai_disabled — expert selalu dibalas walau ai_enabled=false** | 4e `ai_enabled` + `ai_always_reply` |
| `session_held_vacuum` | admin sedang "masuk dummy" (hold). Tiap percobaan perpanjang vacuum +5 mnt. **Hold MENANG atas `always_reply`** | 4e `hold` — matikan hold di sheet AI dummy |
| `storm_off` | ngambek: `storm_until` masa depan / `ai_offline_until` (dipicu hinaan, lihat `INSULT_TERMS`) | 4e + 4f |
| `sleeping` | jam tidur dummy (`asleepAt`), kecuali `ai_no_sleep`/`ai_always_reply`/`ai_wake_until` aktif | sheet AI dummy → jam aktif; kartu dummy chip Tidur/Bangun |
| `friday_prayer` | Jumat siang, dummy perempuan | hanya Jumat 11.30–14.00 |
| `rate_limited` | kuota/jam habis (`ai_max_replies_per_hour`, **default 30**; min interval **default 5 dtk**). Dummy di-set `idle` | 4h hitung out dummy 1 jam terakhir |
| `rate_min_interval` | balasan dummy terakhir < `ai_min_interval_sec` (default 2 dtk) | 4h |
| `already_replied` / `already_claimed` / `debounce_older_trigger` / `pause_newer_trigger` | balapan trigger: pesan beruntun, hanya trigger TERBARU yang membalas | normal bila kirim banyak pesan cepat |
| `global_off` | `ai_global_enabled=false` | 4a |
| `no_history` / `no_profile` | data chat/profil rusak | 4h + `profiles` |

## 6. Tabel gejala → penyebab

| Gejala | Penyebab paling mungkin |
|---|---|
| SEMUA dummy diam (termasuk Admin) | 4b secret kosong, 4c provider mati, 4a global off |
| Admin dibalas, dummy X tidak | gate per-dummy (4e/4f): hold, storm, sleep, rate. **Catat: `always_reply` menembus ai_disabled/sleep/storm/rate — kalau expert tetap diam, cek `hold`** |
| Kadang dibalas kadang tidak | rate limit, sleep, storm, debounce pesan beruntun |
| Reaktif OK tapi proaktif tidak pernah | cron mati (4d), hold, cooldown 3 jam, pesan terakhir dari dummy |
| Pesan user centang-1 berjam-jam | AI tidak enqueue/balas sama sekali → mulai dari 4b, 4e, 4g |

## 7. Log keputusan AI (migrasi `20260914050000_ai_reply_log.sql`)

Sejak migrasi ini, menebak dilarang: tiap pesan → baris `enqueue`,
tiap exit edge function → baris `edge`. Langkah debug = baca log dari
baru ke lama, bukan baca code.

```sql
-- 7a. Apa yang terjadi di satu chat (terbaru dulu)
select created_at, stage, decision, proactive, trigger_msg_id, detail
from ai_reply_log where chat_id = '<CHAT_ID>'
order by id desc limit 20;

-- 7b. Agregat skip per jam = detektor anomali
-- (lonjakan skipped:* = tidak sesuai algoritma / provider mati)
select date_trunc('hour', created_at) as jam, decision, count(*)
from ai_reply_log where created_at > now() - interval '24 hours'
group by 1, 2 order by 1 desc, 3 desc;

-- 7c. Via RPC admin dari app (tanpa SQL editor):
-- supabase.rpc('admin_get_ai_reply_log', params: {'p_chat_id': chatId, 'p_limit': 100})
```

Aturan baca: `enqueue/enqueued` + tanpa baris `edge` = function tak pernah
jalan (secret salah / pg_net gagal / LLM hang — cek log edge). Baris `edge`
dengan `skipped:<alasan>` = cocokkan ke tabel §5. `enqueued` tanpa
`trigger_msg_id` + `proactive=true` = sapaan proaktif.

### 7.1 Status penerapan (2026-09-14, sudah LIVE)

Semua komponen berikut SUDAH aktif di project prod `fohcucyyejdryryoxitm`:

| Komponen | Status |
|---|---|
| `ai_reply_log` + `ai_log_reply()` + 2 index + RLS | terpasang |
| `ai_reply_post()` versi ber-log | terpasang |
| trigger `ai_reply_enqueue` versi ber-log | terpasang |
| RPC `admin_get_ai_reply_log(text, int)` | terpasang |
| cron `chatyuk-ai-log-cleanup` (`0 3 * * *`) | aktif |
| edge `ai-reply` wrapper observability | terdeploy |
| `cron.job` lain (presence/recovery/daily-life) | aktif |

Bukti verifikasi live 1 putaran (chat didi↔aqila):
`enqueue/enqueued` → `edge/replied` (model `mimo-v2.5-free`);
percobaan lain `edge/error:empty_reply` (LLM balas kosong — dulu jadi
"diam misterius") dan `edge/skipped:already_claimed` (dedupe jalan).
`enqueue/skipped:dummy_disabled` tertangkap saat chat ke BinorMuda
(`ai_enabled=false`), dan `skipped:rate_max` saat `ai_reply_post` lama
belum ber-log → pelajaran: **`create or replace function` bisa TIDAK
mengganti body** bila signature identik tapi OID di-cache; kalau log
hilang padahal migrasi "sukses", `drop function` lalu create ulang.

## 8. Jalur alternatif saat `supabase db query --linked` buntu

CLI butuh konek langsung ke pooler 5432 (sering diblokir; 6543 biasanya
terbuka tapi CLI tidak pakai itu). Endpoint SQL yang benar di Management
API: `POST /v1/projects/{ref}/database/query` (bukan `/db/query` — itu 404).
**Hanya satu statement per request** (banyak statement → 400): pecah file
migrasi manual, dan jangan lupa `read_only:false` untuk DDL.

```powershell
$tok = ((Get-Content .env | Where-Object { $_ -match '^SUPABASE_ACCESS_TOKEN\s*=' }) -replace '^[^=]*=\s*','').Trim().Trim('"').Trim("'")
$ref = ((Get-Content .env | Where-Object { $_ -match '^SUPABASE_PROJECT_REF\s*=' }) -replace '^[^=]*=\s*','').Trim().Trim('"').Trim("'")
$h = @{"Authorization"="Bearer $tok"; "Content-Type"="application/json"}
$b = @{query="select 1 as ok"; read_only=$true} | ConvertTo-Json
Invoke-RestMethod -Uri "https://api.supabase.com/v1/projects/$ref/database/query" -Headers $h -Method Post -Body $b -TimeoutSec 60
```

Untuk PostgREST (tanpa SQL, bypass RLS): `api-keys` → `service_role`.
**Jangan print key ke output** (sensor seperti §4b). PostgREST kadang
504 — ulangi 2-4x dengan jeda 3 detik.

## 9. Capture Xiaomi (adb, Windows)

```powershell
$adb="$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
& $adb devices -l   # harus: 579e4d6 device model:24129PN74G
& $adb -s 579e4d6 shell screencap -p /sdcard/screen.png
& $adb -s 579e4d6 pull /sdcard/screen.png C:\Users\zaini\AppData\Local\Temp\opencode\screen.png
```

Lalu `read` file png-nya. Catat: jam status bar vs jam pesan,
centang-1/2 tiap bubble, header chat, toggle di sheet "Mode AI Dummy".
