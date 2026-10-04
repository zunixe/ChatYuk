# SOCIAL_GRAPH — Follow / Teman / Subscribe (ChatYuk)

> **Untuk AI/dev berikutnya.** Dokumen ini menjelaskan 3 sistem relasi sosial
> ChatYuk, perbedaannya, efeknya ke fitur lain, dan **dua definisi "teman"**
> yang sengaja dibiarkan berbeda. Cari fitur di `FEATURE_MAP.md`, cari aturan
> relasi di sini.
>
> Sumber kebenaran SQL = `supabase/snapshots/functions.sql` (auto-generate).
> Migration fondasi = `supabase/migrations/20260816040000_social_graph.sql`.

---

## 1. Tiga sistem relasi

| Sistem | Tabel | Arah | Persetujuan | Biaya |
|---|---|---|---|---|
| **Follow** | `follows` | Satu arah (A→B) | Tidak | Gratis |
| **Teman** | `friend_requests` (accepted) + 2 baris `follows` | Dua arah | Ya (accept) | Gratis |
| **Subscribe** | `subscriptions` | Satu arah | Tidak | Berbayar (YukCoin) |

Subscribe **terpisah** dari Follow/Teman — jangan dicampur. Pembahasan
subscribe ada di akhir dokumen.

---

## 2. Perbedaan Follow vs Teman

| Aspek | **Follow** (`follows`, 1 arah) | **Teman** (`friend_requests` accepted → mutual follow) |
|---|---|---|
| Arah | Satu arah (A ikut B; B belum tentu ikut A) | Dua arah (timbal balik) |
| Cara | Tap "Ikuti" — tanpa persetujuan | "Tambah Teman" → kirim request → lawan **Terima** |
| Baris DB | insert 1 baris `follows` | 1 baris `friend_requests` (accepted) **+ 2 baris `follows`** |
| Efek utama | Post B muncul di Feed → tab **Mengikuti** | Buka fitur privacy tingkat "teman" + story "friends" |
| Notif | "X mulai mengikuti kamu" (1 arah) | "X mengirim permintaan teman" + badge inbox |
| Tombol UI | `btnFollow` / `btnUnfollow` (teks) | `btnAddFriend` / `btnFriendRequested` / `btnFriends` (ikon) |

**Dipisah visual dengan sengaja:** Follow = tombol **teks**, Tambah Teman =
tombol **ikon**. Tujuannya agar user sadar keduanya berbeda (lihat
`lib/widgets/leaderboard_sheet.dart`).

### Yang HANYA didapat dari Teman (mutual)
1. **Privacy per-field** (`privacy_can_view`): presence, foto profil, last_seen,
   about, story — bisa diset "Hanya Teman".
2. **Story visibility `friends`** (`_are_friends` di policy `stories`/`story_slides`).
3. **Daftar "Teman kecuali"** (`privacy_friends`, `privacy_excludable_users`).
4. **Timeline post `visibility = 'friends'`**.
5. **Story tray** menampilkan story teman.

### Yang HANYA didapat dari Follow
1. Tab **Feed → "Mengikuti"** (`timeline scope 'following'`).
2. **Post visibility `followers`** (follower-only).
3. **Story visibility `followers`**.
4. **Notif post baru** dari akun yang di-follow (`notify_post_followers`).
5. **Top Aktif / leaderboard** follow cepat.

---

## 3. ⚠️ DUA definisi "teman" (SENGAJA berbeda)

Ada **dua** helper berbeda di DB. Ini **bukan bug** — masing-masing dipakai
untuk kebutuhan yang berbeda:

| Helper | Definisi | Dipakai oleh |
|---|---|---|
| `_are_friends(a,b)` | `friend_requests.status = 'accepted'` | **Story**: `stories`, `story_slides`, `story_tray`, `mark_story_seen` |
| `_privacy_are_friends(a,b)` | **Mutual follow** (`follows` dua arah) | **Privacy**: `privacy_can_view`, Top Aktif (`activity_leaderboard`), `privacy_friends`, `privacy_excludable_users` |

Definisi:
- `_are_friends` → `supabase/migrations/20260906000000_stories.sql:57`
- `_privacy_are_friends` → `supabase/migrations/20260920130003_privacy_friends_mutual.sql:21`

**Kenapa dibiarkan berbeda?** Because the app's "Teman" list
(`SocialProvider.friends`, filter "Teman" di chat, profil) memakai **mutual
follow** (`social_list('friends')`), sedangkan story memakai `friend_requests`
accepted. Menyatukan keduanya berisiko mengubah visibilitas story secara
global. Keputusan: **biarkan 2 definisi**, tetapi pastikan keduanya
**konsisten saat putus teman** (lihat §4).

> **Aturan untuk dev:** kalau kamu mengubah salah satu definisi, cek dampaknya
> ke 2 sisi: story (`_are_friends`) DAN privacy/Top Aktif (`_privacy_are_friends`).
> Jalankan `supabase/tests/privacy_test.sql`.

---

## 4. Aturan putus teman (`unfollow_user`) = putus PENUH

`unfollow_user(p_followee)` (migration
`20261006070000_unfollow_clears_friend_requests.sql`) menghapus:
1. baris `follows` saya→dia, **DAN**
2. baris `friend_requests` (accepted & pending) **kedua arah** antara saya & dia.

Alasan: dulu hanya `follows` yang dihapus → `_are_friends` (friend_requests
accepted) tetap TRUE → **story mantan teman masih terlihat (stale)**.
Dengan fix ini, `_are_friends` dan `_privacy_are_friends` **selaras** setelah
putus teman.

> Catatan: karena Teman = mutual follow, "berhenti mengikuti" satu arah saja
> (via tombol `btnUnfollow`) sekaligus memutus status teman. Tidak ada tombol
> "putus teman" terpisah.

### UI: cara memutus pertemanan / membatalkan permintaan (2026-10)

Karena unfollow = putus penuh, agar user tidak bingung, layar profil
(`user_info_screen.dart`) memakai **label & aksi dinamis**:

| Status saat ini | Tombol 1 (Teman) | Tombol 2 (Follow) |
|---|---|---|
| Belum apa-apa | "Tambah Teman" (`_addFriend`) | "Ikuti" (`_toggleFollow`) |
| Sudah kirim permintaan | **"Batalkan"** (`_cancelFriendRequest` → dialog konfirmasi) | "Ikuti" / "Berhenti Ikuti" |
| Sudah berteman | "Teman" (`_unfriend` → dialog konfirmasi) | **"Putus Teman"** (`_unfriend` → dialog) |

- **Putus teman** (`_unfriend`): dialog "Putus pertemanan?" → `unfollow` (server
  hapus `follows` + `friend_requests`) → snackbar `unfriendDone`.
- **Batalkan permintaan** (`_cancelFriendRequest`): dialog "Batalkan permintaan
  teman?" → ambil id dari `friendRequestOutbox()` (cari `uid == target`) →
  `cancelFriendRequest` → snackbar `cancelRequestDone`.
- Tombol "Teman"/"Terkirim" yang dulu **mati** (`onTap: () {}`) kini **aktif**
  dan berkonfirmasi.

### Helper bersama & cakupan tombol (2026-10)

Aksi putus teman / batalkan permintaan dipusatkan di
**`lib/widgets/social_actions.dart`** (`confirmUnfriend`, `confirmCancelRequest`,
`cancelFriendRequestFor`, `doUnfriend`, `runUnfriend`, `runCancelRequest`) —
agar dialog & snackbar konsisten.

Tombol "Tambah Teman"/status kini **aktif** di semua tempat (dulu mati saat
sudah teman/pending):

| Lokasi | friend | pending | else |
|---|---|---|---|
| Profil (`user_info_screen.dart`) | tombol "Teman" → putus | "Batalkan" → cancel | kirim request |
| Leaderboard (`leaderboard_sheet.dart`) | ikon `group_remove` → putus | ikon `cancel` → cancel | kirim request |
| Daftar online (`online_users_screen.dart`) | → putus | → cancel | kirim request |
| Daftar chat (`private_chats_screen.dart` `_FriendButton`) | → putus | → cancel | kirim request |
| Ruang chat 1:1 (`private_chat_screen.dart` menu) | item "Tambah Teman" **disembunyikan** | **disembunyikan** | tampil |

> Di ruang chat 1:1, menu **"Ikuti"** juga dinamis: kalau sudah follow jadi
> **"Berhenti Ikuti"** (`menuUnfollow` → `unfollow`).

---

## 5. Alur menjadi teman

```
A tap "Tambah Teman" pada B
        │
        ▼
send_friend_request(p_to=B)
  → insert friend_requests(from=A, to=B, status='pending')
  → push notif ke B: "A mengirim permintaan teman"
  → return {ok:true, status:'pending'}   (client: tombol jadi "Terkirim")

B buka Permintaan Teman → Terima
        │
        ▼
respond_friend_request(p_request_id, p_accept=true)
  → update friend_requests.status = 'accepted'
  → insert follows(A→B)   ← otomatis
  → insert follows(B→A)   ← otomatis  ⇒ mutual follow = "teman"
```

**Fakta penting:**
- Berteman **otomatis** membuat follow dua arah → A & B saling muncul di
  "Mengikuti" satu sama lain.
- Saling follow manual **tidak** otomatis jadi teman (status `friend` tetap
  butuh baris `friend_requests` accepted).
- Hanya **user terdaftar** yang bisa follow/berteman (anon diblok via
  `_social_registered_guard` / `SOCIAL_REGISTERED_ONLY`).

---

## 6. Client: state & realtime

- `lib/providers/social_provider.dart` — state `_following`, `_friends`,
  `_pendingFriendRequests`, `_subscribed` + counter inbox. Dimuat dari disk
  cache dulu (instant), lalu refresh network.
- Realtime: channel `social-rt-<uid>` mendengarkan `follows` + `friend_requests`
  → refresh set (debounce 400ms).
- `watchFriendRequestCount(uid)` → badge inbox.

### ⚠️ `isFriend` pada post dari realtime
- RPC `list_posts`/`get_post` menghitung `isFriend` = **mutual follow**
  (lihat `20260817000000_timeline_posts.sql:368`).
- **Realtime stream `posts` hanya membawa kolom mentah tabel** — TIDAK ada
  `is_friend` (itu computed, bukan kolom). Karena itu
  `TimelineProvider._mapRow` tidak boleh mengarang `isFriend` dari row
  realtime; `PostCard` harus resolve dari `SocialProvider.isFriend(authorId)`
  dengan fallback ke `_p['isFriend']` (dari server saat load RPC).
- Bug historis: `_mapRow` hardcode `'isFriend': false` → badge "Teman" pada
  post baru (via realtime) hilang sampai feed di-refresh. **Sudah diperbaiki.**

---

## 7. Referensi file

| Lapis | Lokasi |
|---|---|
| UI | `lib/screens/user_info_screen.dart`, `online_users_screen.dart`, `private_chats_screen.dart`, `leaderboard_sheet.dart` |
| Widget | `lib/widgets/post_card.dart` (badge friend), `lib/widgets/leaderboard_sheet.dart` (tombol follow/teman) |
| Provider | `lib/providers/social_provider.dart` |
| Service | `lib/services/social_service.dart` |
| String | `lib/config/strings.dart` (§ Sosial: `btnFollow`, `btnAddFriend`, `hintFollowVsFriend`, `sheetFollowVsFriend*`) |
| SQL inti | `follow_user`, `unfollow_user`, `send_friend_request`, `respond_friend_request`, `social_list`, `my_social_status`, `privacy_can_view`, `_are_friends`, `_privacy_are_friends`, `follow_count_sync` |
| Test | `test/social_provider_test.dart`, `test/social_friend_request_test.dart`, `test/post_card_test.dart`, `supabase/tests/privacy_test.sql` |

---

## 8. Subscribe (ringkas — sistem ketiga, terpisah)

- `subscribe_creator(p_creator, p_periods)` — bayar YukCoin, cut platform
  (default 30%) → `platform_revenue`, sisanya `earned` ke creator.
- Hanya **topup + earned** (bonus tidak berlaku). Perpanjang otomatis bila
  `expires_at` mendatang.
- Efek konten: post/story ber-visibility `subscribers` hanya terlihat
  subscriber aktif.
- UI: `lib/screens/subscriptions_screen.dart`, profil (tombol `btnSubscribe`).

---

## 9. Invariant (dijaga test)

1. `respond_friend_request(accept)` → 2 baris `follows` (mutual) + status accepted.
2. `unfollow_user` → hapus `follows` **dan** `friend_requests` kedua arah →
   `_are_friends` & `_privacy_are_friends` = false.
3. Berteman otomatis mutual-follow; saling follow tidak otomatis berteman.
4. Anon tidak bisa follow/berteman.
5. Story `friends` butuh `_are_friends`; privacy `friends` butuh `_privacy_are_friends`.
6. Badge "Teman" di post (realtime) = `SocialProvider.isFriend(authorId)`,
   bukan nilai hardcode.
