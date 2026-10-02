# ARCHITECTURE — ChatYuk

> Ikhtisar arsitektur aplikasi: lapisan, alur data, backend, dan konvensi.
> Untuk peta fitur→kode→SQL→test yang sangat detail, lihat
> [`FEATURE_MAP.md`](FEATURE_MAP.md). Untuk menjelaskan performa, lihat
> [`PERFORMANCE.md`](PERFORMANCE.md).

---

## 1. Ringkasan

ChatYuk adalah aplikasi **Flutter** (Android) dengan backend **Supabase**
(PostgreSQL + Auth + Realtime + Edge Functions) dan **Firebase** (FCM push,
Analytics). Tidak ada server API milik sendiri — logika server hidup di
RPC Postgres (SECURITY DEFINER), trigger, cron, dan Edge Functions (Deno).

```
┌──────────────────────── Flutter app (lib/) ────────────────────────┐
│  screens/  ── UI (termasuk panel admin)                            │
│  providers/ ── state (ChangeNotifier) + orkestrasi                 │
│  services/  ── akses Supabase (RPC, table, realtime, storage)       │
│  core/      ── cache, media, perf, ui util (tak bergantung UI)     │
└───────────────┬───────────────────────────────┬────────────────────┘
                │ PostgREST / RPC (HTTPS)        │ Realtime (WebSocket)
                ▼                               ▼
┌──────────────────────── Supabase ──────────────────────────────────┐
│  Postgres: tabel + RLS + RPC (plpgsql) + trigger + cron (pg_cron)  │
│  Auth, Storage, Realtime                                           │
│  Edge Functions (Deno): push, AI reply, topup verify, dll          │
└───────────────┬───────────────────────────────┬────────────────────┘
                │ pg_net (HTTP dari DB)          │ Firebase Admin SDK
                ▼                               ▼
        Edge Functions / webhook            Firebase FCM (push)
```

---

## 2. Lapisan client (`lib/`)

| Folder | Tanggung jawab |
|--------|----------------|
| `config/` | Theme, strings (i18n ID/EN), `supabase_config.dart` (init + HTTP client), `app_flavor.dart` (flavor), regions |
| `core/` | Non-UI: `cache/` (SQLite terenkripsi), `media/`, `call/`, `chat/`, `perf/` (PerfProbe), `ui/` (nav guard, util widget) |
| `models/` | Model data (User, Message, Room, dll) + (de)serialisasi |
| `providers/` | State management `ChangeNotifier` (Provider). Provider besar dipecah `part` mixin (mis. `providers/admin/*`) |
| `screens/` | UI screen; panel admin di `screens/admin_*` + `screens/admin_panel/` |
| `services/` | Akses Supabase: RPC, tabel, realtime channel, storage, edge function |
| `widgets/` | Widget bersama yang dipakai lintas screen |
| `mixins/`, `utils/` | Mixin layar & helper murni |

**Entry point:**
- `lib/main.dart` — build user (flavor `apkpure`/`play`).
- `lib/main_admin.dart` — build internal (flavor `admin`, appId `.admin`).
- Keduanya berbagi `lib/app.dart` (root widget + daftar provider).

### Alur data (pola umum)
`screens` membaca state via `context.watch/select` → `Provider` memanggil
`Service` → `Service` memanggil Supabase (RPC/tabel) → hasil dipetakan ke
`Model` → `notifyListeners()` → UI rebuild. Realtime: `Service` membuka
channel Supabase dan mem-push update ke provider.

**Aturan penting:**
- UI **tidak** memanggil `Supabase` langsung — selalu lewat `services/`.
- String UI **wajib bilingual** (ID+EN) di `config/strings*.dart`.
- Tipografi pakai token `AppText`/`AppGlyph` (bukan `TextStyle` ad-hoc).

---

## 3. Backend (`supabase/`)

| Bagian | Isi |
|--------|-----|
| `migrations/` | Skema, RPC, trigger, cron, kebijakan RLS (urut waktu) |
| `functions/` | Edge Functions (Deno) |
| `snapshots/functions.sql` | Sumber kebenaran SQL (auto-generate) |

### Edge Functions
`send-push`, `ai-reply`, `ai-daily-life`, `dummy-manage`, `fanout`,
`outbox-worker`, `welcome-bonus`, `play-topup-verify`, `turn-credentials`,
`admin-cf-usage`, `migrate-photos`, `terms`, `r`, plus fungsional lama
`topup-create`/`topup-webhook`/`ipaymu-*` (tidak dipakai di app).

### Autentikasi secret antar-layanan
Edge DB→Function memakai header `x-app-secret` yang nilainya dari
`app_settings.app_shared_secret` (bukan anon key). Revoke `SELECT` kolom itu
dari `anon/authenticated` agar tidak bocor.

### Pola "fan-out lewat outbox"
Notifikasi massal (mis. "X online", AI) **tidak** menunggu HTTP di dalam
transaksi — ditulis ke tabel outbox, lalu `outbox-worker` mengirim.
Tujuannya: transaksi DB cepat & tahan gagal.

### Cron (`pg_cron`)
Contoh job: `chatyuk-housekeeping` (*/1m — presence idle + voice + room
cleanup), `chatyuk-ai-presence` (*/5m), `chatyuk-ai-claim-recovery` (*/5m),
`chatyuk-ai-missed-recovery` (*/3m). Daftar & jadwal lengkap: lihat
migrasi & [`MIGRATION_LOG.md`](MIGRATION_LOG.md).

---

## 4. Realtime & Presence

- **Pesan** (`private_messages`/`messages`) — channel per chat
  (`msg-<chatId>`) dengan filter server-side; INSERT di-append langsung
  (0 round-trip), UPDATE/DELETE memicu reload ter-debounce.
- **Presence** (online/idle/offline) — `RealtimeHub` mengelola channel
  presence global; status dihitung server (`effectiveStatusOf`, cron tick).
  Ini fitur **paling rawan regresi** — lihat FEATURE_MAP §1.
- **Persistensi lokal** — pesan & blob cache disimpan di SQLite terenkripsi
  (SQLCipher); kunci dari Android Keystore. Foto/voice = file terenkripsi
  terpisah (`core/media`).

---

## 5. Entry flavor & distribusi

Dua dimensi flavor: **store × env**.

| Flavor | appId | Entry | Top up Play Billing |
|--------|-------|-------|---------------------|
| `apkpure` | `com.chatyuk.chatyuk` | `main.dart` | ❌ (kebijakan Play) |
| `play` | `com.chatyuk.chatyuk` | `main.dart` | ✅ |
| `admin` | `com.chatyuk.chatyuk.admin` | `main_admin.dart` | ❌ (uji read-only) |

Detil build/signing: lihat [`../README.md`](../README.md) & [`../AGENTS.md`](../AGENTS.md).

---

## 6. Konvensi & catatan lintas-fitur

- **Instrumentasi RPC satu jalur** — semua RPC dibungkus `measuredRpc`
  (`core/perf/rpc_probe.dart`) agar terukur seragam saat `PERF_PROBE`.
- **Koneksi HTTP** — `SupabaseConfig.init()` memasang `HttpClient` dengan
  `connectionTimeout` 5s + `idleTimeout` 15s untuk mencegah "ngelag setelah
  idle" (koneksi keep-alive basi). Jangan hapus tanpa pengganti.
- **Koalesensi RPC** — panggilan read idempoten yang sering dobel saat boot
  di-dedupe in-flight (lihat `points_service.dart`, `social_service.dart`).
- **Cache dengan TTL** — pilih TTL sesuai sifat data (lihat FEATURE_MAP §10b).
- **Widget bersama** — jangan bikin salinan baru; pakai yang ada
  (mis. `GenderAvatar`, `ProfileAvatar`) — lihat FEATURE_MAP §10d.

---

## 7. Referensi
- [`FEATURE_MAP.md`](FEATURE_MAP.md) — peta fitur→kode→SQL→test (paling detail).
- [`PERFORMANCE.md`](PERFORMANCE.md) — metodologi & hasil pengukuran (PerfProbe).
- [`MIGRATION_LOG.md`](MIGRATION_LOG.md) — riwayat perubahan skema/SQL.
- [`SECURITY_AUDIT.md`](SECURITY_AUDIT.md) — audit keamanan (RLS, ACL, secret).
- [`../CONFIG.md`](../CONFIG.md) — konfigurasi (Supabase, OAuth, keystore).
