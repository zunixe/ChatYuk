# MIGRATION_LOG — catatan perubahan versi & penerapan

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
