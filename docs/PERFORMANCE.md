# PERFORMANCE — apa yang sudah diperbaiki & aturan lanjutan

> **BACA DULU sebelum mengoptimalkan apa pun.** Dokumen ini mencatat optimasi
> yang SUDAH ada beserta alasannya, supaya perubahan berikutnya **menambah**,
> bukan **merusak** (mis. mengembalikan `context.watch` yang sudah diganti
> `select`, atau menghapus `TickerMode`/`RepaintBoundary`).

Terakhir diperbarui: 2026-09-18 (branch `develop`).

---

## 1. Hasil pengukuran (baseline)

Diukur di **Xiaomi 24129PN74G** (1200×2670, 120Hz), build rilis adminProd,
pakai `dumpsys SurfaceFlinger --latency` (jalur render Flutter sebenarnya —
`gfxinfo` TIDAK bisa dipakai karena pipeline-nya Skia/Vulkan, bukan HWUI).

| Metrik | Nilai | Ambang |
|---|---|---|
| p50 frame | **3.5 ms** | 16.7 ms (60fps) |
| p90 frame | **4.4 ms** | 16.7 ms |
| p99 frame | **6.6 ms** | 16.7 ms |
| Jank (>16.7ms) | **0 (0.0%)** | — |

Kesimpulan: rendering sudah mulus dengan margin ~2.5×. **Kalau user masih
merasa lambat, tersangka utamanya adalah WAKTU TUNGGU DATA (RPC/DB), bukan
render** — ukur dulu sebelum mengubah kode render.

### Cara mengukur ulang (WAJIB pakai jalur ini)

```bash
export PATH="$PATH:$HOME/Library/Android/sdk/platform-tools"
DEV=192.168.18.33:38467
# 1) cari layer Flutter (nama berubah tiap app dibuka!)
adb -s $DEV shell dumpsys SurfaceFlinger --list | grep -i chatyuk
# 2) ambil latency layer utama (contoh: ...MainActivity#84991)
adb -s $DEV shell dumpsys SurfaceFlinger --latency \
  "com.chatyuk.chatyuk.admin/com.chatyuk.chatyuk.MainActivity#<ID>" > /tmp/lat.txt
# 3) hitung persentil dari kolom (desiredPresent - actualPresent)
```

> Catatan: `adb logcat | grep '\[PERF\]'` hanya jalan di build dengan
> `--dart-define=PERF_PROBE=true` (debug/profil). **JANGAN pasang build
> debug/profil ke HP admin untuk uji the underlying provider Sign-In** — SHA-1 debug
> tidak terdaftar di OAuth client → `DEVELOPER_ERROR`. Lihat bagian 5.

---

## 2. Optimasi yang SUDAH diterapkan (jangan dibalik!)

### 2.1 `TickerMode` per tab — `lib/app.dart`
Setiap halaman di dalam `IndexedStack` dibungkus `TickerMode(enabled: tab == i)`.
**Alasan:** animasi halaman yang TIDAK aktif (mis. `_sharePulse` di menu Online
yang dulu `..repeat()` selamanya) terus meminta vsync → compositor tidak pernah
idle → semua tab terasa berat.
**Jangan:** hapus `TickerMode` atau mengembalikan `repeat()` tanpa syarat tab.

### 2.2 Pulse share hanya saat tab Online aktif — `online_users_screen.dart`
`_sharePulse` dipicu/dihentikan oleh listener `NavProvider` (`_syncSharePulse`).
Listener di-`removeListener` saat `dispose`.

### 2.3 `context.select` menggantikan `context.watch` — beberapa file
- `online_users_screen.dart`: `watch<AuthProvider>()` → `select` per field
  (`uid`, `profile.avatar`, `profile.nickname`, `profile.isRegistered`,
  `isRealAdmin`, `dummySessionActive`, `isAnonymous`). **Ini kunci:** heartbeat
  presence AuthProvider berubah tiap beberapa detik; `watch` membuat SELURUH
  halaman rebuild tiap kali.
- `widgets/offline_banner.dart`: `watch<ConnectivityProvider>()` →
  `select<bool>((c) => c.online)`.

**Aturan lanjutan:** di dalam `build()` sebuah *halaman penuh*, WAJIB pakai
`select` untuk provider yang sering berubah (Auth, Connectivity, presence).
`watch` hanya untuk provider yang jarang berubah dan memang seluruh halaman
harus ikut berubah (mis. `ThemeProvider` bila memang tema global).

### 2.4 Tulis-ulang hanya saat INPUT berubah — `private_chats_screen.dart`
Dulu filter+sort 50 chat dijalankan **di dalam `build()`** → tiap rebuild
(tema, badge, presence) mengurutkan ulang semuanya. Sekarang:
`_recomputeFiltered()` dipanggil hanya bila `_recomputeDirty || queryChanged ||
liveChanged` (dibandingkan dengan `_sameStatusMap`). Hasil disiarkan lewat
`ValueNotifier` (`_listNotifier`, `_archivedNotifier`, `_pageNotifier`) supaya
hanya bagian list yang rebuild.

**Jangan:** kembalikan komputasi berat ke `build()`, atau menambah `setState()`
di `addPostFrameCallback` (dulu bikin build KEDUA di frame pertama tab).

### 2.5 `RepaintBoundary` per kartu list
- `private_chats_screen.dart` (kartu chat), `online_users_screen.dart`
  (`_UserCard`), `timeline_screen.dart` (`PostCard`).
Satu kartu berubah (badge/centang/like) tidak repaint seluruh list.

### 2.6 Warm/prefetch dikurangi & ditunda
- `_warmTopChats`: **6 → 2 chat**. Prefetch = query DB per chat; 6 sekaligus di
  jalur frame pertama tab Pesan menahan frame.
- `app.dart`: prewarm timeline 3 dtk (sudah ada) + **prewarm tab lain bertahap**
  (`_scheduleTabPrewarm`, 1 tab / 800ms mulai 1.2 dtk) → tap tab terasa instan
  ala Telegram karena halaman sudah dibangun saat idle.
- `lib/main.dart`: `prewarmDb` + `MediaDiskCache.prewarm` paralel dengan
  Supabase/Firebase init.

### 2.7 Throttle `notifyActivity()` — `auth_provider.dart`
`Listener` global di `app.dart` memanggil `notifyActivity()` pada SETIAP
pointer-down. Dulu tiap sentuhan = `Timer` baru. Sekarang dibatasi 1×/detik
via `_lastActivityAt` (idle→online tetap selalu diproses).

### 2.8 Pil navigasi lebih cepat — `app.dart`
`_navPill`: 500ms → **260ms** (collapse 180ms). Kurva `easeOutExpo` tetap.

### 2.9 Respons sentuhan dipercepat (klik & tahan terasa "nempel")
Permintaan user: klik/tap harus sangat sensitif, dan tahan pesan jangan lama.

- **`lib/config/theme.dart` → `AppTiming`**: satu sumber nilai gesture.
  - `longPress = 320ms` (Flutter default **500ms**).
  - `splash = 90ms`.
- **`lib/widgets/app_gesture.dart` → `AppGestureDetector`**: pengganti
  `GestureDetector` yang meneruskan `duration` ke `LongPressGestureRecognizer`.
  `GestureDetector` bawaan Flutter **tidak** mengekspos durasi long-press —
  itu sebabnya harus `RawGestureDetector`.
- **Dipakai di titik tahan-lama:**
  - `private_chat_message.dart` (bubble private) — toolbar reaksi/seleksi.
  - `room_chat_screen.dart` (bubble room).
  - `private_chats_screen.dart` (kartu list Pesan) — mode seleksi.
  - `online_users_screen.dart` (kartu pengguna online) — bubble unread.
- **`theme.dart` → `tooltipTheme`**: `waitDuration` diturunkan ke
  `AppTiming.longPress` supaya label tooltip ikut cepat.
- **Tombol kirim** (`private_chat_screen.dart`): `onTapDown` → `lightImpact()`
  (getar instan saat ditekan). Mic sudah pakai haptic sejak awal.

**Aturan lanjutan:** untuk gesture yang butuh tahan-cepat, pakai
`AppGestureDetector`, JANGAN `GestureDetector` biasa (durasi long-press-nya
tidak bisa diatur → kembali 500ms). Kalau butuh durasi berbeda, tambahkan
field di `AppTiming`, jangan hardcode angka.

### 2.10 Logout tidak boleh menggantung (fix spinner tak berujung)
Masalah: spinner logout muter terus karena menunggu network tanpa timeout.
- `services/social_service.dart` → `clearAnonSocial()`: `.timeout(5s)`.
- `services/auth_service.dart` → `goOffline()`: `.timeout(3s)`.
- `screens/profile_screen.dart` → `_confirmLogout()`: `clearAnonSocial` dibungkus
  try/catch + timeout; `auth.signOut().timeout(8s)`; `finally` selalu
  `chat.reset()` + `setState(_loggingOut = false)`.

**Aturan:** setiap RPC di jalur keluar/transisi layar WAJIB punya timeout, dan
kegagalan jaringan tidak boleh menahan user keluar.

---

## 3. Alat ukur (opsional, untuk pengembangan)

`lib/services/perf_probe.dart` — aktif HANYA dengan
`--dart-define=PERF_PROBE=true` + `kDebugMode || kProfileMode`.
Saat off = no-op total (tanpa Stopwatch, tanpa alokasi, tanpa map entry).

Fungsi:
- `tabStart/tabEnd(i)` — tap tab → frame pertama tab ter-render.
- `buildCount(key)` / `notifyCount(key)` — hitung rebuild & notify.
- `timed(key, fn)` — **ukur satu operasi async (fetch data)**.
- `measure(key, fn)` — ukur blok sinkron (parse/sort).
- `report(label)` — cetak ringkasan semua metrik.

```bash
flutter run --dart-define=PERF_PROBE=true
adb logcat | grep '\[PERF\]'
```

Titik ukur terpasang:
| Key | Lokasi | Mengukur |
|---|---|---|
| `MainNav` | `app.dart` | build + tap→frame per tab |
| `Online` | `online_users_screen.dart` | build halaman |
| `ChatList` | `private_chats_screen.dart` | build halaman list chat |
| `chat.listFetch` | `chat_service.dart` | fetch 50 row `private_chats` |
| `online.diskLoad` | `online_users_provider.dart` | load cache disk pengguna online |

### ⚠️ Jebakan: probe butuh mode profil, tapi profil merusak Sign-In

`PERF_PROBE` hanya mengeluarkan log di **profil/debug** (karena `dlog`
di-gate `kDebugMode || kProfileMode`). Tapi build profil = **debug key** →
SHA-1 `ff:1f:f6:2d:...` tidak terdaftar → **the underlying provider Sign-In gagal
`DEVELOPER_ERROR`** (sudah 2× kejadian).

Pilihan yang benar (urut rekomendasi):
1. **Ukur render pakai app rilis** (Sudah login) via `SurfaceFlinger --latency`
   — tidak butuh build probe sama sekali. Ini yang dipakai untuk baseline 3.5ms.
2. Kalau memang butuh angka `fetch`/`build`: daftarkan SHA-1 debug
   (`ff:1f:f6:2d:...` lengkap) sebagai OAuth client tambahan di the underlying provider
   Cloud untuk package yang dipakai build probe.
3. JANGAN pasang build debug/profil ke HP yang dipakai kerja harian tanpa
   mendaftarkan SHA-1-nya lebih dulu.

> Flavor `adminDev` pernah dibuat untuk ini (`--flavor adminDev` +
> `src/adminDev/the underlying provider-services.json`) tapi **sudah dihapus** karena
> appId-nya (`com.chatyuk.chatyuk.admin.dev`) tetap butuh SHA-1 terdaftar
> sendiri. Kalau mau dipakai lagi: buat ulang gsj-nya + daftarkan SHA-1 debug.

---

## 4. Yang SUDAH bagus — jangan diutak-atik tanpa alasan

- Lazy `IndexedStack` via `_visitedTabs` (`app.dart`).
- `_warmFuture` dengan timeout 400ms (`app.dart`) — skeleton tidak menahan
  lebih lama dari itu.
- `_SwapMask` anti-blink (frame pertama MainNav ditutup salinan skeleton).
- `MessageCache.peekRawList` sinkron + `preloadRawList` saat bootstrap.
- `MediaDiskCache.readSync` untuk avatar (instan, tanpa network).
- Cache memori + TTL + disk di `RoomProvider.loadMyGroups` (30s TTL).
- `AutomaticKeepAliveClientMixin` di `OnlineUsersScreen` & `TimelineScreen`
  (`wantKeepAlive => true`) — state tidak dibuang saat pindah tab.
- `_AsyncAvatar` + `_avatarImageByUid` (MemoryImage stabil per-uid) — avatar
  tidak kedip saat list reorder.
- Debounce 180ms untuk avatar-only churn di `OnlineUsersProvider`.

---

## 4b. Nilai gesture (rujukan cepat)

| Nilai | Lama | Baru | Dipakai di |
|---|---|---|---|
| Long-press | 500ms (Flutter) | **320ms** (`AppTiming.longPress`) | tahan pesan/chat/online |
| Tooltip wait | ~500ms (Flutter) | **320ms** (`tooltipTheme`) | semua tooltip ikon |
| Pil nav | 500ms | **260ms** | `_navPill` (`app.dart`) |
| Logout timeout | ∞ (bisa hang) | 5s/3s/8s | `_confirmLogout`, `goOffline`, `clearAnonSocial` |

## 5. Jebakan yang pernah menggigit

1. **Build debug/profil di HP admin → the underlying provider Sign-In gagal
   `DEVELOPER_ERROR`.** Sebab: SHA-1 debug (`ff:1f:f6:2d:...`) bukan SHA-1
   rilis (`8C:CC:42:E3:...`) yang terdaftar di OAuth client. Untuk uji
   sign-in WAJIB pakai build rilis (`--release`, keystore
   `android/keystore/chatyuk-release-v2.jks`). Kalau perlu profil untuk
   profiling, install ke HP lain atau daftarkan SHA-1 debug di the underlying provider Cloud.
2. **`gfxinfo` tidak berguna untuk Flutter** (Skia/Vulkan, bukan HWUI) — selalu
   0 frame. Pakai `SurfaceFlinger --latency`.
3. **Nama layer SurfaceFlinger berubah** tiap app dibuka (`#84991` dsb.) — selalu
   ambil ulang dengan `--list`, jangan hardcode.
4. **Rebuild tanpa `flutter clean` kadang tidak mengubah tampilan** (keluhan
   "masih belum berubah"). Kalau user melaporkan UI tidak berubah: `flutter
   clean` + build ulang + minta user **tutup total app** sebelum cek.

---

## 6. Rencana optimasi berikutnya (belum dikerjakan)

Diurutkan berdasar dugaan dampak × risiko. Kerjakan **satu per satu sambil
mengukur**; centang kalau selesai dan pindahkan ke bagian 2.

### Prioritas tinggi (tersangka utama sisa kelambatan = waktu DATA, bukan render)
- [ ] **#1 Ukur & perbaiki waktu fetch per tab.** Instrumentasi SUDAH dipasang
      (`chat.listFetch`, `online.diskLoad`). Yang belum diukur:
      `OnlineUsersProvider` emit pertama (RPC `get_online_users`),
      `TimelineProvider.prewarm` (`list_posts`). Cara ukur: lihat bagian 3
      (ingat: probe butuh profil → jangan di HP kerja tanpa daftar SHA-1 debug).
      Target: tahu jalur mana yang >300ms, lalu perbaiki yang paling lambat.
- [ ] **#2 Satukan jalur notify `OnlineUsersProvider`.** Sekarang ada 2 jalur
      (`_debounce` 180ms untuk avatar-only + jalur langsung). Bisa memicu 2
      `notifyListeners()` berurutan → 2 rebuild halaman. Satukan jadi satu
      jalur dengan debounce tunggal.
- [ ] **#3 Kurangi payload realtime `private_chats`.** Row dikirim LENGKAP tiap
      perubahan (termasuk `participants`, `participant_names` jsonb, dll).
      Kalau ada kolom besar yang tidak dipakai kartu list, pindahkan ke tabel
      terpisah atau pertimbangkan hanya kirim kolom yang berubah.

### Prioritas sedang
- [ ] **#4 `_chatSubtitle` + sort di `_recomputeFiltered`** dijalankan per
      perubahan data. Kalau list >100 chat, pertimbangkan cache hasil sort per
      `lastMessageAt` (sekarang `List.of` + sort penuh tiap kali).
- [ ] **#5 `RepaintBoundary` pada baris unread/preview** di kartu list — kalau
      profiling menunjukkan masih ada repaint berlebih saat badge berubah.
- [ ] **#6 Tunda fetch avatar batch** di `OnlineUsersProvider` sampai list
      pertama ter-render (sekarang ikut jalur warm).

### Prioritas rendah (fitur, bukan optimasi)
- [ ] **#7 Badge angka di ikon launcher** (MIUI/Android) — butuh plugin
      (`flutter_app_badger` / channel `ShortcutBadger`). Semua notif chat
      digabung jadi satu angka.
- [ ] **#8 Suara & getar kustom per chat/kontak** — butuh channel notifikasi
      dinamis per chat + preferensi user.
- [ ] **#9 Snapshot tab** (`RepaintBoundary.toImage`) — kemungkinan **TIDAK
      perlu** setelah prewarm idle; hanya kerjakan kalau pengukuran ulang
      menunjukkan masih ada jeda saat tap tab.

### Aturan kerja (WAJIB)
1. Setiap perubahan performa harus punya **alasan terukur** (angka, bukan
   perasaan) — ukur dulu dengan cara bagian 1/3.
2. Ukur **sebelum & sesudah**; kalau tidak ada perbaikan angka, revert.
3. Catat di dokumen ini (bagian 2 untuk yang selesai, bagian 6 untuk sisa).
4. **Jangan membalik** optimasi yang sudah ada: `TickerMode`, `select` (bukan
   `watch`), `RepaintBoundary`, `AppGestureDetector` (long-press 320ms),
   prewarm idle, timeout di jalur logout.

## 7. Ringkasan perubahan per tanggal

| Tanggal | Perubahan | Dampak terukur |
|---|---|---|
| 2026-09-18 | TickerMode per tab, `select` ganti `watch`, recompute keluar `build()`, `RepaintBoundary`, prewarm tab idle, throttle `notifyActivity`, pil nav 500→260ms | p50 3.5ms / p99 6.6ms / **0% jank** |
| 2026-09-18 | Long-press 500→320ms (`AppGestureDetector`), tooltip 320ms, haptic tombol kirim, timeout logout (5s/3s/8s) | Responsif (belum ada angka; perlu ukur tap→toolbar) |
| 2026-09-18 | Instrumentasi `PerfProbe.timed` untuk `chat.listFetch` & `online.diskLoad` | `online.diskLoad` = 75.8ms (1 sampel) |
