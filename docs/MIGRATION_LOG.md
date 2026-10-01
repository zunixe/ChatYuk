
## 2026-10-05 — Leaderboard "Top Aktif" (keaktifan: pesan + reaksi)

- **Migrasi** `20261005030000_activity_leaderboard.sql`:
  `activity_leaderboard(p_scope, p_limit, p_offset)` → jsonb
  `{scope, entries[], me}`. Skor = pesan private + pesan room + reaksi
  (`weekly`=7 hari, `alltime`=seumur hidup). Kecualikan dummy + excluded;
  hanya user nyata (registered atau status <> offline) — pola
  `points_leaderboard`. Entri + `msg_count` & `reaction_count`.
- **App:** `PointsService.activityLeaderboard` + passthrough provider;
  `ActivityLeaderboardScreen` (tab Mingguan/Sepanjang Masa, kartu rank +
  sub-label "N pesan · N reaksi", bar peringkat sendiri).
- **Ikon:** `Icons.emoji_events_rounded` di `leading` AppBar menu Online,
  tepat di samping ikon Search (`leadingWidth: 96`). Semua user boleh lihat.
- **Catatan:** `profiles.login_streak`/`last_login_date` TIDAK dipakai
  (cuma 3 baris — fitur daily-login mati). "Sering online" diproksikan via
  keaktifan chat (label "Top Aktif", bukan klaim presence).
- **Verifikasi:** `check_migrations` OK; pgTAP `schema_sync` 55/55;
  `points_service_io_test` +2 hijau; `flutter analyze` 0/0.

## 2026-10-05 — Laporan admin: nickname pelapor & terlapor + fix filter bulan

- **Migrasi** `20261005020000_admin_reported_users_nickname.sql`:
  `admin_stats_compute()` blok `reported_users` diperkaya → `reported_nickname`,
  `reported_registered`, `reporters` [{id, nickname}]. Admin kini tahu SIAPA
  yang dilaporkan (dulu cuma uid terpotong). Non-FROZEN, sisa fungsi persis
  live.
- **App:** `ReportedUsersCard` tampilkan nama terlapor + "Dilaporkan oleh: …"
  (pelapor ≠ terlapor jelas).
- **Fix filter bulan** (`registrationschart_card`): dropdown bulan 12 terakhir
  diurutkan eksplisit descending (terbaru di atas) via `_monthOptions()`.
- Verifikasi: `check_migrations` OK; analyze 0/0; admin tests hijau.

## 2026-10-05 — Insight registrasi CEO (panel admin Ringkasan)

**Alasan:** kartu "Registrasi Email" hanya menampilkan bar per-hari satu bulan.
Untuk keputusan CEO, dibutuhkan KPI + tren + konteks akuisisi.

- **Migrasi** `20261005010000_admin_registrations_insights.sql`:
  - `admin_registration_kpis()` → total terdaftar, total anon, konversi (%),
    baru bulan ini, baru bulan lalu, MoM %, baru hari ini, rata-rata/hari,
    hari terbaik (+jumlahnya), aktif hari ini. SEMUA mengecualikan dummy +
    excluded uid (user nyata; beda dari `admin_stats_compute`).
  - `admin_registrations_monthly(p_months)` → total per bulan (LEFT JOIN
    `generate_series` supaya bulan kosong tidak bolong) untuk tren 12 bulan.
- **App:** `AdminService.fetchRegistrationKpis/fetchRegistrationsMonthly`,
  `AdminProvider.fetchRegistrationInsights` (cache 1×), kartu
  `registrationschart_card.dart` dirombak: grid KPI (6 tile) + tren 12 bulan
  (CustomPaint, highlight bulan terakhir + delta chip vs bulan lalu) + bar
  harian (tandai hari terbaik) + tombol "Lihat daftar".
- **Konsistensi KPI:** dummies (12 akun) & excluded uid dibuang → angka CEO
  tidak menghitung akun dummy. MoM % hanya ditampilkan bila bulan lalu ≥ 10
  (hindari +22900% saat bulan lalu = 1).
- **Verifikasi:** `check_migrations` OK; pgTAP `schema_sync_test` 52/52;
  `admin_service_test` +2 test hijau; `flutter analyze` 0/0.

### Rename timestamp (AGENTS.md §2) — drift WIP

Dua migrasi untracked bentrok timestamp (checker menolak):
- `20261001000000_admin_chats_participant_genders.sql` → `20261001005000_...`
  (bentrok `coin_engine_config`).
- `20261001010000_admin_app_versions_sort_newest.sql` → `20261001015000_...`
  (bentrok `disable_free_points`).

## 2026-10-04 — Gate onboarding (`needs_onboarding`) + fix test tertinggal

**Alasan:** gate "wajib isi username" dulu (`nicknameSet` / migrasi
`20261002070000/080000`) di-**revert** di commit `5eb347e`. Pendekatan baru
memakai kolom **`needs_onboarding`** (dibuat trigger `handle_new_user_profile`).

- **Migrasi** `20261004060000_needs_onboarding_flag.sql` (kolom
  `needs_onboarding boolean not null default true`) + `20261004070000_reapply_trigger_with_onboarding.sql`.
- **App:** `UserModel.needsOnboarding` (fromMap/toMap/copyWith), gerbang root
  `app.dart`, `auth_provider.dart`, `auth_service_profile.dart`.
- **Fix:** `test/models_test.dart` masih menguji `nicknameSet` (API yang sudah
  di-revert) → **7 `flutter analyze` error**. Diganti 6 test `needsOnboarding`
  (key absen → false, true/false eksplisit, non-bool → false, toMap, copyWith).
  `flutter analyze` kembali 0 error/0 warning.

### Rename timestamp (AGENTS.md §2)

`20261001000000_admin_chats_participant_genders.sql` **bentrok** dengan
`20261001000000_coin_engine_config.sql` (dua file, prefix sama → apply tidak
deterministik, `check_migrations` menolak). Di-rename →
**`20261001005000_admin_chats_participant_genders.sql`** (slot bebas, urut
setelah coin_engine_config). Fungsi `admin_list_chats_page` sudah live di prod
(participant_genders terpasang).

## 2026-10-04 — Noise filter `ai_reply_log`

**Alasan (audit):** tabel `ai_reply_log` (retensi 7 hari) mentok ~11.4k baris /
~7 MB, padahal hanya ~39 baris `replied` per 7 hari. **84% isinya DUA decision
tak informatif:** `skipped:dummy_disabled` (5.401) + `skipped:ai_disabled`
(4.195) = "dummy penerima AI-off", yang sinyalnya sudah ada di
`dummy_accounts.ai_enabled`. Noise ini menenggelamkan kasus menarik.

- **Migrasi** `20261004080000_ai_reply_log_noise_filter.sql`:
  - `create or replace public.ai_log_reply(...)` (signature identik) + denylist:
    `if p_decision in ('skipped:dummy_disabled','skipped:ai_disabled') then return;`.
  - Semua call-site SQL (`ai_reply_enqueue`/`ai_reply_post` — FROZEN) ikut
    terfilter otomatis karena lewat helper pusat. **Fungsi FROZEN TIDAK
    disentuh** → tak butuh header `-- menyentuh:` / snapshot refresh.
  - Apply via Management API (3 statement: create fn, revoke, grant). SUDAH
    TERAPPLIED di `fohcucyyejdryryoxitm`.
- **Edge:** `supabase/functions/ai-reply/index.ts` — denylist setara di shadow
  `json()` (jalur insert `edge`). **Deploy v196 ACTIVE** via
  `supabase functions deploy ai-reply --use-api`.
- **Cleanup:** hapus 9.596 baris noise lama → 11.417 → 1.821 baris (84% turun);
  `VACUUM public.ai_reply_log` → dead tuples 0 (ruang dipakai-ulang insert
  berikutnya; file tetap ~7 MB, tidak akan tumbuh lagi).
- **Verifikasi live:** definisi `ai_log_reply` memuat filter; uji terarah —
  `skipped:dummy_disabled` & `skipped:ai_disabled` → **tidak** insert,
  `skipped:rate_max` → insert (baris uji dihapus); `check_migrations.sh --all`
  OK bersih; pgTAP `ai_test.sql` hijau.
- **Efek:** skema/retensi tak berubah — hanya penulis log. Cara debug
  "dummy diam" berpindah ke `dummy_accounts.ai_enabled` (lihat
  `docs/AI_DUMMY_DEBUG.md §7.0`).

## 2026-10-04 — Atribusi sumber user (tab admin baru)

**Tujuan:** admin tahu user datang dari kanal mana (Facebook/IG/Google/TikTok/
referral/organik).

- **Migrasi** `20261004000000_attribution.sql`:
  - Kolom `attribution_source`, `utm_source/medium/campaign/content`,
    `referrer_raw`, `attribution_at` di `public.user_devices` (+2 index).
  - `upsert_device` diperluas dgn 6 param attribution (DEFAULT '') — call-site
    lama (7/8 arg) tetap valid (overload PostgREST). **TULIS SEKALI**
    (`coalesce(existing, excluded)`) supaya resume tidak menimpa kanal asli.
  - RPC admin: `admin_attribution_summary(p_days)`,
    `admin_attribution_users_page(p_source,limit,offset)`.
- **App:** `lib/services/attribution_service.dart` (Play Install Referrer +
  Firebase Analytics), disuntik di `device_info_service.dart` (`upsert_device`)
  + bootstrap `main.dart`. UI: `admin_attribution_tab.dart` (tab ke-9).
- **Build fix:** `android/build.gradle.kts` menaikkan `compileSdk` plugin lama
  (mis. `android_play_install_referrer` = 33) ke 36 → build release tidak gagal
  karena `androidx.exifinterface` menuntut compileSdk ≥ 34.
- **Verifikasi:** migrasi diuji di Postgres 16 lokal (idempotent, write-once,
  RPC ok, backward-compat 7/8-arg ok); `test/attribution_test.dart` (14 test);
  build APK `apkpureProd` OK + gate anti-admin OK.

## 2026-10-03 — stuck_users: hanya user terdaftar

**Alasan:** di ekonomi YukCoin, saldo awal semua user = 0 (kecuali klaim
welcome bonus anon). Definisi lama `stuck_users` (points = 0 & aktif 7 hari)
jadi false-positive — hampir semua user baru anon terhitung "terjebak"
padahal normal. Ditambah `is_registered = true` → yang dihitung hanya user
yang SUDAH daftar email tapi saldo 0.

**Migrasi:** `20261003000300_stuck_users_registered.sql` (apply via Management
API, SUDAH TERAPPLIED): rewrite `admin_stats_compute` — SALINAN PERSIS body
live (dari `20260905100000_admin_stats_exclude_dummies.sql`), **hanya baris
`stuck_users`** diubah. ACL `service_role` dipertahankan. Cache stats di-reset.
- Bukan fungsi FROZEN (tak ada di frozen_functions.txt / snapshot).
- **Verifikasi live:** `has_new_def=true`, `has_old_def=false`; ACL
  `authenticated=false`, `service_role=true`.

**Kode klien:** `config/strings_admin.dart` (`adminStuckUsers` →
"user terdaftar saldo 0 (7 hari)").

## 2026-10-03 — Rapikan label & toast panel Poin (bilingual)

- **Danger Zone**: "Reset semua user ke 50 poin" → "Reset saldo semua user
  ke 50 YukCoin" (+judul/body). Mass bonus → "Bonus Massal YukCoin".
- **Hardcode toast → `s.`** (AGENTS.md): ForceLogoutCard
  (`adminForceLogoutDone`, reuse `errGeneric`), DangerZone (`adminResetDone`),
  MassBonusCard (`adminMassBonusDone`), FeaturePublishCard
  (`adminFeaturePublished`/`adminFeatureHidden`, `errGeneric`, judul/desc +
  4 label fitur `adminFlag*`).
- **Status YukCoin v2** ditampilkan di bawah toggle-nya (`adminYukcoinV2On/Off`)
  + `adminRealtimeDesc` diperjelas (points_enabled = saklar utama ekonomi).
- TANPA migrasi. `flutter analyze` 0 error/0 warning.

## 2026-10-03 — Admin Pengaturan Poin selaras sistem YukCoin

**Bug kritis diperbaiki:** `admin_update_point_settings` (versi 20261001020000)
masih menulis kolom `call_free_minutes_daily` yang DROPPED di
`20261003000000_coin_call_no_free.sql` → SETIAP Simpan Pengaturan Poin dari
panel admin GAGAL (SQLSTATE 42703). Migrasi `20261003000100` sudah membetulkan
`metered_pricing_public` tapi melewatkan RPC ini.

**Migrasi:** `20261003000200_admin_point_settings_yukcoin.sql` (apply via
Management API, SUDAH TERAPPLIED):
1. Rewrite `admin_update_point_settings`: buang `call_free_minutes_daily` +
   semua field faucet mati; TAMBAH welcome bonus (`welcome_anon_coins`,
   `welcome_register_coins`, `welcome_max_claims_per_ip_day`), YukCoin v2
   (`yukcoin_v2_enabled`, `cost_undo_message`, `cost_edit_message`,
   `cost_extra_photo_slot`, `cost_ghost_mode_daily`), `gift_cut_pct`.
2. Rewrite `points_quests`: tak baca lagi kolom faucet (daily/weekly/oneTime
   dikosongkan — layar misi sudah orphan & reward faucet no-op).
3. DROP 19 kolom faucet mati di `app_settings` (`bonus_registered/rated/shared/
   profile/first_photo/room_read/new_chat/invited/first_room/referral/
   online_5min/30min/60min/120min/first_friend`, `room_reads_daily_limit`,
   `new_chats_daily_limit`, `share_click_reward`, `share_click_cap_daily`).
   `bonus_price_multiplier` DIPERTAHANKAN (masih dipakai room_pricing,
   send_gift, unlock_photo).
- Bukan fungsi FROZEN. Snapshot FROZEN tidak berubah.
- **Verifikasi live:** 0 sisa kolom mati; `admin_update_point_settings` &
  `points_quests` tak menyebut kolom yang di-drop; 30 kolom yang ditulis RPC
  semua ada.

**Kode klien:** `lib/screens/admin_panel_screen.dart` (`_pointFields` dirapikan
per grup + toggle boolean `_pointFlags`), `admin_panel/widgets/point_tab_cards.dart`
(switch YukCoin v2 + label), `config/strings_admin.dart` (label YukCoin bilingual).
`flutter analyze` 0 error. Layar misi (`missions_screen.dart`) orphan — tak
tersentuh perilaku.

## 2026-10-03 — Coin untuk nelp (tanpa gratis) + welcome bonus bertahap + fix keamanan

**Keputusan produk:** nelp MURNI pakai coin (tanpa kuota gratis); tarif audio 6 /
video 20 coin per menit; welcome bonus bertahap — anon 100 coin (cukup video 5
menit) + register 100 coin (total 200, register langsung dapat full); anti-farming
sekali per device (`install_id`) + limit per IP/hari.

**Migrasi (apply via Management API, urut):**
1. `20261003000000_coin_call_no_free.sql`
   - DROP kolom kuota-gratis: `profiles.call_free_{audio,video}_seconds_today`,
     `call_free_date`, `app_settings.call_free_minutes_daily`; DROP fungsi
     `call_free_limit_sec()`.
   - Rewrite `call_billing_tick`: tanpa gratis, `billable_minutes = ceil(elapsed/60)`,
     idempoten (`yukcoin_consumptions`), afford-guard (saldo tak minus), return
     `per_minute`.
   - **FIX KEAMANAN**: `charge_metered` revoke dari `authenticated` → hanya
     `service_role` (sebelumnya user bisa mendebit coin user lain via param p_caller).
   - Tabel `bonus_claims` (`install_id, kind, user_id, ip`) + RPC
     `credit_welcome_bonus` (service_role, 3 lapis: install_id, IP/24jam, user).
   - Config: `welcome_anon_coins=100`, `welcome_register_coins=100`,
     `welcome_max_claims_per_ip_day=3`.
2. `20261003000100_fix_metered_pricing_public.sql` — `metered_pricing_public`
   error 42703 setelah kolom `call_free_minutes_daily` dihapus → dikembalikan
   tanpa kolom itu.

**Edge function (deploy --use-api):**
- `welcome-bonus` (verify_jwt=true) — tangkap IP server-side (x-forwarded-for),
  panggil `credit_welcome_bonus`.
- `play-topup-verify` (verify_jwt=true) — verifikasi purchase ke Google Play
  Developer API → `credit_play_topup`.

**Verifikasi live:** kolom `call_free_*` = 0 sisa; `metered_pricing_public()`
return audio 6/video 20; `charge_metered` ACL = {postgres, service_role};
`credit_welcome_bonus` ada; 2 edge function ACTIVE.

## 2026-09-30 — Notif "X online" → teman + follower + pernah chat

**Minta user:** saat A online, notifikasinya ke teman, follower, dan orang
yang pernah chat dengan dia (dulu HANYA yang pernah chat).
**Migrasi:** `20260930052500_online_notify_friends_followers.sql` — penerima
`notify_contact_online` = UNION(teman mutual | follower-ku | pernah 1:1
chat); chatId diisi bila ada chat (tap → chat), NULL bila tidak (klien:
tap → profil); skip blokir dua arah (selaras get_online_users; dulu tak
dicek); guard lain utuh (transisi →online; author dummy tak notify).
**Klien:** `_openFromData` — `online` tanpa chatId → `UserInfoScreen`
(sebelumnya jatuh ke chat kosong).
**Apply:** Management API + catat `schema_migrations`.
**Test:** pgTAP `online_notify_test.sql` 6/6 (teman/follower/chatter dapat +
chatId; stranger & diblokir tidak; idle→online notify lagi).

## 2026-10-02 — Deteksi Fake GPS (flag device + heuristik server), tandai saja

**Minta user:** di admin panel bisa tahu lokasi GPS asli atau palsu — flag
device + heuristik; badge/ikon di info lat-long & peta; riwayat perlu.
**Migrasi:** `20261002060000_fake_gps_detect.sql`:
- `profiles` + `location_mocked / location_mock_reason / location_accuracy_m
  / location_flagged_at`; `user_location_history` + `location_mocked /
  mock_reason / accuracy_m`.
- `update_my_location` 4-arg → 6-arg (`+p_mocked`, `+p_accuracy`); overload
  lama DI-DROP. Heuristik: `is_mocked` (device `Position.isMocked`) |
  `accuracy_zero` (akurasi ≤0) | `impossible_speed` (>250 m/s, **butuh jeda
  ≥10 dtk**) | `spoof_delta` (GPS↔IP >500 km). Hanya `p_source='gps'`.
- `admin_stats_detail` (FROZEN, `-- menyentuh:`) + `location_mocked` /
  `mock_reason` di 4 query users_*; `admin_user_detail` location_history +
  `mocked/reason/accuracy_m`.
**Klien:** `LocationService` baru tipe `DeviceFix` (lat/lon/mocked/accuracy)
→ `p_mocked`/`p_accuracy`; provider export `DeviceFix`; 3 call-site
(entry/register/location_picker) diadaptasi.
**Admin UI:** pin peta merah + ikon `gpp_bad` (prioritas), baris koordinat
"GPS (Fake)" + reason, legenda, `stat_detail_sheet`, riwayat di
`user_detail_sheet` (badge).
**Apply:** Management API + catat `schema_migrations`. Snapshot FROZEN
di-regenerate (diff = hanya 4 baris `admin_stats_detail`, 0 hapus).
**Test:** pgTAP `fake_gps_test.sql` 7/7.
**Batasan (SADAR):** `isMocked` bisa dilewati sebagian Fake GPS → indikator,
BUKAN bukti 100%; tidak untuk auto-ban. Ambang heuristik konstanta mudah ubah.

## 2026-09-30 — Fix chatId NULL di payload outbox "online" (temuan review)

**Bug:** penerima tanpa chat 1:1 dapat `chatId: null` → outbox-worker →
send-push `String(null)` = string `"null"` → cek `.isEmpty` klien gagal →
jatuh ke layar chat rusak, bukan profil.
**Migrasi:** `20260930053000_online_notify_chatid_fix.sql` — 1 baris:
`coalesce(contact_chat,'')` di `notify_contact_online`.
**Review lanjutan:** PostCard di layar detail tak refresh (like/komen/share/
follow/boost) karena hanya andalkan `updatePost` provider + rebuild parent —
tambah `_patchLocal` (patch map lokal + setState) di 5 situs; hapus post
dari detail kini pop via callback `onDeleted`.

## 2026-09-29 — Audit notif post timeline (3 kurang diperbaiki)

**Diminta user cek ulang.** Temuan & fix (`20260929220200_timeline_post_notify_audit.sql`):
1. `get_post` belum ada gate ANON_DISABLED (ada di `list_posts`) → anon bisa
   baca post public. Ditambah (bypass dummy & admin, cermin list_posts).
2. Post public dari author **dummy** akan blast semua user asli → cabang
   public→semua kini dilewati bila author dummy (follower/subscriber dummy
   tetap dapat seperti dulu).
3. Klien: tipe FCM `timeline` (topic) lolos dari toggle prefs Timeline →
   `shouldShowForFcmType` kini memetakan `timeline` → toggle `timeline`.
**Test:** pgTAP `timeline_post_notify_test.sql` 13/13 (+anon ditolak, +cek
definisi); prefs timeline on/off hijau.

## 2026-09-29 — Notif post timeline sesuai visibilitas + tap buka postingan

**Minta user:** post PUBLIC → notifikasi untuk SEMUA + tap masuk ke
postingannya; FOLLOWERS → follower saja; SUBSCRIBERS → subscriber saja.
**Temuan:** trigger `notify_post_followers` untuk public hanya ke follower
(+subscriber-non-follower); fanout topic `timeline-all` tembak SEMUA
visibilitas (bocor isi followers/subscribers-only; walau topic belum ada
subscriber); tap `timeline_post` hanya buka tab Timeline (bukan postnya).
**Migrasi:** `20260929213300_timeline_post_notify_all.sql` — cabang `public`
→ loop semua profil registered non-dummy non-exclude (kecuali author; skip
blokir); `notify_timeline_post_fanout` hanya bila `public`; RPC BARU
`get_post(p_id)` (bentuk = item `list_posts`, hormat visibilitas+blokir).
**Klien:** `PostDetailScreen` (pakai ulang `PostCard`); tap
`timeline_post`/`timeline` + `postId` → detail; tanpa postId → tab Timeline.
**Apply:** Management API + catat `schema_migrations`.
**Test:** pgTAP `timeline_post_notify_test.sql` 10/10; `timeline_service_test`
(+getPost) hijau; `post_detail_screen_test` hijau; `flutter analyze` 0/0.

## 2026-09-29 — Privacy picker: kandidat = semua yang pernah chat (registered + anon)

**Keluhan (user):** memilih "Hanya orang tertentu", nama "Kartika"
(registered, pernah 1:1 chat) tidak muncul saat dicari.
**Akar:** `privacy_excludable_users` @20260929130000 hanya menambah chatters
`is_registered = false` (anon) → user registered non-teman tak pernah jadi
kandidat.
**Migrasi:** `20260929140000_privacy_excludable_all_chatters.sql` — buang
syarat `is_registered = false`; kandidat kini = teman | follower-ku |
subscriber aktifku | **pernah 1:1 chat (registered maupun anon)** | sudah di
daftar saya. Limit 300→500.
**Apply:** Management API + catat `schema_migrations`. Verifikasi live: sebagai
`tisubasah` → `privacy_excludable_users()` memuat `Kartika` (is_friend=false).
**Test:** pgTAP `privacy_only_test.sql` 15/15 (+2 assert: chatter registered
muncul; isolated tak muncul).

## 2026-09-29 — Privasi "Hanya orang tertentu" (only) menggantikan circle + fix allowlist

**Keluhan (user):** di Pengaturan › Privasi, memilih opsi "Kenalan" tidak
bisa memilih siapa orangnya; harusnya ada pilihan orang tertentu saja.
**Akar (lebih besar):** `update_privacy_settings` di DB live MASIH 4 nilai
lama (`everyone/friends/except/nobody`) — jadi memilih `circle`,
`everyone_except`, maupun `friends_except` SELALU gagal
(`Invalid presence visibility`) dan tak tersimpan. Keputusan user: ganti
mode otomatis `circle` → `only` = daftar PUTIH yang dipilih manual.
**Migrasi:** `20260929130000_privacy_only_whitelist.sql` — constraint 6
nilai `..._except`, `only`, `nobody` (data `circle`→`only`); drop
`_privacy_is_circle` (tak ada pemakai lain); `privacy_can_view` cabang
`only` → `v_excluded` (whitelist, **menyentuh: privacy_can_view**);
`get_online_users` cermin `only` (join exclusion yang sama = daftar putih);
`update_privacy_settings` allowlist 6 nilai + guard `only` wajib 1+ orang;
`privacy_excludable_users` kandidat diperluas (teman|follower|sub-aktif|
anon-pernah-chat|sudah-di-daftar-`only`).
**Apply:** Management API + catat `schema_migrations`. Verifikasi live:
constraint_ok (`only`), helper circle=0, gate/online has `only`,
update allowlist has `only`, versi tercatat.
**Test:** pgTAP `privacy_only_test.sql` 13/13 (daftar putih lolos; teman
non-daftar DITOLAK; field tanpa daftar tak ada yang lolos; guard `only`
tanpa daftar ditolak; cermin online list). `privacy_test.sql` 6-opsi OK.
Widget `privacy_widget_test.dart` (picker daftar putih) + unit enum hijau.
**Rollback:** constraint `circle`, re-apply gate/online @20260929120000
(helper circle), re-apply `update_privacy_settings` @20260920130000.

## 2026-09-29 — Privasi mode "circle" (Kenalan), nilai visibility ke-6 — DIGANTIKAN

> DIGANTIKAN oleh `20260929130000_privacy_only_whitelist.sql` (di atas):
> mode `circle` otomatis → `only` daftar putih manual; helper
> `_privacy_is_circle` di-drop. Catatan di bawah untuk riwayat.

**Kebutuhan (user):** profil hanya tampil untuk orang tertentu — teman,
follower, subscriber, atau yang pernah chat (termasuk anon). Opsi lama
(teman = mutual saja; pernah-chat-non-teman = stranger) tidak cukup.
Keputusan: mode baru `circle` ( inbound saja: yang follow aku, subscriber
aktifku, teman, pernah 1:1 chat); TANPA `circle_except`; list tetap
tampil+sensor (tidak ada sembunyi-baris baru).
**Migrasi:** `20260929120000_privacy_circle_visibility.sql` — constraint
5→6 nilai; helper baru `_privacy_is_circle()` (follows-inbound | subscription
aktif | `private_chats.participants @>`; mutual tercakup inbound; grants
= pola RPC standar); cabang `circle` di `privacy_can_view`
(**menyentuh: privacy_can_view**, sumber @20260924230000, cabang lama
byte-identik); cermin `circle` di 4 flag + filter presence
`get_online_users` (sumber @20260926020000). Reader lain (presence_for,
avatar_for, nearby, story_tray/slides, profile_public) memanggil gate
langsung → tanpa ubah. `idx_private_chats_participants_gin` sudah ada.
Bukan fungsi FROZEN → snapshot tidak perlu.
**Apply:** Management API + catat `schema_migrations`. Verifikasi live:
constraint_ok, helper ada, gate_ok + mirror_ok via `pg_get_functiondef`.
**Test:** pgTAP `privacy_circle_test.sql` 17/17 (teman/follower/sub-aktif/
chat/anon-chat lolos; stranger/sub-kedaluwarsa/following-searah ditolak;
daftar-kecuali diabaikan; cabang friends utuh; cermin online list +
presence_for). Regresi: privacy 17/17, bypass 7/7, presence 9/9, story
20/20, contract 11/11, schema_sync 44/45 (1 gagal pre-existing nearby
share_location, tak terkait).
**Klien:** enum `circle` + sheet 5→6 opsi + string bilingual
(`privacyCircle`/`privacyCircleDesc`); test widget 14/14 hijau.
**Rollback:** kembalikan visibility pemakai circle → friends, constraint
5-nilai, re-apply gate @20260924230000 + get_online_users @20260926020000.
# MIGRATION_LOG â€” catatan perubahan versi & penerapan

## 2026-09-29 â€” Monitor chat realtime (policy SELECT admin)

**Keluhan (user):** pesan baru di monitor chat admin telat 5-10 detik.
**Akar:** policy SELECT `private_messages` live hanya untuk peserta chat â†’
Supabase Realtime (tunduk RLS) tidak mengirim event ke sesi admin â†’ layar
hanya mengandalkan poll 5 dtk. Tabel sudah di publication realtime.
**Migrasi:** `20260929010000_admin_monitor_realtime_select.sql` â€” policy BARU
`private_messages_admin_select` FOR SELECT USING (`is_admin_request()`);
read-only, hanya admin; user biasa tetap policy peserta; admin sudah baca
semua via RPC (`admin_get_chat_messages_page`) jadi tidak ada akses baru
secara substansi. Bukan fungsi FROZEN â†’ snapshot tidak perlu.
**Apply:** Management API + catat `schema_migrations`.
**Verifikasi live:** policy ada (`pg_policies`), USING = `is_admin_request()`;
`smoke_anon_register.sh` OK; pgTAP `contract` 11/11, `delete_message` 4/4,
`regression` 5/5 hijau. `schema_sync` 44/45 â€” 1 gagal
(`nearby_users() gate share_location`) tidak terkait perubahan ini
(pre-existing, jalur nearby).
**Klien:** tanpa perubahan â€” `_subscribeRealtime` sudah benar, event kini
mengalir; pesan baru tampil instan, poll 5 dtk tinggal fallback.

## 2026-09-26 â€” Video di private chat + video "sekali lihat"

**Kebutuhan (user):** "di private chat di bawah icon tambah, selain foto bisa
kirim video juga tapi dilimit videonya dan dicompress" + "video sama kaya foto
ada timernya cuman timernya untuk sekali lihat AJA (kalo sesuai panjang video
kan)". Keputusan: durasi maks 60 dtk, hasil kompres â‰¤8 MB, preview sebelum
kirim, private dulu (room menyusul).

**Migrasi (bukan FROZEN, kecuali notif):**
- `20260926120000_chat_photos_guard_video.sql` (sesi paralel) â€” guard storage
  izinkan video/mp4 â‰¤20 MB di bucket chat-photos.
- `20260926130000_private_chat_video_type.sql` â€” `private_messages.type` +
  `'video'`; `notify_private_message` body `[Video]` (**menyentuh:
  notify_private_message**).
- `20260926160000_video_once_type.sql` â€” + `video_once` & `video_once_expired`.
  (Timestamp awal `20260926140000` BENTROK dgn sesi paralel
  `messages_allow_location_type.sql` â†’ dinaikkan.)
- `20260926150000_notif_video_label.sql` â€” label `[Video]` untuk ketiga type
  video (**menyentuh: notify_private_message**). Snapshot di-refresh.

**Keputusan desain penting:** `duration_ms` untuk video = PANJANG VIDEO
(playback), BUKAN timer. Karena itu "sekali lihat" video ditandai lewat TYPE
(`video_once`) â€” menumpang duration_ms akan bertabrakan makna (foto memakai
duration_ms sebagai timer countdown).

**Klien:**
- `storage_photo_service.dart`: `chatVideoPath`/`uploadChatVideo`/
  `compressChatVideo` (480p)/`videoDurationMs`; **fix `isPath()`** menerima
  `.mp4`/`.mov` (tanpa ini path video dikira base64 â†’ bubble gagal).
- `chat_photo_send_mixin.dart`: `videoPickToPreview` (validasi durasi â†’
  kompres + progress â†’ poster â†’ preview) + `sendVideoFromPreview`/`_sendVideoLike`
  (optimistic + poin + upload + outbox `uploadKind: 'video'`).
- `chat_video_bubble.dart` (BARU): poster + play + durasi; `locked` untuk
  `video_once_expired`; `VideoPlayerScreen` publik (dipakai preview composer).
- `chat_composer_input.dart`: preview video (play + badge durasi + toggle
  "sekali lihat") + chip "Kirim Video".
- `chat_send_mixin.dart`: router video sebelum foto.
- Outbox flush: cabang `uploadKind == 'video'`.

**Bug yang ditemukan & diperbaiki saat smoke test HP:**
1. Tombol send tetap jadi tombol MIC saat hanya video pending (kondisi
   `hasText/hasPhoto` tak menghitung video) â†’ video tak pernah terkirim.
2. Preview video tak bisa diputar (tidak ada aksi tap) â†’ tombol play sekarang
   membuka `VideoPlayerScreen`.
3. `pendingVideoMs` di mixin berbentuk FIELD â†’ menutupi getter layar â†’ durasi
   selalu 0. Diganti `get` (analyzer menjaga: layar memakai `@override get`).

**Test:** `test/chat_video_bubble_test.dart` 11 assert (label durasi, batas
60 dtk/8 MB, deteksi path, regresi `isPath` video). `analyze` 0 error.


## 2026-09-26 â€” Voice stage global room (`20260926100000`)

- **Fitur:** max 6 mic nyala (audio-only), pendengar unlimited, mic default
  mati, admin/owner mute paksa, keluar room = turun stage otomatis.
- **Isi:** tabel `room_voice_signals` (+index, RLS global/member, realtime)
  + `room_voice_speakers` (+index, RLS select saja); RPC join (enforce max 6
  via heartbeat 45 dtk) / heartbeat / leave / mute (owner/app-admin +
  sinyal v_mute) / sweep; cron `sweep_room_voice` tiap menit.
- **Check:** `check_migrations.sh` OK bersih (policy baru pakai `-- SAFE:`).
- **Apply:** Management API + catat `schema_migrations`. Verifikasi: 2 tabel
  ada, 5 RPC ada, cron job 26 aktif.
- **Client:** `room_voice_service.dart` (mesh audio, pola broadcast) +
  `VoiceMicButton`/`VoiceStageStrip` + wiring `room_chat_screen.dart`
  (global room saja). Test `room_voice_session_test.dart` 3/3.

## 2026-09-26 â€” Admin scale Fase 2: N+1 â†’ agregasi + sheet paginasi

- **`20260926060000`**: `admin_list_dummies_page` â€” `unread` 50Ã— correlated
  â†’ 1Ã— GROUP BY + join (`ai_persona` tetap dikirim).
- **`20260926070000`**: `admin_list_chats_page` â€” total â†’ estimasi reltuples;
  count+max per chat â†’ 1Ã— agregasi (semantik urutan `call` dipertahankan).
- **`20260926080000`**: `admin_user_detail` â€” count via agregasi;
  `location_history` dibatasi 200; kunci JSON tidak berubah.
- **`20260926090000`**: `admin_stats_users_page` (BARU) â€” daftar user
  statistik ber-paginasi; `admin_stats_detail` (FROZEN) tidak disentuh.
  Client `stat_detail_sheet.dart` infinite scroll untuk 4 kunci user.
- Apply via Management API + catat `schema_migrations`; verifikasi definisi
  live per fungsi.

## 2026-09-26 â€” Fix paginasi admin_list_deleted (`20260926050000`)

**Bug:** `LIMIT/OFFSET` di subquery union tanpa `ORDER BY` dalam (urut baru
di agregat luar) â†’ halaman 2+ mengambil baris acak/duplikat saat data banyak.

**Fix:** `order by sort_at desc nulls last` di dalam subquery sebelum limit;
output halaman-1 identik. Dasar = definisi live 20260926000000
(device_count/location_count dipertahankan). Bukan fungsi frozen.
Apply via Management API + catat `schema_migrations`. Verifikasi live:
definisi memuat klausa fix; paginasi deterministik (page1=100, page2=5,
overlap=0, batas urutan benar); EXPLAIN = Index Only Scan via
`deleted_users_deleted_idx`.

## 2026-09-25 â€” Story admin ghost-mode (`20260926030000`)

**Kebutuhan (user):** "chatyuk admin jangan keliatan kalo liat story orang"
+ "hapus yang udah keliatan" â€” admin moderasi story harus invisible.

**Akar:** viewer memanggil `mark_story_seen_bulk` untuk semua user termasuk
admin â†’ baris `story_views(viewer_id=admin)` tercatat â†’ pemilik story melihat
nama admin di daftar penonton.

**Migrasi `20260926030000_story_admin_ghost.sql`** (bukan FROZEN):
- `mark_story_seen`: return ok tanpa insert bila `is_admin_request()` dan
  bukan author sendiri.
- `mark_story_seen_bulk`: WHERE + `(s.author_id = uid or not is_admin_request())`
  â†’ bulk admin hanya mencatat milik sendiri.
- `story_viewers`: filter `not exists (auth.users email=zunixe)` â†’ baris admin
  tidak pernah dikembalikan (walau lolos via client lama).
- CLEANUP: `delete from story_views using auth.users where email=zunixe`
  â†’ jejak yang sudah tercatat terhapus (live: 0 sisa).
- Client `story_viewer_screen.dart`: `_isAdminCached` (init) + skip `_markSeen`
  / buang antrean di `_flushSeen` bila admin lihat story orang â†’ 0 RPC.
- Test: `story_test.sql` +3 assert ghost (single/bulk/viewers).
- Apply via Management API + verified live (single/bulk/viewers true).
- Catatan: `check_migrations --all` masih FAIL timestamp duplikat lama
  `20260926020000` (online_list_about + story_mute) â€” pre-existing, bukan
  dari migrasi ini.

## 2026-09-25 â€” Tentang tampil di kartu Online (`20260926020000`)

**Kebutuhan (user):** isi Tentang tampil di bawah baris gender di halaman
Online. Kolom output baru `about` di `get_online_users` + `presence_for`
(fast-path presence), hormati `about_visibility` + exclusions (pola sama
dengan avatar/last_seen). Kosong/tidak diizinkan â†’ server kirim `''`,
kartu menyembunyikan barisnya. Klien: baris italic maxLines 2 di
`_UserCard`; `UserModel.fromMap`/`toMap` sudah membawa `about` (cache
disk ikut). Bukan FROZEN. Apply via Management API + verified live
(`about_ok`, privacy `about`). Test: `schema_sync_test.sql` +2 assert
(31/31), `online_visibility_test.dart` +3 (24/24).

## 2026-09-25 â€” Riwayat device + GPS tetap di tab Terhapus (`20260926000000`)

**Kebutuhan (user):** "info perangkatnya jangan dihapus di admin sama gpsnya"
+ "riwayat device dan riwayat gpsnya" â€” user yang sudah dihapus harus tetap
menampilkan info perangkat & riwayat GPS di admin panel tab Terhapus.

**Akar:** `delete_my_account` (20260923130000) & `admin_delete_anon_user`
(20260921230000) menghapus eksplisit `user_devices` + `user_location_history`
SEBELUM `delete profiles` (wajib, kalau tidak 23502 NOT NULL). Efek samping:
`admin_deleted_device_history(nickname)` (baca `nickname_snapshot` live) selalu
kosong untuk hapusan baru, dan GPS tak ada RPC-nya di tab Terhapus.

**Migrasi `20260926000000_deleted_device_gps_archive.sql`** (bukan FROZEN):
- `deleted_users` +2 kolom: `devices jsonb`, `locations jsonb` (default `'[]'`).
- `fn_archive_deleted_user` (dasar = live): snapshot â‰¤50 device + â‰¤100 lokasi
  terbaru SEBELUM baris live dihapus; insert mencakup kedua kolom.
- `admin_deleted_device_history`: utamakan snapshot arsip terbaru per nickname,
  fallback ke live yatim (arsip lama).
- BARU `admin_deleted_location_history(p_user_id)` â†’ snapshot GPS/IP arsip.
- `admin_list_deleted`: item arsip +`device_count`/`location_count`
  (pending tetap 0). Live tables tetap dibersihkan (deletion sukses, tab
  Perangkat tanpa orphan).
- Client: `AdminService.getDeletedLocationHistory` +
  `AdminProvider.getDeletedLocationHistory`; `AdminDeletedTab._showDetail`
  fetch device (by nick) + lokasi (by uid); `DeletedDetailSheet` section
  "Riwayat GPS" (hijau=gps, oranye=ip, â‰¤20 terbaru) + string bilingual
  `adminDeletedLocationHistory`/`adminDeletedNoLocation`.

**Apply:** via Management API, versi tercatat di `schema_migrations`.
**Status: DITERAPPLIED & TERVERIFIKASI LIVE** â€” kolom `devices`/`locations` ada;
`admin_deleted_location_history` ada; `fn_archive` memuat `v_devices`/
`v_locations`; `admin_list_deleted` memuat counts. pgTAP baru
`supabase/tests/deleted_archive_test.sql` 8/8 hijau. `flutter test`
`test/admin_service_test.dart` 29/29 hijau (termasuk RPC lokasi baru).
Catatan: arsip LAMA (terhapus sebelum migrasi) tetap kosong â€” snapshot hanya
untuk hapusan setelah migrasi ini.

## 2026-09-25 â€” Email + sort register-terbaru di Reg ringkasan (`20260925061000`)

**Kebutuhan (user):** tab Reg ringkasan admin tampilkan email + sort
register paling baru di atas (bukan online).

**Migrasi `20260925061000_admin_stats_detail_reg_email.sql`** (menyentuh
FROZEN `admin_stats_detail`, header ada; dasar = snapshot live persis):
`'email', email` ke KEEMPAT list user + `users_registered`
`order by created_at desc nulls last` (list lain tetap `last_seen`).
UI `userRow` SUDAH membaca `u['email']` â€” tanpa ubah client.

**Apply:** via Management API, versi tercatat di `schema_migrations`.
**Status: DITERAPPLIED & TERVERIFIKASI LIVE** â€” blok `users_registered`
live memuat email + sort created_at; snapshot diregenerate.

## 2026-09-25 â€” PEMISAH global vs grup + ikon upload (`20260925054000`)

**Kebutuhan (user, tegas):** room buatan explore = GLOBAL ROOM persis
seperti global lama (chat terbuka, tanpa anggota/password); grup (legacy
`'private'`) tampil di tab Grup saja. Kasus: 'Curhat Kehidupan' telanjur
masuk Grup. Ikon room bisa upload sendiri.

**Migrasi `20260925054000_room_global_split.sql`** (menyentuh FROZEN
`create_private_room`, header ada; dasar = live persis):
room kategori â†’ `is_private=false` (GLOBAL, kolom lain sama);
data fix `category <> 'private' AND is_private` â†’ global (1 room:
Curhat Kehidupan); `list_room_explore` + `AND is_private=false`
(grup tidak bocor ke Global Room); `storage_object_owner_ok` (BUKAN
frozen) + cabang `room-icons/<uid>/<file>` (ikon upload, fail-closed
tetap untuk prefix lain).

**Apply:** via Management API, versi tercatat di `schema_migrations`.
**Status: DITERAPPLIED & TERVERIFIKASI LIVE** â€” Curhat Kehidupan
`is_private=False`; explore Indonesia â†’ 11 room semua global;
snapshot diregenerate (diff = hanya tambahan split, tanpa cabang hilang).

## 2026-09-24 â€” Explore room + buat room gratis per kategori (`20260924221000`)

**Kebutuhan (user):** Global Room ala gambar â€” chip kategori (Rame/Game/Musik/
Curhat/...) + satu list gabungan global + grup (member â€¢ online, preview,
badge unread, waktu relatif, Live HANYA grup) + FAB Buat Room gratis.

**Migrasi `20260924221000_room_explore.sql`** (menyentuh FROZEN
`create_private_room`, header ada; dasar = snapshot live persis):
tambah `p_category` (allowlist 10 kategori + `'private'` legacy);
kategori ASLI = GRATIS (skip ledger), terbuka (`approval_required=false`,
`max_members=200`); legacy `'private'` tidak berubah (bayar + antre + 20).
Overload 4-arg lama di-DROP (cegah PostgREST 300, preseden 2026-09-11).
BARU: tabel `room_reads` (unread sync) + RLS own-row;
RPC `list_room_explore(p_country)` (member/online/pesan terakhir/is_live
grup-only/unread) + `mark_room_read(p_room_id)`.

**Apply:** via Management API, versi tercatat di `schema_migrations`.
**Status: DITERAPPLIED & TERVERIFIKASI LIVE** â€” overload tinggal 1;
`list_room_explore('Indonesia')` â†’ 11 room; snapshot diregenerate
(diff = hanya tambahan kategori/gratis, tanpa cabang hilang).

## 2026-09-24 â€” Avatar gender di sheet Ringkasan (`20260924110000`)

**Kebutuhan (laporan user):** daftar user di sheet Ringkasan (Users, Active,
Msgs, Reg, Anon) disamakan Pengguna Online â€” foto + ketahuan laki/
perempuan. Data `gender` sudah ada, tapi `id` (untuk foto) hanya ada di
`users_all`, dan `messages_today` tanpa sender/gender.

**Migrasi `20260924110000_admin_stats_detail_gender_photo.sql`** (menyentuh
FROZEN `admin_stats_detail`, header ada; dasar = definisi live persis):
tambah `'id'` ke users_active/registered/anonymous +
`'sender_id'`/`'sender_gender'` ke messages_today. Murni aditif.

**Client (`admin_panel_screen`):** `userRow` + `msgRow` pakai avatar warna
gender (biru/pink ala Online) + ikon â™‚/â™€ di samping nama; foto via
`AdminAvatarCircle` yang sudah ada (lazy per viewport).

**Apply:** via Management API, versi tercatat di `schema_migrations`.
**Status: DITERAPPLIED & TERVERIFIKASI LIVE** â€” `pg_get_functiondef`
memuat `sender_gender` + `'id', id` Ã—4; snapshot diregenerate
(stamp baru, diff = hanya tambahan itu, tanpa cabang hilang).

## 2026-09-24 â€” Breakdown ukuran tabel di Ringkasan (`20260924100000`)

**Kebutuhan (laporan user):** angka "Database 71MB" di kartu Ringkasan tidak
bisa ditelusur â€” mau diklik lalu terlihat tabel/fungsi mana yang besar untuk
cek pertumbuhan.

**Migrasi `20260924100000_admin_table_sizes.sql`** (fungsi BARU, bukan
FROZEN): `admin_table_sizes(p_limit=30)` â€” guard admin sama seperti
`admin_storage_stats`, return `{db_bytes, tables: [{schema, table,
total_bytes, table_bytes, index_bytes, rows_est}]}`. Hanya baca katalog
(`pg_total_relation_size` + `reltuples` estimasi) â€” tanpa seq-scan.
Fungsi SQL sendiri tidak memakan ruang berarti; yang diukur = tabel (+index).

**Client:** `AdminService.getTableSizes` + `AdminProvider.fetchTableSizes`
(fresh tiap sheet dibuka) + sheet `tablesize_sheet.dart` dari baris Database
(chevron). String admin bilingual baru 6 biji.

**Apply:** via Management API, versi tercatat di `schema_migrations`.
**Status: DITERAPKAN & TERVERIFIKASI LIVE** â€” RPC balas
`db_bytes=74034323` (~71MB âœ… cocok dengan kartu). Top live:
`cron.job_run_details` 35MB (!), `ai_reply_log` ~4MB, `private_messages`
~2.6MB, `call_signals` ~2.2MB, `auth.refresh_tokens` ~1.8MB.

## 2026-09-23 â€” Delete private chat selalu gagal: fix cast trigger (`20260923160000`)

**Masalah (laporan user: gagal delete pesan):**
`deletePrivateMessage` â†’ `update is_deleted=true` selalu di-rollback oleh
trigger `scrub_reply_snapshot_private` yang membandingkan
`replied_to_id (text) = new.id (bigint)` tanpa cast â†’ Postgres error
"operator does not exist: text = bigint". Room aman
(`messages.replied_to_id` bigint). Backfill di migrasi asal sudah pakai
`::text`, hanya trigger yang kelewat.

**Migrasi `20260923160000_fix_private_delete_trigger.sql`** (fungsi non-FROZEN):
`where pm.replied_to_id = new.id::text`.

**Apply:** via Management API, versi tercatat di `schema_migrations`.
**Status: DITERAPKAN & TERVERIFIKASI LIVE** â€” `pg_get_functiondef`
mengandung `new.id::text`.

## 2026-09-23 â€” Hapus akun: fix 23502 user_devices/user_location_history (`20260923130000`)

**Masalah (laporan user: hapus akun anon "hdjdjfj" selalu gagal):**
`delete_my_account()` â†’ `delete from public.profiles` memicu FK
`user_devices.user_id` / `user_location_history.user_id` yang aksinya
SET NULL â€” tetapi kedua kolom `user_id` NOT NULL â†’ `23502 null value in
column "user_id"`. Komentar lama ("hardware milik install, FK SET NULL")
salah asumsi. Akun tanpa device row lolos, sehingga bug tak terdeteksi
(reproduksi awal dgn anon kosong: `{"ok": true}`).

**Migrasi `20260923130000_delete_account_devices_fix.sql`** (fungsi
non-FROZEN; definisi penuh disalin dari live + 2 baris hapus eksplisit
SEBELUM `delete from profiles`; grant tidak diubah):
- `delete from public.user_devices where user_id = v_uid;`
- `delete from public.user_location_history where user_id = v_uid;`

**Apply:** via Management API (bukan `db push`), versi `20260923130000`
dicatat di `schema_migrations`. **Status: DITERAPKAN & TERVERIFIKASI LIVE** â€”
anon + device + location + ledger â†’ `delete_my_account` = `{"ok": true}`,
sisa artefak test 0 (dibersihkan tuntas via pola replica-role).

**Test:** `supabase/tests/delete_account_test.sql` BARU (4 assert, hijau:
hapus eksplisit ada, urutan SEBELUM profiles, komentar usang hilang).
Tanpa rebuild aplikasi (fix server-side; app 1.2.49 sudah memanggil RPC ini).
Lihat `docs/INCIDENT_DELETE_ACCOUNT_23502.md`.

## 2026-09-23 â€” Penonton story: admin bebas + pariti mark_seen (`20260923120000`)

**Masalah (audit fungsi penonton story, versi live diverifikasi via Management
API):**
1. `story_viewers` HANYA mengizinkan author (`s.author_id = auth.uid()`),
   padahal UI (`story_viewer_screen.dart`) menampilkan tombol penonton untuk
   `_own || _isAdmin`. Admin membuka slide dummy â†’ RPC `raise 'Unauthorized'`
   â†’ klien dulu menelan error jadi `[]` â†’ admin melihat "Belum ada penonton"
   (salah, menyesatkan).
2. `mark_story_seen` (single) mendukung `'everyone'/'registered'/'friends'`
   TANPA `'followers'` dan TANPA cek blokir.
3. `mark_story_seen_bulk` mendukung `'everyone'/'followers'/'friends'`
   TANPA `'registered'`.
   Keduanya belum memanggil `privacy_can_view(author,'story')` yang sudah jadi
   sumber kebenaran di `story_slides` + `story_tray` â†’ penonton tidak tercatat
   untuk sebagian kombinasi visibility (daftar penonton kurang).

**Migrasi `20260923120000_story_viewers_admin_markseen_parity.sql`** (3 fungsi
non-FROZEN; signature TIDAK berubah, tanpa `DROP FUNCTION`):
- `story_viewers`: guard jadi author ATAU `public.is_admin_request()`
  (guard admin anti-rentan â€” cek email di DB, bukan hanya klaim JWT).
- `mark_story_seen` + `mark_story_seen_bulk`: daftar visibility DISAMAKAN ke
  `everyone`/`followers`/`friends`/`registered` + cek blokir dua arah +
  `privacy_can_view(author,'story')`.
- Fungsi FROZEN `story_slides` & `create_story` TIDAK disentuh.

**Klien:** `story_service.dart` `fetchViewers` sekarang `List<StoryViewer>?`
(`null` = gagal, `[]` = kosong) â€” dulu keduanya `[]` sehingga kegagalan
menyamar jadi "belum ada penonton"; `story_provider.dart` + `story_viewer_screen.dart`
menampilkan pesan gagal (`storyViewersLoadFail`) bila `null`.

**Apply:** via Management API (bukan `db push`), versi `20260923120000` di-apply
2026-09-23. **Status: DITERAPKAN & TERVERIFIKASI LIVE** â€”
`story_viewers` punya `is_admin_request`; `mark_story_seen` &
`mark_story_seen_bulk` memuat `followers` + `registered` + `privacy_can_view`.

**Test:** `supabase/tests/story_test.sql` BARU (17 assert, hijau);
`test/story_viewer_model_test.dart` BARU + grup `fetchViewers` di
`test/story_social_io_test.dart`. `flutter test` 1025 hijau, SQL tests 11 file hijau.

## 2026-09-22 â€” Privasi "Orang Sekitar": filter blokir + gate berbagi (`20260922140000`)

**Masalah (audit fitur Nearby):**
1. `nearby_users` **tanpa filter `blocks`** â†’ user yang saling memblokir tetap
   muncul di daftar Orang Sekitar (keberadaan + jarak bocor; chat-nya sendiri
   sudah ditolak server).
2. Gate "harus bagikan lokasi dulu" hanya di UI
   (`nearby_screen` `if (!_shareOn)`) â†’ panggilan RPC langsung tetap bisa
   melihat orang lain walau viewer `share_location=false` (bisa "mengintip").
3. `get_online_users` punya lubang blokir **sama** (daftar online tak memfilter
   `blocks`).

**Migrasi `20260922140000_nearby_privacy_blocks_share_gate.sql`** (menyentuh
FROZEN `nearby_users` + non-frozen `get_online_users`):
- `nearby_users`: gate simetris â€” bila `share_location=false` â†’ `raise exception
  'Share required'` (dicek sebelum cek `lat/lon`, sebelum `'No location'`);
  tambah filter blokir dua arah (`blocks`) idiom sama dengan `story_slides`.
- `get_online_users` (kedua overload plpgsql): tambah filter blokir dua arah.
  Tidak ada gate share di sini (online list bukan fitur lokasi).

**Klien:** `lib/config/strings.dart` + `nearbyNeedShareDesc` (bilingual);
`lib/screens/nearby_screen.dart` memetakan error `'share required'` â†’ empty
state "Butuh berbagi lokasi" (dibedakan dari `'no location'`).

**Apply:** via Management API (bukan `db push`), versi `20260922140000` dicatat
di `supabase_migrations.schema_migrations`. **Status: DITERAPKAN 2026-09-22** â€”
terverifikasi live: `nearby_users` punya `public.blocks` + `'Share required'`;
`get_online_users` punya `public.blocks`. Snapshot FROZEN di-regenerate
(`supabase/snapshots/functions.sql`, diff = hanya `nearby_users`). Test pgTAP
`schema_sync_test.sql` +4 assert (29/29 hijau).

## 2026-09-22 â€” Konfigurasi popup update aplikasi (`20260922120000`)

**Fitur:** klien menampilkan popup update saat masuk app bila ada versi baru.
Sumber kebijakan = `app_settings` (bukan hardcode), sehingga admin bisa
mengaktifkan/mengubah tanpa rilis ulang.

**Migrasi `20260922120000_app_update_config.sql`:** tambah 4 kolom ke
`public.app_settings` (idempotent, tanpa DROP/ALTER TYPE, tidak menyentuh
fungsi FROZEN):
- `update_enabled boolean not null default false` â€” saklar fitur (default OFF
  supaya aman dirilis sebelum admin mengisi).
- `latest_version text not null default ''` â€” versionName terbaru (`X.Y.Z`).
- `min_version text not null default ''` â€” batas bawah; versi lokal di bawah
  ini â†’ popup wajib (force).
- `update_notes text not null default ''` â€” catatan rilis (bilingual, teks
  bebas dari admin).

**Klien:** `lib/services/app_update_service.dart` (fetch policy + banding
semver + deteksi installer Play + Play Core flexible/immediate),
`lib/providers/update_provider.dart` (state + snooze 24 jam),
`lib/widgets/update_dialog.dart`. Non-Play (apkpure/admin) â†’ tombol membuka
listing Play di browser.

**Apply:** via Management API (bukan `db push`), lalu catat versi di
`supabase_migrations.schema_migrations`. **Status: DITERAPKAN 2026-09-22** â€”
4 kolom terverifikasi ada; versi `20260922120000` tercatat. Detail + rollback
di `supabase/migrations/APPLIED_VIA_API.md`.

## 2026-09-22 â€” Privacy hardening: tutup bypass REST (`20260922100000`, `20260922110000`)

**Masalah (audit privasi):** setting privasi berfungsi di jalur RPC, tapi bisa
**dilewati via REST langsung** karena RLS `profiles_select`/`user_photos_select`
= `USING(true)` dan kolom sensitif masih ter-grant SELECT ke `anon`+`authenticated`.

**Yang bocor (terverifikasi live):**
- `user_photos.photo` â†’ readable anon+authenticated â†’ **bypass paywall**
  `get_user_photos_access`/`unlock_photo` (foto terkunci bisa dibaca gratis).
- `profiles.status` + `last_seen` â†’ bypass `presence_visibility`/`last_seen_visibility`.
- `profiles.avatar` â†’ bypass `profile_photo_visibility`.
- `story_tray` tidak cek `privacy_can_view(author,'story')` â†’ story "nobody"
  tetap muncul (avatar + count slide) di tray.

**Sudah aman sebelumnya (tidak disentuh):** `lat/lon/lat_gps/lon_gps/lat_ip/
lon_ip/ip_address/email/fcm_token/about` â€” tidak ter-grant; `app_shared_secret`
tak ada SELECT grant.

**Migrasi 1 â€” `20260922100000_privacy_harden_columns.sql`:**
- RPC baru (security definer, grant `authenticated` saja): `presence_for(uuid[])`,
  `avatar_for(uuid)`, `avatars_for(uuid[])`, `my_photos()` â€” semua menerapkan
  `privacy_can_view` + blokir + invisible.
- `revoke select (status, last_seen, avatar, share_location) on profiles`
  â†’ baca via RPC di atas.
- `user_photos`: **revoke table-level SELECT** dulu (grant `arwdDxtm` menutupi
  revoke kolom!) lalu `grant select (id, user_id, photo_preview, created_at)`.
  Foto asli hanya lewat RPC ber-gating (`get_user_photos_access`/`my_photos`).

**Migrasi 2 â€” `20260922110000_story_tray_privacy.sql`:**
- `story_tray` tambah `privacy_can_view(author, 'story', auth.uid())` +
  mask avatar via `profile_photo_visibility`.

**Dampak klien (diubah di commit yang sama):** `chat_service_presence.dart`
(getUserStatus/getUserLastSeen/fast-path/fallback) & `avatar_service.dart`
(get/refresh/prefetch) â†’ RPC; `getPhotos(own)` â†’ `my_photos`, foto orang lain â†’
`get_user_photos_access`; `auth_service_auth.dart` buang kolom revoked dari
copy profil; `user_info_screen.dart` pakai `getPhotosWithAccess`.

**Apply:** Management API (bukan `db push` â€” hang di mesin ini), tercatat di
`APPLIED_VIA_API.md`. **Verifikasi live:** `has_column_privilege('authenticated',
'profiles','avatar','SELECT')=false`, `('anon','user_photos','photo','SELECT')=false`,
`photo_preview`=true; REST anon/authenticated â†’ 403 utk kolom revoked, 200 utk
kolom aman; RPC â†’ 200 (anon RPC â†’ 401); masking avatar terbukti
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


## 2026-09-21 â€” Fix guard `friend_requests` (`20260921220000`)

**Bug (severity tinggi, ditemukan saat menulis `supabase/tests/privacy_test.sql`):**
`_social_registered_guard()` ditulis untuk tabel `follows`
(`new.follower_id`/`new.followee_id`), tetapi trigger
`social_guard_friend_requests` memasang fungsi yang sama di `friend_requests`
(kolomnya `from_id`/`to_id`). Akibatnya **setiap** `INSERT`/`UPDATE`
`friend_requests` gagal `42703 record "new" has no field "follower_id"`.

Dampak nyata:
- `send_friend_request()` & `respond_friend_request()` selalu gagal.
- `_are_friends()` selalu `false` â†’ visibility privacy `'friends'` mati.
- `privacy_friends()` selalu kosong â†’ picker "Teman kecuali" selalu empty.

**Fix:** guard membaca kolom sesuai `TG_TABLE_NAME` (`friend_requests` â†’
`from_id`/`to_id`; selain itu â†’ `follower_id`/`followee_id`). Logika guard
tidak berubah: tetap menolak akun `is_registered = false` (kecuali dummy).

- Apply: Management API (bukan `db push`), tercatat di `schema_migrations`
  (`20260921220000`). Lihat `supabase/migrations/APPLIED_VIA_API.md`.
- Verifikasi live: insert teman antar-registered â†’ sukses; antar-anon â†’
  `SOCIAL_REGISTERED_ONLY` (perilaku benar, bukan lagi 42703).
- Test: `supabase/tests/privacy_test.sql` (23 assert, termasuk seed
  `friend_requests` accepted) + tripwire di `regression_test.sql`.
- `bash scripts/check_migrations.sh --all` â†’ OK bersih.

## 2026-09-20 â€” Privacy: 5 opsi + "kecuali" teman/anon (`20260920130002`â€“`0004`)

Uji coba di HP menemukan 3 bug pada privasi:

1. **Daftar "kecuali" kosong walau punya teman.** Enforcement memakai
   `_are_friends` (friend_requests accepted) sementara aplikasi memakai
   mutual follow â†’ tidak sinkron. Ditambah `privacy_friends()` (`0002`),
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

## 2026-09-20 â€” Privacy fixes (`20260920130001`)

Hasil cek ulang menemukan 4 regresi yang lalu diperbaiki:

1. `nearby_users` memakai `order by 12` padahal hanya 11 kolom â†’ error saat
   dipanggil. Dikembalikan ke `order by 11 asc`.
2. `get_online_users` terlanjur mencabut akses `anon` (perilaku lama:
   `authenticated, anon`). Dipulihkan, dan filter privacy di-INLINE (bukan
   fungsi per baris) supaya listing online tidak melambat.
3. `profile_public` kehilangan `share_location` + `points` milik sendiri â€”
   berdampak ke toggle "bagikan lokasi" di Nearby dan fallback bonus login.
   Dikembalikan khusus untuk pemilik (`about` tetap kosong bagi non-pemilik).
4. `mark_chat_read` saat read-receipt OFF tidak menolkan `unread_counts`
   penerima â†’ badge tidak pernah hilang. Sekarang badge SELALU dinolkan;
   hanya `last_read_at` yang tidak ditulis sehingga centang biru tetap aman.

- Helper `privacy_can_view` dan seluruh RPC privacy tetap dipakai.
- Test: `schema_sync_test.sql` (26 assert) + `test/privacy_provider_test.dart`
  dan `test/privacy_settings_test.dart` lulus.
- `bash scripts/check_migrations.sh --all` â†’ OK bersih.

## 2026-09-20 â€” Privacy settings foundation (`20260920130000`)


- Menambahkan visibility privacy untuk presence, last seen, foto profil,
  about, story, dan read receipts.
- Menambahkan tabel pengecualian teman per pemilik dan field privacy.
- Menambahkan RPC `my_privacy_settings`, `update_privacy_settings`,
  `replace_privacy_exclusions`, dan helper `privacy_can_view`.
- UI `Profile > Pengaturan > Privasi` sudah tersedia dengan pilihan Semua
  orang, Teman, Teman kecuali, dan Tidak ada.
- Default semua visibility tetap `everyone`; read receipts tetap aktif.

## 2026-09-20 â€” Restore guard `ai_always_online` (`20260920120002`)

- **Masalah:** `ai_reply_enqueue` live sudah memiliki pengecualian
  `ai_always_online`, tetapi migration `20260915090000` yang terakhir
  mendefinisikannya di repo belum membawa cabang tersebut.
- **Perbaikan:** migration restore baru mengambil perilaku dari snapshot live,
  mempertahankan toggle AIâ†”AI, `ai_always_reply`, rate limit, logging, dan
  guard agar dummy `ai_always_online` tidak diturunkan ke `idle`.
- **Apply:** diterapkan via Supabase Management API dan versi
  `20260920120002` sudah dicatat di `schema_migrations`.
- **Verifikasi:** `scripts/snapshot_functions.sh` menyimpan 30 fungsi;
  `bash scripts/check_migrations.sh --all` menghasilkan `OK bersih`.

## 2026-09-20 â€” Story viewer inline reply, like, dan share (`20260920120001`)

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

## 2026-09-21 â€” Tab Terhapus: tampilkan anon pending + hapus anon (`20260921210000`)

**Kebutuhan:** di tab "Terhapus", tampilkan BERSAMAAN user terhapus (arsip)
dan user anon yang belum terhapus, dan admin bisa menghapus anon itu supaya
nickname-nya bebas dipakai.

**Sebelumnya:** `admin_list_deleted` hanya membaca `deleted_users` (arsip).
Menghapus anon hanya mungkin lewat `cleanup_stale_anonymous` (>7 hari) atau
`claim_nickname` â€” nickname tertahan sampai 7 hari.

**Perbaikan:**
- `admin_delete_anon_user(p_uid)` â€” hapus 1 user anon: arsip dulu
  (`fn_archive_deleted_user`, reason `admin_delete`), bersihkan
  room_presence/blocks/reports/user_photos/devices/location/contact + chat
  privat, lalu `profiles` & `auth.users`. Menolak REGISTERED & DUMMY
  (cek DUMMY lebih dulu karena dummy ber-`is_registered=true`).
  `coin_ledger` append-only â†’ trigger `coin_ledger_no_delete` dimatikan
  sementara (pola `admin_delete_dummy`).
- `admin_list_deleted(p_limit,p_offset,p_include_pending)` â€” tambah item
  `pending` (anon belum dihapus, `pending=true`, `deleted_at=null`),
  diurut `last_seen`. Signature 2-arg di-DROP.
- Client: service `deleteAnonUser` + `listDeleted(includePending)`,
  provider `deleteAnonUser` (refresh otomatis), UI filter
  Semua/Terhapus/Belum dihapus + badge oranye + tombol hapus di detail.

**Verifikasi live (rollback):** anon `caritemen` â†’ profil & auth terhapus,
arsip 1 baris; user terdaftar â†’ `REGISTERED`; dummy â†’ `DUMMY`.
List: 11 arsip + 84 anon pending = 95 total (sebelumnya 11).

## 2026-09-21 â€” Lokasi: GPS dipisah dari IP + history diperbaiki (`20260921200000`)

**Dua bug nyata (terukur di live DB):**
1. `user_location_history` **0 baris** padahal 66 user ber-`loc_source='gps'`.
   Sebab: migrasi `20260815150000` membuat OVERLOAD 4-arg `update_my_location`
   TANPA logika `insert ... history`; client memanggil yang 4-arg â†’ history
   tidak pernah tercatat.
2. **GPS tertimpa IP** â€” saat GPS gagal fix, fallback IP menulis ke
   `profiles.lat/lon` yang sama â†’ koordinat GPS terakhir hilang.

**Perbaikan:**
- Kolom terpisah `lat_gps/lon_gps/gps_updated_at` + `lat_ip/lon_ip/ip_updated_at`.
  IP **tidak menimpa** GPS; `lat/lon/loc_source` (dibaca peta admin &
  `nearby_users`) = GPS bila ada, else IP â†’ kontrak pembaca tidak berubah.
- Satu jalur RPC `update_my_location` (overload lama di-DROP) yang SELALU
  mencatat history untuk gps & ip.
- Backfill data lama ke kolom sesuai `loc_source`.
- `admin_location_sources()` untuk ringkasan GPS/IP/history.
- Client: pencatatan lokasi hanya saat **online** (`_isLocationEligible`) â€”
  idle/invisible/dummy/banned tidak menulis â†’ yang tersimpan adalah lokasi
  terakhir saat benar-benar aktif.

**Verifikasi live:** GPS (-6.2,106.8) lalu IP (-7.9999,110.9999) â†’
`lat/lon` tetap GPS, `lat_ip/lon_ip` terisi, history 2 baris (gps+ip).

`nearby_users` FROZEN â€” tidak disentuh.

## 2026-09-21 â€” `install_id` pindah ke MediaDrm (`20260921190000`)

**Alasan:** `install_id` lama (`android-<ANDROID_ID>`) berubah saat signing key
/ user profile berbeda â†’ device yang sama tampil sebagai device baru (device
ter-exclude "muncul lagi"). MediaDrm (Widevine) `deviceUniqueId` stabil per
perangkat FISIK: tahan reinstall, ganti keystore, Dual Apps/Second Space.

**Implementasi:**
- Kotlin `MainActivity.mediaDrmDeviceId()` â†’ method channel `deviceUniqueId`.
- Dart `ScreenSecureService.deviceUniqueId()`; `DeviceInfoService.installId()`
  â†’ `drm-<hex>`, fallback `android-<ANDROID_ID>` bila Widevine tak ada.
- `upsert_device` (9-arg) menerima `p_legacy_install_id`: memigrasi baris lama
  milik user yang sama **in-place** + membuang duplikat brand+model yang sama.
  Signature lama (7-arg & 8-arg) di-DROP dulu agar tidak jadi overload.

**Verifikasi live:** HP `24129PN74G` â†’ baris `drm-e21f475d9d83113fb46e08f3547b60c5`
(1.2.43-admin); baris `android-2f218335e9fd56d5` milik uid yang sama
**digantikan**, bukan bertambah (tidak ada duplikat).

## 2026-09-21 â€” INSIDEN: device ter-exclude "muncul lagi" (`20260921170000` + `20260921180000`)

**Gejala:** admin exclude 1 HP, tapi device yang sama **muncul lagi** di tab
Perangkat dengan install_id BERBEDA.

**Akar masalah:** `install_id` = `android-<ANDROID_ID>`, dan Android 8+
meng-scope `ANDROID_ID` ke **(device + user profile + app signing key)**.
Terbukti di DB: model `24129PN74G` punya DUA install_id â€”
`android-2f218335e9fd56d5` (1.2.16â†’1.2.43) dan `android-e29a2f7c3e9624c6`
(hanya 1.2.40). Jadi exclude berbasis device **rapuh**.

**Perbaikan dua arah:**
1. `20260921170000_admin_exclude_cascade_uids.sql`:
   - `admin_list_devices` kini memakai `admin_excluded_uids()` (device **dan**
     uid manual) â€” sebelumnya hanya `excluded_devices`.
   - RPC baru `admin_exclude_device_cascade(p_install_id)`: exclude device
     **sekali** menambahkan semua uid yang pernah login di device itu ke
     `excluded_uids` â†’ exclude tahan walau install_id berubah.
   - Backfill: uid dari device yang sudah ter-exclude dimasukkan (2 â†’ 17 uid).
2. `20260921180000_admin_unexclude_uid_sync.sql`:
   - `admin_set_excluded_devices` menyinkronkan `excluded_uids`: uid yang
     device-nya tidak lagi ter-exclude **dibuang**, tapi uid tanpa baris
     device (anon manual) **dipertahankan**.

**Verifikasi (live `fohcucyyejdryryoxitm`):** cascade 17â†’18 uid; un-exclude
18â†’17 uid + device kembali 3; `admin_list_devices` total 44 baris â†’ 29
(15 milik uid ter-exclude disembunyikan).

**Aturan:** `admin_stats_detail` FROZEN â€” tidak disentuh. Snapshot
`functions.sql` tidak memuat `admin_list_devices`, jadi tidak perlu update.

Setiap migrasi yang di-apply atau di-rename WAJIB dicatat di sini supaya AI/dev
berikutnya tahu. Format: tanggal | versi | aksi | catatan.

## 2026-09-21 â€” INSIDEN: `delete_my_account` gagal untuk user ber-koin (`20260921160000_delete_my_account_ledger_fix.sql`)

**Gejala:** user dengan riwayat koin menekan "Hapus Akun" â†’ error
`coin_ledger is append-only`. Terdampak **177 user** (semua yang punya ledger).
Melanggar syarat Google Play (akun harus bisa dihapus).

**Akar:** `20260911000000_delete_my_account.sql` memanggil
`delete from public.coin_ledger` tanpa menonaktifkan trigger append-only
`coin_ledger_no_delete`. Fungsi sah lain (`admin_delete_chat`, hapus dummy,
purge) memakai `set local session_replication_role = 'replica'` â€” pola TERLEWAT.

**Fix:** bungkus hapus ledger+dummy-poin dengan toggle `session_replication_role`
(replica â†’ origin), persis pola `20260815040000_admin_delete_chat_coinledger_fix.sql`.
Definisi diambil dari LIVE, hanya menambah blok itu.

Verifikasi: `delete_my_account` memuat `session_replication_role` (true);
simulasi hapus ledger user ber-koin â†’ sukses (sebelumnya DITOLAK); migrasi
tercatat di `schema_migrations`. `check_migrations --all` hanya FAIL
pre-existing `ai_reply_enqueue` â€” bukan dari migrasi ini.

## 2026-09-21 â€” INSIDEN: semua pendaftaran gagal (`42501 permission denied for table profiles`)

**Gejala:** login/register anon, Google, & email semuanya gagal; Auth sign-in
sendiri sukses (token terbit) tapi `registerProfile()` ditolak server.

**Akar:** `20260915120000_security_hardening.sql` mencabut SELECT level-tabel
`public.profiles` dan hanya memberi grant kolom publik â€” **tanpa**
`email, ip_address, fcm_token, lat, lon`. PostgREST `upsert`
(`ON CONFLICT DO UPDATE`) butuh SELECT pada KOLOM YANG DITULIS, sehingga upsert
yang menyertakan kolom sensitif â†’ `42501`. Ini pola regresi yang sama dengan
insiden `20260812200000` (direvert oleh `20260812230000`).

**Keputusan:** perbaiki di **KLIEN**, bukan melonggarkan grant (hardening tetap
utuh â€” kolom sensitif tidak bisa di-SELECT publik):
- `auth_service_profile.dart` `registerProfile()`: upsert **kolom publik saja**
  + `update()` terpisah untuk `fcm_token`/`email`/`ip_address` (UPDATE tidak
  butuh SELECT kolom tsb; RLS `profiles_update_own` tetap berlaku).
- `auth_service_auth.dart` `linkGoogleProfile()`: idem (upsert `old` publik,
  email via UPDATE terpisah).

**Tidak ada migrasi DB** (murni klien). Verifikasi HTTP live: anon + email
register â†’ upsert 201/200, update sensitif 204 (sebelumnya 403).

**Pelajaran:** setiap kali `grant select (kolom...)` dipersempit di `profiles`,
WAJIB cek jalur `upsert` klien â€” upsert butuh SELECT semua kolom yang ditulis.
Lihat `lib/services/auth_service_profile.dart` (komentar guard).

## 2026-09-21 â€” Fitur mention `@` (`20260921120000_mentions.sql`)

Apply via Management API + recorded. **Tidak menyentuh fungsi FROZEN**;
hanya menambah kolom dan satu fungsi/trigger baru.

| Objek | Isi |
|---|---|
| `messages.mentions` | `jsonb not null default '[]'` â€” `[{"uid","name"}]` per pesan room/grup |
| `private_messages.mentions` | idem untuk private 1:1 |
| `notify_mention_room()` + trigger `notify_mention_room_trg` | `AFTER INSERT ON messages` â€” push TERARAH hanya ke uid yang di-mention (kecuali sender), token dari `user_devices` â†’ fallback `profiles.fcm_token`, `type='mention'` + `toUid` |

`@all` di-ekspansi di KLIEN menjadi daftar uid eksplisit (hanya private
room/grup oleh owner/admin, cap 100 uid) â€” di global room `@all` dimatikan
total. Private 1:1 sudah punya `notify_private_message` per pesan, jadi
mention di sana hanya highlight (tanpa push tambahan).

Verifikasi: `information_schema.columns` punya `mentions` di kedua tabel;
`pg_trigger` punya `notify_mention_room_trg`; `schema_migrations` memuat
`20260921120000`. Edge `send-push` dideploy ulang (`--use-api`) dengan
`'mention'` ditambahkan ke `dataOnlyTypes`.
`check_migrations --all` FAIL pre-existing lapis 5 (`ai_reply_enqueue`/
`ai_always_online`) â€” bukan dari migrasi ini.

## 2026-09-19 â€” Retensi call otomatis: cron `chatyuk-call-sweep` (`20260919094500_call_sweep_cron.sql`)

Apply via Management API + recorded. **Tidak menyentuh fungsi FROZEN**
(`admin_sweep_calls` bukan anggota `scripts/frozen_functions.txt`) dan tidak
mengubah definisi fungsi/tabel/policy apa pun â€” hanya menjadwalkan.

| Objek | Isi |
|---|---|
| Cron `chatyuk-call-sweep` | `*/5 * * * *` â†’ `select public.admin_sweep_calls()` (idempotent: `unschedule` dulu bila ada) |

**Masalah:** `admin_sweep_calls()` sudah benar (akhiri `ringing` >90 dtk,
`answered` tanpa heartbeat >75 dtk, hapus `call_signals` call selesai >1 jam)
tetapi hanya terpanggil saat admin membuka panel (`admin_service.dart`). Untuk
user biasa: call zombie menggantung & `call_signals` menumpuk. Bukti DB saat
review: 436 baris `calls`, 81 baris `call_signals` tapi **2.160 kB**.

Verifikasi: `select jobname,schedule,active from cron.job where
jobname='chatyuk-call-sweep'` â†’ `*/5 * * * *`, `active=true`;
`schema_migrations` memuat `20260919094500`.
`check_migrations --all` FAIL pre-existing lapis 5 (`ai_reply_enqueue`/
`ai_always_online`) â€” bukan dari migrasi ini.

## 2026-09-19 â€” Dummy idle hilang di app: RPC `dummy_uids()` (`20260919082500_dummy_uids_rpc.sql`)

Apply via Management API + recorded. Tidak menyentuh fungsi FROZEN, tabel,
policy, atau grant yang ada (murni tambah 1 RPC + grant execute).

| Objek | Isi |
|---|---|
| `dummy_uids()` | `SETOF uuid`, `SECURITY DEFINER`, `STABLE` â€” daftar `uid` dummy_accounts; `GRANT EXECUTE` ke `authenticated, anon` |

**Masalah:** di app hanya Sarah (online) tampil, Dhanu (idle) hilang â€” padahal
di admin keduanya ada, dan Dhanu sempat muncul lalu hilang lagi (flapping).
Akar: `dummy_accounts` RLS admin-only (`dummy_admin_all`) â†’ select langsung
dari HP selalu 0 baris (RLS, bukan error) â†’ `_fetchDummyUids()` = set kosong
â†’ `filterRpcOnlineRows` menggugurkan Dhanu sebagai "idle zombie" (idle tanpa
socket hanya lolos via daftar dummy). Online lolos tanpa syarat â€” makanya
Sarah tidak pernah terpengaruh.

**Client:** `_fetchDummyUids()` (`chat_service.dart`) kini `_sb.rpc('dummy_uids')`
(PostgREST kembalikan array uuid â†’ `'$r'` per elemen). Bentuk respons beda
dari `.select()` (bukan Map) â€” jangan kembalikan ke `(r as Map)['uid']`.

**Test:** assert baru di `supabase/tests/contract_test.sql` (`dummy_uids() ada`).

Verifikasi: `select '44d9832a-...'::uuid in (select dummy_uids())` â†’ true;
`flutter analyze` 0 error/warning; `flutter test` 241/241 hijau.
`check_migrations --all` FAIL pre-existing lapis 5 `ai_reply_enqueue`/
`ai_always_online` (sudah gagal sebelum migrasi ini â€” bukan dari migrasi ini).

## 2026-09-18 â€” Optimasi performa story (`20260918120000_story_perf.sql`)

Apply via Management API + recorded. Tidak menyentuh fungsi FROZEN.
Snapshot diregenerasi (hanya berubah baris timestamp).

| Objek | Isi |
|---|---|
| `idx_story_views_story_viewer` | Index `(story_id, viewer_id)` â€” percepat cek "sudah dilihat?" per slide saat `story_views` membesar |
| `mark_story_seen_bulk(uuid[])` | RPC baru â€” tandai banyak slide dalam 1 round-trip; guard visibility/blocks sama seperti `mark_story_seen`; `on conflict do nothing` (idempoten) |

### âš ï¸ `story_tray` SENGAJA TIDAK diubah (rewrite JOIN = REGRESI)

Rencana awal: ubah subquery per-baris (N+1) di `story_tray` jadi
`LEFT JOIN profiles` + `DISTINCT ON` thumb terbaru. **Sudah diukur di DB
live dan hasilnya LEBIH LAMBAT** â€” jadi di-revert ke bentuk asli:

| Skenario | Subquery (asli) | JOIN (rewrite) |
|---|---|---|
| Data asli, 2 author | **0.082 ms** | 0.157 ms |
| Simulasi 300 author / 1200 slide | **29.5 ms** | 51.0 ms |

(per panggilan, rata-rata 100â€“300 iterasi)

Hasil kedua versi **identik** (diverifikasi: 2 author, 0 baris beda di kedua
arah) â€” jadi tidak ada alasan menanggung lambatnya. Planner PostgreSQL sudah
menangani subquery skalar ini dengan baik; JOIN + DISTINCT ON menambah
materialisasi yang tidak perlu.

**Jangan "optimalkan" `story_tray` lagi tanpa mengukur dulu.**

Verifikasi: index ada, RPC ada, `story_tray()` tetap 2 author.
`run_sql_tests.sh` semua lolos. `check_migrations --all` FAIL pre-existing
`ai_reply_enqueue`/`ai_always_online` (bukan dari migrasi ini).

## 2026-09-17 â€” Centang-2 di preview list Pesan (kolom `last_sender_id`)

Migrasi `20260917180000_last_sender_id.sql` SUDAH APPLY via Management API + recorded
di `schema_migrations`. Menyentuh FROZEN `handle_new_private_message` (header ada,
snapshot di-regenerate â€” diff hanya stamp + 1 baris `last_sender_id`, tanpa cabang hilang).

| Objek | Isi |
|---|---|
| `private_chats.last_sender_id` (uuid, nullable) | Pengirim pesan terakhir; diisi trigger tiap pesan baru; backfill 50/50 chat berisi (0 chat berisi tanpa sender) |
| Trigger `handle_new_private_message` | Tambah `last_sender_id = new.sender_id`; cabang preview image/view_once/coin/gift + unread + last_read dipertahankan |

UI: preview pesan terakhir di card list Pesan (`private_chats_screen.dart`) kini
diawali `âœ“âœ“` bila pesan terakhir dariku â€” biru (`primary`) kalau lawan sudah baca
(`lastMessageAt <= lastReadAt[lawan]`), abu kalau belum; tanpa centang bila dari lawan.
Model `PrivateChatInfo.lastSenderId` (fromMap/toMap/copyWith + `_rowToPrivateChat`).

Verifikasi: `flutter analyze` 2 file 0 error 0 warning (infos pre-existing);
`flutter test` 227/227 hijau; `run_sql_tests.sh notif_chat_test.sql` lolos (2 assert baru);
`check_migrations --all` FAIL pre-existing lapis 5 `ai_reply_enqueue`/`ai_always_online`
(sudah gagal di HEAD bersih sebelum migrasi ini â€” bukan dari migrasi ini).

## 2026-09-17 â€” Fitur: long-press ala WA (reaksi + bintang + teruskan) â€” private & room

Migrasi `20260917000000_message_reactions_stars.sql` SUDAH APPLY via Management API.
Tabel baru saja, tidak menyentuh fungsi FROZEN.

| Objek | Isi |
|---|---|
| `message_reactions` | Satu baris = satu user + satu emoji (`chat_type` private/room, `chat_id`, `message_id`, `user_id`, `emoji`, unique per kombinasi) |
| `starred_messages` | Bintang per-user (`user_id`, `chat_type`, `chat_id`, `message_id`, unique per user+pesan) |
| `private_messages.is_forwarded` / `messages.is_forwarded` | Flag label "Diteruskan" di bubble |

UI: tahan pesan â†’ header jadi toolbar (balas/bintang/hapus/teruskan/â€¢â€¢â€¢) + bar emoji
(ðŸ‘ â¤ï¸ ðŸ˜‚ ðŸ˜® ðŸ˜¢ ðŸ™ ðŸ˜ +) mengambang di atas bubble; tap = multi-seleksi.
Badge reaksi + ikon bintang + label Diteruskan tampil di bubble.
Forward: sheet pilih chat/room â†’ kirim ulang dengan `is_forwarded=true`.

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
`ai_reply_enqueue`/`ai_always_online` â€” bukan dari migrasi ini);
`flutter test` 216/216 hijau; tabel + kolom terverifikasi ada di DB live.

## 2026-09-16 â€” Fitur: swipe-to-reply (geser kanan = balas) â€” private & grup

Tanpa migrasi SQL. Murni Dart.

| File | Perubahan |
|---|---|
| `widgets/private_chat_message.dart` | Widget baru `SwipeToReply` (publik) + param opsional `MessageBubble.onSwipeReply` |
| `screens/private_chat_screen.dart` | `onSwipeReply` diisi untuk pesan LAWAN saja (`isMe \|\| isDeleted` â†’ null) |
| `screens/room_chat_screen.dart` | `SwipeToReply(enabled: m.senderId != auth.uid && !m.isDeleted)` membungkus `_MessageBubble` |

**Cara kerja:** `onHorizontalDragUpdate` menggeser bubble 0â€“72 px ke kanan; ikon
reply di kiri muncul & menguat; lepas â‰¥48 px â†’ masuk mode balas, <48 px â†’ balik.

**Jebakan yang sudah dihindari:**
- Pesan SENDIRI tidak di-swipe â€” swipe kanan dari tepi kiri = swipe-back sistem
  iOS, kalau aktif user tidak bisa keluar chat.
- Pakai `onHorizontalDrag*`, BUKAN `Dismissible` (Dismissible menggeser permanen
  & bentrok dengan long-press action bar).
- `SwipeToReply` wajib PUBLIK â€” sempat `_SwipeToReply` sehingga gagal dipakai
  dari `room_chat_screen.dart`.

Detail invariant: `docs/FEATURE_MAP.md` Â§3b.

## 2026-09-16 â€” Perf: buka private chat instan + centang-2 instan + typing ikut scroll

Tanpa migrasi SQL. Murni Dart â€” detail invariant di
`docs/FEATURE_MAP.md` Â§3a (baca dulu sebelum menyentuh file di bawah).

**Masalah (dilaporkan user):**
1. Buka private chat ada jeda (tidak seperti WhatsApp).
2. Centang-2 muncul belakangan â€” padahal kalau sudah pernah dibaca harusnya
   langsung centang-2.
3. Bubble typing tidak ikut scroll bersama pesan.

**Akar masalah & perbaikan:**

| File | Perubahan |
|---|---|
| `private_chats_screen.dart` | Transisi `PageRouteBuilder` 320 ms â†’ 150 ms (sempat 0 ms, dikembalikan karena terasa "patah"); tambah `_warmTopChats()` â€” 6 chat teratas di-prefetch ke memori saat list dimuat |
| `online_users_screen.dart`, `story_viewer_screen.dart` | Transisi ke `PrivateChatScreen` 320 ms â†’ 150 ms |
| `chat_stream_session.dart` | `controller.onListen` = **replay** `_current`. Broadcast tidak menyimpan emit terakhir; emit memori di `initState` hilang sebelum `StreamBuilder` subscribe |
| `private_chat_screen.dart` | `_primeReadFromCache()` baca 2 sumber memori (snapshot live `_privateChatsLast` + `peekRawList`), ambil terbaru â€” sebelumnya hanya `peekRawList` yang bisa basi |
| `private_chat_screen.dart` | `_otherLastRead` jadi **monoton maju** (di stream & kv): nilai null/lebih tua tidak boleh menurunkan centang-2 |
| `private_chat_screen.dart` | `isRead` pakai `!msg.timestamp.isAfter(...)` (`<=`) â€” sebelumnya `isBefore` ketat, pesan dengan timestamp sama tidak ikut centang-2 |
| `private_chat_screen.dart` | Subscription non-kritis (`_subscribeStatus`, `_subscribeTyping`, `_chatInfoSub`, profil lawan, `markAsRead`) ditunda ke post-frame |
| `private_chat_screen.dart` | Toast bonus: `Future.microtask` ke-dobel tiap `build()` â†’ dijaga `_bonusToastScheduled` (sekali per buka chat) |
| `private_chat_screen.dart` | Bubble typing dipindah dari luar `ListView` jadi **item list paling bawah** (`itemCount + 1`, index 0 saat `reverse: true`) supaya ikut scroll |

**Catatan build (bukan migrasi):** flavor admin yang benar = `adminProd`
(bukan `admin`), karena ada dimensi env dev/prod. RK:

```sh
flutter build apk --release --flavor apkpureProd --dart-define=APP_FLAVOR=apkpure \
  --obfuscate --split-debug-info=build/app/symbols
flutter build apk --release --flavor adminProd -t lib/main_admin.dart \
  --dart-define=APP_FLAVOR=apkpure --obfuscate --split-debug-info=build/app/symbols
```

## 2026-09-15 â€” Story harian: expert dikecualikan + panel admin

| Versi | Aksi |
|---|---|
| 20260914150050_admin_get_dummy_stories.sql | RPC baru `admin_get_dummy_stories(p_uid,p_days)` â€” list story harian satu dummy (14 hari) + status terisi/kosong (panel admin) |

**Catatan:** awalnya `...150000` lalu di-rename karena bentrok dengan
`20260914150000_storage_ownership.sql` (session paralel).

**Fix terkait (bukan migrasi):**
- `ai-daily-life`: story harian HANYA untuk dummy `kind='regular'` â€” expert
  (Admin Chatyuk/CS) tidak dibuatkan story.
- `config.toml`: `[functions.ai-daily-life] verify_jwt=false`.
- **INSIDEN**: env `APP_SHARED_SECRET` edge â‰  `app_settings.app_shared_secret`
  â†’ cron `chatyuk-ai-daily-life` gagal diam-diam (pg_net anggap HTTP 200 sukses
  walau body `{"error":"unauthorized"}`). Disamakan via
  `supabase secrets set APP_SHARED_SECRET=<nilai app_settings>`; invoke manual
  kini `ok:true`.

## 2026-09-14 â€” Security: fix Storage IDOR + limit upload server-side

**Masalah (review ulang):** policy bucket `chat-photos` hanya cek
`auth.role() = 'authenticated'` tanpa ownership/path check â†’ IDOR: user
authenticated mana pun bisa overwrite/delete file user lain (avatar, gallery,
voice, story, post).

| Versi | Aksi |
|---|---|
| 20260914150000_storage_ownership.sql | Helper `storage_object_owner_ok(name)` (owner-or-admin per path) + ganti 4 policy bucket `chat-photos` (insert/update/delete wajib owner) + trigger `trg_chat_photos_guard` (whitelist `content_type` + limit 8 MB) |

**Catatan:** path layout mengikuti `storage_photo_service.dart`:
`avatars/<uid>_<ts>.jpg`, `gallery|posts|story|timeline/<uid>/<file>`,
`chat|voice/<chatId>/<file>` (chat/voice divalidasi sebagai peserta `private_chats`).
Admin lewat `is_admin_request()`. Tidak menyentuh fungsi FROZEN.

## 2026-09-14 â€” Audit performa: paginasi & hilangkan fetch tanpa limit

**Masalah:** beberapa RPC/query memuat SELURUH tabel tanpa limit â†’ lag (polling
admin tiap 15â€“30 dtk menarik ribuan baris).

| Versi | Aksi |
|---|---|
| 20260914130050_admin_list_dummies_page.sql | RPC baru `admin_list_dummies_page(p_limit,p_offset)` â€” paging daftar dummy (versi lama `admin_list_dummies()` TIDAK diubah) |
| 20260914140000_friend_request_pagination.sql | RPC baru `friend_request_inbox_page/outbox_page(p_limit,p_offset)` (versi lama tidak diubah) |

**Catatan:** `20260914130050` awalnya ditulis `...130000` lalu di-rename karena
bentrok timestamp dengan `20260914130000_ai_provider_models.sql` (session paralel).

## 2026-09-14 â€” Audit drift kode â†” DB: pulihkan fitur & sinkron pencatatan

**Masalah ditemukan (audit):** 3 fitur rusak di produksi karena migrasi ada di
repo tapi tak ter-apply; 38 versi sudah ter-apply tapi tak tercatat di
`schema_migrations` (drift pencatatan).

**Aksi â€” apply migrasi yang selama ini tertunda:**

| Versi | Fitur dipulihkan |
|---|---|
| 20260909000000_mute_archive_chats.sql | Bisukan & Arsipkan chat (kolom `muted_by`/`archived_by` + RPC `mute_private_chat`/`archive_private_chat`) |
| 20260908000000_room_gift.sql | Kirim gift di room live (RPC `send_room_gift`) |
| 20260914110000_dummy_kind.sql | Filter Expert/Regular di admin (kolom `kind` + `admin_list_dummies`) |
| 20260914110001_dummy_kind_experts.sql | Koreksi set EXPERT (5 akun: Admin Chatyuk, Dr Nara, HardwareExpert, Kang Modal, SoftwareExpert) |
| 20260914110002_expert_flags.sql | Admin Chatyuk `ai_always_reply=true`; HardwareExpert `long_answers=true` |

**Aksi â€” sinkron pencatatan:** 38 versi yang objeknya sudah ada di DB (diverifikasi
via probe `pg_proc`/`information_schema.tables`) dicatat ke
`schema_migrations`. Total kini 246 versi file bertimestamp tercatat (sebelumnya
205). Tidak ada lagi versi file yang belum tercatat.

**Obsolete (JANGAN apply â€” sengaja dihapus):**
- `20260819150001_calls_notify_trigger.sql` + `20260823155000_notify_call_trigger.sql`
  â†’ membuat trigger `notify_call_trigger` yang **redundan** dengan
  `notify_call_ringing_trigger`; sudah dihapus di `20260827000000_notif_fix.sql`.
  Fungsi `notify_call` memang tidak ada di DB (by design).

**Selaraskan kode ke skema (bukan ubah DB):**
- `messages.inserted_at` tidak ada â†’ kode diselaraskan ke `created_at`
  (`room_chat_screen.dart`, `group_media_screen.dart`).
- `room_presence.country/city` tidak ada â†’ pembacaan dihapus di
  `chat_service.dart` (kosongkan, tanpa query kolom nir-skema).

## 2026-09-14 â€” Lapis 6: perbaikan 8 timestamp duplikat

**Masalah:** `supabase_migrations.schema_migrations.version` adalah PRIMARY KEY,
tapi ada 8 pasang file migrasi dengan prefix timestamp SAMA â†’ file kedua tidak
dijamin ter-apply (bergantung urutan filesystem). Ini bikin drift lokalâ†”remote.

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

## 2026-09-14 â€” Lapis 3: harness test SQL

| Versi | Aksi | Catatan |
|---|---|---|
| 20260914100000_sql_test_harness.sql | applied + recorded | schema `supabase_tests` + `check()`/`report()`/`mk_dummy()` |

## 2026-09-27 â€” Dimensi foto post (feed proporsional ala Threads)

| Versi | Aksi | Catatan |
|---|---|---|
| 20260927000000_posts_image_dims.sql | applied + recorded | `posts.image_w/image_h/image_dims` + `create_post(p_image_dims)` + FROZEN `list_posts` output `images/imageW/imageH/imageDims` (4 baris ditambah, 0 dihapus) |

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

## 2026-09-14 â€” INSIDEN: guard mendeteksi regresi live (ai_always_online)

**Kejadian:** saat menerapkan Lapis 6 (apply ulang file migrasi yang di-rename),
`20260913180001_dummy_wake.sql` ter-apply â€” fungsi `ai_presence_tick` versi itu
**tidak punya blok `if ai_always_online`**, sehingga cabang Admin Chatyuk 24/7
hilang di DB live (persis pola regresi lama). Restore-nya ada di
`20260914020000_admin_chatyuk_always_online_restore.sql` yang tidak ikut ter-apply
(urutan).

**Deteksi:** `scripts/run_sql_tests.sh` (test `presence_test.sql`) GAGAL dengan
"definisi memuat cabang ai_always_online" + "always_online â†’ online". Guard
bekerja seperti desain.

**Perbaikan:** apply ulang `20260914020000` â†’ `ai_always_online` kembali (pos=389).
Semua 35 assert hijau kembali.

**Pelajaran (WAJIB):** setelah apply ulang file lama, **re-apply migrasi
"restore/patch" yang lebih baru** untuk fungsi yang sama, ATAU gunakan
`create or replace` dari snapshot terbaru sebagai sumber. Inilah alasan
frozen-functions guard + snapshot ada.

## 2026-09-24 â€” 20260924230000_admin_privacy_bypass.sql (APPLY)

- **Fitur:** toggle Bypass Privasi (Admin > Global Setting). ON + viewer admin
  â†’ `privacy_can_view()` true semua field (foto/status/last_seen/about/story).
  User biasa tidak terdampak (server cek `auth.email()`).
- **Isi:** kolom `app_settings.privacy_bypass_enabled` (default false);
  rewrite `privacy_can_view` (BUKAN frozen â€” tanpa header/snapshot);
  RPC `admin_set_privacy_bypass(p_enabled)` (guard admin); baca via
  `admin_get_point_settings` (full row).
- **Apply:** Management API + catat `schema_migrations`. Verifikasi: kolom
  false, RPC ada, pgTAP `privacy_bypass_test.sql` 7/7.

## 2026-09-26 â€” 20260926010000_location_history_dedupe.sql (APPLY)

- **Temuan:** `user_location_history` penuh ratusan baris koordinat identik
  (tulis tiap 1-2 dtk saat idleâ†’online flap; mis. 1389 baris/7 hari, 18 titik
  beda). Pengambilan GPS-nya benar (titik berubah saat bergerak).
- **Isi:** `profiles` lat/lon tetap update tiap panggilan; baris history
  hanya bila bergerak >50m (`earth_distance`) ATAU titik terakhir >30 mnt.
  Definisi fungsi disalin persis dari live (overload 4-arg dipertahankan).
- **Apply:** Management API + catat `schema_migrations`. Verifikasi:
  def memuat earth_distance + p_ip; cek matematika 0m vs 1135m OK.

## 2026-09-26 â€” 20260926040000_story_mute.sql (APPLY)

- **Fitur:** mute story ala IG (tahan tile tray â†’ Benamkan). Tile jadi
  transparan + pindah paling belakang, tanpa ring; viewer paging melewati
  yang dibenamkan (kecuali tile-nya diketuk sengaja).
- **Isi:** tabel `story_mutes` (RLS deny, tulis via RPC); RPC
  `mute/unmute_story_author` (guard auth, tolak self); rewrite
  `story_tray()` (BUKAN frozen): flag `muted`, `has_unseen` mati bila mute,
  urutan muted terakhir.
- **Apply:** Management API + catat `schema_migrations` (rename 2x karena
  tabrakan timestamp sesi lain: 020000â†’030000â†’040000). Verifikasi: RPC ada,
  pgTAP `story_mute_test.sql` 4/4.

## 2026-09-26 â€” 20260926110000_story_video.sql (APPLY)

- **Fitur:** story VIDEO pendek (maks 15 dtk, polos). Rekam tahan-shutter
  dari kamera app, preview + publish, viewer play + auto-advance durasi.
- **Isi:** kolom stories.media_type/video_path/duration_ms + CHECK;
  rewrite FROZEN create_story (+3 param defaults, validasi path story/ +
  durasi 1-15000ms), story_slides + story_tray (+kolom video/has_video);
  DROP overload lama (hindari PostgREST 300). Policy Storage tak berubah
  (bucket+owner agnostik ekstensi). RLS 10/hari + purge tak berubah.
- **Apply:** Management API + snapshot regenerate (diff aditif) + catat
  schema_migrations. Verifikasi: 1 overload, kolom ada, guard OK,
  pgTAP story_video_test.sql 7/7.

## Catatan story video â€” tanpa migrasi tambahan (pakai 20260926110000)

- Kompres 720p hemat (Â±3 MB) + poster JPEG di `image_path` (kolom lama,
  tanpa kolom `poster_path` baru, tanpa rewrite FROZEN tambahan).
- Cap pasca-kompresi 15 MB (client). Timeout download video 15â†’30 dtk.

## 2026-09-26 â€” 20260926120000_chat_photos_guard_video.sql (APPLY)

- **Masalah:** publish story video SELALU gagal (`gagal membagikan story`).
  Poster JPEG terupload sukses, video ditolak trigger `chat_photos_guard`
  (`Tipe file tidak diizinkan: video/mp4`) â€” guard hanya whitelist gambar+audio.
- **Isi:** tambah tipe video (mp4/quicktime/3gpp/mkv) + batas video 20 MB
  (non-video tetap 8 MB). Fail-closed tipe lain. Server-only, tanpa ubah APK.
- **Apply:** Management API + catat schema_migrations. Verifikasi:
  `pg_get_functiondef` memuat `video/mp4` âœ….

## 2026-09-26 â€” 20260926140000_messages_allow_location_type.sql (APPLY)

- **Fitur:** kirim LOKASI (ala WhatsApp) di private chat & room â€” koordinat
  JSON di kolom `text` (`{"lat":..,"lng":..,"label":".."}`), `type='location'`.
- **Masalah:** `private_messages_type_check` & `messages_type_check` belum
  memuat `'location'` â†’ insert ditolak check constraint.
- **Isi:** tambah satu nilai `'location'` ke kedua constraint (nilai lama
  dipertahankan; idempotent drop+add).
- **Apply:** Management API. Verifikasi (live): kedua constraint kini memuat
  `'location'` âœ… (query `pg_constraint`).

## 2026-09-27 â€” 20260927090000_update_manual_push.sql (APPLY)

- **Fitur:** tombol "Kirim Popup Update" di admin panel â€” admin memicu popup
  update manual (mis. user menekan "Nanti"/snooze, atau catatan penting baru).
- **Isi:** `app_settings.update_push_at timestamptz` (stempel push terakhir)
  + RPC `admin_push_update()` (SECURITY DEFINER, guard `is_admin_request()`,
  set `update_push_at = now()`). Grants: authenticated + service_role.
- **Alur klien:** saat app DIBUKA, klien banding `update_push_at` server vs
  waktu push terakhir yang dilihat (prefs). Lebih baru â†’ tampilkan popup
  walau versi sudah di-snooze. Tidak perlu app dibuka saat push.
- **Apply:** Management API. Verifikasi (live): kolom `update_push_at`
  (timestamptz) + fungsi `admin_push_update` ada âœ….

## 2026-09-27 â€” 20260927100000_profile_birthdate_phone.sql (APPLY)

- **Fitur:** Pengaturan â€º Akun â€” simpan **tanggal lahir asli** (date picker) +
  **nomor HP**.
- **Isi:** `profiles.birth_date date` + `profiles.phone text` (nullable) +
  constraint kewarasan (birth_date 1900..hari ini; phone `^\+?[0-9]{6,20}$`).
- **Privasi:** TIDAK ditambahkan ke RPC publik mana pun â€” hanya pemilik baris
  yang membaca (RLS). Tidak bocor ke user lain.
- **Apply:** Management API. Verifikasi (live): kedua kolom ada âœ….

## 2026-09-27 â€” 20260927120000_index_dedup_and_fix.sql (APPLY)

- **Tujuan:** optimasi index (skala jutaan user) â€” tanpa menyentuh fungsi,
  grant, RLS, atau semantik query apa pun.
- **Dasar audit LIVE** (`pg_indexes`/`pg_index`/`pg_stat_user_indexes`,
  stats_reset 2026-07-24 â€” jadi `idx_scan=0` valid, bukan index baru):
  1. `private_chats`: `idx_private_chats_participants_gin` **DAN**
     `private_chats_participants_gin_idx` â†’ definisi **IDENTIK**
     (`USING gin (participants)`) = duplikat persis.
  2. `private_chats.idx_private_chats_last_message_at_desc` (btree) ADA di file
     `20260829020000_perf_indexes.sql` tetapi **TIDAK ADA di live** (drift),
     padahal `private_chats.idx_scan` = 1,7jt & urutan list chat pakai
     `last_message_at desc` â†’ index ini PERLU ditambahkan.
- **Isi:** (a) ADD `idx_private_chats_last_message_at_desc` (additive, idempotent);
  (b) DROP `private_chats_participants_gin_idx` (duplikat persis, penanda `-- SAFE:`).
- **SENGAJA TIDAK di-drop:** `idx_story_views_story_viewer` â€” kolomnya = pkey,
  TETAPI **dikunci** `supabase/tests/story_test.sql` ('index â€¦ ada') sebagai
  kontrak. Sempat di-drop; test FAIL (19/20) â†’ **di-recreate** & file migrasi
  dikoreksi agar tidak menghapus index itu. Pelajaran: test suite menangkap
  penghapusan yang terlihat "aman" â€” hormati kontrak test.
- **Apply:** Management API `POST /v1/projects/{ref}/database/query`. Versi
  dicatat di `supabase_migrations.schema_migrations` (20260927120000).
- **Verifikasi live:**
  - EXPLAIN list chat â†’ `Index Scan using idx_private_chats_last_message_at_desc` âœ…
  - EXPLAIN RLS chat â†’ `Bitmap Index Scan on idx_private_chats_participants_gin` âœ…
    (duplikat yang di-drop tidak dipakai planner)
  - EXPLAIN story_views â†’ `Index Only Scan using story_views_pkey` âœ…
  - Total index: 163 â†’ 163 (add 1, drop 1, story index di-recreate).
  - `bash scripts/run_sql_tests.sh` â†’ **19/19 file lolos** (schema_sync 31/31,
    story_test 20/20). `check_migrations.sh --all` â†’ OK bersih.
- **Rollback:** `drop index idx_private_chats_last_message_at_desc;` +
  `create index private_chats_participants_gin_idx on public.private_chats using gin (participants);`
- **Backup definisi index sebelum ubah:** `/tmp/chatyuk_idx_backup/indexes_before.json` (163 baris).

## 2026-09-27 â€” 20260927130000_drop_useless_brin_index.sql (APPLY)

- **Tujuan:** lanjutan dedup index. Hanya buang index yang TERBUKTI tidak berguna
  & tidak dikontrak test. Tidak menyentuh fungsi/grant/RLS.
- **Dasar audit LIVE** (`pg_index`/`pg_stat_user_indexes`, stats_reset 2026-07-24):
  - `idx_private_chats_last_message_at_brin` (BRIN) `idx_scan=0`.
  - Kolomnya sama dengan btree `idx_private_chats_last_message_at_desc` (baru
    ditambahkan di `20260927120000`).
  - BRIN berguna hanya bila data TERURUT FISIK; `last_message_at` terus di-update
    ke `now()` â†’ urutan acak â†’ BRIN praktis tak pernah menang (scan=0). Tidak
    dikunci `supabase/tests/*`, tidak disebut fungsi/RPC â†’ drop aman.
- **Isi:** DROP `idx_private_chats_last_message_at_brin` (penanda `-- SAFE:`).
- **SENGAJA TIDAK di-drop** (meski terlihat "terliput" â€” semua idx_scan > 0,
  jadi masih aktif dipakai planner): `user_devices_user_idx` (scan=30.602),
  `idx_coin_ledger_bucket` (scan=18.618), `idx_coin_ledger_user` (94).
  Juga tidak di-drop (scan=0 tapi dipakai fitur): `idx_private_chats_{pinned,
  muted,archived}_by`, `idx_rooms_muted_by`, `idx_posts_country_boost_created`,
  `idx_blocks_reverse`, `user_devices_fcm_idx`, `idx_*_need_migrate`,
  `coin_ledger_pkey` (PRIMARY KEY).
- **Apply:** Management API. Versi dicatat di `schema_migrations` (20260927130000).
- **Verifikasi live:**
  - `pg_indexes` â†’ hanya `idx_private_chats_last_message_at_desc` tersisa âœ…
  - EXPLAIN list chat â†’ `Index Scan using idx_private_chats_last_message_at_desc` âœ…
  - Total index: 163 â†’ 162.
  - `run_sql_tests.sh` â†’ **19/19 file lolos**. `check_migrations.sh --all` â†’ OK.
- **Rollback:** `create index if not exists idx_private_chats_last_message_at_brin
  on public.private_chats using brin (last_message_at);`

## 2026-09-27 â€” Outbox Fase A: edge function `outbox-worker` (ADDITIVE, bukan migrasi)

- **Latar:** 15 fungsi live masih pakai `net.http_post` SINKRON di trigger
  (transaksi INSERT pesan menunggu HTTP round-trip). Tabel `public.outbox`
  sudah ada sejak `20260901020000` tapi **mati** (tak ada worker/cron).
- **Fase A (dilakukan sekarang â€” nol risiko):** deploy edge function
  `outbox-worker` (self-contained, tanpa import `_shared` â€” deploy Management
  API single-file tak sertakan folder itu). Worker: ambil batch `outbox`
  (`sent_at is null`, order id), teruskan `type='push'` â†’ `send-push`
  (header `x-app-secret`), set `sent_at=now()`; gagal â†’ biarkan null (retry);
  baris >24 jam dibuang (anti-backlog). Guard: `x-app-secret` ATAU service_role.
- **TIDAK mengubah perilaku apa pun:** tidak ada trigger yang menulis ke outbox,
  jadi outbox tetap kosong â†’ worker no-op. **Belum ada cron** yang memanggilnya.
- **Deploy:** Management API `POST /v1/projects/{ref}/functions/deploy?slug=outbox-worker`
  â†’ **ACTIVE v1**.
- **Verifikasi live:**
  - invoke worker saat outbox kosong â†’ `{"ok":true,"processed":0}` âœ…
  - insert 1 baris uji (token invalid) â†’ `{"processed":1,"failed":1}`, `sent_at` tetap null âœ…
  - baris uji dibersihkan â†’ `outbox count = 0` âœ…
- **Sisa (Fase B/C â€” BELUM dikerjakan, butuh uji E2E notif):** cron pemanggil
  worker (*/1m) + pindahkan trigger `notify_*` dari `net.http_post` sinkron ke
  `insert into outbox`. Sentuh fungsi FROZEN â†’ butuh header `-- menyentuh:` +
  regen snapshot + uji E2E dummy.

## 2026-09-27 â€” Outbox Fase B: cron worker + notify_mention_room â†’ outbox (APPLY)

- **Tujuan:** mulai memindahkan trigger notifikasi dari `net.http_post` SINKRON
  ke `insert into outbox` (transaksi tulis pesan tidak lagi menunggu HTTP).
- **Migrasi 1 â€” `20260927150000_outbox_worker_cron.sql`:** cron
  `chatyuk-outbox-worker` `* * * * *` memanggil edge `outbox-worker` via
  `net.http_post` (x-app-secret). Saat outbox kosong â†’ no-op.
- **Migrasi 2 â€” `20260927140000_notify_mention_via_outbox.sql`:** ganti
  `perform net.http_post(...)` â†’ `insert into public.outbox (type, payload)`
  di `notify_mention_room` (BUKAN FROZEN). **Logika lain 100% identik** (guard
  mentions, sender_display/avatar, room_name, v_body, loop user_devices,
  fallback profiles.fcm_token) â€” hanya cara kirim yang berubah. Dasar = definisi
  LIVE terbaru (`pg_get_functiondef`).
- **Apply:** Management API (cron dulu, baru trigger). Versi dicatat:
  `20260927140000` + `20260927150000`.
- **Verifikasi live:**
  - cron run: `succeeded` (2Ã— dalam 2 menit) âœ…
  - fungsi: `uses_outbox=true, uses_http=false` âœ…
  - **Uji E2E (dummyâ†’dummy, semua [TEST]):** insert device dummy (token FCM
    PALSU) + insert pesan room `Iran_general` dgn mention ke dummy target â†’
    **outbox terisi 1 baris** (`data.type=mention`, title=General, token target) âœ…
    â†’ jalankan worker â†’ `{"processed":1,"failed":1}` (token palsu ditolak FCM,
    tepat; token nyata akan `sent`) âœ…
  - data uji dibersihkan tuntas: msgs=0, devices=0, outbox=0 âœ…
  - `run_sql_tests.sh` â†’ **19/19 lolos** (mention_test 6/6). `check_migrations` OK.
- **Rollback:** re-apply `notify_mention_room` dari definisi lama
  (`/tmp/notify_mention_room_BEFORE.sql` atau migrasi `20260921120000_mentions.sql`);
  `select cron.unschedule('chatyuk-outbox-worker');`
- **CATATAN PENTING:** mulai sekarang, notif mention BERGANTUNG pada cron +
  edge `outbox-worker` aktif. Bila worker mati, mention tidak terkirim (tapi
  pesan tetap tersimpan â€” bukan data loss, hanya notif). Trigger lain
  (`notify_private_message`, `call_push`, dll) MASIH pakai `net.http_post`
  sinkron (belum dipindah).

## 2026-09-27 â€” Outbox Fase C: notify_private_message â†’ outbox (APPLY)

- **menyentuh: notify_private_message** (FROZEN).
- **Tujuan:** pindahkan jalur notif pesan 1:1 (paling sering) dari
  `net.http_post` sinkron ke `insert into outbox`.
- **Migrasi `20260927160000_notify_private_via_outbox.sql`:** ganti **kedua**
  `perform net.http_post(...)` (cabang `type='call'`/missed_call + cabang pesan
  biasa) â†’ `insert into public.outbox (type, payload) values ('push', ...)`.
  Logika lain 100% IDENTIK (dedup call 30 dtk, resolusi receiver dari
  participants, guard receiver_token, sender_display/avatar, v_body preview
  tipe image/video/voice/coin/gift/teks-200). Dasar = definisi LIVE terbaru.
- **Snapshot:** `scripts/snapshot_functions.sh` dijalankan (30/30 fungsi).
  `git diff supabase/snapshots/functions.sql` = **hanya 2 blok http_post â†’
  outbox + stamp @20260927160000**, 0 baris logika hilang (direview). Guardrail
  `check_migrations.sh --all` â†’ OK bersih.
- **Apply:** Management API. Versi dicatat `schema_migrations` (20260927160000).
- **Verifikasi live:**
  - fungsi: `uses_outbox=true, uses_http=false` âœ…
  - **Uji E2E (dummyâ†’dummy, semua [TEST]):** buat chat [TEST] dummy + isi
    `profiles.fcm_token` target (token PALSU) + insert pesan 1:1 â†’
    **outbox terisi** (`data.type=message`, title sender, token target) âœ… â†’
    worker â†’ `{"processed":1,"failed":1}` (token palsu, tepat) âœ…
  - data uji dibersihkan tuntas (msgs/chats/devices/outbox=0,
    `profiles.fcm_token` dipulihkan ke '') âœ…
  - `run_sql_tests.sh` â†’ **19/19 lolos** (notif_chat 10/10, mention 6/6). âœ…
- **Rollback:** re-apply definisi lama dari `/tmp/notify_private_message_LIVE.sql`
  atau migrasi `20260926150000_notif_video_label.sql` + regen snapshot.
- **âš ï¸ TEMUAN PENTING (belum diubah, butuh keputusan):** `notify_private_message`
  membaca **`profiles.fcm_token`**, BUKAN `user_devices.fcm_token`. Padahal
  `20260827000000` sudah mengosongkan `profiles.fcm_token`. Akibatnya notif
  pesan 1:1 hanya terkirim bila `profiles.fcm_token` terisi (klien lama) â€”
  device klien baru (`user_devices`) tidak menerima. BUKAN regresi dari
  perubahan ini (perilaku lama sudah begitu), tapi titik lemah yang perlu
  dirapikan (arahkan ke `user_devices` + fallback profiles) â€” KANDIDAT LANJUTAN.
- **Fungsi live `net.http_post` sinkron: 14 â†’ 13.**

## 2026-09-27 â€” Outbox Fase D: fix token notif + pindah call ke outbox + test (APPLY)

Tiga langkah sekaligus (semua terverifikasi, data uji dibersihkan).

### D1 â€” helper `user_fcm_tokens` + notif baca `user_devices` (BUKAN profiles)
- **Masalah nyata:** beberapa trigger baca **`profiles.fcm_token`** SAJA
  (legacy, dikosongkan `20260827000000`) â†’ notif TIDAK sampai ke device klien
  baru (`user_devices`). Terbukti saat uji: panggilan masuk (`call_push` 6-arg)
  & chat 1:1 tidak menghasilkan push karena token profil kosong.
- **Migrasi `20260927170000_user_fcm_tokens_helper.sql`:** helper terpusat
  `user_fcm_tokens(uid)` â†’ token dari `user_devices` (aktif) + **fallback**
  `profiles.fcm_token` HANYA bila tak ada device bertoken (kompat klien lama).
  SECURITY DEFINER, read-only, additive.
- **Migrasi `20260927180000_notif_use_user_devices_tokens.sql`:** `call_push`
  (6-arg), `notify_contact_online`, `notify_broadcast_started` â†’ pakai helper.
- **Migrasi `20260927190000_notify_private_use_user_devices.sql`:**
  `notify_private_message` (FROZEN, menyentuh) â†’ token via helper + loop
  (semua device). Payload & logika lain 100% IDENTIK.

### D2 â€” `call_push` (2 overload) + `notify_call_ended` â†’ outbox
- **Migrasi `20260927200000_call_push_via_outbox.sql`** (keduanya FROZEN,
  `-- menyentuh:`). Ganti `net.http_post` â†’ `insert into outbox`. Logika &
  payload identik; `notify_call_ended` tetap set `notif_sent_at` (idempoten).

### D3 â€” test pgTAP (mengunci arsitektur)
- **`supabase/tests/outbox_notif_test.sql` (BARU, 16 assert):** tabel outbox,
  helper, cron `chatyuk-outbox-worker`, trigger notif memakai outbox & TIDAK
  http_post sinkron, token via `user_fcm_tokens`, konsistensi
  `posts.author_name == profiles.nickname`, index kunci skala.

### Verifikasi
- Snapshot `functions.sql` di-regen (30/30). Diff = hanya `net.http_post` â†’
  `insert into outbox` + sumber token; 0 cabang logika hilang (direview).
- Guardrail `check_migrations.sh --all` â†’ OK bersih.
- **Uji E2E (dummy, [TEST]):** `call_push` â†’ outbox `type=call` token device âœ…;
  `notify_private_message` â†’ outbox `type=message` âœ…; worker proses âœ…;
  data uji dibersihkan (devices/outbox=0) âœ….
- **SQL tests: 20/20 file lolos** (outbox_notif_test 16/16, call 18/18,
  notif_chat 10/10, schema_sync 31/31).
- **Fungsi live `net.http_post` sinkron: 13 â†’ 10** (mention, private_message,
  call_pushÃ—2, notify_call_ended sudah pindah).
- Versi tercatat: `20260927170000..20260927200000`.

### Sisa (belum dipindah ke outbox â€” masih `net.http_post` sinkron)
`send_reengage_notifications`, `social_push`, `ai_reply_post`, `ai_proactive_tick`,
`notify_online_fanout`, `notify_room_fanout`, `notify_timeline_*_fanout`,
`notify_contact_online`, `notify_broadcast_started` (Ã—2 = 10 fungsi).
Fanout topical & AI sudah punya pola async sendiri (pg_net non-blocking),
prioritas lebih rendah.

### Rollback
- D1/D2: re-apply definisi lama dari `20260926150000`/`20260913130001` +
  `/tmp/notify_private_message_LIVE.sql`, lalu regen snapshot.
- D1 helper: `drop function public.user_fcm_tokens(uuid);`

## 2026-09-27 â€” Outbox Fase E: contact_online & broadcast â†’ outbox (fanout DIREVERT)

- **Tujuan:** lanjut pindahkan sisa trigger `net.http_post` (+ dukungan
  endpoint majemuk di worker).
- **Migrasi `20260927210000_fanout_and_online_via_outbox.sql`:** pindah 6 fungsi
  ke outbox (4 fanout topical + `notify_contact_online` +
  `notify_broadcast_started`). Worker diperluas (**v2**) mendukung
  `payload.endpoint` = `send-push` (default, back-compat) / `fanout`.
- **Migrasi `20260927220000_revert_fanout_to_http.sql` (REVERT fanout):**
  ditemukan saat uji bahwa edge **`fanout`** mengautentikasi via **service_role
  JWT** (`isServiceRoleJwt`), sedangkan worker memakai `fetch` dgn
  `SUPABASE_SERVICE_ROLE_KEY` yang formatnya tidak dijamin JWT di runtime â†’
  workerâ†’fanout **gagal** (workerâ†’send-push OK karena `send-push` terima
  `x-app-secret`). Daripada mematikan fanout topical (notif online/room/
  timeline), 4 fanout **dikembalikan** ke `net.http_post` (perilaku asli).
  `notify_contact_online` + `notify_broadcast_started` **TETAP via outbox**
  (pakai send-push + x-app-secret, terbukti jalan).
- **Verifikasi:**
  - `notify_contact_online` â†’ outbox `type=online` (3 baris, 1 per kontak) âœ…
  - `notify_broadcast_started` â†’ outbox (send-push) âœ…
  - fanout topical â†’ `http_post` lagi (hp=true, ob=false) âœ…
  - snapshot regen (30/30) + `check_migrations` OK + **SQL tests 20/20 lolos**
  - outbox & data uji bersih (0) âœ…
- **Status akhir `net.http_post` sinkron: 15 â†’ 8** (7 pindah ke outbox:
  mention, private_message, call_pushÃ—2, call_ended, contact_online,
  broadcast_started).
- **SISA 4 fungsi `net.http_post` (SENGAJA tidak dipindah â€” bukan trigger,
  dipanggil cron/RPC, sudah punya pola async sendiri, prioritas rendah):**
  `ai_proactive_tick`, `ai_reply_post`, `send_reengage_notifications`,
  `social_push`, + 4 fanout topical (kembali sinkron karena keterbatasan auth
  edge `fanout`). Untuk memindah fanout ke outbox nanti: samakan auth
  `fanout` agar menerima `x-app-secret` (perlu deploy multi-file `_shared`).
- Versi tercatat: `20260927210000`, `20260927220000`.

## 2026-09-27 â€” Outbox Fase F: fix penumpukan token FCM basi (worker v3 + RPC)

- **Temuan saat verifikasi produksi:** outbox menumpuk ~97 baris (tidak
  terkirim). Setelah investigasi: baris berasal dari **`profiles.fcm_token`**
  yang **basi** (device lama / project Firebase lama `chatyuk-8470e`). FCM
  menolak `404 NotRegistered` / `403 SenderIdMismatch`. Worker lama menandai
  `failed` â†’ retry selamanya â†’ menumpuk.
- **Fix 1 â€” `outbox-worker` v3:** kegagalan **4xx = PERMANEN** â†’ tandai
  `sent_at` (dibuang), jangan retry; 5xx/timeout = transient â†’ retry. Terbukti
  outbox 96 â†’ 0 (30 drop di run pertama, sisanya menyusul; 2 nyata terkirim).
- **Fix 2 â€” `send-push` auto-clean diperluas:** selain `NotRegistered` (404),
  kini juga `SenderIdMismatch` (403) dibersihkan. **Ditemukan bug:** auto-clean
  lama pakai PostgREST `.from('profiles').update().eq('fcm_token', token)`
  â†’ **0 baris** (PostgREST tak bisa filter kolom `fcm_token` karena SELECT
  di-revoke). 
- **Fix 3 â€” RPC `purge_fcm_token(text)` (`20260927230000`, SECURITY DEFINER,
  service_role only):** hapus token dari `profiles` + `user_devices` dengan
  andal. `send-push` kini memanggil `admin.rpc('purge_fcm_token', ...)`.
  Terbukti: 199 â†’ 198 profil (token uji terhapus).
- **Efek:** token basi terbersihkan otomatis seiring waktu â†’ outbox tidak
  menumpuk. Bukan regresi (perilaku lama sama: kirim ke `profiles.fcm_token`
  basi; dulu gagal diam-diam via http_post, kini terlihat & self-healing).
- **Verifikasi:** outbox pending=0 (dikuras cron tiap menit), data uji bersih,
  **SQL tests 20/20 lolos**, `check_migrations` file sesi bersih.
- Versi/deploy: `send-push` v64, `outbox-worker` v3, migrasi `20260927230000`.
- **CATATAN:** ada file `supabase/migrations/20260928000000_unified_yukcoin.sql`
  (BUKAN dari sesi ini) yang membuat `check_migrations --all` DITOLAK (policy/
  grant tanpa `-- SAFE:`). Perlu diperbaiki oleh pembuatnya.

## 2026-09-27 â€” 20260928020000_purge_location_history_90d.sql (APPLY)

- **Tujuan:** retensi `user_location_history` (tabel tumbuh tiap update
  lokasi user). Di jutaan user, tanpa retensi tabel membengkak tanpa batas.
- **Isi:** fungsi `purge_location_history_90d()` (buang baris `created_at <
  now()-90d`, SECURITY DEFINER) + cron harian `purge-location-history-90d`
  (`10 4 * * *`). Data ini hanya dibaca fitur admin untuk riwayat JANGKA
  PENDEK â†’ 90 hari cukup.
- **Zero-impact:** semua baris saat ini < 30 hari â†’ purge = 0 (tabel tetap
  4687). Persiapan skala, bukan perubahan perilaku.
- **Apply:** Management API. Versi tercatat `20260928020000`.
- **Catatan timestamp:** awalnya `20260928010000` BENTROK dengan file lain
  (`20260928010000_align_profiles_points_default.sql`, BUKAN sesi ini) â†’
  di-rename ke `20260928020000` (guardrail timestamp unik). Versi
  `schema_migrations` sudah dikoreksi.
- **Verifikasi:** fungsi ada + cron active âœ…; `purge_location_history_90d()`
  â†’ 0; tabel tetap 4687; **SQL tests 20/20 lolos**.
- **Rollback:** `select cron.unschedule('purge-location-history-90d');
  drop function public.purge_location_history_90d();`

## 2026-09-27 â€” 20260927110000_view_once_video_expire_policy.sql (APPLY)

- **Masalah:** video "sekali lihat" (type='video_once') di private chat TIDAK
  terkunci di penerima â€” bisa diputar ulang selamanya (beda dari foto yang
  terkunci setelah ditonton). Penyebab: policy
  `private_messages_update_view_once` hanya mengizinkan `type =
  'view_once_expired'` (foto) â†’ update penerima ke `video_once_expired`
  DITOLAK RLS (0 baris). Room bahkan belum punya policy expire sama sekali.
- **Isi:** perluas WITH CHECK jadi `type in ('view_once_expired',
  'video_once_expired')` untuk `private_messages` & tambah policy setara
  untuk `messages` (room; global room = semua login, private room = member).
  Qual siapa-yang-boleh TIDAK diubah.
- **Apply:** Management API. Verifikasi (live): kedua policy memuat
  `video_once_expired` âœ….

## 2026-09-27 â€” 20260927120000_admin_chat_messages_media.sql (APPLY)

- **Fitur:** monitor admin bisa MELIHAT semua media di chat: foto biasa,
  video, dan view-once foto/video; call/video-call (teks) juga tampil.
- **Masalah:** `admin_get_chat_messages_page` lama hanya mengisi `image_data`
  untuk view_once; TIDAK mengirim `image_path` â†’ foto biasa & video kosong
  di monitor (FotoCache tak punya path).
- **Isi:** tambah key `image_path`, `is_deleted`, `edited`; `image_data`
  tetap utuh untuk view_once/video_once (+expired). Guard admin TIDAK berubah.
- **Apply:** Management API. Verifikasi (live): fungsi baru terpasang.

## 2026-09-27 â€” Admin lihat SEMUA user (excluded diberi badge) (APPLY)

- **Masalah (user):** "SimpleMe ga muncul di admin padahal online". Ternyata
  SimpleMe **ter-exclude** karena device `drm-10b31...` ada di
  `excluded_devices` (exclude berbasis perangkat menyeret semua akun yang
  login di device itu) + uid-nya juga di `excluded_uids` manual. BUKAN bug
  kode â€” tapi kebijakan menyembunyikan total bikin user asli "hilang".
- **Keputusan user:** admin harus bisa lihat SEMUA (excluded/enggak), cukup
  diberi badge `EXCLUDED`.
- **Migrasi:**
  - `20260928070000_admin_show_excluded_with_flag.sql` â€” `admin_stats_detail`
    (FROZEN, menyentuh): keempat `users_*` **tidak lagi membuang** excluded,
    tambah field `'excluded'`. DUMMY tetap dibuang.
  - `20260928080000_admin_users_page_show_excluded.sql` â€” `admin_stats_users_page`
    (dipakai sheet Users di ringkasan): sama â€” biarkan excluded, tambah flag.
- **SENGAJA TIDAK diubah** (jalur user nyata â€” exclude device = akun test/dev
  TIDAK boleh tampil ke user asli): `list_posts`, `nearby_users`,
  `create_private_room`, `_anon_write_ok`, `_social_registered_guard`,
  `admin_stats_compute` (kartu angka tetap seperti semula).
- **Client:** `usermap_card.dart` â€” buang filter `isHiddenUid` (peta tampil
  semua), tambah badge di detail. `stat_detail_sheet.dart` â€” badge EXCLUDED
  di baris user.
- **Verifikasi live:** `admin_stats_users_page('all',500,0)` mengembalikan
  SimpleMe/AntoSusanto/halo dengan `excluded=true`; snapshot regen (30/30);
  `check_migrations` file sesi bersih; test admin 96/96 lolos.
- **Catatan:** file `20260927120000_index_dedup_and_fix.sql` (sesi lebih awal)
  di-rename â†’ `20260927125000_index_dedup_and_fix.sql` karena bentrok timestamp
  dengan `20260927120000_admin_chat_messages_media.sql` (file paralel).

## 2026-09-28 ï¿½ 20260928110000_drop_profiles_public_view.sql (APPLY)

- **Sumber:** temuan Security Advisor Supabase ï¿½ *"View public.profiles_public
  is defined with the SECURITY DEFINER property"*.
- **Akar masalah:** view milik `postgres` (SECURITY DEFINER = hak OWNER,
  menembus RLS `profiles`), di-GRANT SELECT/INSERT/UPDATE/DELETE/TRUNCATE ke
  `anon` + `authenticated`. Siapa pun bisa `select * from profiles_public` ?
  bocor `avatar`/`last_seen`/`status` SEMUA user (membatalkan hardening yang
  mencabut SELECT profiles.avatar).
- **Isi:** `drop view if exists public.profiles_public;` ï¿½ view LEGACY, 0
  referensi di kode (lib/ & supabase/), 0 dependen (view/fungsi lain).
- **Verifikasi live:** `count(*) profiles_public = 0`; kolom sensitif `profiles`
  (`avatar/last_seen/fcm_token/status`) tetap TANPA SELECT untuk anon/auth
  (hardening utuh).
- **Rollback:** buat ulang dengan `with (security_invoker = true)` agar ikut
  RLS pemanggil (lihat header migrasi).
- **Catatan:** audit lengkap 467 temuan advisor ? `docs/SECURITY_AUDIT.md`
  (profiles_public selesai; berikutnya anon SECURITY DEFINER & search_path).

## 2026-09-28 ï¿½ Security hardening lanjutan (3 migrasi, APPLY)

Lanjutan audit advisor (467 ? 326 temuan). Semua **0 perubahan body** fungsi
(hanya REVOKE/ALTER SET), jadi fungsi FROZEN tidak tersentuh.

- **`20260928120000_revoke_anon_internal_functions.sql`** ï¿½ REVOKE EXECUTE
  56 fungsi internal/trigger/admin (notify_*, *_count_sync, sync_*, admin_*,
  dll.) dari **PUBLIC, anon, authenticated**. Temuan
  `anon_security_definer_function_executable` **88 ? 32**.
  - **Temuan kunci:** `revoke ... from anon` SENDIRIAN tidak cukup ï¿½ Postgres
    memberi EXECUTE ke `PUBLIC` default & anon mewarisinya. Wajib `from public`.
    Terverifikasi `has_function_privilege('anon',...)` baru false setelah ini.
  - Fungsi klien (get_online_users, avatar_for, deduct_chat_point, dst.) TIDAK
    di-revoke ï¿½ diverifikasi tak ada yang putus (`authenticated=true` tetap).
  - Helper lintas-fungsi/policy (is_admin_request, fn_room_role,
    _privacy_are_friends, storage_object_owner_ok, dst.) SENGAJA dibiarkan.
- **`20260928130000_set_function_search_path.sql`** ï¿½ ALTER FUNCTION SET
  `search_path = public, pg_temp` untuk 28 fungsi. Temuan
  `function_search_path_mutable` **28 ? 0**.
- **HIBP** (`password_hibp_enabled=true` via Auth config API) ï¿½
  `auth_leaked_password_protection` **1 ? 0**.
- Verifikasi: `flutter analyze`-0 (tak ada perubahan Dart); advisor re-scan;
  `has_function_privilege`/`proconfig` dicek langsung. Detail: `docs/SECURITY_AUDIT.md`.

## 2026-09-28 ï¿½ 20260928140000_revoke_authenticated_internal_legacy.sql (APPLY)

- **Tujuan:** lanjut audit advisor ï¿½ cabut EXECUTE 38 fungsi internal/legacy
  dari `authenticated` (+PUBLIC+anon). Temuan `authenticated_security_definer_
  function_executable` **221 ? 183**. Total advisor **326 ? 288**.
- **Isi:** REVOKE untuk `admin_*` legacy (register_dummy/renew_dummy_token/
  list_dummies/dummy_uids/ï¿½), `ai_*` tick/cleanup/claim, `ledger_*`,
  `call_push`, `friend_request_inbox/outbox`, `presence_idle_tick`,
  `room_voice_sweep`, `purge_inactive_accounts`, `send_reengage_notifications`,
  `social_push`, `yukcoin_total`, dll. + GRANT balik ke `service_role`.
- **Bukti aman:** semua pemanggil internal fungsi ini **SECURITY DEFINER**
  (diverifikasi: `ledger_spend_dual` ? boost_post/send_gift/unlock_photo/
  create_private_room/extend_private_room; `ledger_spend_paid` ? send_coins/
  subscribe_creator/ledger_spend_dual; `yukcoin_total` ? spend_yukcoin) ?
  definer jalan sebagai owner, rantai TIDAK putus.
- **Tidak direvoke:** 10 helper lintas-fungsi/policy (`is_admin_request`,
  `fn_room_role`, `_anon_*`, `_privacy_are_friends`, `storage_object_owner_ok`,
  `chat_photos_guard`, `user_fcm_tokens`, `privacy_can_view`, `privacy_friends`)
  & semua RPC klien (diverifikasi `has_function_privilege` tetap true).
- **`extension_in_public` SENGAJA DIBIARKAN** (cube/earthdistance ? fitur
  "Orang Sekitar"; pg_net ? notif; pindah schema = risiko tinggi, manfaat 1 lint).
  Alasan lengkap: `docs/SECURITY_AUDIT.md` ï¿½6.

## 2026-09-28 â€” 20260928150000_restore_admin_storage_stats_grant.sql (SUDAH APPLY)

- **Tujuan:** kembalikan EXECUTE `admin_storage_stats()` ke `authenticated`.
  Efek samping hardening `20260928120000` (cabut dari authenticated, sisa
  service_role) â†’ kartu "Penggunaan Data Supabase" di panel admin 403/loading
  terus (app admin login via JWT = role authenticated).
- **Isi:** 1 baris GRANT saja (body fungsi TIDAK disentuh â€” bukan FROZEN).
- **Bukti aman:** guard admin internal di body (`auth.email()='zunixe@gmail.com'`
  atau service_role, selain itu `raise 'Unauthorized'`); preseden
  `admin_table_sizes` memang di-grant ke authenticated.
- **Client:** `getStorageStats`/`getTableSizes`/`getCfUsage` kini timeout 30 dtk
  + kartu tampil error + tombol retry (tidak spinner selamanya).
- **Apply:** via Management API 2026-09-28; versi dicatat di `schema_migrations`.
- **Verifikasi live:** `auth_can_exec=true`, `anon_can_exec=false` (hardening tetap).

## 2026-09-28 â€” 20260928160000_admin_storage_stats_pro_quota.sql (SUDAH APPLY)

- **Tujuan:** kuota kartu admin ikut paket PRO (sebelumnya hardcode FREE tier
  â†’ progress bar penuh padahal pemakaian kecil). DB 512 MB â†’ 8 GB
  (8589934592), storage 1 GB â†’ 100 GB (107374182400) sesuai supabase.com/pricing.
- **Isi:** body disalin utuh dari 20260825170000 (tak ada migrasi lain yang
  menyentuh body); hanya 2 angka kuota + komentar yang berubah. Bukan FROZEN.
- **Apply:** via Management API 2026-09-28; versi dicatat di `schema_migrations`.
- **Verifikasi live:** `qdb=8589934592`, `qstor=107374182400`.

## 2026-09-28 â€” 20260928170000_admin_storage_stats_bandwidth.sql (SUDAH APPLY)

- **Tujuan:** tampilkan batas bandwidth di kartu admin (Pro = 250 GB egress).
  Pemakaian live TIDAK diekspos API mana pun (hanya dashboard Supabase â†’
  Usage), jadi yang ditampilkan = kuota + hint.
- **Isi:** body disalin utuh dari 20260928160000; tambah 2 key output
  (`quota_bandwidth_bytes=268435456000`, `plan='pro'`). Bukan FROZEN.
- **Apply:** via Management API 2026-09-28; versi dicatat di `schema_migrations`.
- **Verifikasi live:** `bw=268435456000`, `plan=pro`.
- **Client:** baris "Bandwidth (egress) â€” Kuota: 250 GB" + hint di kartu
  (string `adminStorageBandwidth`/`adminBandwidthHint`, bilingual).

## 2026-09-28 â€” 20260928180000_restore_admin_dummy_uids_policy_grant.sql (SUDAH APPLY) âš ï¸ INSIDEN

- **GEJALA (laporan user):** SEMUA panggilan (audio & video) gagal â€” pesan
  "Hanya akun terdaftar yang bisa melakukan panggilan" walau
  `app_settings.call_anon_enabled = true`. Timeline juga rusak. Error asli
  dari logcat: `PostgrestException ... permission denied for function
  admin_dummy_uids, code: 42501`.
- **AKAR:** hardening `20260928140000` mencabut EXECUTE `admin_dummy_uids()`
  dari `authenticated`. Tapi fungsi itu dipanggil **DI DALAM policy RLS**
  `calls.calls_insert` (with check) & `posts.posts_select` (qual) â€” dan policy
  RLS dievaluasi sebagai **role pemanggil**, bukan definer. Jadi setiap
  INSERT calls & SELECT posts oleh user login kena 42501 SEBELUM logika toggle
  anon tercapai. (Asumsi "hanya dipanggil trigger/cron/definer" salah untuk
  fungsi ini.)
- **Isi:** 1 baris `grant execute on function public.admin_dummy_uids() to
  authenticated;` (body TIDAK disentuh). `anon` tetap dicabut.
- **Apply:** via Management API 2026-09-28; versi dicatat di `schema_migrations`.
- **Verifikasi live:** `auth_can=true, anon_can=false`; simulasi role
  `authenticated` â†’ `admin_dummy_uids()=14`, `select posts=19` (0 error 42501).
- **âš ï¸ PELAJARAN (untuk audit berikutnya):** fungsi yang dipanggil di
  `qual`/`with_check` policy, VIEW, atau kolom DEFAULT dijalankan sebagai
  caller â€” **TIDAK BOLEH** di-revoke dari role yang memakai policy itu, walau
  fungsinya SECURITY DEFINER. Sebelum REVOKE, scan dulu:
  `select policyname from pg_policies where (qual||with_check) ~ '<fn>';`
  Lihat `docs/SECURITY_AUDIT.md`.

## 2026-09-28 â€” 20260928190000_restore_calls_insert_anon_branch.sql (SUDAH APPLY) âš ï¸ INSIDEN KEDUA

- **GEJALA lanjutan:** setelah 20260928180000 (grant), panggilan MASIH gagal
  "Hanya akun terdaftar yang bisa melakukan panggilan" walau toggle anon ON.
- **AKAR:** policy live `calls_insert` ternyata versi LAMA 20260912000050
  (registered-only absolut, TANPA cabang `call_anon_enabled`), padahal
  `20260912090000_call_anon_toggle.sql` **tercatat applied** di
  `schema_migrations`. Pola "recorded but not actually applied / tertimpa"
  (lihat APPLIED_VIA_API.md). Jadi anon/dummy tetap ditolak RLS.
- **Isi:** re-apply definisi policy versi benar (identik 20260912090000,
  idempoten) â€” tambah cabang `call_anon_enabled` untuk anon & dummy.
- **Apply:** via Management API 2026-09-28; versi dicatat di `schema_migrations`.
- **Verifikasi live:** `has_anon_branch=true`; simulasi INSERT `calls` sebagai
  role authenticated + uid anon (toggle ON) â†’ **berhasil** (return inserted id,
  tanpa 42501). Rollback â†’ data produksi tak tersentuh.
- **CATATAN:** dua insiden berurutan (grant + policy basi) sama-sama membuat
  SEMUA panggilan gagal. Sebelum menyalahkan client, SELALU tarik error asli
  (`debugPrint('[CALL-START] ...')` di logcat) + verifikasi `pg_policies` live,
  bukan hanya `schema_migrations`.

## 2026-09-28 â€” 20260928203000_admin_chat_org_sync.sql (SUDAH APPLY)

- **Masalah (laporan user):** kategori folder monitor chat (mis. "Huha") dibuat
  di HP Xiaomi tidak muncul di HP Redmi. Akar: `admin_chat_org.dart` menyimpan
  PIN + kategori HANYA di SharedPreferences lokal per HP (murni sisi klien).
- **Isi:** tabel `public.admin_chat_org` (1 baris global: `pinned_chat_ids`,
  `category_list`, `category_map` jsonb) â€” RLS enabled TANPA policy (deny
  semua), hanya service_role & RPC security-definer (guard email admin) yang
  akses. RPC `admin_get_chat_org()` + `admin_set_chat_org(text[], text[], jsonb)`.
- **Apply:** via Management API 2026-09-28; versi dicatat di `schema_migrations`.
- **Verifikasi live:** round-trip `admin_set_chat_org` â†’ `admin_get_chat_org`
  mengembalikan `category_list=['Huha']` + map yang benar.
- **Klien:** provider `orgGet`/`orgSet` bridge; load = lokal dulu (instan) lalu
  server (sumber kebenaran); setiap mutasi push ke server. **Seed upgrade:**
  server kosong + lokal ada â†’ dorong lokal ke atas (jangan hapus).
- **âš ï¸ Pelajaran:** fitur "alat kerja admin" yang dulu sengaja lokal (prefs)
  tetap berisiko saat admin pakai >1 HP. Bila ada keluhan "ada di HP A tidak di
  HP B", cek dulu apakah state-nya server atau lokal.

## 2026-09-28 â€” 20260928200000_stagger_cron_schedules.sql (SUDAH APPLY)

- **TUJUAN (stabilitas, bukan fitur):** cron per-menit kehabisan worker pg_cron
  di instance Micro â†’ banyak run gagal `job startup timeout`.
- **BUKTI (live, 24 jam):** `cron.job_run_details` â†’ 414/8956 run gagal (4.6%);
  menit kelipatan 5 pernah 11 job gagal serentak. `SHOW max_worker_processes`
  = 6 (dipakai autovacuum 3 + realtime 2 walsender + pg_net). Ada 5 job
  `* * * * *` TERPISAH + 4 job `*/5` yang menabrak di menit sama.
- **ISI:**
  1. Fungsi BARU `housekeeping_tick()` (wrapper; bukan FROZEN) yang memanggil
     berurutan `presence_idle_tick()`, `room_voice_sweep()`, + 2 DELETE
     cleanup room (sinyal/broadcaster basi). Tiap blok `exception when others`.
  2. Job BARU `chatyuk-housekeeping` (`* * * * *`) â†’ 1 worker, bukan 5.
  3. Lepas 4 job lama per-menit: `cleanup-room-signals`,
     `cleanup-stale-broadcasters`, `chatyuk-presence-idle`, `sweep_room_voice`.
  4. `chatyuk-outbox-worker` â†’ `*/2` (http_post bisa tahan lama; jangan ikut
     tiap menit).
  5. Job `*/5` disebar menitnya (`1-59/5`, `2-59/5`, `3-59/5`).
     `chatyuk-call-sweep` TIDAK diubah â€” dikunci `call_test.sql` (`*/5 * * * *`).
- **CATATAN pg_cron:** format 6-field (detik) TIDAK didukung di instance ini â€”
  job dengan jadwal `0 * * * * *` berhenti total (tidak jalan). Percobaan
  awal pakai detik sudah di-REVERT.
- **Verifikasi live:** maks 5 job/menit (dulu 10-11), **0 gagal** setelah
  perubahan; `housekeeping_tick()` â†’ `{voice_sweep:0, presence_idle:0}`;
  `room_signals`/`room_broadcasters` basi = 0.
- **Test:** `outbox_notif_test.sql` 16/16, `ai_test.sql` 16/16,
  `call_test.sql` 20/20 hijau.
- **Rollback:** `/tmp/chatyuk_cron_backup/jobs_before.json` (definisi awal);
  `cron.unschedule('chatyuk-housekeeping')` + `cron.schedule(...)` job lama.
- **Bukan** fungsi FROZEN â†’ snapshot tidak berubah (revert setelah regenerate
  karena drift `nearby_users` dari sesi lain bukan bagian perubahan ini).

## 2026-09-28 â€” 20260928210000_disable_ai_daily_life_cron.sql (SUDAH APPLY)

- **Tujuan:** hentikan cron `chatyuk-ai-daily-life` (jobid 15, `0 22 * * *`)
  karena belum dipakai â€” mengurangi beban/worker pg_cron.
- **Isi:** `cron.unschedule('chatyuk-ai-daily-life')` (hapus dari scheduler,
  bukan sekadar `active=false`).
- **Verifikasi live:** `count(*) from cron.job where jobname='chatyuk-ai-daily-life'`
  â†’ 0. Total job aktif 17 â†’ 16.
- **Tidak ada test** yang mengunci job ini; tidak menyentuh FROZEN/GRANT/RLS.
- **Aktifkan lagi:** jalankan ulang blok `cron.schedule('chatyuk-ai-daily-life',
  '0 22 * * *', ...)` dari `20260912010000_audit_cleanup_batch.sql`.

## 2026-09-28 â€” 20260928220000_restore_admin_rpcs_execute.sql (SUDAH APPLY) âš ï¸ INSIDEN KETIGA

- **GEJALA (log Postgres):** `42501 permission denied for function
  admin_sweep_calls` & `admin_registrations_daily` berulang. Chart registrasi
  admin + sweep zombie call rusak.
- **AKAR:** hardening `20260928120000` + `20260928140000` memakai daftar
  revoke yang terverifikasi "0 referensi di lib/ sebagai .rpc()" â€” tetapi
  deteksi berbasis grep itu **melewatkan RPC multi-baris** (mis.
  `await _rpc(\n 'admin_registrations_daily', ...)`). Akibatnya 6 fungsi
  admin yang MASIH dipanggil app admin ikut dicabut:
  `admin_sweep_calls`, `admin_registrations_daily`,
  `admin_contact_messages_page`, `admin_contact_set_read`,
  `admin_contact_delete`, `admin_set_privacy_bypass`.
- **KENAPA AMAN dikembalikan:** ke-6 fungsi punya guard internal
  `if coalesce(auth.email(),'') != 'zunixe@gmail.com' then raise`. EXECUTE
  bukan bypass â€” hanya pintu masuk ke guard. Preseden sah:
  `admin_storage_stats` memang authenticated=true + guard sama.
- **Isi:** 6 baris `grant execute ... to authenticated` (body tidak disentuh).
- **Apply:** Management API. Versi dicatat di `schema_migrations`.
- **Verifikasi live:** authoritative `has_function_privilege('authenticated',â€¦)`
  = true untuk ke-6 fungsi; `anon` = false. Simulasi
  `set local role authenticated` â†’ `admin_sweep_calls()` jalan (bukan 42501).
  Cron `chatyuk-call-sweep` kembali `succeeded 1 row`.
- **GUARD BARU:** 8 assert di `supabase/tests/schema_sync_test.sql`
  mengunci: authenticated boleh EXECUTE 7 fungsi admin tsb, anon DILARANG.
- **âš ï¸ PELAJARAN:** audit "0 referensi di lib/" WAJIB pakai parser/pola yang
  menangkap pemanggilan **multi-baris** â€” grep satu baris tidak cukup.
  Scan: `scripts/audit_revoked_rpcs.py` (lihat SECURITY_AUDIT.md).

## 2026-09-29 â€” 20260929000000_fix_cleanup_stale_anonymous.sql (SUDAH APPLY)

- **GEJALA:** log Postgres `P0001 coin_ledger is append-only` berulang +
  `23503` FK `user_devices`/`user_location_history`; **1.597 akun anon stale
  MENUMPUK** (cleanup tak pernah berhasil membersihkan).
- **REPRODUKSI (aman, rollback):**
  `begin; select public.cleanup_stale_anonymous(0); rollback;`
  â†’ `ERROR P0001 coin_ledger is append-only ... delete from auth.users`.
- **AKAR (3 defect di fungsi lama):**
  1. `delete from auth.users` cascade ke `coin_ledger` (FK ON DELETE CASCADE)
     tapi trigger append-only `coin_ledger_no_delete` menolak cascade â†’
     error. (`delete_my_account`/`admin_delete_anon_user` sudah benar.)
  2. `delete from public.profiles` dijalankan SEBELUM user_devices/
     user_location_history dihapus â†’ FK SET NULL vs kolom NOT NULL â†’ 23503.
  3. Loop TANPA `exception` per-user â†’ SATU user gagal membatalkan SELURUH
     cleanup â†’ akun stale menumpuk.
- **Isi:** redefine fungsi mengikuti pola `delete_my_account` yang terverifikasi
  (hapus device/location lebih dulu; hapus coin_ledger + point_events dengan
  trigger dimatikan; `exception when others` per user).
- **Verifikasi live (rollback):** `would_delete=1683`, TANPA error append-only.
- **GUARD BARU:** 2 assert `schema_sync_test.sql` (fungsi wajib menyebut
  disable trigger coin_ledger + hapus devices/location + `exception when others`).
- **âš ï¸ PELAJARAN:** setiap loop hapus-user WAJIB bungkus `exception` per user â€”
  satu baris bermasalah (mis. ledger) tidak boleh menggagalkan migrasi data
  massal, kalau tidak akun stale diam-diam menumpuk berbulan-bulan.

## 2026-09-29 â€” 20260929020000_reduce_presence_write_load.sql (SUDAH APPLY)

- **Konteks:** stall panel admin (57014/timeout). Akar UTAMA = compute **Nano**
  (RAM 0,5 GB, I/O 11 MB/s) â€” DIPERBAIKI dengan upgrade ke **Micro** (RAM 1 GB,
  I/O 87 MB/s, harga SAMA) via API `billing/addons`. Lihat PERFORMANCE.md Â§22.
- **Migrasi ini = perbaikan pendamping** (mengurangi volume tulis profiles):
  1. `notify_online_fanout` AFTER â†’ **BEFORE UPDATE**: set
     `new.last_online_notified_at` langsung, hapus `UPDATE profiles` NESTED
     (dulu 1 transisi status = 2Ã— tulis + 9 trigger profiles dipicu ulang).
  2. `notify_online_fanout` + `notify_contact_online` **skip akun dummy**
     (14 bot ikut fanout tiap `ai_presence_tick` tiap 5 menit â†’ http_post +
     outbox spam; 94 chat berisi dummy).
  3. `housekeeping_tick` pangkas `cron.job_run_details` > 7 hari.
- **Verifikasi live:** trigger `profiles_online_fanout_trigger` = BEFORE UPDATE
  (`tgtype` bit); uji transisi dummy online â†’ `net._http_response` TIDAK nambah
  (224 â†’ 224); `housekeeping_tick()` â†’ `cron_purged` kendali jalan.
- Bukan fungsi FROZEN. Snapshot FROZEN TIDAK berubah (revert diff `nearby_users`
  pre-existing dari sesi lain).


## 2026-09-29 — Panggilan Terbaru (fitur klien, TANPA migrasi)

- **Fitur:** menu ⋮ tab Pesan → halaman "Panggilan Terbaru" (riwayat call
  masuk/keluar ala WhatsApp). Tap baris → buka chat; ikon call → panggil ulang
  jenis terakhir (audio→fullscreen, video→mode chat).
- **Data:** tabel `public.calls` yang SUDAH ADA — RLS `calls_select`
  (`auth.uid() = caller_id OR callee_id`) otomatis membatasi ke user sendiri.
  Query client `.or(caller_id.eq.me,callee_id.eq.me)` → **tidak ada perubahan
  DB, tidak ada RPC baru, tidak ada grant/RLS yang disentuh.**
- **Kode:** `lib/services/call_service.dart` (`listMyRecentCalls`,
  `lookupNicknames`), `lib/providers/call_provider.dart` (passthrough),
  `lib/core/call/call_history_entry.dart` (murni), `lib/screens/call_history_screen.dart`,
  `lib/screens/chats_screen.dart` (item menu), `lib/config/strings.dart` (7 getter).
- **Verifikasi:** `flutter analyze` 0 error/0 warning; `test/call_history_test.dart`
  14/14 hijau; `check_screen_boundary.sh` — file baru 0 import services.

## 2026-10-01 — Setup Produk Google Play (in-app products) + secret edge function

- **Masalah:** Play Console blokir pembuatan produk: "Aplikasi belum memiliki
  produk sekali beli — harus menambahkan izin PENAGIHAN ke APK". APK rilis
  (1.2.61) di-upload sebelum `in_app_purchase` ditambahkan.
- **Fix:** bump 1.2.62+84 → build AAB `playProd` (izin `com.android.vending.BILLING`
  ikut dari plugin) → upload ke **internal testing** via Play Console. Blokir
  terbuka.
- **Produk dibuat via Google Play Developer API** (service account
  `chatyuk-play-upload@chatyuk-7c9e4`, sudah ada di `fastlane/google-play.json`,
  ter-gitignore):
  - Endpoint: `PATCH .../v3/applications/{pkg}/onetimeproducts/{id}?allowMissing=true&regionsVersion.version=2026/01&updateMask=listings,purchaseOptions`
    (catatan: path **huruf kecil** `onetimeproducts`; bahasa listing `id`).
  - Aktivasi: `POST .../oneTimeProducts/-/purchaseOptions:batchUpdateStates`
    (`activatePurchaseOptionRequest`, purchaseOptionId `buy`).
  - 5 produk ACTIVE: `chatyuk_coins_700`/1850/3900/8200/21500 =
    Rp 10.000/25.000/50.000/100.000/250.000 (sinkron `topup_packages`).
- **Secret edge function** (`play-topup-verify`): `GOOGLE_PLAY_SA_JSON`
  (isi `fastlane/google-play.json`), `ANDROID_PACKAGE_NAME=com.chatyuk.chatyuk`.
- **Verifikasi:** kelima produk `state=ACTIVE` + harga IDR sesuai.
