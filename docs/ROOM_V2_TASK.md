# TASK — Room v2: "Sesi Terjadwal + Host" (Redesign Model Bisnis)

> Prompt untuk AI coding. Baca `AGENTS.md` DULU sebelum coding — semua
> aturan di sana (bilingual `s.*`, `AppText` token tanpa `fontSize:` mentah,
> larangan `services/` di screen, file ≤800 baris, aturan migrasi
> `-- SAFE:`/timestamp unik/fungsi FROZEN/apply via Management API,
> larangan akun user asli untuk test) berlaku penuh untuk task ini.

## 1. Konteks bisnis (kenapa)

Model bisnis ChatYuk: user beli YukCoin → spend (gift/room privat/call/
subscribe) → creator withdraw → platform ambil cut. Hari ini global room
adalah **kanal kosong permanen** — tidak ada alasan user datang, stay,
atau spend. Semua kompetitor yang berhasil (Bigo party room, Litmatch,
Clubhouse) memakai pola sama: **room = venue, acara terjadwal + host =
produknya**. Task ini mengubah global room dari "chat channel" menjadi
"panggung sesi live yang dijadwalkan dan di-host manusia".

Prinsip: jangan bangun media baru — voice stage, broadcast stage, gift,
ledger, presence, notif SUDAH ADA. Yang dibangun = lapisan "programming"
(jadwal + host + routing ekonomi) di atasnya.

## 2. Yang sudah ada (jangan dibuat ulang — baca ini dulu)

| Komponen | Lokasi |
|---|---|
| Tabel `rooms` (global): `id text`, `name`, `description`, `icon`, `order`, `country`, `category` | `supabase/migrations/20260812000000_baseline_from_loose_sql.sql` |
| Private room: `is_private`, `owner_id`, `live_uid`, `live_started_at`, `room_members.role` (owner/admin/member) | `20260814170000_private_rooms.sql`, `20260825210000_private_room_v2.sql` |
| Voice stage global room (audio, maks 6 mic, unlimited listener, tap-to-stage, mute paksa owner/admin) — tabel `room_voice_signals`, `room_voice_speakers`, RPC join/heartbeat/leave/mute/sweep | `20260926100000_room_voice_stage.sql`, `lib/screens/room_chat/widgets/voice_stage_strip.dart`, `lib/providers/riverpod/room_voice_provider.dart` |
| Broadcast video ≤4 broadcaster (`live_uid`/`live_started_at` compat) | `20260827050000_room_broadcast_4_and_list.sql`, `widgets/broadcast_stage.dart`, `room_broadcast_service.dart` |
| Gift di room → owner, cut platform `gift_cut_pct` (default 30), bubble `type='gift'`, debit bonus→topup→earned | `send_room_gift` di `20260908000000_room_gift.sql` — **saat ini HANYA private room** |
| Presence per room (`room_presence`) | baseline |
| Notif push + `rooms.last_notified_at` (pola notif "room live" sudah ada untuk private) | `20260828020000_unified_fanout_debounce.sql` dkk |
| Mission/point/level/leaderboard; mission reward perempuan → bucket `earned` (withdrawable) | `20261031100001_gender_points_missions.sql`, `20261110040000_female_mission_withdrawable.sql` |
| Admin panel (tab-tab `lib/screens/admin_*`) | `lib/screens/admin_panel/` |
| Explore room UI | `lib/screens/rooms_explore_screen.dart`, `widgets/room_explore_card.dart`, `category_chips.dart` |
| Akun dummy (TEST ONLY — dilarang produksi & dilarang masuk statistik) | `dummy_accounts` |

## 3. Spec yang dibangun

### 3a. Data model baru (1 migrasi, timestamp unik)

```sql
-- Host: flag di profiles (admin-set), bukan role baru
alter table public.profiles
  add column if not exists is_host boolean not null default false;

-- Sesi terjadwal per room
create table public.room_sessions (
  id          bigint generated always as identity primary key,
  room_id     text not null references public.rooms(id) on delete cascade,
  host_uid    uuid not null references public.profiles(id),
  title       text not null,                  -- "Karaoke Malam Jumat"
  format      text not null default 'bebas',  -- karaoke|curhat|debat|quiz|werewolf|musik|bebas
  starts_at   timestamptz not null,
  ends_at     timestamptz not null,           -- rencana durasi
  status      text not null default 'scheduled'
              check (status in ('scheduled','live','ended','cancelled')),
  started_at  timestamptz,                    -- aktual (KPI keterlambatan)
  ended_at    timestamptz,
  peak_viewers int not null default 0,        -- update dari room_presence saat live
  gifts_total  int not null default 0,        -- koin kotor selama sesi
  created_by  uuid not null,
  created_at  timestamptz not null default now()
);
create index room_sessions_room_idx on public.room_sessions (room_id, status, starts_at);
create index room_sessions_live_idx on public.room_sessions (status) where status = 'live';

-- Opt-in reminder "ingatkan saat mulai"
create table public.room_session_reminders (
  session_id bigint not null references public.room_sessions(id) on delete cascade,
  user_id    uuid not null,
  created_at timestamptz not null default now(),
  primary key (session_id, user_id)
);
```

RLS: SELECT publik untuk `room_sessions` & `room_session_reminders` (own
rows untuk reminders); semua write lewat RPC `security definer`.
GRANT/REVOKE di tabel baru tidak butuh `-- SAFE:` (bukan tabel bersama);
kalau menyentuh `profiles`/`messages`/`rooms` policy → WAJIB `-- SAFE:` +
`smoke_anon_register.sh` + update `docs/FEATURE_MAP.md`.

### 3b. RPC (`security definer`, pola yang sama dengan kode existing)

- `schedule_room_session(room_id, host_uid, title, format, starts_at, ends_at)`
  — admin only. Validasi: host `is_host=true`; maks 1 sesi `scheduled`/`live`
  per room pada rentang yang overlap; `starts_at < ends_at`.
- `start_room_session(session_id)` — hanya `host_uid` sesi itu atau app-admin.
  Guard: tidak ada sesi `live` lain di room yang sama. Set `status='live'`,
  `started_at=now()` → trigger notif ke reminders (pakai pola notif/outbox
  yang sudah ada, hormati `last_notified_at` debounce).
- `end_room_session(session_id)` — host/admin. `status='ended'`, `ended_at`.
  Auto-end: cron sweep — sesi `live` > `ends_at + 2 jam` → ended.
- `next_room_sessions(room_ids[])` — untuk lobby/explore: per room ambil
  sesi `live` ATAU `scheduled` terdekat (1 baris/room, join host name/avatar).
- `toggle_session_reminder(session_id)` — insert/delete reminder sendiri.
- Extend `send_room_gift`: saat ini menolak non-private room. Tambah cabang:
  room global + ada sesi `status='live'` → penerima = `session.host_uid`
  (bukan `owner_id`), `gifts_total` sesi += koin kotor. Ledger, cut
  platform, lineage, bubble `type='gift'` IDENTIK — jangan duplikasi
  logika wallet, pindahkan ke helper atau tambah parameter penerima.
  Tanpa sesi live di room global → tolak dengan pesan friendly `s.*`.
  ⚠️ Fungsi ini kemungkinan FROZEN — cek `scripts/frozen_functions.txt`;
  kalau frozen: header `-- menyentuh: send_room_gift` + ambil versi dari
  `supabase/snapshots/functions.sql` + `scripts/snapshot_functions.sh`
  setelah apply + review diff.
- `session_host_mute(room_id, target_uid)` — host sesi live boleh mute
  speaker di voice stage (perluas cek owner/admin yang ada).

### 3c. Client (Flutter)

- **Room card** (`room_explore_card.dart` + lobby list): badge state
  prioritas — `LIVE` merah + judul sesi + nama host + jumlah penonton;
  else `⏰ Hari ini 21.00 — {title}` + host + tombol "Ingatkan"
  (toggle `room_session_reminders`, icon bell). Sort: live dulu.
- **Dalam room** (`room_chat/`): banner sesi di bawah AppBar saat
  scheduled/live (judul + host + countdown/status); host dapat tombol
  "Mulai Sesi"/"Akhiri"; badge 👑/label host di avatar & bubble host;
  speaker strip: host di-highlight.
- **Admin**: tab/form jadwal sesi (pilih room, host dari `is_host`,
  title, format, jam) + toggle `is_host` di detail user + tabel stats
  sesi (peak_viewers, gifts_total, started vs scheduled).
- Semua string lewat `strings.dart` bilingual. Tidak ada `fontSize:`.
- Screen → provider saja; RPC lewat provider/riverpod yang sudah ada
  (tambah method passthrough — jangan import `services/` di screen).

### 3d. Statistik & aturan anti-fake

- `peak_viewers`: update berkala saat live dari `room_presence`
  **dengan mengecualikan `dummy_accounts`** — akun test tidak boleh
  menggelembungkan KPI host (fee host diukur dari angka ini).
- KPI yang harus bisa dijawab query: % sesi mulai ≤15 mnt dari jadwal,
  durasi aktual, peak viewers, total gift, jumlah speaker unik naik stage.

### 3e. NON-GOALS (jangan dibangun)

- ❌ Video wajib / fitur media baru — audio stage sudah cukup (broadcast
  video tetap jalan apa adanya)
- ❌ Self-serve apply jadi host — admin assign manual
- ❌ Auto split fee host — fee dibayar manual di luar app; app hanya KPI
- ❌ Reminder email — push saja
- ❌ Gift jenis baru / perubahan katalog
- ❌ Framing dating/kenalan di UI string apa pun
- ❌ Dummy account di statistik atau sebagai "penonton" produksi

## 4. Urutan kerja yang disarankan

1. Baca `AGENTS.md`, `docs/FEATURE_MAP.md`, `docs/PERFORMANCE_RULES.md`,
   `scripts/frozen_functions.txt`
2. Migrasi tabel + RPC (apply via Management API — CLI hang di Mac ini)
3. Extend `send_room_gift` (cabang sesi live)
4. Provider + UI: room card, banner sesi, kontrol host
5. Admin: jadwal + toggle is_host + stats
6. pgTAP untuk RPC baru + `flutter test` tetap hijau
7. `bash scripts/check_migrations.sh --all` + kalau sentuh fungsi frozen/
   grant tabel bersama → checklist AGENTS.md lengkap

## 5. Acceptance criteria

- [ ] Admin jadwalkan sesi → tampil di room card dgn jam + nama host
- [ ] Host start sesi → card berubah LIVE + push ke user yang "Ingatkan"
- [ ] Gift di room GLOBAL saat sesi live → masuk ke host (nett setelah
      cut), ledger `platform_revenue` benar, bubble gift muncul
- [ ] Gift ditolak saat tidak ada sesi live (room global)
- [ ] Host bisa mute speaker; member biasa tidak
- [ ] Dummy accounts TIDAK terhitung di `peak_viewers`
- [ ] `flutter analyze` 0 error/warning; `check_migrations.sh` bersih;
      snapshot functions diff direview kalau ada fungsi frozen disentuh
- [ ] Semua UI string bilingual via `s.*`; 0 `fontSize:` mentah

## 6. Catatan bisnis untuk reviewer

Angka KPI host (fee Rp150–500K/minggu, target: sesi mulai tepat waktu ≥90%,
sapa member baru <5 menit, peak viewers tumbuh mingguan) diukur dari data
sesi ini — presisi `started_at` vs `starts_at` dan `peak_viewers` penting
untuk kontrak, bukan sekadar statistik.
