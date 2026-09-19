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

### 1e. PASS KEDUA — tab admin dibuka 2× (2026-09-18)

Tujuan: memisahkan **cold start RPC** dari **query berat**. Angka n=1 =
kunjungan pertama, n=2 = kunjungan kedua (tab sama).

| RPC | n=1 (cold) | n=2 (warm) | Selisih |
|---|---|---|---|
| `admin_list_deleted` | 147.5 | **378.1** | +230 (naik!) |
| `admin_list_chats_page` | **297.4** | 138.0 | −159 |
| `admin_active_calls` | 226.2 | 137.6 | −89 |
| `admin_list_devices` | 174.5 | 152.6 | −22 |
| `admin_list_dummies_page` | 167.4 | 136.5 | −31 |
| `admin_contact_messages_page` | 156.4 | 128.1 | −28 |
| `admin_registrations_daily` | 154.8 | 136.2 | −19 |
| `admin_hidden_uids` | 169.8 | 147.9 | −22 |
| `admin_ai_settings` | 161.8 | 147.6 | −14 |
| `admin_ai_provider_list` | 130.7 | 132.8 | +2 |
| `admin_storage_stats` | 275.6 | — | (hanya 1×) |
| `admin_sweep_calls` | 266.4 | — | (hanya 1×) |

**Kesimpulan pass-2:**

1. **Cold start terbukti, tapi tidak dominan.** Rata-rata turun ~20-25% di
   kunjungan kedua (bukan 40% seperti dugaan awal dari 1 sampel).
2. **`admin_list_deleted` justru NAIK** (147→378ms) — jadi bukan cold start,
   melainkan **variasi jaringan/DB**, bukan pola query berat. n=2 masih terlalu
   sedikit untuk menyimpulkan.
3. **Semua RPC admin tetap < 400ms** dan mayoritas 128-175ms di kondisi warm.
   Ini menyerupai baseline latency jaringan (bandingkan `online.rpc` warm
   119-166ms). **Tidak ada query admin yang perlu dioptimasi.**
4. **Putusan akhir admin panel: TIDAK ada pekerjaan optimasi.** Semua dalam
   batas wajar; variasi antar-panggilan lebih besar daripada selisih cold/warm.

### 1f. PASS KEDUA — jalur data utama

| Jalur | Pass 1 | Pass 2 | Catatan |
|---|---|---|---|
| `chat.listFetch` | 505.8 (1×) | **788.7 / 622.3** (2×) | ⚠️ masih jalur TERLAMBAT; 2× karena snapshot+refresh |
| `online.rpc` | 21-1319 | 67.6 → 119-317 | ✅ stabil di 119-166ms setelah warm |
| `online.rpcCountry` | 135-665 | 119.9-165.0 | ✅ stabil |
| `timeline.rpc` | 142-201 | 117.3-171.4 | ✅ stabil |
| `online.diskLoad` | 20-53 | 63.7 | ✅ (& avatar sudah non-blocking) |

**`chat.listFetch` = satu-satunya target tersisa.** Terukur 505-788ms (1 query
sah, bukan lagi duplikasi). Ini query `private_chats` limit 50 dengan
`select()` seluruh kolom (banyak jsonb). Kandidat berikutnya: perkecil kolom
yang di-`select` di `_fetchPrivateChatRows` — **bukan** lewat Realtime
(#3 sudah dibatalkan), melainkan di query fetch-nya sendiri.

> Nama paket `com.chatyuk.chatyuk.admin.dev` terlihat di log — itu sisa
> instalasi lama (flavor `adminDev` yang sudah dihapus), tidak dipakai.

### 1g. Fix `chat.listFetch` — TERBUKTI (2026-09-18, 15:12)

Dua perubahan di `_fetchPrivateChatRows` (`chat_service.dart`):

1. **`select()` → 17 kolom eksplisit.** `hidden_by`/`hidden_at` TIDAK pernah
   dibaca di jalur ini (penyaringan tersembunyi lewat `getHiddenChats`
   terpisah) — membuangnya memangkas payload per baris × 50 baris.
2. **Fetch + hidden PARALEL** (`Future.wait`). Dulu berurutan = 2 RTT.

**Hasil terukur (bukti langsung dari logcat):**

| | Waktu | PID |
|---|---|---|
| `chat.hiddenFetch` | 370.7 ms | 25419 (build baru) |
| `chat.listFetch` | 380.2 ms | 25419 (build baru) |

Selisih timestamp keduanya **9 milidetik** (15:12:38.956 vs .965) → keduanya
berjalan **bersamaan**, masing-masing ~375ms.

- **Sebelum:** fetch (~380ms) → berurutan → hidden (~370ms) = **~750ms**
- **Sesudah:** paralel → **~380ms** (dibatasi yang terlama)
- **Hemat ~370ms (≈50%)** di jalur kritis tab Pesan.

> Metodologi: log memuat 2 proses (PID 20138 = build lama, 25419 = build baru).
> Angka 1136.8ms berasal dari PID lama & kondisi cold yang berkompetisi dengan
> `online.rpc` (775ms) — **bukan** hasil perubahan ini. Selalu pisahkan per-PID.

### 1h. Analisa cold start & warm-up RPC (2026-09-18, 15:24 & 15:46)

**Cold start BERSIH** (tanpa kontaminasi installer/permission/Sign-In) sangat
berbeda dari yang terkontaminasi:

| | Terkontaminasi (install) | Bersih |
|---|---|---|
| Proses lahir → frame tampil | ~11 detik | **+600-783ms** |
| `online.rpc` pertama | 775-1319ms | 839ms |
| `chat.listFetch` pertama | 1136ms | 839ms |

> **Android melaporkan `Displayed ... +600ms`** — UI SUDAH muncul cepat.
> Yang telat adalah KONTENNYA (RPC pertama 839ms), bukan app-nya.

**Diagnosis yang BENAR (setelah diukur):**

1. ❌ ~~"4 RPC bertabrakan sehingga saling memperlambat"~~ — **DIBANTAH data.**
   Setelah dihitung waktu MULAI tiap RPC (selesai − durasi), semuanya
   **sudah berurutan**, bukan bersamaan:
   `online.rpc` 42.974 → `rpcCountry` 43.967 → `timeline` 45.033 → dst.
2. ✅ **Hanya RPC PERTAMA yang mahal (839ms)**; setelah itu semua normal
   127-170ms. Penyebab: TLS handshake + koneksi pool Supabase yang masih
   dingin. Ini sifat jaringan/inisialisasi, bukan query.
3. ❌ ~~"Profil sendiri selalu fetch server, cache tidak dibaca"~~ — **SALAH.**
   `_loadCachedProfile()` sudah dipakai di `_init()` (`auth_provider.dart:283`):
   profil dari cache tampil lebih dulu, network menyusul.

**Perbaikan yang dikerjakan: WARM-UP RPC** (`main.dart`, `_warmupRpcConnection`).
Setelah `runApp` (UI sudah tampil), tunggu 600ms lalu panggil satu query
paling ringan (`app_settings`) untuk membayar TLS handshake + memanaskan
koneksi SEBELUM user membuka tab. Fire-and-forget, timeout 8s.

**Hasil terukur:**

| Jalur (panggilan pertama) | Sebelum warm-up | Sesudah warm-up |
|---|---|---|
| `online.rpc` | **839.0 ms** | **245.5 ms** (−71%) |
| `chat.listFetch` | **839.3 ms** | **449.4 ms** (−46%) |
| `online.rpcCountry` | 149.4 ms | 147.7 ms (setara) |
| `timeline.rpc` | 169.6 ms | 168.1 ms (setara) |

Jalur yang tadinya menanggung biaya koneksi dingin turun drastis; jalur yang
memang sudah di belakangnya tidak terpengaruh (bagus — tidak ada regresi).

> Catatan: `[WARMUP]` log tidak muncul di rilis karena memakai `dlog`
> (di-gate `kDebugMode`). Efektivitasnya dibuktikan lewat angka `[PERF]`,
> bukan lewat log itu.

### 1i. Ukur BERULANG — memisahkan noise dari pola (2026-09-18)

`PerfProbe.report()` dipanggil otomatis tiap app di-background, kini mencetak
`min/p50/p90/max` (bukan hanya rata-rata). Aturan baca:
- `max` jauh dari `p50` tapi `p90` dekat `p50` → **noise jaringan** (jitter).
- `p90` ikut naik mendekati `max` → **pola nyata** (ada yang sistematis).

**`chat.listFetch` — 8 sesi cold start:**

| Sesi | Nilai |
|---|---|
| 1 | 254.0 ms |
| 2 | 296.1 ms |
| 3 | 304.1 ms |
| 4 | 313.5 ms |
| 5 | 362.9 ms |
| 6 | 386.0 ms |
| 7 | 406.4 ms |
| 8 | 434.5 ms |

`min=254  avg=344.7  max=434.5  sebaran=180ms`

**Kesimpulan: NOISE, bukan pola.** Sebarannya kontinu dan merata (254→434ms)
tanpa lompatan — ciri jitter jaringan/hotspot, bukan query yang kadang berat.
Sebelum optimasi: 505-788ms; sesudah: **254-434ms (avg 345ms)**. Tidak ada
`max` ekstrem seperti dulu (788ms, 1136ms).

**`online.rpc` — 6 sesi:**

| Sesi | p50 | max |
|---|---|---|
| 1 | 143.4 | 148.2 |
| 2 | 189.6 | 214.5 |
| 3 | 151.5 | 151.5 |
| 4 | **247.2** | **533.8** |
| 5 | 158.7 | 172.2 |
| 6 | 203.1 | 526.6 |

Sesi 4 & 6 punya `max` 526-534ms saat p50 hanya 203-247ms → **lonjakan sesaat**
(kemungkinan WiFi/hotspot hiccup atau GC). p50 stabil di 143-247ms. Karena
`p90` tidak selalu tinggi, ini **noise**, bukan pola.

**`online.rpcCountry` — sangat stabil:** p50 133-164ms, max 141-201ms, tanpa
lonjakan di seluruh 6 sesi.

**Yang perlu diperhatikan:** `chat.hiddenFetch` pernah **1023.5ms** sekali
(1 dari 8 sesi). Itu juga lonjakan tunggal — sisa 7 sesi 245-455ms. Dipantau,
belum perlu tindakan.

**Putusan:** tidak ada pola yang perlu diperbaiki. Semua variasi berbentuk
jitter jaringan. **Pekerjaan performa SELESAI.**

### 1j. Call & video call — instrumentasi + optimasi (2026-09-19)

Diukur di **Xiaomi 24129PN74G** (1200×2670, 520dpi), build **RILIS** apkpure +
`--dart-define=PERF_PROBE=true`, `adb logcat | grep '[PERF]'`. Protokol:
2–3 video call berurutan, tiap call ±15–20 dtk (mic on/off, kamera on/off,
swap video), lalu app di-background agar `PerfProbe.report` mencetak ringkasan.

**Sebelum (baseline):**

| Metrik | Nilai | Catatan |
|---|---|---|
| `call.turnFetch` | **1760 ms (cold)** / 218 ms (warm) | HTTP ke edge `turn-credentials` tiap call |
| `call.setupMedia` | **5509 ms (cold)** / 255 ms | getUserMedia + createPeerConnection (termasuk turnFetch) |
| `call.initToConnected` | 12735 / 18105 ms | didominasi waktu user menekan "terima" |
| `call.offerToConnected` | 11668 / 11738 ms | idem — offer memang dikirim sebelum callee jawab |
| `build CallScreen` | **26** untuk 2 call (≈13/call) | timer 1 dtk `setState` seluruh layar |

**Sesudah (3 call):**

| Metrik | Nilai | Perubahan |
|---|---|---|
| `call.turnFetch` | 436 ms (call 1, sesi baru) → **0.1 / 0.0 ms** | **−100%** (cache memori 12 jam) |
| `call.setupMedia` | 804 → 344 → **40 ms** | **−85%** (call 3 vs cold) |
| `call.initToConnected` | avg **5104 ms** (3656–6109) | turun dari 12735–18105 |
| `call.offerToConnected` | avg **3880 ms** | turun dari ~11700 (sebagian karena user lebih cepat jawab) |
| `build CallScreen` | 49 untuk 3 call (≈16/call) | naik relatif karena sesi lebih panjang + swap/resize; **timer tidak lagi memicu rebuild** |

**Perbaikan yang diterapkan:**

1. **Cache kredensial TURN** (`call_config.dart`) — Cloudflare TTL 24 jam, client
   cache 12 jam. Round-trip edge hilang di call ke-2+ **dan** tiap watch PC.
   Terbukti: `0.1ms` / `0.0ms` (hit cache).
2. **Timer durasi terisolasi** (`call_screen.dart`) — `ValueNotifier<String>` +
   `ValueListenableBuilder`; `build()` layar call tidak lagi jalan tiap detik.
3. **`RepaintBoundary`** mengelilingi tiap `RTCVideoView` (fullscreen, bubble
   kecil, panel overlay) — perubahan kontrol/teks tidak meraster ulang video.
4. **`dlog` overlay di-gate `kDebugMode`** (`chat_call_overlay.dart`) — string
   panjang tidak lagi disusun tiap rebuild di build rilis.
5. **Timer `CallBanner`** hanya hidup saat banner terlihat (`_syncTicker`).
6. **Tombol kontrol rata** (`call_screen.dart`, `chat_call_overlay.dart`) —
   `spaceEvenly` (dulu `center` → menumpuk di tengah) + `crossAxisAlignment.start`
   (lingkaran End call yang punya label dulu membuat tombol lain turun ~8px di
   520dpi).

**Aturan lanjutan:** jangan kembalikan `_fetchCloudflare` tanpa cache, jangan
pakai `setState` untuk update durasi call, dan pertahankan `RepaintBoundary`
di sekitar `RTCVideoView`.

### 1k. Retensi call otomatis (server, 2026-09-19)

`admin_sweep_calls()` (akhiri `ringing` basi >90 dtk, `answered` tanpa heartbeat
>75 dtk, hapus `call_signals` call selesai >1 jam) dulu **hanya** terpanggil saat
admin membuka panel → untuk user biasa call zombie menggantung & `call_signals`
menumpuk (terukur 2.160 kB untuk 81 baris). Sekarang dijadwalkan cron
`chatyuk-call-sweep` `*/5 * * * *`. Tidak mengubah isi fungsi (bukan FROZEN).

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

### 2.10 Story — galeri, tray, viewer (diukur 2026-09-18)

- **Grid galeri**: `_thumbs` + `setState` global → `ValueNotifier<int>`
  (`_thumbsTick`) + `ValueListenableBuilder` per tile. Dulu tiap thumbnail
  selesai memicu `setState` → **seluruh grid rebuild** (100 foto = 100×
  rebuild saat scroll). Sekarang hanya tile pemiliknya.
- **Batasi decode paralel** thumbnail ke 4 (`_thumbConcurrency`) — dulu
  semua sekaligus rebutan CPU.
- **`RepaintBoundary`** per tile grid galeri & tile tray story.
- **`_StoryTrayTile`**: guard `_thumb != null` (tidak decode ulang saat
  widget di-recycle).
- **`markSeen` → bulk**: viewer mengumpulkan id slide yang ditonton lalu
  kirim **sekali** (RPC `mark_story_seen_bulk`) saat ganti author / keluar
  viewer. Dulu 1 RPC per slide (lihat 10 slide = 10 RPC). Ada fallback
  ke `mark_story_seen` satu-satu bila RPC bulk belum ada di server.
- **Skip refresh tray** untuk author yang sedang dibuka
  (`StoryProvider.setViewingAuthor`) — event realtime-nya tidak memicu RPC
  tray penuh; ring sudah di-update lokal.
- **Viewer lifecycle** (`WidgetsBindingObserver`): app di-background →
  auto-advance berhenti (tidak menandai slide yang tak ditonton); kembali →
  **lanjut dari sisa waktu** (opsi A), bukan mulai ulang 5 detik.
- **Composer**: `readAsBytes` + proses gambar digabung jadi **satu
  `compute`** (`_readAndProcessStory`) — dulu read di main thread lalu
  compute terpisah (2 hop, bytes mentah sempat menyeberang).

**Hasil ukur (perangkat 192.168.18.33):**

| Metrik | Sebelum | Sesudah |
|---|---|---|
| `story.tray` (RPC) | 387 ms | **156 ms** |
| `story.slides` (RPC) | — | 141–170 ms |

> ⚠️ **`story_tray` JANGAN ditulis ulang jadi JOIN.** Sudah dicoba dan
> terbukti LEBIH LAMBAT (2 author: 0.082→0.157ms; 300 author: 29.5→51.0ms).
> Planner PostgreSQL sudah optimal dengan subquery skalar. Detail di
> `docs/MIGRATION_LOG.md` (2026-09-18).

### 2.11 Logout tidak boleh menggantung (fix spinner tak berujung)
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

`lib/core/perf/perf_probe.dart` — aktif HANYA dengan
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
| `call.turnFetch` | `call_config.dart` | fetch kredensial Cloudflare TURN |
| `call.setupMedia` | `call_service.dart` | `getUserMedia` + `createPeerConnection` |
| `call.initToConnected` | `call_service.dart` | `init()` → `CallPhase.inCall` (rekam) |
| `call.offerToConnected` | `call_service.dart` | offer dikirim → connected (rekam) |
| `CallScreen` (build) | `call_screen.dart` | jumlah rebuild layar call |
| `CallOverlay` (build) | `chat_call_overlay.dart` | jumlah rebuild overlay video chat |
| `call.watchPc` (build) | `call_service.dart` | jumlah PC watcher admin dibuat |

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
- [x] **#5 `RepaintBoundary` baris preview/unread SELESAI (2026-09-18).**
      Baris bawah kartu (centang-2 + preview + badge unread) diberi layer
      repaint sendiri. Alasannya bukan karena ada jank terukur, tapi karena
      **baris itu berubah paling sering** (tiap pesan masuk / read-receipt)
      dan sebelumnya menandai SELURUH kartu (termasuk avatar/foto) untuk
      repaint. Layer tambahan hanya SATU per kartu — jauh di bawah ambang
      yang bisa merusak raster cache.
- [x] **#6 Tunda avatar batch `OnlineUsersProvider` SELESAI (2026-09-18).**
      Batch avatar (N pembacaan kv) tidak lagi di-`await` sebelum list
      dipasang; list tampil dulu, avatar diisi di latar lewat
      `_loadDiskAvatars` (dengan guard balapan vs stream). Efek: frame
      pertama daftar online tidak lagi menunggu N pembacaan disk.
      Catatan: `online.diskLoad` terukur 20-53ms, jadi ini **bukan**
      perbaikan besar — nilainya lebih ke menghilangkan penundaan yang
      bergantung jumlah user (N× pembacaan → 0 di jalur kritis).

### Prioritas rendah (fitur, bukan optimasi) — TIDAK dikerjakan sebagai perf
- [~] **#7 Badge angka di ikon launcher — DITOLAK (2026-09-18).** Plugin
      `flutter_app_badger` yang dulu direkomendasikan **sudah discontinued**
      di pub.dev. Menambah dependency tak-terpelihara ke proyek rilis =
      risiko build/bug tanpa perbaikan hulu. Lagi pula ini **fitur**, bukan
      optimasi (nol dampak ke waktu render/fetch). Bila memang diinginkan:
      kerjakan sebagai fitur terpisah, idealnya lewat channel notifikasi
      Android langsung (tanpa plugin mati).
- [~] **#8 Suara & getar kustom per chat — DITOLAK sebagai bagian perf
      (2026-09-18).** Ini fitur baru (channel notifikasi dinamis per chat +
      preferensi user + UI pengaturan) — nol hubungan dengan performa.
      `flutter_local_notifications` + `audioplayers` sudah tersedia, jadi
      secara teknis bisa; tapi harus direncanakan sebagai fitur.
- [~] **#9 Snapshot tab — DIBATALKAN (2026-09-18).** Pengukuran mendukung
      putusan dokumen sendiri ("kemungkinan TIDAK perlu"): render
      p50 3.5ms / p99 6.6ms / **0% jank**, dan prewarm tab idle sudah jalan.
      Tidak ada jeda saat tap tab yang perlu ditutup snapshot. Membuat
      snapshot (toImage) justru menambah biaya memori & kerja GPU.

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
| 2026-09-18 | Story: notifier thumbnail galeri, RepaintBoundary tray/grid, bulk `markSeen`, skip refresh author aktif, viewer lifecycle, composer 1-hop | `story.tray` 387→**156ms**; `markSeen` N slide→1 RPC |
| 2026-09-18 | Index `story_views(story_id,viewer_id)` + RPC `mark_story_seen_bulk` | JOIN rewrite `story_tray` **dibatalkan** (terbukti regresi) |
| 2026-09-18 | Probe 2-mode (`releaseMeasure` untuk rilis — Sign-In aman tanpa SHA-1 debug); tambah titik ukur `online.rpc`, `online.rpcCountry`, `timeline.rpc`, `timeline.rpcMore`, `onlineUsers` | Belum ada angka — build probe siap, menunggu pembacaan `adb logcat` |
| 2026-09-18 | `OnlineUsersProvider`: 2 jalur notify → 1 `_scheduleCommit` (avatar-only 180ms / perubahan nyata 32ms) | Belum ada angka — pantau `notify onlineUsers` |
| 2026-09-18 | **UKUR jalur data** (`PERF_PROBE=true` rilis): `online.rpc` 21-260ms, `online.rpcCountry` 136-163ms, `timeline.rpc` 142-169ms, `online.diskLoad` ~21ms, **`chat.listFetch` 291-755ms × 8 beruntun** | Menemukan bottleneck utama = `chat.listFetch` |
| 2026-09-18 | **Fix dedupe `chat.listFetch`** (`_chatListFetchInFlight`): 5 pemanggil `getMyPrivateChats` tidak lagi menembak query sama bersamaan | 8 fetch → 1 (terverifikasi: 505.8ms sekali) |
| 2026-09-18 | **Fix kedip list Pesan**: recompute dipindah dari "build berikutnya" ke dalam `StreamBuilder` (sebelum `_listNotifier.value` dibaca) | List muncul di frame yang sama; hilang kedip EmptyStateView 1 frame |
| 2026-09-18 | **Instrumentasi seluruh tab admin**: wrapper `AdminService._rpc()` — 43 RPC terukur otomatis | Tidak ada tab >350ms; tertinggi `admin_storage_stats` 340.6ms; cold-start RPC berpengaruh ~40% |
| 2026-09-18 | **#5** `RepaintBoundary` baris preview/unread; **#6** avatar batch disk dipindah ke latar (`_loadDiskAvatars` + guard balapan) | #6 menghapus penundaan N×pembacaan kv dari jalur kritis daftar online. Test: cache disk antar-test dibersihkan (bug isolasi test tersingkap) |
| 2026-09-18 | **#7/#8 ditolak** (fitur, bukan perf; plugin badge discontinued) & **#9 dibatalkan** (render 0% jank — tidak ada jeda untuk ditutup) | Tidak ada perubahan kode. Alasan lengkap di bagian 6 |
| 2026-09-18 | **Pass 2** — tab admin dibuka 2× + jalur data diulang | Cold start hanya ~20-25% (bukan 40%); **admin panel tidak perlu optimasi** (semua <400ms, mayoritas 128-175ms). `chat.listFetch` tetap target tunggal (505-788ms) |
| 2026-09-18 | **Fix `chat.listFetch`**: `select()`→17 kolom eksplisit (buang `hidden_by/at` yang tak dipakai) + fetch & hidden **paralel** (`Future.wait`) | **~750ms → ~380ms (hemat ~50%)**. Bukti: `hiddenFetch` 370.7ms vs `listFetch` 380.2ms, selisih timestamp 9ms = jalan bersamaan. Metrik baru: `chat.hiddenFetch` |
| 2026-09-18 | **Warm-up RPC** (`main.dart`): setelah UI tampil, satu query ringan untuk membayar TLS handshake + memanaskan koneksi | `online.rpc` pertama **839→245ms (−71%)**; `chat.listFetch` pertama **839→449ms (−46%)**. Jalur lain tidak terpengaruh (tanpa regresi) |
| 2026-09-18 | **Probe: statistik persentil** (`min/p50/p90/max`) + `report()` otomatis saat app di-background | 8 sesi cold: `chat.listFetch` **254-434ms (avg 345)**, sebaran kontinu = **noise jaringan**, bukan pola. `online.rpc` p50 143-247ms dengan lonjakan tunggal 526-534ms (jitter). **Tidak ada pola tersisa untuk diperbaiki.** |
| 2026-09-19 | **Call/video call — instrumentasi + optimasi** (`PerfProbe.record`/`buildCount` di rilis): cache TURN 12 jam, timer durasi `ValueNotifier`, `RepaintBoundary` video, gate `dlog` overlay, timer `CallBanner` on-demand, tombol kontrol rata | `call.turnFetch` **1760→0.1ms** (cache), `call.setupMedia` **5509→40ms**, `initToConnected` 12735–18105→**avg 5104ms**; `build CallScreen` berhenti dipicu timer |
| 2026-09-19 | **Cron `chatyuk-call-sweep` */5m** — retensi call zombie + `call_signals` >1 jam (dulu hanya saat admin buka panel) | Mencegah `call_signals` membengkak (2.160 kB / 81 baris saat diukur) |

### 8. Target tersisa

**Tidak ada.** Semua item bagian 6 sudah tertutup:
- Selesai: #1, #2, #4, #5, #6
- Dibatalkan/ditolak dengan alasan tertulis: #3, #7, #8, #9

Semua jalur data terukur kini dalam rentang wajar:

| Jalur | Nilai akhir |
|---|---|
| `online.diskLoad` | 23-64 ms |
| `online.rpc` | 119-268 ms (warm) |
| `online.rpcCountry` | 119-187 ms |
| `timeline.rpc` | 117-175 ms |
| `chat.listFetch` | **380 ms** (dulu 505-788) |
| Semua RPC admin | 128-395 ms |

Yang masih di atas baseline hanya kondisi **cold start** (`online.rpc`
775-1319ms pada panggilan pertama) — itu sifat jaringan + inisialisasi
Supabase, bukan query. Bila suatu saat terasa mengganggu, kandidatnya
*warm-up RPC saat app idle*; belum dikerjakan karena belum terbukti
mengganggu pengalaman.
