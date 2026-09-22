# MIGRATION_LOG — catatan perubahan versi & penerapan

## 2026-09-22 — Privacy hardening: tutup bypass REST (`20260922100000`, `20260922110000`)

**Masalah (audit privasi):** setting privasi berfungsi di jalur RPC, tapi bisa
**dilewati via REST langsung** karena RLS `profiles_select`/`user_photos_select`
= `USING(true)` dan kolom sensitif masih ter-grant SELECT ke `anon`+`authenticated`.

**Yang bocor (terverifikasi live):**
- `user_photos.photo` → readable anon+authenticated → **bypass paywall**
  `get_user_photos_access`/`unlock_photo` (foto terkunci bisa dibaca gratis).
- `profiles.status` + `last_seen` → bypass `presence_visibility`/`last_seen_visibility`.
- `profiles.avatar` → bypass `profile_photo_visibility`.
- `story_tray` tidak cek `privacy_can_view(author,'story')` → story "nobody"
  tetap muncul (avatar + count slide) di tray.

**Sudah aman sebelumnya (tidak disentuh):** `lat/lon/lat_gps/lon_gps/lat_ip/
lon_ip/ip_address/email/fcm_token/about` — tidak ter-grant; `app_shared_secret`
tak ada SELECT grant.

**Migrasi 1 — `20260922100000_privacy_harden_columns.sql`:**
- RPC baru (security definer, grant `authenticated` saja): `presence_for(uuid[])`,
  `avatar_for(uuid)`, `avatars_for(uuid[])`, `my_photos()` — semua menerapkan
  `privacy_can_view` + blokir + invisible.
- `revoke select (status, last_seen, avatar, share_location) on profiles`
  → baca via RPC di atas.
- `user_photos`: **revoke table-level SELECT** dulu (grant `arwdDxtm` menutupi
  revoke kolom!) lalu `grant select (id, user_id, photo_preview, created_at)`.
  Foto asli hanya lewat RPC ber-gating (`get_user_photos_access`/`my_photos`).

**Migrasi 2 — `20260922110000_story_tray_privacy.sql`:**
- `story_tray` tambah `privacy_can_view(author, 'story', auth.uid())` +
  mask avatar via `profile_photo_visibility`.

**Dampak klien (diubah di commit yang sama):** `chat_service_presence.dart`
(getUserStatus/getUserLastSeen/fast-path/fallback) & `avatar_service.dart`
(get/refresh/prefetch) → RPC; `getPhotos(own)` → `my_photos`, foto orang lain →
`get_user_photos_access`; `auth_service_auth.dart` buang kolom revoked dari
copy profil; `user_info_screen.dart` pakai `getPhotosWithAccess`.

**Apply:** Management API (bukan `db push` — hang di mesin ini), tercatat di
`APPLIED_VIA_API.md`. **Verifikasi live:** `has_column_privilege('authenticated',
'profiles','avatar','SELECT')=false`, `('anon','user_photos','photo','SELECT')=false`,
`photo_preview`=true; REST anon/authenticated → 403 utk kolom revoked, 200 utk
kolom aman; RPC → 200 (anon RPC → 401); masking avatar terbukti
(`everyone`=path, `nobody`='').

## 2026-09-21 - Penanda "peserta sudah dihapus" (20260921230000)

**Masalah:** saat akun dihapus (self-delete / admin hapus anon / hapus dummy /
purge), baris private_chats ikut DIHAPUS. Lawan bicara hanya melihat chat itu
hilang mendadak tanpa penjelasan. Lebih buruk: bila pengirim masih menyimpan
last_read_at lawan di cache lokal, pesan barunya tetap tampak **centang-2**
padahal tidak ada perangkat lawan yang menerimanya (read-receipt hantu).

**Solusi:** baris chat DIPERTAHANKAN + kolom penanda
private_chats.deleted_participants uuid[]. ISI PESAN DIHAPUS (privasi: isi
percakapan tidak tinggal di server atas nama user yang sudah pergi; sesuai
keputusan pemilik produk). Klien menampilkan label "Akun dihapus", mengunci
kirim, mengabaikan centang-2, dan user boleh menghapus chat itu sendiri.

**Yang ditambahkan:**
- Kolom private_chats.deleted_participants uuid[] not null default '{}'.
- Helper terpusat mark_chats_user_deleted(p_uid uuid) - idempoten
  (array_agg(distinct ...)): hapus seluruh isi percakapan di chat yang
  melibatkan uid, lalu pasang penanda + kosongkan metadata preview.
  **message_count SENGAJA tidak dinolkan** - klien menyaring messageCount > 0;
  kalau dinolkan, baris justru terbuang dari daftar dan label tidak pernah
  muncul (membatalkan tujuan fitur).
- Fungsi yang diubah agar memakai helper: delete_my_account,
  admin_delete_anon_user, admin_delete_dummy, purge_inactive_accounts.

**Tidak diubah:** admin_delete_chat (tombol hapus chat di monitor admin) -
itu penghapusan chat eksplisit, bukan penghapusan akun.

- Apply: Management API (bukan db push - hang di mesin ini), tercatat di
  schema_migrations (20260921230000). Lihat APPLIED_VIA_API.md.
- Verifikasi live: deleted_participants ada (col_ok=1),
  mark_chats_user_deleted ada (fn_ok=1), dan keempat fungsi penghapus
  akun memanggil helper (pakai_helper=true).


## 2026-09-21 — Fix guard `friend_requests` (`20260921220000`)

**Bug (severity tinggi, ditemukan saat menulis `supabase/tests/privacy_test.sql`):**
`_social_registered_guard()` ditulis untuk tabel `follows`
(`new.follower_id`/`new.followee_id`), tetapi trigger
`social_guard_friend_requests` memasang fungsi yang sama di `friend_requests`
(kolomnya `from_id`/`to_id`). Akibatnya **setiap** `INSERT`/`UPDATE`
`friend_requests` gagal `42703 record "new" has no field "follower_id"`.

Dampak nyata:
- `send_friend_request()` & `respond_friend_request()` selalu gagal.
- `_are_friends()` selalu `false` → visibility privacy `'friends'` mati.
- `privacy_friends()` selalu kosong → picker "Teman kecuali" selalu empty.

**Fix:** guard membaca kolom sesuai `TG_TABLE_NAME` (`friend_requests` →
`from_id`/`to_id`; selain itu → `follower_id`/`followee_id`). Logika guard
tidak berubah: tetap menolak akun `is_registered = false` (kecuali dummy).

- Apply: Management API (bukan `db push`), tercatat di `schema_migrations`
  (`20260921220000`). Lihat `supabase/migrations/APPLIED_VIA_API.md`.
- Verifikasi live: insert teman antar-registered → sukses; antar-anon →
  `SOCIAL_REGISTERED_ONLY` (perilaku benar, bukan lagi 42703).
- Test: `supabase/tests/privacy_test.sql` (23 assert, termasuk seed
  `friend_requests` accepted) + tripwire di `regression_test.sql`.
- `bash scripts/check_migrations.sh --all` → OK bersih.

## 2026-09-20 — Privacy: 5 opsi + "kecuali" teman/anon (`20260920130002`–`0004`)

Uji coba di HP menemukan 3 bug pada privasi:

1. **Daftar "kecuali" kosong walau punya teman.** Enforcement memakai
   `_are_friends` (friend_requests accepted) sementara aplikasi memakai
   mutual follow → tidak sinkron. Ditambah `privacy_friends()` (`0002`),
   lalu disamakan ke mutual follow lewat `_privacy_are_friends()` (`0003`).
2. **Semantik "kecuali" salah.** Dulu `except` = "SEMUA orang kecuali
   daftar" sehingga non-teman ikut melihat. Dipisah tegas (`0004`):
   `everyone_except` (semua, kecuali daftar) vs `friends_except` (teman,
   kecuali daftar). Nilai lama `except` dimigrasi ke `friends_except`.
3. **Daftar kecuali hanya teman.** `privacy_excludable_users()` kini
   mengembalikan **teman + anon yang pernah chat** (badge "Anon"), dan
   kedua opsi "kecuali..." bisa memilih keduanya.

- `privacy_can_view()` diperluas jadi 5 cabang; `get_online_users()`
  memakai perhitungan set-based agar listing online tidak lambat.
- Hasil uji live: `privacy_friends()` = 1 (SimpleMe),
  `privacy_excludable_users()` = 37 kandidat.
- Test: `supabase/tests/privacy_test.sql` (17 assert) + 23 test Flutter
  (`test/privacy_*_test.dart`) lulus; `flutter analyze` 0 error.

## 2026-09-20 — Privacy fixes (`20260920130001`)

Hasil cek ulang menemukan 4 regresi yang lalu diperbaiki:

1. `nearby_users` memakai `order by 12` padahal hanya 11 kolom → error saat
   dipanggil. Dikembalikan ke `order by 11 asc`.
2. `get_online_users` terlanjur mencabut akses `anon` (perilaku lama:
   `authenticated, anon`). Dipulihkan, dan filter privacy di-INLINE (bukan
   fungsi per baris) supaya listing online tidak melambat.
3. `profile_public` kehilangan `share_location` + `points` milik sendiri —
   berdampak ke toggle "bagikan lokasi" di Nearby dan fallback bonus login.
   Dikembalikan khusus untuk pemilik (`about` tetap kosong bagi non-pemilik).
4. `mark_chat_read` saat read-receipt OFF tidak menolkan `unread_counts`
   penerima → badge tidak pernah hilang. Sekarang badge SELALU dinolkan;
   hanya `last_read_at` yang tidak ditulis sehingga centang biru tetap aman.

- Helper `privacy_can_view` dan seluruh RPC privacy tetap dipakai.
- Test: `schema_sync_test.sql` (26 assert) + `test/privacy_provider_test.dart`
  dan `test/privacy_settings_test.dart` lulus.
- `bash scripts/check_migrations.sh --all` → OK bersih.

## 2026-09-20 — Privacy settings foundation (`20260920130000`)


- Menambahkan visibility privacy untuk presence, last seen, foto profil,
  about, story, dan read receipts.
- Menambahkan tabel pengecualian teman per pemilik dan field privacy.
- Menambahkan RPC `my_privacy_settings`, `update_privacy_settings`,
  `replace_privacy_exclusions`, dan helper `privacy_can_view`.
- UI `Profile > Pengaturan > Privasi` sudah tersedia dengan pilihan Semua
  orang, Teman, Teman kecuali, dan Tidak ada.
- Default semua visibility tetap `everyone`; read receipts tetap aktif.

## 2026-09-20 — Restore guard `ai_always_online` (`20260920120002`)

- **Masalah:** `ai_reply_enqueue` live sudah memiliki pengecualian
  `ai_always_online`, tetapi migration `20260915090000` yang terakhir
  mendefinisikannya di repo belum membawa cabang tersebut.
- **Perbaikan:** migration restore baru mengambil perilaku dari snapshot live,
  mempertahankan toggle AI↔AI, `ai_always_reply`, rate limit, logging, dan
  guard agar dummy `ai_always_online` tidak diturunkan ke `idle`.
- **Apply:** diterapkan via Supabase Management API dan versi
  `20260920120002` sudah dicatat di `schema_migrations`.
- **Verifikasi:** `scripts/snapshot_functions.sh` menyimpan 30 fungsi;
  `bash scripts/check_migrations.sh --all` menghasilkan `OK bersih`.

## 2026-09-20 — Story viewer inline reply, like, dan share (`20260920120001`)

- **UI:** story milik orang lain memakai kotak foto yang sama dengan composer;
  balasan awalnya berupa tombol di dalam foto, lalu membuka field yang bisa
  digeser bebas di dalam kotak foto. Saat mengetik, tombol send tampil bersama
  like dan share.
- **Like:** `story_likes` + RPC `toggle_story_like(uuid)` menyimpan toggle
  like per user/story. `story_slides()` mengembalikan `like_count` dan
  `liked`; `story_viewers()` mengembalikan penonton yang memberi like.
- **Share:** memakai share sheet HP melalui `share_plus`, tanpa data sensitif.
- **Server:** migrasi diterapkan via Supabase Management API dan versi
  `20260920120001` sudah dicatat di `schema_migrations`. Snapshot FROZEN
  `story_slides` diperbarui dari fungsi live.
- **Verifikasi:** `test/story_social_io_test.dart` dan
  `test/story_provider_test.dart` lulus.

## 2026-09-21 — Tab Terhapus: tampilkan anon pending + hapus anon (`20260921210000`)

**Kebutuhan:** di tab "Terhapus", tampilkan BERSAMAAN user terhapus (arsip)
dan user anon yang belum terhapus, dan admin bisa menghapus anon itu supaya
nickname-nya bebas dipakai.

**Sebelumnya:** `admin_list_deleted` hanya membaca `deleted_users` (arsip).
Menghapus anon hanya mungkin lewat `cleanup_stale_anonymous` (>7 hari) atau
`claim_nickname` — nickname tertahan sampai 7 hari.

**Perbaikan:**
- `admin_delete_anon_user(p_uid)` — hapus 1 user anon: arsip dulu
  (`fn_archive_deleted_user`, reason `admin_delete`), bersihkan
  room_presence/blocks/reports/user_photos/devices/location/contact + chat
  privat, lalu `profiles` & `auth.users`. Menolak REGISTERED & DUMMY
  (cek DUMMY lebih dulu karena dummy ber-`is_registered=true`).
  `coin_ledger` append-only → trigger `coin_ledger_no_delete` dimatikan
  sementara (pola `admin_delete_dummy`).
- `admin_list_deleted(p_limit,p_offset,p_include_pending)` — tambah item
  `pending` (anon belum dihapus, `pending=true`, `deleted_at=null`),
  diurut `last_seen`. Signature 2-arg di-DROP.
- Client: service `deleteAnonUser` + `listDeleted(includePending)`,
  provider `deleteAnonUser` (refresh otomatis), UI filter
  Semua/Terhapus/Belum dihapus + badge oranye + tombol hapus di detail.

**Verifikasi live (rollback):** anon `caritemen` → profil & auth terhapus,
arsip 1 baris; user terdaftar → `REGISTERED`; dummy → `DUMMY`.
List: 11 arsip + 84 anon pending = 95 total (sebelumnya 11).

## 2026-09-21 — Lokasi: GPS dipisah dari IP + history diperbaiki (`20260921200000`)

**Dua bug nyata (terukur di live DB):**
1. `user_location_history` **0 baris** padahal 66 user ber-`loc_source='gps'`.
   Sebab: migrasi `20260815150000` membuat OVERLOAD 4-arg `update_my_location`
   TANPA logika `insert ... history`; client memanggil yang 4-arg → history
   tidak pernah tercatat.
2. **GPS tertimpa IP** — saat GPS gagal fix, fallback IP menulis ke
   `profiles.lat/lon` yang sama → koordinat GPS terakhir hilang.

**Perbaikan:**
- Kolom terpisah `lat_gps/lon_gps/gps_updated_at` + `lat_ip/lon_ip/ip_updated_at`.
  IP **tidak menimpa** GPS; `lat/lon/loc_source` (dibaca peta admin &
  `nearby_users`) = GPS bila ada, else IP → kontrak pembaca tidak berubah.
- Satu jalur RPC `update_my_location` (overload lama di-DROP) yang SELALU
  mencatat history untuk gps & ip.
- Backfill data lama ke kolom sesuai `loc_source`.
- `admin_location_sources()` untuk ringkasan GPS/IP/history.
- Client: pencatatan lokasi hanya saat **online** (`_isLocationEligible`) —
  idle/invisible/dummy/banned tidak menulis → yang tersimpan adalah lokasi
  terakhir saat benar-benar aktif.

**Verifikasi live:** GPS (-6.2,106.8) lalu IP (-7.9999,110.9999) →
`lat/lon` tetap GPS, `lat_ip/lon_ip` terisi, history 2 baris (gps+ip).

`nearby_users` FROZEN — tidak disentuh.

## 2026-09-21 — `install_id` pindah ke MediaDrm (`20260921190000`)

**Alasan:** `install_id` lama (`android-<ANDROID_ID>`) berubah saat signing key
/ user profile berbeda → device yang sama tampil sebagai device baru (device
ter-exclude "muncul lagi"). MediaDrm (Widevine) `deviceUniqueId` stabil per
perangkat FISIK: tahan reinstall, ganti keystore, Dual Apps/Second Space.

**Implementasi:**
- Kotlin `MainActivity.mediaDrmDeviceId()` → method channel `deviceUniqueId`.
- Dart `ScreenSecureService.deviceUniqueId()`; `DeviceInfoService.installId()`
  → `drm-<hex>`, fallback `android-<ANDROID_ID>` bila Widevine tak ada.
- `upsert_device` (9-arg) menerima `p_legacy_install_id`: memigrasi baris lama
  milik user yang sama **in-place** + membuang duplikat brand+model yang sama.
  Signature lama (7-arg & 8-arg) di-DROP dulu agar tidak jadi overload.

**Verifikasi live:** HP `24129PN74G` → baris `drm-e21f475d9d83113fb46e08f3547b60c5`
(1.2.43-admin); baris `android-2f218335e9fd56d5` milik uid yang sama
**digantikan**, bukan bertambah (tidak ada duplikat).

## 2026-09-21 — INSIDEN: device ter-exclude "muncul lagi" (`20260921170000` + `20260921180000`)

**Gejala:** admin exclude 1 HP, tapi device yang sama **muncul lagi** di tab
Perangkat dengan install_id BERBEDA.

**Akar masalah:** `install_id` = `android-<ANDROID_ID>`, dan Android 8+
meng-scope `ANDROID_ID` ke **(device + user profile + app signing key)**.
Terbukti di DB: model `24129PN74G` punya DUA install_id —
`android-2f218335e9fd56d5` (1.2.16→1.2.43) dan `android-e29a2f7c3e9624c6`
(hanya 1.2.40). Jadi exclude berbasis device **rapuh**.

**Perbaikan dua arah:**
1. `20260921170000_admin_exclude_cascade_uids.sql`:
   - `admin_list_devices` kini memakai `admin_excluded_uids()` (device **dan**
     uid manual) — sebelumnya hanya `excluded_devices`.
   - RPC baru `admin_exclude_device_cascade(p_install_id)`: exclude device
     **sekali** menambahkan semua uid yang pernah login di device itu ke
     `excluded_uids` → exclude tahan walau install_id berubah.
   - Backfill: uid dari device yang sudah ter-exclude dimasukkan (2 → 17 uid).
2. `20260921180000_admin_unexclude_uid_sync.sql`:
   - `admin_set_excluded_devices` menyinkronkan `excluded_uids`: uid yang
     device-nya tidak lagi ter-exclude **dibuang**, tapi uid tanpa baris
     device (anon manual) **dipertahankan**.

**Verifikasi (live `fohcucyyejdryryoxitm`):** cascade 17→18 uid; un-exclude
18→17 uid + device kembali 3; `admin_list_devices` total 44 baris → 29
(15 milik uid ter-exclude disembunyikan).

**Aturan:** `admin_stats_detail` FROZEN — tidak disentuh. Snapshot
`functions.sql` tidak memuat `admin_list_devices`, jadi tidak perlu update.

Setiap migrasi yang di-apply atau di-rename WAJIB dicatat di sini supaya AI/dev
berikutnya tahu. Format: tanggal | versi | aksi | catatan.

## 2026-09-21 — INSIDEN: `delete_my_account` gagal untuk user ber-koin (`20260921160000_delete_my_account_ledger_fix.sql`)

**Gejala:** user dengan riwayat koin menekan "Hapus Akun" → error
`coin_ledger is append-only`. Terdampak **177 user** (semua yang punya ledger).
Melanggar syarat Google Play (akun harus bisa dihapus).

**Akar:** `20260911000000_delete_my_account.sql` memanggil
`delete from public.coin_ledger` tanpa menonaktifkan trigger append-only
`coin_ledger_no_delete`. Fungsi sah lain (`admin_delete_chat`, hapus dummy,
purge) memakai `set local session_replication_role = 'replica'` — pola TERLEWAT.

**Fix:** bungkus hapus ledger+dummy-poin dengan toggle `session_replication_role`
(replica → origin), persis pola `20260815040000_admin_delete_chat_coinledger_fix.sql`.
Definisi diambil dari LIVE, hanya menambah blok itu.

Verifikasi: `delete_my_account` memuat `session_replication_role` (true);
simulasi hapus ledger user ber-koin → sukses (sebelumnya DITOLAK); migrasi
tercatat di `schema_migrations`. `check_migrations --all` hanya FAIL
pre-existing `ai_reply_enqueue` — bukan dari migrasi ini.

## 2026-09-21 — INSIDEN: semua pendaftaran gagal (`42501 permission denied for table profiles`)

**Gejala:** login/register anon, Google, & email semuanya gagal; Auth sign-in
sendiri sukses (token terbit) tapi `registerProfile()` ditolak server.

**Akar:** `20260915120000_security_hardening.sql` mencabut SELECT level-tabel
`public.profiles` dan hanya memberi grant kolom publik — **tanpa**
`email, ip_address, fcm_token, lat, lon`. PostgREST `upsert`
(`ON CONFLICT DO UPDATE`) butuh SELECT pada KOLOM YANG DITULIS, sehingga upsert
yang menyertakan kolom sensitif → `42501`. Ini pola regresi yang sama dengan
insiden `20260812200000` (direvert oleh `20260812230000`).

**Keputusan:** perbaiki di **KLIEN**, bukan melonggarkan grant (hardening tetap
utuh — kolom sensitif tidak bisa di-SELECT publik):
- `auth_service_profile.dart` `registerProfile()`: upsert **kolom publik saja**
  + `update()` terpisah untuk `fcm_token`/`email`/`ip_address` (UPDATE tidak
  butuh SELECT kolom tsb; RLS `profiles_update_own` tetap berlaku).
- `auth_service_auth.dart` `linkGoogleProfile()`: idem (upsert `old` publik,
  email via UPDATE terpisah).

**Tidak ada migrasi DB** (murni klien). Verifikasi HTTP live: anon + email
register → upsert 201/200, update sensitif 204 (sebelumnya 403).

**Pelajaran:** setiap kali `grant select (kolom...)` dipersempit di `profiles`,
WAJIB cek jalur `upsert` klien — upsert butuh SELECT semua kolom yang ditulis.
Lihat `lib/services/auth_service_profile.dart` (komentar guard).

## 2026-09-21 — Fitur mention `@` (`20260921120000_mentions.sql`)

Apply via Management API + recorded. **Tidak menyentuh fungsi FROZEN**;
hanya menambah kolom dan satu fungsi/trigger baru.

| Objek | Isi |
|---|---|
| `messages.mentions` | `jsonb not null default '[]'` — `[{"uid","name"}]` per pesan room/grup |
| `private_messages.mentions` | idem untuk private 1:1 |
| `notify_mention_room()` + trigger `notify_mention_room_trg` | `AFTER INSERT ON messages` — push TERARAH hanya ke uid yang di-mention (kecuali sender), token dari `user_devices` → fallback `profiles.fcm_token`, `type='mention'` + `toUid` |

`@all` di-ekspansi di KLIEN menjadi daftar uid eksplisit (hanya private
room/grup oleh owner/admin, cap 100 uid) — di global room `@all` dimatikan
total. Private 1:1 sudah punya `notify_private_message` per pesan, jadi
mention di sana hanya highlight (tanpa push tambahan).

Verifikasi: `information_schema.columns` punya `mentions` di kedua tabel;
`pg_trigger` punya `notify_mention_room_trg`; `schema_migrations` memuat
`20260921120000`. Edge `send-push` dideploy ulang (`--use-api`) dengan
`'mention'` ditambahkan ke `dataOnlyTypes`.
`check_migrations --all` FAIL pre-existing lapis 5 (`ai_reply_enqueue`/
`ai_always_online`) — bukan dari migrasi ini.

## 2026-09-19 — Retensi call otomatis: cron `chatyuk-call-sweep` (`20260919094500_call_sweep_cron.sql`)

Apply via Management API + recorded. **Tidak menyentuh fungsi FROZEN**
(`admin_sweep_calls` bukan anggota `scripts/frozen_functions.txt`) dan tidak
mengubah definisi fungsi/tabel/policy apa pun — hanya menjadwalkan.

| Objek | Isi |
|---|---|
| Cron `chatyuk-call-sweep` | `*/5 * * * *` → `select public.admin_sweep_calls()` (idempotent: `unschedule` dulu bila ada) |

**Masalah:** `admin_sweep_calls()` sudah benar (akhiri `ringing` >90 dtk,
`answered` tanpa heartbeat >75 dtk, hapus `call_signals` call selesai >1 jam)
tetapi hanya terpanggil saat admin membuka panel (`admin_service.dart`). Untuk
user biasa: call zombie menggantung & `call_signals` menumpuk. Bukti DB saat
review: 436 baris `calls`, 81 baris `call_signals` tapi **2.160 kB**.

Verifikasi: `select jobname,schedule,active from cron.job where
jobname='chatyuk-call-sweep'` → `*/5 * * * *`, `active=true`;
`schema_migrations` memuat `20260919094500`.
`check_migrations --all` FAIL pre-existing lapis 5 (`ai_reply_enqueue`/
`ai_always_online`) — bukan dari migrasi ini.

## 2026-09-19 — Dummy idle hilang di app: RPC `dummy_uids()` (`20260919082500_dummy_uids_rpc.sql`)

Apply via Management API + recorded. Tidak menyentuh fungsi FROZEN, tabel,
policy, atau grant yang ada (murni tambah 1 RPC + grant execute).

| Objek | Isi |
|---|---|
| `dummy_uids()` | `SETOF uuid`, `SECURITY DEFINER`, `STABLE` — daftar `uid` dummy_accounts; `GRANT EXECUTE` ke `authenticated, anon` |

**Masalah:** di app hanya Sarah (online) tampil, Dhanu (idle) hilang — padahal
di admin keduanya ada, dan Dhanu sempat muncul lalu hilang lagi (flapping).
Akar: `dummy_accounts` RLS admin-only (`dummy_admin_all`) → select langsung
dari HP selalu 0 baris (RLS, bukan error) → `_fetchDummyUids()` = set kosong
→ `filterRpcOnlineRows` menggugurkan Dhanu sebagai "idle zombie" (idle tanpa
socket hanya lolos via daftar dummy). Online lolos tanpa syarat — makanya
Sarah tidak pernah terpengaruh.

**Client:** `_fetchDummyUids()` (`chat_service.dart`) kini `_sb.rpc('dummy_uids')`
(PostgREST kembalikan array uuid → `'$r'` per elemen). Bentuk respons beda
dari `.select()` (bukan Map) — jangan kembalikan ke `(r as Map)['uid']`.

**Test:** assert baru di `supabase/tests/contract_test.sql` (`dummy_uids() ada`).

Verifikasi: `select '44d9832a-...'::uuid in (select dummy_uids())` → true;
`flutter analyze` 0 error/warning; `flutter test` 241/241 hijau.
`check_migrations --all` FAIL pre-existing lapis 5 `ai_reply_enqueue`/
`ai_always_online` (sudah gagal sebelum migrasi ini — bukan dari migrasi ini).

## 2026-09-18 — Optimasi performa story (`20260918120000_story_perf.sql`)

Apply via Management API + recorded. Tidak menyentuh fungsi FROZEN.
Snapshot diregenerasi (hanya berubah baris timestamp).

| Objek | Isi |
|---|---|
| `idx_story_views_story_viewer` | Index `(story_id, viewer_id)` — percepat cek "sudah dilihat?" per slide saat `story_views` membesar |
| `mark_story_seen_bulk(uuid[])` | RPC baru — tandai banyak slide dalam 1 round-trip; guard visibility/blocks sama seperti `mark_story_seen`; `on conflict do nothing` (idempoten) |

### ⚠️ `story_tray` SENGAJA TIDAK diubah (rewrite JOIN = REGRESI)

Rencana awal: ubah subquery per-baris (N+1) di `story_tray` jadi
`LEFT JOIN profiles` + `DISTINCT ON` thumb terbaru. **Sudah diukur di DB
live dan hasilnya LEBIH LAMBAT** — jadi di-revert ke bentuk asli:

| Skenario | Subquery (asli) | JOIN (rewrite) |
|---|---|---|
| Data asli, 2 author | **0.082 ms** | 0.157 ms |
| Simulasi 300 author / 1200 slide | **29.5 ms** | 51.0 ms |

(per panggilan, rata-rata 100–300 iterasi)

Hasil kedua versi **identik** (diverifikasi: 2 author, 0 baris beda di kedua
arah) — jadi tidak ada alasan menanggung lambatnya. Planner PostgreSQL sudah
menangani subquery skalar ini dengan baik; JOIN + DISTINCT ON menambah
materialisasi yang tidak perlu.

**Jangan "optimalkan" `story_tray` lagi tanpa mengukur dulu.**

Verifikasi: index ada, RPC ada, `story_tray()` tetap 2 author.
`run_sql_tests.sh` semua lolos. `check_migrations --all` FAIL pre-existing
`ai_reply_enqueue`/`ai_always_online` (bukan dari migrasi ini).

## 2026-09-17 — Centang-2 di preview list Pesan (kolom `last_sender_id`)

Migrasi `20260917180000_last_sender_id.sql` SUDAH APPLY via Management API + recorded
di `schema_migrations`. Menyentuh FROZEN `handle_new_private_message` (header ada,
snapshot di-regenerate — diff hanya stamp + 1 baris `last_sender_id`, tanpa cabang hilang).

| Objek | Isi |
|---|---|
| `private_chats.last_sender_id` (uuid, nullable) | Pengirim pesan terakhir; diisi trigger tiap pesan baru; backfill 50/50 chat berisi (0 chat berisi tanpa sender) |
| Trigger `handle_new_private_message` | Tambah `last_sender_id = new.sender_id`; cabang preview image/view_once/coin/gift + unread + last_read dipertahankan |

UI: preview pesan terakhir di card list Pesan (`private_chats_screen.dart`) kini
diawali `✓✓` bila pesan terakhir dariku — biru (`primary`) kalau lawan sudah baca
(`lastMessageAt <= lastReadAt[lawan]`), abu kalau belum; tanpa centang bila dari lawan.
Model `PrivateChatInfo.lastSenderId` (fromMap/toMap/copyWith + `_rowToPrivateChat`).

Verifikasi: `flutter analyze` 2 file 0 error 0 warning (infos pre-existing);
`flutter test` 227/227 hijau; `run_sql_tests.sh notif_chat_test.sql` lolos (2 assert baru);
`check_migrations --all` FAIL pre-existing lapis 5 `ai_reply_enqueue`/`ai_always_online`
(sudah gagal di HEAD bersih sebelum migrasi ini — bukan dari migrasi ini).

## 2026-09-17 — Fitur: long-press ala WA (reaksi + bintang + teruskan) — private & room

Migrasi `20260917000000_message_reactions_stars.sql` SUDAH APPLY via Management API.
Tabel baru saja, tidak menyentuh fungsi FROZEN.

| Objek | Isi |
|---|---|
| `message_reactions` | Satu baris = satu user + satu emoji (`chat_type` private/room, `chat_id`, `message_id`, `user_id`, `emoji`, unique per kombinasi) |
| `starred_messages` | Bintang per-user (`user_id`, `chat_type`, `chat_id`, `message_id`, unique per user+pesan) |
| `private_messages.is_forwarded` / `messages.is_forwarded` | Flag label "Diteruskan" di bubble |

UI: tahan pesan → header jadi toolbar (balas/bintang/hapus/teruskan/•••) + bar emoji
(👍 ❤️ 😂 😮 😢 🙏 😁 +) mengambang di atas bubble; tap = multi-seleksi.
Badge reaksi + ikon bintang + label Diteruskan tampil di bubble.
Forward: sheet pilih chat/room → kirim ulang dengan `is_forwarded=true`.

| File | Perubahan |
|---|---|
| `lib/services/message_reaction_service.dart` | Baru: toggle/watch reaksi & bintang |
| `lib/widgets/message_reaction_bar.dart` | Baru: `ReactionBar`, `ReactionBadge`, sheet emoji tambahan |
| `lib/widgets/forward_picker_sheet.dart` | Baru: picker chat/room tujuan teruskan |
| `lib/models/message_model.dart` | Tambah `isForwarded` (fromMap/toMap/copyWith) |
| `lib/services/chat_service.dart` + `chat_stream_session.dart` + `providers/chat_provider.dart` | Select + insert `is_forwarded` |
| `lib/widgets/private_chat_message.dart` | `MessageBubble`: `selected`, `reactions`, `starred`, `onTapSelect`, label Teruskan, badge reaksi |
| `lib/screens/private_chat_screen.dart` + `room_chat_screen.dart` | Mode seleksi WA: AppBar toolbar, reaction overlay, aksi balas/bintang/salin/hapus/teruskan/edit, `PopScope` back = batal seleksi |
| `lib/config/strings.dart` | 11 getter bilingual baru (menuForward/menuStar/menuUnstar/menuCopy/msgMessageCopied/msgStarred/msgUnstarred/msgForwarded/forwardTitle/forwardSearchHint/msgForwardedLabel/msgReactionFailed) |
| `supabase/tests/schema_sync_test.sql` | 4 assert baru utk 2 tabel + 2 kolom |

Verifikasi: `flutter analyze` file terkait 0 error 0 warning (1 warning pre-existing di
`admin_chat_view_screen.dart:513` + FAIL pre-existing `check_migrations` lapis 5
`ai_reply_enqueue`/`ai_always_online` — bukan dari migrasi ini);
`flutter test` 216/216 hijau; tabel + kolom terverifikasi ada di DB live.

## 2026-09-16 — Fitur: swipe-to-reply (geser kanan = balas) — private & grup

Tanpa migrasi SQL. Murni Dart.

| File | Perubahan |
|---|---|
| `widgets/private_chat_message.dart` | Widget baru `SwipeToReply` (publik) + param opsional `MessageBubble.onSwipeReply` |
| `screens/private_chat_screen.dart` | `onSwipeReply` diisi untuk pesan LAWAN saja (`isMe \|\| isDeleted` → null) |
| `screens/room_chat_screen.dart` | `SwipeToReply(enabled: m.senderId != auth.uid && !m.isDeleted)` membungkus `_MessageBubble` |

**Cara kerja:** `onHorizontalDragUpdate` menggeser bubble 0–72 px ke kanan; ikon
reply di kiri muncul & menguat; lepas ≥48 px → masuk mode balas, <48 px → balik.

**Jebakan yang sudah dihindari:**
- Pesan SENDIRI tidak di-swipe — swipe kanan dari tepi kiri = swipe-back sistem
  iOS, kalau aktif user tidak bisa keluar chat.
- Pakai `onHorizontalDrag*`, BUKAN `Dismissible` (Dismissible menggeser permanen
  & bentrok dengan long-press action bar).
- `SwipeToReply` wajib PUBLIK — sempat `_SwipeToReply` sehingga gagal dipakai
  dari `room_chat_screen.dart`.

Detail invariant: `docs/FEATURE_MAP.md` §3b.

## 2026-09-16 — Perf: buka private chat instan + centang-2 instan + typing ikut scroll

Tanpa migrasi SQL. Murni Dart — detail invariant di
`docs/FEATURE_MAP.md` §3a (baca dulu sebelum menyentuh file di bawah).

**Masalah (dilaporkan user):**
1. Buka private chat ada jeda (tidak seperti WhatsApp).
2. Centang-2 muncul belakangan — padahal kalau sudah pernah dibaca harusnya
   langsung centang-2.
3. Bubble typing tidak ikut scroll bersama pesan.

**Akar masalah & perbaikan:**

| File | Perubahan |
|---|---|
| `private_chats_screen.dart` | Transisi `PageRouteBuilder` 320 ms → 150 ms (sempat 0 ms, dikembalikan karena terasa "patah"); tambah `_warmTopChats()` — 6 chat teratas di-prefetch ke memori saat list dimuat |
| `online_users_screen.dart`, `story_viewer_screen.dart` | Transisi ke `PrivateChatScreen` 320 ms → 150 ms |
| `chat_stream_session.dart` | `controller.onListen` = **replay** `_current`. Broadcast tidak menyimpan emit terakhir; emit memori di `initState` hilang sebelum `StreamBuilder` subscribe |
| `private_chat_screen.dart` | `_primeReadFromCache()` baca 2 sumber memori (snapshot live `_privateChatsLast` + `peekRawList`), ambil terbaru — sebelumnya hanya `peekRawList` yang bisa basi |
| `private_chat_screen.dart` | `_otherLastRead` jadi **monoton maju** (di stream & kv): nilai null/lebih tua tidak boleh menurunkan centang-2 |
| `private_chat_screen.dart` | `isRead` pakai `!msg.timestamp.isAfter(...)` (`<=`) — sebelumnya `isBefore` ketat, pesan dengan timestamp sama tidak ikut centang-2 |
| `private_chat_screen.dart` | Subscription non-kritis (`_subscribeStatus`, `_subscribeTyping`, `_chatInfoSub`, profil lawan, `markAsRead`) ditunda ke post-frame |
| `private_chat_screen.dart` | Toast bonus: `Future.microtask` ke-dobel tiap `build()` → dijaga `_bonusToastScheduled` (sekali per buka chat) |
| `private_chat_screen.dart` | Bubble typing dipindah dari luar `ListView` jadi **item list paling bawah** (`itemCount + 1`, index 0 saat `reverse: true`) supaya ikut scroll |

**Catatan build (bukan migrasi):** flavor admin yang benar = `adminProd`
(bukan `admin`), karena ada dimensi env dev/prod. RK:

```sh
flutter build apk --release --flavor apkpureProd --dart-define=APP_FLAVOR=apkpure \
  --obfuscate --split-debug-info=build/app/symbols
flutter build apk --release --flavor adminProd -t lib/main_admin.dart \
  --dart-define=APP_FLAVOR=apkpure --obfuscate --split-debug-info=build/app/symbols
```

## 2026-09-15 — Story harian: expert dikecualikan + panel admin

| Versi | Aksi |
|---|---|
| 20260914150050_admin_get_dummy_stories.sql | RPC baru `admin_get_dummy_stories(p_uid,p_days)` — list story harian satu dummy (14 hari) + status terisi/kosong (panel admin) |

**Catatan:** awalnya `...150000` lalu di-rename karena bentrok dengan
`20260914150000_storage_ownership.sql` (session paralel).

**Fix terkait (bukan migrasi):**
- `ai-daily-life`: story harian HANYA untuk dummy `kind='regular'` — expert
  (Admin Chatyuk/CS) tidak dibuatkan story.
- `config.toml`: `[functions.ai-daily-life] verify_jwt=false`.
- **INSIDEN**: env `APP_SHARED_SECRET` edge ≠ `app_settings.app_shared_secret`
  → cron `chatyuk-ai-daily-life` gagal diam-diam (pg_net anggap HTTP 200 sukses
  walau body `{"error":"unauthorized"}`). Disamakan via
  `supabase secrets set APP_SHARED_SECRET=<nilai app_settings>`; invoke manual
  kini `ok:true`.

## 2026-09-14 — Security: fix Storage IDOR + limit upload server-side

**Masalah (review ulang):** policy bucket `chat-photos` hanya cek
`auth.role() = 'authenticated'` tanpa ownership/path check → IDOR: user
authenticated mana pun bisa overwrite/delete file user lain (avatar, gallery,
voice, story, post).

| Versi | Aksi |
|---|---|
| 20260914150000_storage_ownership.sql | Helper `storage_object_owner_ok(name)` (owner-or-admin per path) + ganti 4 policy bucket `chat-photos` (insert/update/delete wajib owner) + trigger `trg_chat_photos_guard` (whitelist `content_type` + limit 8 MB) |

**Catatan:** path layout mengikuti `storage_photo_service.dart`:
`avatars/<uid>_<ts>.jpg`, `gallery|posts|story|timeline/<uid>/<file>`,
`chat|voice/<chatId>/<file>` (chat/voice divalidasi sebagai peserta `private_chats`).
Admin lewat `is_admin_request()`. Tidak menyentuh fungsi FROZEN.

## 2026-09-14 — Audit performa: paginasi & hilangkan fetch tanpa limit

**Masalah:** beberapa RPC/query memuat SELURUH tabel tanpa limit → lag (polling
admin tiap 15–30 dtk menarik ribuan baris).

| Versi | Aksi |
|---|---|
| 20260914130050_admin_list_dummies_page.sql | RPC baru `admin_list_dummies_page(p_limit,p_offset)` — paging daftar dummy (versi lama `admin_list_dummies()` TIDAK diubah) |
| 20260914140000_friend_request_pagination.sql | RPC baru `friend_request_inbox_page/outbox_page(p_limit,p_offset)` (versi lama tidak diubah) |

**Catatan:** `20260914130050` awalnya ditulis `...130000` lalu di-rename karena
bentrok timestamp dengan `20260914130000_ai_provider_models.sql` (session paralel).

## 2026-09-14 — Audit drift kode ↔ DB: pulihkan fitur & sinkron pencatatan

**Masalah ditemukan (audit):** 3 fitur rusak di produksi karena migrasi ada di
repo tapi tak ter-apply; 38 versi sudah ter-apply tapi tak tercatat di
`schema_migrations` (drift pencatatan).

**Aksi — apply migrasi yang selama ini tertunda:**

| Versi | Fitur dipulihkan |
|---|---|
| 20260909000000_mute_archive_chats.sql | Bisukan & Arsipkan chat (kolom `muted_by`/`archived_by` + RPC `mute_private_chat`/`archive_private_chat`) |
| 20260908000000_room_gift.sql | Kirim gift di room live (RPC `send_room_gift`) |
| 20260914110000_dummy_kind.sql | Filter Expert/Regular di admin (kolom `kind` + `admin_list_dummies`) |
| 20260914110001_dummy_kind_experts.sql | Koreksi set EXPERT (5 akun: Admin Chatyuk, Dr Nara, HardwareExpert, Kang Modal, SoftwareExpert) |
| 20260914110002_expert_flags.sql | Admin Chatyuk `ai_always_reply=true`; HardwareExpert `long_answers=true` |

**Aksi — sinkron pencatatan:** 38 versi yang objeknya sudah ada di DB (diverifikasi
via probe `pg_proc`/`information_schema.tables`) dicatat ke
`schema_migrations`. Total kini 246 versi file bertimestamp tercatat (sebelumnya
205). Tidak ada lagi versi file yang belum tercatat.

**Obsolete (JANGAN apply — sengaja dihapus):**
- `20260819150001_calls_notify_trigger.sql` + `20260823155000_notify_call_trigger.sql`
  → membuat trigger `notify_call_trigger` yang **redundan** dengan
  `notify_call_ringing_trigger`; sudah dihapus di `20260827000000_notif_fix.sql`.
  Fungsi `notify_call` memang tidak ada di DB (by design).

**Selaraskan kode ke skema (bukan ubah DB):**
- `messages.inserted_at` tidak ada → kode diselaraskan ke `created_at`
  (`room_chat_screen.dart`, `group_media_screen.dart`).
- `room_presence.country/city` tidak ada → pembacaan dihapus di
  `chat_service.dart` (kosongkan, tanpa query kolom nir-skema).

## 2026-09-14 — Lapis 6: perbaikan 8 timestamp duplikat

**Masalah:** `supabase_migrations.schema_migrations.version` adalah PRIMARY KEY,
tapi ada 8 pasang file migrasi dengan prefix timestamp SAMA → file kedua tidak
dijamin ter-apply (bergantung urutan filesystem). Ini bikin drift lokal↔remote.

**Aksi:** file KEDUA tiap pasangan di-rename ke `versi+1 detik`, di-apply ulang
(semua idempotent: `create or replace` / `... if (not) exists`), lalu versi baru
dicatat di `schema_migrations`. Verifikasi dampak: tidak ada (idempotent).

| Versi lama (file ke-2) | Versi baru | Status |
|---|---|---|
| 20260911140000_drop_dummy_ai_overload.sql | 20260911140001 | applied + recorded |
| 20260911150000_ai_chat_state_consent.sql | 20260911150001 | applied + recorded |
| 20260912000000_call_push_guard.sql | 20260912000050 | applied + recorded |
| 20260912010000_chat_update_trigger_admin_bypass.sql | 20260912010001 | applied + recorded |
| 20260912090000_dummy_ai_model_param.sql | 20260912090001 | applied + recorded |
| 20260913180000_dummy_wake.sql | 20260913180001 | applied + recorded |
| 20260913190000_dummy_photos_toggle.sql | 20260913190001 | applied + recorded |
| 20260914060000_presence_idle_tick.sql | 20260914060001 | applied + recorded |

## 2026-09-14 — Lapis 3: harness test SQL

| Versi | Aksi | Catatan |
|---|---|---|
| 20260914100000_sql_test_harness.sql | applied + recorded | schema `supabase_tests` + `check()`/`report()`/`mk_dummy()` |

Cara jalankan test: `scripts/run_sql_tests.sh` (via Management API, transaksional).

## Cara mencatat migrasi baru (WAJIB)

Setelah apply via Management API (`APPLIED_VIA_API.md`):

```bash
TOK=$(cat /tmp/sbtoken); REF=fohcucyyejdryryoxitm
curl -s -X POST "https://api.supabase.com/v1/projects/$REF/database/query" \
  -H "Authorization: Bearer $TOK" -H "Content-Type: application/json" \
  --data '{"query":"insert into supabase_migrations.schema_migrations (version) values ('\''<VERSI>'\'') on conflict do nothing;"}'
```

Lalu tambahkan baris ke tabel di atas.

## 2026-09-14 — INSIDEN: guard mendeteksi regresi live (ai_always_online)

**Kejadian:** saat menerapkan Lapis 6 (apply ulang file migrasi yang di-rename),
`20260913180001_dummy_wake.sql` ter-apply — fungsi `ai_presence_tick` versi itu
**tidak punya blok `if ai_always_online`**, sehingga cabang Admin Chatyuk 24/7
hilang di DB live (persis pola regresi lama). Restore-nya ada di
`20260914020000_admin_chatyuk_always_online_restore.sql` yang tidak ikut ter-apply
(urutan).

**Deteksi:** `scripts/run_sql_tests.sh` (test `presence_test.sql`) GAGAL dengan
"definisi memuat cabang ai_always_online" + "always_online → online". Guard
bekerja seperti desain.

**Perbaikan:** apply ulang `20260914020000` → `ai_always_online` kembali (pos=389).
Semua 35 assert hijau kembali.

**Pelajaran (WAJIB):** setelah apply ulang file lama, **re-apply migrasi
"restore/patch" yang lebih baru** untuk fungsi yang sama, ATAU gunakan
`create or replace` dari snapshot terbaru sebagai sumber. Inilah alasan
frozen-functions guard + snapshot ada.
