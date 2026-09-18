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

### 1b. Hasil ukur JALUR DATA (2026-09-18, `PERF_PROBE=true` di build rilis)

Diukur pakai `PerfProbe.timed` (mode `releaseMeasure`) + `adb logcat | grep '[PERF]'`.

| Jalur | Nilai terukur | Verdict |
|---|---|---|
| `online.diskLoad` | **20.6 / 23.2 ms** | ✅ aman |
| `online.rpc` (global) | **21.4 / 127.4 / 235.3 / 260.0 ms** | ⚠️ bervariasi (21→260ms) |
| `online.rpcCountry` | **135.8 / 136.6 / 162.6 ms** | ⚠️ sedang |
| `timeline.rpc` (halaman 1) | **142.1 / 147.9 / 148.2 / 168.8 ms** | ✅ aman |
| `chat.listFetch` | **291–755 ms**, rata-rata **~450-500 ms**, **8× beruntun** | ❌ **BOTTLENECK UTAMA** |

**Temuan kunci (`chat.listFetch`):**

1. **Nilainya paling lambat** (291-755ms) — jauh di atas jalur lain.
2. **Dipanggil 8× beruntun dalam ~1 detik** (log 10:30:59: 381.9, 462.3, 665.8,
   677.5, 322.8, 306.6, 425.8, 306.0 ms). Bukan 1 query lambat, tapi **query
   yang sama diulang-ulang**.
3. **Sebab:** `getMyPrivateChats(uid)` dipanggil dari 5 tempat —
   `app.dart:798` (nav), `private_chats_screen.dart:299` (list Pesan),
   `private_chat_screen.dart:227` (layar chat), `room_members_sheet.dart:516`
   (sheet anggota), `online_users_screen.dart:426`. Tiap panggilan **pertama**
   membuat channel realtime baru + memicu `reload()` masing-masing. Tidak ada
   dedupe → semuanya menembak `private_chats` bersamaan.
4. **Kerugian:** 8× beban DB + 8× payload `private_chats` (yang berisi banyak
   jsonb) untuk data yang SAMA, dan 8× `controller.add()` → potensi rebuild
   beruntun di list chat.

**Perbaikan (sudah diterapkan):** `reload()` sekarang **dedupe in-flight** —
kalau fetch untuk uid itu sedang jalan, panggilan lain menunggu future yang
sama (`_chatListFetchInFlight`). 8 fetch → 1.

### 1c. Verifikasi dedupe (2026-09-18, 10:54, proses baru 28001)

Setelah fix, `chat.listFetch` muncul **1× saja (505.8ms)** — bukan 8× beruntun.
Fix terbukti bekerja.

**Temuan lanjutan dari log yang sama:**

| Jalur | Nilai pasca-fix | Catatan |
|---|---|---|
| `online.rpcCountry` | **665.4ms** (1 dari 4 sampel; sisanya 136-171ms) | ⚠️ 1 sampel melonjak — perlu dipantau, belum tentu pola |
| Semua jalur lain | stabil | `online.rpc` 134-523ms, `timeline.rpc` 167-201ms, `online.diskLoad` 36ms |
| Anomali | `chat.listFetch` **4314.9ms** di proses LAMA (21363, n=12 — sebelum reinstall fix) | Sampel dari sesi sebelum fix, kemungkinan antrean 8 fetch yang menumpuk. **Abaikan** kecuali muncul lagi di proses baru |

> Catatan metodologi: sampel 10:53:56 berasal dari **proses lama**
> (PID 21363, app versi sebelum fix). Angka valid pasca-fix hanya dari PID
> 28001 (10:54 ke atas). Jangan campur keduanya saat menyimpulkan.

> Catatan: `chat.listFetch` sempat ditulis "aman" di dokumen lama karena hanya
> ada 1 sampel. Setelah diukur berulang, ternyata inilah bottleneck-nya —
> pelajaran: **jangan simpulkan dari 1 sampel.**

### 1d. Hasil ukur TAB ADMIN PANEL (2026-09-18, semua tab diklik)

Instrumentasi: wrapper `AdminService._rpc()` → metrik `admin.<nama_rpc>`
(43 RPC terukur otomatis, no-op saat probe off).

| RPC | Nilai | Verdict |
|---|---|---|
| `admin_storage_stats` | **340.6 ms** | ❌ terlambat |
| `admin_ai_provider_list` | **332.5 ms** | ❌ terlambat |
| `admin_stats` | **316.5 ms** | ❌ terlambat |
| `admin_list_devices` | **293.5 / 171.6 ms** | ⚠️ borderline (2 sampel) |
| `admin_get_point_settings` | **292.0 ms** | ⚠️ borderline |
| `admin_ai_settings` | **287.5 ms** | ⚠️ borderline |
| `admin_registrations_daily` | 203.6 / 220.5 / 186.6 ms | ✅ aman |
| `admin_hidden_uids` | 186.4 / 174.1 / 181.4 ms | ✅ aman |
| `admin_sweep_calls` | 186.4 ms | ✅ aman |
| `admin_list_dummies_page` | 185.5 ms | ✅ aman |
| `admin_list_deleted` | 182.9 ms | ✅ aman |
| `admin_stats_detail` | 167.7 ms | ✅ aman |
| `admin_active_calls` | 152.9 ms | ✅ aman |
| `admin_contact_messages_page` | 150.3 ms | ✅ aman |
| `admin_list_chats_page` | 216.0 ms | ✅ aman |

**Kesimpulan admin panel:**

1. **Tidak ada tab yang benar-benar parah** — tertinggi 340ms, dan semuanya
   selesai di bawah 350ms. Tidak ada satu pun yang mendekati `chat.listFetch`
   (505-755ms).
2. **Rata-rata menumpuk di ~150-340ms** — ini menyerupai *baseline* latency
   Supabase dari jaringan ini (bandingkan `online.rpc` yang juga 130-260ms).
   Artinya sebagian besar waktu adalah **jarak jaringan + cold start RPC**,
   bukan query yang berat.
3. **3 RPC >300ms** (`admin_storage_stats`, `admin_ai_provider_list`,
   `admin_stats`) — kandidat optimasi kalau tab tersebut terasa lambat.
   Perlu ukur ulang beberapa kali dulu untuk memastikan bukan cold start
   semata (semua sampel ini n=1 di kunjungan pertama tab).
4. **Tab dibuka berurutan & semua n=1** → angka ini termasuk cold-start RPC
   (first-call ke Supabase). Kunjungan kedua `admin_list_devices` turun
   293.5→171.6ms, jadi **cold start memang berpengaruh ~40%**.

**SISA (kalau tab admin terasa lambat):** lakukan pass kedua (buka tab dua
kali) untuk memisahkan cold-start vs query berat, baru optimasi RPC >300ms
yang konsisten.

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
| `online.rpc` | `chat_service.dart` | RPC `get_online_users` (global, limit 200) |
| `online.rpcCountry` | `chat_service.dart` | RPC `get_online_users` (shard country, limit 100) |
| `timeline.rpc` | `timeline_provider.dart` | RPC `list_posts` halaman PERTAMA (refresh) |
| `timeline.rpcMore` | `timeline_provider.dart` | RPC `list_posts` paginasi (saat scroll) |
| `onlineUsers` (notify) | `online_users_provider.dart` | jumlah `notifyListeners()` |

> `timeline.rpc` dipisah dari `timeline.rpcMore` karena hanya halaman pertama
> yang menahan kemunculan tab Timeline; paginasi terjadi saat user sudah
> melihat konten.

### ⚠️ Jebakan: probe butuh mode profil, tapi profil merusak Sign-In

**SUDAH DIPECAHKAN (2026-09-18)** — lihat "Mode pengukuran" di bawah:

`PerfProbe` sekarang punya **dua mode**:
- `enabled` — butuh debug/profil (log lewat `dlog`).
- `releaseMeasure` — aktif di **build RILIS** + `--dart-define=PERF_PROBE=true`;
  log lewat `print` sehingga tetap terbaca `adb logcat` di rilis.

Karena pengukuran jalur DATA tidak butuh debug key, **build rilis sudah cukup**
untuk mengukur `fetch`/`build` — Sign-In tetap jalan, tidak perlu daftar SHA-1
debug lagi. Yang tetap butuh mode profil hanyalah metrik `tabEnd`/`buildCount`
(mereka memakai `dlog`).

```bash
# Ukur jalur data di HP kerja TANPA merusak Sign-In:
flutter build apk --release --flavor apkpureProd --dart-define=APP_FLAVOR=apkpure \
  --dart-define=PERF_PROBE=true --obfuscate --split-debug-info=build/app/symbols
adb logcat | grep '\[PERF\]'
```

> Catatan sejarah: flavor `adminDev` pernah dibuat untuk ini
> (`--flavor adminDev` + `src/adminDev/google-services.json`) tapi **sudah
> dihapus** karena appId-nya (`com.chatyuk.chatyuk.admin.dev`) tetap butuh
> SHA-1 terdaftar sendiri. Tidak perlu dihidupkan lagi — pakai `releaseMeasure`.

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
- [x] **#1 Instrumentasi jalur data SELESAI + SUDAH DIUKUR (2026-09-18).**
      Empat titik ukur ditambahkan: `online.rpc` (RPC `get_online_users` global),
      `online.rpcCountry` (shard country), `timeline.rpc` (RPC `list_posts`
      halaman pertama), `timeline.rpcMore` (paginasi) + `onlineUsers` (hitung
      notify). Sekaligus `PerfProbe` diberi mode `releaseMeasure` sehingga
      pengukuran bisa jalan di **build rilis** (Sign-In tetap aman — tidak perlu
      daftar SHA-1 debug lagi).
      Hasil: lihat bagian **1b** (jalur data), **1c** (verifikasi dedupe),
      **1d** (seluruh tab admin). Kesimpulan: bottleneck tunggal =
      `chat.listFetch` (duplikasi query) — sudah diperbaiki di #4.
- [x] **#2 Satukan jalur notify `OnlineUsersProvider` SELESAI (2026-09-18).**
      Dua jalur (debounce 180ms avatar-only + jalur langsung) digabung jadi
      SATU fungsi `_scheduleCommit`. Delay dibedakan: avatar-only 180ms
      (anti-kedip cold start), perubahan nyata 32ms (≈2 frame @120Hz) —
      cukup menggabungkan burst emission tanpa terasa lag. Efek: burst
      emission tidak lagi menghasilkan 2 `notifyListeners()` berurutan
      (2 rebuild halaman per frame). Bisa dipantau lewat metrik
      `notify onlineUsers`.
- [x] **#3 DIBATALKAN — tidak mungkin diterapkan (2026-09-18).** Tiga alasan:
      (a) Supabase Realtime **tidak bisa** memilih kolom — payload ditentukan
      publication di server, bukan SQL klien, jadi "kirim hanya kolom yang
      berubah" secara harfiah tidak ada; (b) setelah dilacak, **semua** kolom
      `private_chats` dikonsumsi `_rowToPrivateChat` (`chat_service.dart:1053`)
      — tidak ada kolom besar yang bisa dibuang/dipindah; (c) memindah kolom =
      mengubah skema + publication, berisiko tinggi, sementara belum ada angka
      yang menunjukkan ini benar-benar masalah. Beban realtime ditangani dari
      sisi klien lewat #2 (burst digabung jadi satu rebuild) yang aman &
      terukur. Bukaan ulang hanya bila pengukuran #1 membuktikan payload ini
      sebagai bottleneck.

### Prioritas sedang
- [x] **#4 Dedupe `chat.listFetch` SELESAI (2026-09-18).** Bukan sekadar
      "cache hasil sort" seperti rencana awal — akar masalahnya ternyata
      **duplikasi query**. `getMyPrivateChats` dipanggil 5 tempat, dan tiap
      panggilan pertama memicu `reload()` sendiri tanpa dedupe → terukur
      **8 fetch beruntun 291-755ms** untuk data yang sama. Perbaikan:
      `_chatListFetchInFlight` — panggilan saat fetch sedang jalan menunggu
      future yang sama. 8 fetch → 1.
      **SISA (kalau masih perlu):** `_comparePinned` + sort penuh per
      perubahan data; kerjakan hanya bila pengukuran ulang masih >300ms.
- [ ] **#5 `RepaintBoundary` pada baris unread/preview** di kartu list — kalau
      profiling menunjukkan masih ada repaint berlebih saat badge berubah.
      Prioritas TURUN: render sudah 0% jank, jadi ini belum terbukti masalah.
- [ ] **#6 Tunda fetch avatar batch** di `OnlineUsersProvider` sampai list
      pertama ter-render (sekarang ikut jalur warm). Prioritas TURUN:
      `online.diskLoad` terukur cuma ~21ms — bukan bottleneck.

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
| 2026-09-18 | Probe 2-mode (`releaseMeasure` untuk rilis — Sign-In aman tanpa SHA-1 debug); tambah titik ukur `online.rpc`, `online.rpcCountry`, `timeline.rpc`, `timeline.rpcMore`, `onlineUsers` | Belum ada angka — build probe siap, menunggu pembacaan `adb logcat` |
| 2026-09-18 | `OnlineUsersProvider`: 2 jalur notify → 1 `_scheduleCommit` (avatar-only 180ms / perubahan nyata 32ms) | Belum ada angka — pantau `notify onlineUsers` |
| 2026-09-18 | **UKUR jalur data** (`PERF_PROBE=true` rilis): `online.rpc` 21-260ms, `online.rpcCountry` 136-163ms, `timeline.rpc` 142-169ms, `online.diskLoad` ~21ms, **`chat.listFetch` 291-755ms × 8 beruntun** | Menemukan bottleneck utama = `chat.listFetch` |
| 2026-09-18 | **Fix dedupe `chat.listFetch`** (`_chatListFetchInFlight`): 5 pemanggil `getMyPrivateChats` tidak lagi menembak query sama bersamaan | 8 fetch → 1 (terverifikasi: 505.8ms sekali) |
| 2026-09-18 | **Fix kedip list Pesan**: recompute dipindah dari "build berikutnya" ke dalam `StreamBuilder` (sebelum `_listNotifier.value` dibaca) | List muncul di frame yang sama; hilang kedip EmptyStateView 1 frame |
| 2026-09-18 | **Instrumentasi seluruh tab admin**: wrapper `AdminService._rpc()` — 43 RPC terukur otomatis | Tidak ada tab >350ms; tertinggi `admin_storage_stats` 340.6ms; cold-start RPC berpengaruh ~40% |
