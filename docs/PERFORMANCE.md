# PERFORMANCE — apa yang sudah diperbaiki & aturan lanjutan

> **BACA DULU sebelum mengoptimalkan apa pun.** Dokumen ini mencatat optimasi
> yang SUDAH ada beserta alasannya, supaya perubahan berikutnya **menambah**,
> bukan **merusak** (mis. mengembalikan `context.watch` yang sudah diganti
> `select`, atau menghapus `TickerMode`/`RepaintBoundary`).

Terakhir diperbarui: 2026-09-30 (branch `develop`).

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

### 1g. Review skala admin panel — "kalau orangnya banyak" (2026-09-26)

Skala live saat ukur: 162 profiles, 66 devices, 341 chats, 2358 messages,
14 dummies, 105 deleted. Pertanyaan: apa yang jebol duluan di 100×?

**Temuan 1 — O(n²) di client (DIPERBAIKI).** `_filtered()`/`_sortedFiltered()`
dipanggil di `itemCount` + di dalam `itemBuilder` **per baris** (devices tab
dan chat list), plus grouping+sort diulang tiap build. Tiap huruf search =
rebuild penuh. Fix (`admin_devices_tab.dart`, `admin_chat_list_screen.dart`):
hitung filter/group/sort **sekali per build** ke variabel lokal, `itemBuilder`
pakai ulang; search di-debounce 250ms.

**Temuan 2 — bug paginasi `admin_list_deleted` (DIPERBAIKI,
`20260926050000`).** `LIMIT/OFFSET` di subquery union **tanpa ORDER BY**
(urut baru di agregat luar) → halaman 2+ acak/duplikat saat data banyak.
Fix: `order by sort_at desc nulls last` di dalam subquery. Verifikasi live:
page1=100, page2=5, overlap=0, batas urutan benar. EXPLAIN: Index Only Scan
via `deleted_users_deleted_idx` ✅.

**Divalidasi aman (tidak diubah):**
- `admin_list_devices`: 1 query, ORDER BY ter-cover `user_devices_seen_idx`,
  total via estimasi `reltuples`. EXPLAIN: index-friendly.
- Semua tab sudah paging server (100/100/50/50/40) + infinite scroll +
  disk cache + polling 30–60 dtk yang skip saat sudah load-more.
- `admin_stats_detail` (FROZEN): 4× full-scan profiles — terbesar, tapi
  cache client 60 dtk + hanya saat buka usermap/sheet. **Sengaja tidak
  disentuh** (aturan frozen); jadi kandidat Fase 2 bila user >2000.
- N+1 di `admin_list_dummies_page` (`unread` per dummy), `admin_list_chats_page`
  (count+max per chat), `location_history` tanpa limit di `admin_user_detail`
  → **SUDAH DIPERBAIKI (2026-09-26, Fase 2):** `20260926060000` (unread via
  1× GROUP BY), `20260926070000` (msg_count/last_noncall via 1× agregasi +
  total estimasi reltuples, semantik urutan `call` dipertahankan),
  `20260926080000` (location_history dibatasi 200 + count via agregasi;
  kunci JSON tidak berubah).
- Sheet detail statistik user → paginasi server via RPC **baru**
  `admin_stats_users_page` (`20260926090000`; filter/bentuk/urut SAMA dengan
  detail; `admin_stats_detail` FROZEN **tidak disentuh**).

**Catatan 100×:** uji beban sintetis 16k baris **sengaja tidak** dilakukan di
DB live (risiko trigger/notifikasi/polusi). Sebagai gantinya: EXPLAIN
index-usage + bukti determinisme paginasi di atas + fix kompleksitas client
(yang terbukti benar secara konstruksi, bukan pengukuran).

### 1h. Diagnosis "ngelag" di HP (2026-09-26, ukur langsung + PERF_PROBE)

Keluhan user: admin panel terasa ngelag. Diukur live di HP (Xiaomi,
build admin diagnosis): **semua RPC 130–360ms, tidak ada query patologis**.
Query per query sudah cepat (EXPLAIN: count devices 0.99ms; payload devices
cuma 36KB). Lag berasal dari **jumlah round-trip saat buka panel**, bukan
1 query lambat:

**Temuan — `armNotifications()` menarik `listDevices(limit: 1000)` tiap buka
panel** (hanya untuk seed ID seen). Bersamaan dengan itu: `fetchStats`,
`_loadPointSettings`, `fetchDevices` (hal. 100), `fetchActiveCalls` +
realtime → 4–5 RPC berat berbarengan di koneksi yang sedang buruk (banner
"Tidak ada koneksi internet" tampil saat ukur).

**Fix (client saja, tanpa SQL):**
- Seed jadi malas (lazy): `fetchDevices` pertama setelah arm = baseline
  diam-diam (`_seedDone` di `AdminBase`; device baru selalu di atas karena
  ORDER BY last_seen desc → halaman-1 cukup). Fetch limit-1000 dihapus total.
- `getExcludedDevices()` di-memo 5 menit di `AdminService` (dulu tiap
  deteksi = 1 RPC; hanya menunda supresi notifikasi, bukan data).
- Test: `armNotifications` verifyNever `listDevices`; fetch-1 seed diam,
  fetch-2 device baru → tepat 1 notifikasi (`admin_provider_di_test.dart`).

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
di sekitar `RTCVideoView`. Gate izin (`ensureCallPermissions` di
`lib/core/call/`) dipanggil SEBELUM `startCall` agar `getUserMedia` tidak
gagal senyap; fallback all-candidates (`_retryWithAllCandidates`, sekali per
sesi) hanya jalan saat `lastConfigWasRelayOnly` true — jangan dihapus.

### 1l. UI panggilan sistem — ConnectionService (2026-09-19)

Panggilan masuk kini memakai UI panggilan SISTEM Android (Telecom
ConnectionService SELF_MANAGED) — ring di layar kunci/headset/Bluetooth,
gaya WhatsApp. Media TETAP WebRTC di Dart; native hanya ring + tombol
jawab/tolak (`docs/CALL_NATIVE.md`).

- Tidak ada tambahan beban render/data: `CallSession.init()` tetap dipanggil
  hanya SETELAH pengguna menerima.
- Ringtone Dart dimatikan saat `usesSystemUi` (Android) → tidak ada nada
  dering dobel (satu audio focus, bukan dua).
- Push `type=call` saat app mati kini ditangkap `ChartyukMessagingService`
  (native) yang tetap memanggil `super.onMessageReceived` sehingga handler
  notifikasi Dart tidak berubah.

### 1k. Retensi call otomatis (server, 2026-09-19)

`admin_sweep_calls()` (akhiri `ringing` basi >90 dtk, `answered` tanpa heartbeat
>75 dtk, hapus `call_signals` call selesai >1 jam) dulu **hanya** terpanggil saat
admin membuka panel → untuk user biasa call zombie menggantung & `call_signals`
menumpuk (terukur 2.160 kB untuk 81 baris). Sekarang dijadwalkan cron
`chatyuk-call-sweep` `*/5 * * * *`. Tidak mengubah isi fungsi (bukan FROZEN).

### 1m. Watch monitor admin — `watch_request` bertarget (2026-09-29)

**Masalah (call audio dian↔sary):** di layar monitor admin, audio-video
peserta "putus tengah jalan" berulang. Bukti DB `call_signals` (call
`3cfd652c`): 12 `watch_request` + peserta membuat `watch_offer` baru 5x
(sary) / 4x (dian) dalam 87 dtk — tiap offer baru menutup pc watch lama.

**Akar:** `watch_request` dikirim **tanpa `to`** padahal dikirim di dalam
loop per peserta (`admin_call_watch_service.dart`) → 2 sinyal identik per
siklus, dan **tiap peserta memproses keduanya** → pc/offer watch dobel
(tak terlihat 4 ms di call video `871e93d9`: 2 offer). Ditambah race
throttle: `_lastWatchReply` baru di-set **setelah** `await isAdminUid`,
jadi dua request bersamaan sama-sama lolos cek "belum pernah balas".

**Perbaikan (tanpa sentuh pc sehat, tanpa ubah fungsi FROZEN):**
1. `watch_request` kini bertarget `to: p.uid` per peserta.
2. Peserta memfilter via `isWatchRequestForMe` (`watch_policy.dart`) —
   sinyal tanpa `to` (versi lama) tetap diterima.
3. Penanda throttle `_lastWatchReply` di-set **sebelum** `await` (tutup
   race double-handle).

**Verifikasi:** `flutter analyze` 0 error/0 warning (info lama tetap);
`test/watch_policy_test.dart` 16/16 (3 assert baru untuk targeting);
subset test call/admin hijau (70/70). Belum diukur ulang di HP — jalankan
build `--profile` lalu pilih call yang di-monitor dan buktikan jumlah
`watch_offer` per 90 dtk turun (target ≤2, dari 9).

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

### 2.12 Private chat: kurangi kerja rebuild & fetch foto burst (2026-09-20)

- `private_chat_screen.dart`: `deletedIds` sekarang dihitung sekali per emission
  stream, bukan sekali untuk setiap bubble. Ini menghapus scan O(N) berulang di
  dalam `itemBuilder` yang sebelumnya menjadi O(N²) saat chat panjang direbuild.
- Auto-load foto lama sekarang memakai antrean dengan maksimal **3 fetch aktif**.
  Sebelumnya semua foto lama yang belum memiliki thumbnail dapat menembak
  request bersamaan dan membebani network, decoding, serta memory.
- Cooldown 10 detik per message ID dan dedupe in-flight tetap dipertahankan.

Perubahan ini belum diukur di perangkat fisik; ukur ulang `chat.listFetch`, jumlah
rebuild `PrivateChatScreen`, dan memory saat chat berisi 100/500/1000 pesan.

### 2.13 Video chat — lazy poster + anti "ngeblink" (2026-09-27)

Fitur video upload & rekam kamera menambah bubble video baru. Audit lazy-load
menemukan dua masalah (bukan render, tapi waktu DATA):

1. **Realtime broadcast/insert memproses video sebagai image** — kondisi
   `msg.imageData.isNotEmpty && msg.type != 'voice'` juga menangkap
   `video`/`video_once`/`video_once_expired`. Akibatnya jalur realtime
   **mengunduh file video PENUH** lalu coba `PhotoCache.save` (generate
   thumbnail dari .mp4 → gagal), membuang bandwidth + menunda emit.
   **Fix** (`chat_stream_session.dart`): kecualikan ketiga type video
   (`!isVideoType` / `!bcIsVideo`) — poster diurus `ChatVideoBubble` sendiri
   (ambil 1 frame dari video). Foto/voice tetap seperti semula.

2. **Poster video tak dibatasi konkurensi** — tiap bubble video mengunduh
   video penuh untuk 1 frame. Puluhan video terlihat saat cold start =
   berebut bandwidth (gejala "ngeblink"). **Fix** (`chat_video_bubble.dart`):
   tambah gate konkurensi statis (`_PosterGate(3)`) — maks 3 unduhan poster
   bersamaan; sisanya antri. Cache disk (`video_poster:<path>`) tetap dicek
   lebih dulu tanpa gate (instan).

Yang **sudah** benar & dipertahankan: `ListView.builder` (hanya item tampil
yang dibangun), `ChatVideoBubble` menunda `_loadPoster()` 1 frame via
`addPostFrameCallback`, poster disimpan ke `MediaDiskCache` (anti-blink),
`ChatVideoBubble` skip render saat `_locked` (sekali-lihat kadaluarsa).

Catatan: `_autoLoadMissingImages` sengaja hanya untuk `image` — video punya
alur poster sendiri di bubble, tidak lewat antrean foto.

### 2.15 Monitor call admin — status jelas + audio lebih cepat (2026-09-29)

Keluhan: saat memantau call dari monitor chat, "suaranya keluar aga lama" dan
tidak jelas apakah itu orangnya belum bicara atau handshake belum selesai.

**Akar (terverifikasi di kode):**
1. `admin_chat_view_screen` menunggu `fetchActiveCalls()` (RPC) dulu baru
   mulai `_syncCallWatch()` → bila call belum ada di daftar, pantau baru jalan
   di tick 5 dtk.
2. Peserta wajib RPC `is_chatyuk_admin` sebelum melayani pantau (tidak ada
   cache) → 1 RTT ekstra tiap sesi.
3. `_handleWatchRequest` membuang permintaan yang datang sebelum media lokal
   siap (`_localStream == null`) → admin menunggu tick berikutnya.
4. Permintaan admin tetap 3 dtk dari awal (tidak ada kadens cepat).
5. `AudioListenChip` selalu menulis "Mendengarkan..." — indikator
   connected/mic hanya ada di overlay **video**, jadi call audio tidak punya
   cara membedakan "belum nyambung" / "mic mati" / "memang diam".
6. `setSpeakerphoneOn(true)` gagal ditelan `catch (_) {}` → audio bisa
   nyangkut di earpiece tanpa tanda.

**Perbaikan (klien saja, tanpa SQL — RLS `call_signals` sudah mengizinkan admin):**
- **A1** `audio_listen_chip.dart`: status NYATA per peserta (Memanggil /
  Menyambungkan / Mikrofon mati / Mendengarkan) + ikon warna; peringatan
  "Audio mode telepon (speaker gagal)".
- **A2** `WatchSession.speakerFailed` di-set saat `setSpeakerphoneOn` gagal.
- **B1** `admin_chat_view_screen`: `_syncCallWatch()` dipanggil langsung (tak
  tunggu RPC fetch), fetch tetap paralel.
- **B2** `CallService.isAdminUid`: cache **positif saja**, TTL 30 mnt (negatif
  selalu recheck — gerbang keamanan tetap).
- **B3** `CallSession._pendingWatchRequests`: permintaan yang datang sebelum
  media siap diantre, dibalas oleh `_flushPendingWatchRequests()` tepat
  setelah `call.setupMedia`.
- **B4** `watch_policy.watchRequestDelay(attempt)`: 3 percobaan pertama 1,5 dtk,
  lalu 3 dtk (throttle peserta 8 dtk & stale 20 dtk **tidak diubah** — pengaman
  anti-putus-audio).

**Metrik baru (PERF_PROBE):** `watch.connect` (request→connected),
`watch.openFirst` (buka layar→peserta pertama connected), `watch.firstAudio`
(track audio pertama tiba). Muncul otomatis di `[PERF]` via `report()`.

**Cara ukur:** build rilis + `--dart-define=PERF_PROBE=true` → 3 call audio →
app di-background → `adb logcat | grep '\[PERF\]'`; tulis tabel sebelum/sesudah
di sini.

| Metrik | Sebelum | Sesudah |
|---|---|---|
| `watch.connect` | (belum ada metrik) | _diisi setelah pengukuran_ |
| `watch.openFirst` | (belum ada metrik) | _diisi setelah pengukuran_ |
| `watch.firstAudio` | (belum ada metrik) | _diisi setelah pengukuran_ |

### 2.14 Monitor chat admin — spinner lama saat buka chat (2026-09-28)

Keluhan: klik chat di monitor admin kadang muter lama. Akar masalahnya tiga,
semuanya di jalur DATA (bukan render):

1. **RPC tanpa timeout** — `AdminService.getChatMessages` (dan
   `getChatLastRead`) satu-satunya RPC buka-chat TANPA `.timeout()`. Saat
   koneksi stall, future tak pernah selesai → spinner (satu-satunya item
   list saat `_msgs` kosong & `_hasMore=true`) muter selamanya. Fix: tambah
   `.timeout(_openTimeout)` 30 dtk seperti RPC buka-panel lain; gagal-timeout
   ditangkap provider → layar tampil banner error + bisa pull-to-refresh,
   bukan blank/spinner abadi.
2. **Foto berebut tanpa batas** — `_loadPhotos` menembak `_loadOnePhoto`
   untuk SEMUA foto sekaligus (tiap foto = cek disk + RPC
   `fetchMessageImage` + download storage + isolate thumbnail). Chat berisi
   banyak foto = N RPC + N download + N isolate berebut → semua spinner foto
   muter lama. Fix: antrean maks **3** bersamaan + cooldown 10 dtk per id
   (pola sama seperti `_autoLoadMissingImages` private chat, §2.12);
   pesan terhapus (`isDeleted`) tidak ikut antre.
3. **O(n²) di `_applyMessages`** — `list.indexOf(m)` di dalam loop +
   `senders.contains` di dalam loop. Fix: loop berindeks + `Set`.

Belum diukur di perangkat (butuh chat berisi banyak foto + jaringan buruk);
klaim "lebih cepat" di sini bersifat konstruksi (konkurensi dibatasi +
timeout), bukan angka. Ukur ulang bila keluhan muncul lagi.

### 2.16 Prewarm tab dipercepat — hilangkan jank "kadang delay" saat pindah tab (2026-09-30)

**Keluhan:** "klik halaman kadang ada delay" saat pindah tab bawah (Online/
Chat/Timeline/Profil). Intermitten → menuntut pengukuran, bukan tebakan.

**Cara ukur (build rilis + `--dart-define=PERF_PROBE=true`, Xiaomi
24129PN74G Android 16, apkpureProd):** skenario cold start → tap tab pada
variasi jeda (1.5/1.8/2.5s) + tab hangat; baca `[PERF] tab{N} tap→frame`,
`janky(build)`, dan `build max`. Jalur data (RPC) diukur bersamaan sebagai
pembanding.

**Data — SEBELUM (n=42 tap, tab1-3 setelah cold start):**

| Metrik | Nilai |
|---|---|
| avg / p50 | 9.5 / 9.1 ms |
| p90 / max | 17.0 / **25.6 ms** |
| tap >16.7ms (jank) | **5 (12%)** |
| `janky(build)` saat prewarm **tanpa tap** | **2** (max 21.2ms) |

Bukti pemisah kunci: tab **hangat** → tap 1.7-13ms, `janky(build)=0`; tab
**belum di-prewarm** (tap@1.5-1.8s) → 14.6-22ms; **prewarm sendiri tanpa tap**
→ 2 jank. Jadi bukan render umum (p50 build 1.4ms) & bukan jalur data
(RPC 115-320ms normal) — melainkan **waktu pembangunan halaman tab**.

**Akar (terukur):** `_scheduleTabPrewarm` (`app.dart`) dulu mulai 1200ms +
interval 800ms → tab3 baru dibangun di **2800ms**, padahal UI sudah interaktif
~1300ms. Tiap `setState(() => _visitedTabs.add(i))` membangun SATU halaman tab
penuh **sinkron dalam frame itu** (1 jank frame). Jendela 1300-2800ms = user
bisa tap tab yang belum dibangun → build halaman jatuh di frame tap → jank.

**Fix (timing saja, `lib/app.dart`):** mulai **300ms** + interval **250ms** →
semua tab hangat ~800ms, **sebelum** UI interaktif. Struktur prewarm tidak
diubah (persis pola "pil nav 500→260ms" §2.8).

**Data — SESUDAH (n=38 tap):**

| Metrik | Sebelum | Sesudah |
|---|---|---|
| tap p90 | 17.0 ms | **14.6 ms** |
| tap max | 25.6 ms | **20.3 ms** |
| tap >16.7ms (jank) | **12%** | **2.6%** (1 dari 38) |
| `janky(build)` prewarm tanpa tap | **2** | **0** (max 13.9ms) |
| tap tab3 @1.8s | 22.0 ms | **6.0 ms** |

**Jangan:** perlambat prewarm (≥800ms interval / ≥1.2s mulai) tanpa mengukur
ulang — itu mengembalikan jendela "belum hangat" & jank tap. Verifikasi dengan
metrik `tab{N} tap→frame` + `janky(build)` di build probe.

### 2.17 Sisa jank tap = FRAME SCHEDULING (vsync), bukan build/raster — BUKAN bug kode (2026-09-30)

Setelah §2.16, sisa jank tap diselidiki mendalam. **Kesimpulan akhir: jank tap
adalah keterlambatan PENJADWALAN frame (menunggu vsync), bukan pekerjaan render.**

**Bukti 1 — frame-nya sendiri cepat.** `frameSummary` sesi tap:

| Sesi | build (p50/max) | raster (p50/max) | janky(build) | janky(raster) |
|---|---|---|---|---|
| A: diam di tab2 | 1.3 / 14.8ms | 3.0 / 10.9ms | 0 | **0** |
| B: scroll tab2 | 0.3 / 13.8ms | 1.9 / 15.2ms | 0 | **0** |
| C: tap bolak-balik | 1.3 / 11.8ms | 2.4 / 10.1ms | 0 | **0** |
| D/E: tap cepat | 1.3 / **8.3ms** | 2.3 / **8.6ms** | 0 | **0** |

Padahal tap→frame bisa 16-18ms. **Frame render hanya ~8ms** — jadi 8-10ms
sisanya = **waktu tunggu vsync** (tap jatuh setelah vsync terlewat → frame baru
menunggu interval berikutnya). Terbukti: `tap→frame ≈ +frame0` (semua waktu di
frame pertama), dan frame pertama itu sendiri cepat.

**Bukti 2 — bukan spesifik tab.** Eksperimen C/D/E (n=192 tap, semua tab):
avg 10.1 / p50 9.3 / p90 17.3 / max 27.1ms; **13% >16.7ms**. Jank muncul di
**tab0 (Online) juga** (17.9/22.2/27.1ms), bukan cuma Timeline. Distribusi
bimodal (p25=5.8ms "langsung", p75=15.4ms "nunggu vsync") — ciri frame pacing,
bukan beban tab. Semakin cepat tap beruntun, semakin sering kena.

**Hipotesis yang GUGUR (terukur):**
- ~~Spike raster foto tab2~~ → diam & scroll di tab2 = `janky(raster)=0`.
- ~~Rebuild widget berat~~ → `build max 8.3ms`, p50 1.3ms.
- ~~Alokasi `_imagePaths()` 2×/build~~ → cache diuji (n=12, jank 8%), DIREVERT.

**Artinya:** "kadang delay" yang dirasa user = **frame pacing Flutter/device**,
bukan kode widget. Mengubah build widget **tidak akan** memperbaikinya (frame
sudah jauh di bawah 16.7ms). Jangan kejar angka ini dengan mengubah kode render
`PostCard`/`TimelineScreen` — akan sia-sia. Bila user menuntut hilang total,
arahnya arsitektur (mis. `SchedulerBinding.scheduleFrame`, mode performa device,
atau investigasi compositor) — risiko tinggi, belum dikerjakan.

**Yang tetap benar dari penyelidikan ini:** §2.16 (prewarm) tetap valid — ia
memangkas jendela "belum hangat" sehingga tab tidak dibangun di frame tap.
Sesudah §2.16, sisa ~13% tap-pacing adalah batas platform.

**AKAR PLATFORM (terukur 2026-09-30): app di-lock 60Hz walau layar 120Hz.**
`dumpsys SurfaceFlinger` saat app jalan: `activeMode vsyncRate=60.00 Hz`
(device global bisa 120). `dumpsys display`: `renderFrameRate 60.000004`,
`appRequest render: (0.0 60.0)`. **Di 60Hz 1 frame = 16.7ms** → tap→frame
16-18ms = tepat 1 interval; di 120Hz akan ~8.3ms (halver).

Penyebab: `AndroidManifest` **tidak** meng-opt-in high-refresh
(`android:preferHighRefreshRate="true"`). Bukti: saat device di-set global 120
(`settings put system peak_refresh_rate 120` + toggle layar), **launch app
langsung menjatuhkan mode ke 60Hz** (id=7) — MIUI menahan app tanpa opt-in.

**Fix DIUJI & DIREVERT (2026-09-30).** Dicoba `preferredDisplayModeId` (mode
refreshRate tertinggi) di `MainActivity.onCreate`. Hasil:

| | tap avg | tap p50 | `janky(raster)` |
|---|---|---|---|
| 60Hz (baseline) | 8.0ms | 7.8ms | **0** |
| 120Hz (fix) | **7.3ms** | **6.6ms** | **41** (raster max 64ms!) |

- Perbaikan tap **marginal** (~0.7ms) — karena frame render cuma ~2ms, latency
  tetap didominasi tunggu vsync (1 interval, di kedua Hz).
- **Regresi raster berat**: `janky(raster)` 0→41 (max 64ms) di 120Hz — GPU
  Adreno tersendat saat dipaksa 120.
- **Tidak konsisten**: `preferredDisplayModeId` kadang dihormati (120),
  kadang tidak (HyperOS override balik 60) — 3/3 sample terakhir = 60Hz.

Kesimpulan: **tidak layak.** Perubahan `MainActivity.kt` DIKEMBALIKAN (§6).
`preferHighRefreshRate` bukan attribute manifest valid (AAPT menolak).
Jangan ulangi tanpa mengukur `janky(raster)` — di device ini 120Hz justru
merugikan. Bila mau dikejar lagi: butuh kontrol per-app dari sisi sistem
(MIUI whitelist) atau profil performa — bukan perubahan app.

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
| `watch.connect` | `admin_call_watch_service.dart` | `watch_request` pertama → peserta tersambung |
| `watch.openFirst` | `admin_call_watch_service.dart` | layar monitor dibuka → peserta PERTAMA tersambung |
| `watch.firstAudio` | `admin_call_watch_service.dart` | `watch_request` pertama → track audio pertama tiba |

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
- Explore room (`RoomProvider.fetchExplore`, 30s TTL + disk): full RPC
  `list_room_explore` HANYA saat buka/ganti negara/pull-refresh/buat room —
  online count segar via stream `_counts` yang sudah ada (update lokal,
  tanpa RPC ulang). Sort/filter Rame-vs-kategori di Dart per emission
  (list ≤200, O(n log n) sekali per notify) — jangan pindah ke SQL
  per kategori (hemat round-trip).
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
| 2026-09-27 | **Avatar: satu kunci cache per uid** (§16) — `getByPath` cek `_cache[uid]` dulu + peta path→uid + seed sinkron RAM/disk di `UserInfoScreen`/`ProfileAvatar` | Halaman profil tak lagi "nge-blink" saat dibuka dari private chat (foto dari disk/daftar chat dipakai instan) |
| 2026-09-27 | **Admin monitor chat: lokal-first** (§17) — `fetchChatMessages({force})` & `_fetch({force})` skip RPC saat pesan sudah ada di cache; server hanya saat kosong / pull-to-refresh | Buka-ulang chat di monitor tidak load ulang dari server; pesan baru tetap via poll 5 dtk + realtime |
| 2026-09-28 | **Monitor chat: timeout RPC + antre foto** (§2.14) — `getChatMessages`/`getChatLastRead` + `.timeout(30s)`; load foto admin dibatasi 3 bersamaan + cooldown 10 dtk; `_applyMessages` O(n²)→O(n) | Konstruksi (belum diukur di HP); spinner abadi hilang, foto tak berebut |
| 2026-09-29 | **Monitor call admin** (§2.15) — chip status nyata per peserta (+ speaker-fallback), mulai pantau tanpa tunggu RPC, cache positif `isAdminUid` 30 mnt, antre request sebelum media siap, kadens 1,5 dtk (3×) lalu 3 dtk; metrik `watch.connect`/`openFirst`/`firstAudio` | Konstruksi (metrik disiapkan); audio mulai lebih cepat + admin bisa bedakan "belum nyambung" vs "mic mati/diam" |
| 2026-09-30 | **Prewarm tab dipercepat** (§2.16) — `_scheduleTabPrewarm` mulai 1200→**300ms**, interval 800→**250ms** (semua tab hangat ~800ms, sebelum UI interaktif ~1300ms) | Jank tap tab 12%→**2.6%** (max 25.6→20.3ms); `janky(build)` prewarm 2→**0**; tap tab3 @1.8s 22.0→**6.0ms** (build rilis+`PERF_PROBE`, Xiaomi 24129PN74G) |
| 2026-09-30 | **Diagnosa sisa jank tap** (§2.17) — 4 eksperimen (diam/scroll/tap-cepat, n=192): frame render cuma **8ms** tapi tap→frame 16-18ms → jank = **frame scheduling (vsync)**, bukan build/raster/tab. Hipotesis raster-foto & alokasi `_imagePaths` GUGUR terukur (cache di-revert) | Bukan bug kode — batas platform. "Kadang delay" = frame pacing; jangan kejar dgn ubah build widget |
| 2026-09-30 | **Memory audit** — PSS cold 233 MB → aktif puncak 267 MB → idle 60s **245 MB** → HOME 185 MB (kembali turun) | **Sehat, tanpa leak** (GC normal); PSS konsisten dgn §13 (~225 MB) |
| 2026-09-30 | **QA Perf TAB TIMELINE** (§2.18) — ukur feed/komentar/like/composer (build probe); tambah metrik `timeline.getPost`/`timeline.createPost` + `buildCount('PostDetail')` | Semua jalur **normal**: `timeline.rpc` 118-211ms, komentar buka #2-3 = 0 RPC (cache §12.1 jalan), like 122-157ms, `build Timeline`=3, jank 0-2. Timeline SEHAT |

### 2.18 QA Perf TAB TIMELINE (2026-09-30)

Diminta "sisir semua bagian Timeline". Ukur dulu (build rilis + `PERF_PROBE`,
Xiaomi 24129PN74G, 60Hz), perbaiki hanya bila ada angka buruk (§6).

| Bagian | Metrik | Hasil | Ukur ulang # | Putusan |
|---|---|---|---|---|
| Feed halaman-1 | `timeline.rpc` | 118-211ms (p50 ~149) | 3× scope | ✅ normal |
| Paginasi | `timeline.rpcMore` | tak terpicu (feed pendek) | — | — |
| Buka komentar ×3 | `timeline.comments` | **n=1, 126.7ms** | #2-3 = **0 RPC** | ✅ cache §12.1 jalan |
| Like/unlike | `timeline.like` | 122-157ms | 2× | ✅ normal |
| Render tab | `buildCount('Timeline')` | 3 | tiap sesi | ✅ sehat |
| Render composer | `buildCount('PostComposer')` | 1 | — | ✅ |
| Jank (semua) | `janky(build/raster)` | 0-2 | tiap sesi | ✅ sama dgn §12.6 |

**Dibanding doc §12.6 (2026-09-20): tidak ada regresi.** `timeline.rpc`
136-144→118-211ms (noise jaringan), komentar cache tetap 0 RPC, like
168→122-157ms.

**Instrumentasi ditambah** (celah yang belum terukur, additive & no-op saat
probe off):
- `timeline_provider.dart`: `getPost`→`timeline.getPost`, `createPost`→
  `timeline.createPost`.
- `post_detail_screen.dart`: `buildCount('PostDetail')`.

**Belum terverifikasi otomatis** (butuh interaksi manual, adb tak andal):
submit composer (`create_post`) & buka `PostDetailScreen` dari notifikasi
`timeline_post`. Metriknya sudah siap — jalankan manual utk mengisi angka.

**Kesimpulan:** Timeline **sehat** — tidak ada masalah performa yang bisa
diperbaiki kode. Sisa keterlambatan (bila ada) = frame pacing (§2.17), bukan
jalur Timeline. Jangan ubah `TimelineScreen`/`PostCard`/provider tanpa angka
baru.

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

---

## 12. Timeline — optimasi foto/komentar/respons (2026-09-20)

Keluhan: timeline terasa berat saat scroll, buka komentar, dan berinteraksi
(like/share). Audit menemukan 4 pola klien yang boros (bukan masalah query DB —
volume data saat audit hanya 6 post / 5 komentar). Perbaikan:

### 12.1 Comment sheet — cache + TTL + realtime terfilter
- **Dulu:** `_CommentsList._load()` SELALU memanggil `list_post_comments` tiap
  sheet dibuka (walau cache baru diisi). Buka-tutup-buka = 3× RPC.
- **Sekarang:** `TimelineProvider.isCommentsFresh(postId)` (TTL 30 dtk) —
  cache segar → tampil instan tanpa RPC. Timestamp cache baru
  (`_commentCacheAt`) diisi di `cacheComments()` + prefetch.
- **Realtime komentar:** channel `post-comments-<postId>` dengan filter
  `post_id=eq.<id>` — komentar baru dari orang lain muncul live; unsubscribe +
  `removeChannel` saat sheet ditutup (tidak menumpuk channel).
- **`shrinkWrap: true` dihapus** — parent `Flexible` sudah memberi tinggi
  bounded; shrinkWrap dulu membangun SEMUA baris komentar sekaligus.

### 12.2 Realtime `posts` — guard notify
- **Dulu:** event UPDATE dari user mana pun (like/view/komentar di post yang
  TIDAK ada di feed aktif) tetap memicu `notifyListeners()` → seluruh layar
  Timeline rebuild percuma (subscribe `posts` tanpa filter).
- **Sekarang:** update hanya diproses bila post ADA di `_posts` DAN nilainya
  benar-benar berubah (like/comment/share/boost). Selain itu → return tanpa notify.

### 12.3 Prefetch komentar saat feed load
- **Dulu:** 5 `list_post_comments` ditembak BERSAMAAN tiap refresh/paginasi.
- **Sekarang:** turun ke **2**, ditunda **500 ms idle** (timer dibatalkan bila
  scope berganti / fetch baru) — tidak lagi bersaing dengan render feed.

### 12.4 Search filter di-cache
- **Dulu:** `postsRaw.where(...)` jalan tiap `build()` saat search aktif.
- **Sekarang:** hasil filter di-cache; recompute hanya saat `posts` atau
  `_appliedSearch` berubah (identitas list + string dibandingkan).

### 12.5 Housekeeping
- Semua instansiasi `TimelineService()` inline di `post_card.dart` → lewat
  `TimelineProvider` (DI, testable).
- `PostCard.didUpdateWidget`: reload thumbnail bila `images`/`imagePath`
  berubah (dulu hanya `initState` → gambar tidak pernah update saat data
  post diganti realtime).

**Verifikasi:** `flutter analyze lib test` 0 error/0 warning; `flutter test`
**725 hijau** (+7 test baru: TTL cache komentar, guard notify realtime).

### 12.6 Hasil pengukuran (build rilis + `PERF_PROBE=true`, Xiaomi 24129PN74G)

Perangkat: `192.168.18.33` (Xiaomi 24129PN74G), jaringan Wi-Fi rumah.

| Jalur | Sebelum (perilaku lama) | Sesudah | Catatan |
|---|---|---|---|
| `timeline.comments` (buka sheet komentar) | **n=3** (tiap buka = 1 RPC, ~150ms/buka = ~450ms) | **n=1 · 153.3 ms** | Buka #2 & #3 dalam 30s dilayani cache — **0 RPC**. Bukti: probe `n=1` meski sheet dibuka 3×. |
| `timeline.comments` (setelah submit komentar) | — | 332.6 ms | Sekali refresh setelah tulis (wajar). |
| `timeline.like` (tap suka) | — | 336.6 ms → 168.7 ms (n=2) | Panggilan kedua lebih cepat (koneksi hangat). |
| `timeline.addComment` (kirim komentar) | — | 338.6 ms | Row benar-benar masuk DB (diverifikasi via Management API: `post_comments.id=9`). |
| `timeline.rpc` (halaman 1 feed) | 142-169 ms | **n=3 min=125.8 p50=136.8 p90=142.4 max=143.8 ms** | 3 panggilan = prewarm 3 scope (all/following/mine). |

**Kesimpulan:** optimasi komentar terbukti — membuka sheet komentar berulang
**tidak lagi menembak RPC** (0 ms setelah buka pertama), dan aksi tulis
(like/komentar) konsisten ~170-340 ms (murni round-trip jaringan, bukan lagi
overhead klien). Tidak ada crash/exception selama sesi ukur (`null check
operator` = 0).

> Catatan: banner "Tidak ada koneksi internet" sesekali muncul (deteksi MIUI)
> meski RPC tetap sukses — bukan indikator kegagalan app.

**Titik ukur baru:** `timeline.comments`, `timeline.like`, `timeline.addComment`,
`timeline.replyComment`, `timeline.share` (ditambahkan di `TimelineProvider`
passthrough, `timeline_provider.dart`).

### 12.7 QA performa per halaman (2026-09-26, Xiaomi 24129PN74G, build rilis + `PERF_PROBE=true`)

**Instrumentasi baru (Fase A):** `PerfProbe.buildCount` di 10 layar
(RoomChat, PrivateChat, Timeline, Profile, UserInfo, StoryViewer,
StoryComposer, Nearby, SocialList, PostComposer). Jalur data sudah tercakup
sebelumnya (`chat.listFetch`, `online.rpc`, `timeline.rpc`, `call.*`,
`admin.*`).

**Hasil buildCount (sesi nyata):**
| Layar | Sebelum fix | Sesudah fix | Catatan |
|---|---|---|---|
| PrivateChat (buka 1 chat + idle) | 50–67 | **3** (ronde kontrol: airplane mode, emisi network dimatikan) | Fix: `watch<AuthProvider>`/`watch<PointsProvider>` → `select` per field |
| RoomChat | — | `select` boolean `enabled` (pola sama, tanpa ronde ukur khusus) | Satu-satunya field yang dipakai render |
| Online / MainNav | 56–66 / 52–61 | 9–10 / 9 (ronde kontrol) | Didominasi emisi realtime (presence), bukan watch — by design |
| Timeline / StoryViewer / UserInfo / Profile / ChatList | 3 / 3 / 2 / 5–12 / 9–15 | — | Sehat, tidak dioptimasi |

**Jalur data (rentang antar-sesi, jaringan rumah berfluktuasi):**
`chat.listFetch` 225–1007ms (normal) dengan spike server hingga max 1.8s
(`pg_stat_statements`: mean 1–22ms, max 887–1845ms — bahkan lookup PK ikut
spike → noise infrastruktur, bukan bentuk query). Sampel >7s adalah artefak
pengujian (request in-flight saat mode pesawat on) dan dibuang. Warm sehat:
`online.rpc` 115–185ms, `timeline.rpc` ~115–156ms, `story.tray` 125–265ms.

**Frame:** `SurfaceFlinger --latency` tidak mengembalikan sampel di perangkat/
Android ini (layer idle; limitasi tooling yang sudah didokumentasikan).
`gfxinfo` (n=19, lemah): p50 6ms, 2 janky. Tidak ada ANR/crash. Memori sehat
(PSS ~237MB).

**Belum terukur (butuh sesi lanjutan):** render tab admin, RoomChat rebuild,
Nearby/SocialList/PostComposer/StoryComposer counts, call 2-device.

**Aturan lanjutan (jangan dibalik):** `select` per field di
`private_chat_screen.dart` / `room_chat_screen.dart` (bukan `watch` penuh);
titik `buildCount` 10 layar di atas.

### 12.8 Kandidat yang GUGUR terukur (2026-09-26, ronde kontrol)

Dua dugaan dari review divalidasi dengan `PerfProbe.measure` di build probe
(sesi nyata: Online scroll 2× + buka 1 chat + background):

| Kandidat | Hasil | Putusan |
|---|---|---|
| `Nav.unread` (fold unread badge BottomNav per emission) | n=23, avg=max=0.0ms | **GUGUR** — trivial, jangan dioptimasi |
| `Online.filter` (filter+dedupe list Online per emission) | n=17, avg=max=0.0ms | **GUGUR** — trivial (<0.05ms), jangan dioptimasi |
| `deletedIds` per bubble (O(N²)) | Sudah sekali-per-emission di kode (bukan per bubble) | **GUGUR** — dugaan keliru, tidak ada yang diperbaiki |
| Image auto-load burst | Sudah antrean `_maxImageFetches` di kode | **GUGUR** — sudah ada, tidak ada yang diperbaiki |

Wrapper `measure` dibiarkan di kode (no-op saat probe off) untuk QA berikutnya.
Bonus validasi: `PrivateChat=3` konsisten pasca-fix select (vs 50–67 sebelum).

### 12.9 Timeline scroll glitch — layout shift foto (2026-09-26)

Keluhan: scroll timeline tidak smooth, "glitch-glitch". Audit: bukan rebuild
(Timeline buildCount=3, sehat) dan bukan fetch ulang (thumb di-cache
`PostPhotoCache`, `gaplessPlayback` sudah on). Penyebabnya **layout shift**:
blok foto dirender `SizedBox.shrink()` sampai thumb tiba, lalu 0→penuh
tiba-tiba — tiap kartu berfoto mendorong konten di bawahnya tepat saat user
scroll. Foto tunggal paling parah (tinggi natural baru diketahui setelah
decode; multi sudah fixed 52+8+260 tapi juga shrink saat loading).

Fix (`post_card.dart`, client saja):
- Area foto dicadangkan sejak **path diketahui** (synchronous dari `_p`),
  bukan saat thumb tiba: kondisi tampil `_imagePaths().isNotEmpty`.
- Placeholder `primary 8%` setinggi layout final selagi thumb loading
  (tunggal 260 / multi 320) → **nol layout shift** saat foto masuk.
- Foto tunggal: tinggi TETAP 260 + `BoxFit.cover` (dulu natural). Trade-off
  disengaja: crop ala feed standar (IG/Threads) demi scroll stabil. Multi
  tidak berubah (sudah 260 + cover).
- Semua path gagal → `SizedBox.shrink` seperti dulu (bukan placeholder abadi).

Konstruksi menjamin nol shift (tinggi final == tinggi placeholder); verifikasi
rasa di HP menyusul. Aturan lanjutan: jangan kembalikan foto tunggal ke tinggi
natural tanpa placeholder ber-animasi, dan jangan tampilkan blok foto
berdasarkan `_imageThumbs` (async).

### 12.10 Dummy AI hilang dari daftar Online — timeout RPC 2s (2026-09-26)

Keluhan: dummy `agoy` online (RPC `get_online_users` mengembalikannya, teruji
via Management API: 7 baris, termasuk agoy `online`) tapi tidak muncul di tab
Pengguna Online; filter negara = Semua, gender = Semua, search kosong.

**Bukti logcat HP (rilis, 21:43–21:45):**
```
21:43:36 [ONLINE-EMIT] calling RPC get_online_users
   ← tidak ada "RPC done", tidak ada "slow path" (menggantung)
21:45:01 [ONLINE-EMIT] fallback 30s tick cachedEmpty=true
21:45:02 [ONLINE-EMIT] slow path n=7   (baru berhasil 85 detik kemudian)
```

**Root cause:** `getOnlineUsers()` memanggil RPC dengan `.timeout(2s)`. Di
jaringan blip (yang memang lazim di HP ini — §1h), RPC pertama tembus 2 dtk →
`catch(_){}` menelan error → `usedRpc=false` → jatuh ke fallback
`presence_for`, yang **hanya memuat user ber-socket realtime**. Dummy AI tidak
punya socket presence → hilang dari daftar walau `profiles.status='online'`.
Ini juga menjelaskan gejala "kadang muncul kadang ilang".

**Fix (`chat_service_presence.dart`, client saja):**
1. Timeout RPC `online.rpc` **2s → 6s** (konsisten dgn batas atas terukur
   21–665ms + margin cold-start).
2. RPC sukses-tapi-kosong tidak lagi ditandai gagal (memang sepi).
3. **RPC gagal + cache sudah berisi** (dari RPC sebelumnya) → **pertahankan
   cache**, JANGAN jatuh ke fallback `presence_for`. Emit dikembalikan; tick
   30s berikutnya memperbarui saat jaringan pulih. Ini menjaga user non-socket
   (dummy/AI) tetap tampil.

Aturan lanjutan: jangan turunkan kembali timeout RPC daftar online di bawah
6s, dan jangan biarkan fallback `presence_for` menimpa cache yang sudah berisi
user dari jalur RPC (fallback hanya untuk cold start tanpa cache).

---

## 13. Memori 864MB → 225MB: bitmap full-res (2026-09-26)

**Gejala:** awal cepat, lama-lama ngetik susah + buka halaman ngelag.
**Ukur HP (Xiaomi):** TOTAL PSS 864MB — Native Heap **500MB**, Dart 6MB.
Artinya ~500MB bitmap Skia: foto chat di-decode full-res (12MP ≈ 48MB/foto)
di semua bubble + viewer tanpa batas.

**Fix (client saja):**
- Bubble chat `cacheWidth: 720–1080` + `filterQuality.medium` (dulu full-res
  + high tiap frame saat scroll) — `private_chat_message.dart`.
- Viewer fullscreen (chat + timeline) evict bitmap saat ditutup.
- Dialog zoom (online/profil/user-info/admin) cap 1080 + evict.
- Carousel profil/galeri + ikon room + avatar admin: cacheWidth sesuai tampil.
- Cap komentar timeline 20 post; ImageCache global 200/100MB di `main.dart`.
- PhotoCache 20+8MB, PostPhoto 30MB, Avatar 100, Story thumbs 80, MessageCache
  30 chat — sudah bounded, tidak disentuh.

**Verifikasi HP:** fresh 256MB; scroll chat foto → **225MB (turun, tidak
tumbuh)**. `flutter test` 1251–1264 hijau. Aturan: jangan tampilkan
`Image.memory` tanpa `cacheWidth` di permukaan persisten; viewer/dialog
WAJIB evict saat tutup.

**Diagnosis lanjutan (build PERF_PROBE):** rebuild wajar (PrivateChat 63× =
event nyata + scroll test, bukan storm); RPC 120–600ms variasi jaringan;
tidak ada query patologis. Sisa lag = varians jaringan, bukan client.

---

## 14. Fase 5 — tutup celah bitmap + hygiene logout (2026-09-26)

Lanjutan §13: audit menemukan 4 titik `Image.memory` yang masih decode
full-res (melanggar aturan §13) + cache gambar tidak dibersihkan saat logout.

**Ditutup:**
- `private_chat_message.dart` viewer view-once inline (buka dari bubble):
  `cacheWidth: 1080` + evict saat route ditutup.
- `async_photo.dart` `AsyncPhotoViewer` (galeri profil + galeri user-info,
  swipe antar foto): `cacheWidth: 1080` + evict di `dispose()`.
- `post_card.dart` `_zoomAuthorPhoto` (dialog zoom avatar): `cacheWidth: 1080`
  + evict saat dialog ditutup.
- `create_room_sheet.dart` preview ikon room: `cacheWidth: 144`.

**Hygiene logout (`lib/core/media/image_cache_hygiene.dart`):**
- Satu titik `ImageCacheHygiene.clearAll()` → kosongkan Flutter `ImageCache`
  (`clear` + `clearLiveImages`) + semua cache aplikasi terdaftar.
- `decodedImageCache` (foto chat) mendaftar malas saat pertama diisi.
- Dipanggil di `AuthProvider.signOut()` dan setelah login Google — foto user
  lama tidak tinggal di RAM saat HP bergantian pemakai.
- Test `image_cache_hygiene_test.dart` (4): registry, idempoten,
  tahan-error, ImageCache bersih.

**Verifikasi HP:** fresh **238MB** (Native Heap 34MB) — konsisten dengan §13
(tidak ada regresi). `flutter analyze` 0/0, `flutter test` **1268 hijau**.

**Catatan:** `post_card.dart` sempat rusak (kurung `carouselPhoto` hilang,
sisa edit edge-to-edge foto) → build gagal walau analyzer lolos; diperbaiki
di sini. Pelajaran: **build rilis = gerbang nyata**, jangan percaya
`analyze` saja untuk perubahan struktur widget.

---

## 15. Instrumentasi RPC seragam + titik ukur (2026-09-26)

Sebelumnya hanya jalur **admin** terukur (`AdminService._rpc` wrapper);
64 RPC user tak terukur, plus `story_service` memakai konvensi ketiga
(`PerfProbe.timed` manual).

**Sekarang satu jalur:** `measuredRpc(sb, fn, {params, label})`
(`lib/core/perf/rpc_probe.dart`) —
- probe on → `PerfProbe.timed('rpc.<fn>')` (admin: `admin.<fn>`)
- probe off → nol overhead, perilaku identik

Dipakai di: AdminService, SocialService, PointsService, PrivateRoomService,
ChatService (gift/room/presence/chatlist via library induk).

**Cara ukur ulang:** build rilis `--dart-define=PERF_PROBE=true`, buka tiap
halaman, `adb logcat | grep '\[PERF\]'`. Titik ukur kini mencakup RPC user
(mis. `rpc.subscribe_creator`, `rpc.get_my_private_chats`) + admin
(`admin.list_devices`) sehingga biaya per-jalur bisa dibandingkan.

Pengecualian sah: jalur yang butuh `.timeout()` chaining tetap pakai
`PerfProbe.timed` langsung (mis. `story.tray`, `story.slides`).

---

## 16. Persistensi avatar — anti-kedip & kunci cache (2026-09-27)

**Keluhan:** di private chat, klik avatar → halaman profil "nge-blink"
(foto keload ulang) padahal foto sudah tampil di daftar/header chat. Minta
disimpan ke lokal seperti yang lain (biar sekali load, seterusnya instan).

### 16.1 Akar masalah — DUA kunci cache untuk gambar yang SAMA

`AvatarB64Service` dulu meng-cache dengan **dua key berbeda** tergantung jalur:

| Jalur | API | RAM key | DISK key |
|---|---|---|---|
| Daftar chat / header chat | `get(uid)` | `_cache[uid]` | `avatars/<uid>.jpg` |
| Halaman profil | `getByPath(path)` | `_pathCache[path]` | `<path>` (versioned) |

Padahal upload avatar menyimpan path **versioned**
(`avatars/<uid>_<millis>.jpg`, lihat `StoragePhotoService.avatarPathVersioned`),
sedangkan jalur uid memakai path **canonical** `avatars/<uid>.jpg`. Karena
key-nya beda, foto yang sudah ada di disk (dari daftar chat) **dianggap miss**
saat halaman profil membacanya lewat path → fetch network ulang → kedip.

### 16.2 Rumus persistensi (SATU kunci per user)

> **Avatar di-cache per `<uid>`. Path apapun (canonical / versioned) dipetakan
> ke uid yang sama, sehingga foto yang pernah dimuat di satu tempat instan di
> tempat lain.**

Aturan yang diterapkan di `lib/services/avatar_service.dart`:

1. **`uidFromAvatarPath(path)`** — `avatars/<uid>.jpg` dan
   `avatars/<uid>_<millis>.jpg` → `<uid>` (buang ekstensi lalu potong di `_`;
   uid adalah UUID, tidak mengandung `_`). Return `''` bila bukan avatar path.
2. **`getByPath(path)`** cek `_cache[uid]` DULU (bukan `_pathCache[path]`):
   hit → isi `_pathCache[path]` + `_uidPath[uid]` → **return instan**.
3. **Ram→disk→network** dipertahankan: `get(uid)` baca `readSync('avatars/<uid>.jpg')`
   (anti-blink cold start); `getByPath` jatuh ke `_downloadWithDisk` (RAM→disk→net).
4. **Tulis DUA key disk** saat download via path: `<path>` **dan** canonical
   `avatars/<uid>.jpg` → pemanggil by-uid berikutnya instan.
5. **Versi path dilacak** (`_uidPath[uid]`): kalau `getByPath` dipanggil dengan
   path versioned BARU (`!=` yang terakhir), cache lama dibuang (`clearForUid`)
   → foto baru tidak tertukar dengan lama, tapi foto sama tetap anti-kedip.
6. **Background refresh** per path (`_bgPathRefreshed` + `_refreshPathInBackground`
   → `_downloadNetwork`): server dicek di latar tanpa menahan UI (sama pola
   `get(uid)` → `_refreshInBackground`).
7. **Seed SINKRON di UI** (frame pertama, tanpa fase inisial→foto):
   - `AvatarB64Service.cachedSync(uid)` — RAM saja (murah; UI list, dipakai
     `ProfileAvatar.initState`).
   - `AvatarB64Service.cachedSyncIncludeDisk(uid)` — RAM lalu disk (dipakai
     `UserInfoScreen.initState` untuk cold start instan).
   - `cachedByPathSync(path)` — RAM/disk by path (via peta `_pathToUid`).
8. **Jangan hafal hasil kosong.** `''` (gagal sesaat/offline) TIDAK disimpan
   permanen → begitu online lagi foto muncul sendiri (pola sama tray story:
   null = gagal → pertahankan cache; hanya timpa saat ada data).

### 16.3 Titik yang DIUBAH

| File | Perubahan |
|---|---|
| `lib/services/avatar_service.dart` | `uidFromAvatarPath`, `_pathToUid`, `_uidPath`, `_bgPathRefreshed`, `cachedSync`/`cachedSyncIncludeDisk`/`cachedByPathSync`, `getByPath` cek uid dulu + refresh latar, `_downloadPath({uid, forceNetwork})`, `_downloadNetwork`, `clearForUid`/`clearForPath` bersihkan lintas-key |
| `lib/providers/avatar_provider.dart` | teruskan `cachedSync` / `cachedSyncIncludeDisk` / `cachedByPathSync` |
| `lib/providers/auth_provider.dart` | `cachedAvatarSync(uid)`, `cachedAvatarSyncDeep(uid)` |
| `lib/screens/user_info_screen.dart` | seed `_avatarB64` SINKRON di `initState` (RAM→disk) |
| `lib/widgets/profile_avatar.dart` | fast-path sinkron di `initState` (RAM saja; jaga list tetap murah) |

### 16.4 Aturan lanjutan (JANGAN dibalik)

- **Satu key per uid.** Semua jalur avatar (daftar, header, profil, timeline)
  WAJIB lewat `AvatarB64Service` agar berbagi RAM+disk. Jangan bikin cache
  lokal baru yang memakai key path mentah (`avatars/<uid>_...jpg`) — itu
  mengembalikan bug kedip.
- `getByPath` **selalu** cek `_cache[uid]` lebih dulu sebelum `_pathCache[path]`.
- Jangan simpan hasil `''` ke cache RAM/disk (avatar bisa "hilang" sampai restart).
- `cachedSync` (RAM) untuk list; `cachedSyncIncludeDisk` (baca file) HANYA untuk
  halaman tunggal — baca file per-item di list panjang = jank frame pertama.

Test: `test/avatar_service_test.dart` (14) — termasuk
`uidFromAvatarPath` (canonical & versioned → uid sama),
`getByPath memakai cache uid — tanpa fetch ulang (anti-kedip)`,
dan `getByPath mengisi cache uid supaya get(uid) instan`.

---

## 17. Admin monitor chat — persistent, tak load ulang dari server (2026-09-27)

**Keluhan:** di admin panel → monitor chat, saat chat dibuka terasa "ngeload
lagi" (pesan lama di-fetch ulang dari server) padahal sudah ada di lokal.
Minta: kalau sudah pernah dibuka → pakai lokal saja, **kecuali pesan baru**.

### 17.1 Akar masalah

`AdminChatViewScreen._fetch()` memang menampilkan cache lokal dulu (memori →
SQLite), TAPI **selalu** memanggil `admin.fetchChatMessages(chatId)`
(RPC `offset:0`) di akhir — jadi tiap buka layar = 1 round-trip server untuk
data yang sudah ada. Bila jaringan lambat → terasa load ulang.

### 17.2 Rumus persistensi (lokal-first, server hanya kalau perlu)

> **Kalau pesan chat sudah ada di cache (RAM sesi ini / SQLite sesi sebelumnya),
> JANGAN fetch server saat buka. Pesan BARU datang dari poll 5 dtk + realtime.
> Server hanya dipanggil saat cache kosong atau dipaksa (pull-to-refresh).**

1. `AdminChatsMx.fetchChatMessages(chatId, {bool force = false})` — early
   return (tanpa RPC) bila `_chatMessages.isNotEmpty && !force`. `force:true`
   memaksa load ulang (dipakai pull-to-refresh).
2. `AdminChatViewScreen._fetch({bool force = false})` — setelah memuat
   memori/SQLite, bila `_msgs.isNotEmpty && !force` → **return**, cukup
   `_hasMore` + `_refreshRead()`. Pull-to-refresh → `_fetch(force: true)`.
3. **Pesan baru** tetap masuk lewat: `_pollTimer` 5 dtk → `refreshChatMessages`
   (merge: hanya menyisipkan id yang belum ada) + realtime `private_messages`
   (insert/update/delete, terfilter `chat_id`) → `_poll()`.

### 17.3 Titik yang DIUBAH

| File | Perubahan |
|---|---|
| `lib/providers/admin/admin_chats.dart` | `fetchChatMessages({force})` — skip RPC bila cache lokal terisi & tak dipaksa (pertahankan pagination & cache disk) |
| `lib/screens/admin_chat_view_screen.dart` | `_fetch({force})` skip server bila `_msgs` sudah ada; `RefreshIndicator.onRefresh` → `_fetch(force: true)` |

### 17.4 Aturan lanjutan (JANGAN dibalik)

- `_fetch()` TANPA `force` **tidak boleh** menembak server kalau sudah ada pesan
  lokal — inilah yang menjaga buka-ulang tetap instan.
- Jalur "pesan baru" WAJIB tetap via poll + realtime (`refreshChatMessages`
  merge by id, bukan replace) — jangan hapus, kalau tidak chat tak update live.
- Aksi yang MEMANG butuh server tetap `force:true` (pull-to-refresh, hapus chat).
- `fetchMoreChatMessages` (paginasi scroll ke atas) tak terpengaruh — tetap
  RPC karena memang memuat pesan lama yang belum ada di cache.

### 17.5 Hemat poll + cache per-chat (2026-09-28)

Keluhan lanjutan: buka chat masih terasa load (poll 5 dtk menembak 40 pesan +
last-read + active-calls + foto tiap buka), buka-tutup-buka chat lain memuat
ulang, dan daftar di belakang layar rebuild tiap poll.

- `refreshChatMessages(chatId, {limit})` - poll kirim `limit: 15` (cukup untuk
  pesan baru); halaman penuh hanya untuk refresh manual. Diam (tanpa notify)
  bila tak ada id baru + abaikan hasil basi saat sudah pindah chat.
- `_fetch`/`_poll` view: `_refreshRead()` (last-read) hanya tiap poll ke-3
  (~15 dtk); guard `_polling` cegah poll tumpuk saat RPC lambat.
- Provider: mem-cache per-chat `_chatMsgMem` (LRU 20) - A->B->A tanpa baca
  disk ulang; dihapus saat chat dihapus.
- `fetchActiveCalls`: skip `notifyListeners` bila sidik id+status+chat sama -
  daftar monitor tidak rebuild tiap 5-10 dtk.
- Timeout foto monitor 30 dtk -> 15 dtk (gagal-cepat, retry via tap).
- Prefetch saat tap kartu (`preloadMessages`) selagi animasi transisi jalan.
- 2026-09-29 (pesan terhapus): merge poll kini TIMPA baris dikenal yang
  berubah (`mergeAdminChatMessages`, sidik id+isi+tipe+hapus+edit) — dulu
  hanya sisip id baru + banding layar cuma id+teks, sehingga pesan yang
  dihapus terjebak tampil konten lama selamanya. Diam bila identik
  (imageData dikecualikan supaya thumb tak terhapus tiap poll); layar simpan
  cache saat berubah. Test: `test/admin_chat_merge_test.dart`.

### 17.6 Sisi bubble dikunci stabil (2026-09-28)

Gejala "kadang semua pesan pindah ke kanan": `_applyMessages` menimpa
`_leftUid` tiap poll dengan hasil hitung-ulang yang bisa null/kosong
(senderId kosong ikut dihitung). Rumus: `_leftUid` hanya diisi bila masih
kosong (tidak pernah ditimpa); `computeMonitorLeftUid` mengabaikan string
kosong di participantOrder/chatId/senders. Test:
`test/admin_chat_back_button_test.dart` (grup computeMonitorLeftUid).

---

## 18. Guard anti double-push kartu monitor chat (2026-09-28)

**Keluhan:** buka chat "Anggi & Jaky" -> panah back (kiri atas) ditekan tidak
ada reaksi (scroll jalan = bukan freeze).

**Akar:** tap 2x cepat saat transisi push belum selesai (frame pertama berat
di chat foto) menumpuk 2 route chat identik. 1x back hanya menutup route
atas -> layar terlihat sama -> "back mati". Widget test membuktikan back
pop normal saat hanya 1 route.

**Rumus:** `tryClaimChatPush(chatId)` (di `admin_chat_view_screen.dart`) -
tap kedua dalam 2 dtk untuk chat yang sama ditolak; klaim dilepas
(`releaseChatPush`) saat route di-pop. Jendela 2 dtk + lepas-saat-pop
artinya buka-ulang setelah back tetap langsung bisa. Dipakai di 2 pintu
masuk: kartu daftar monitor + kartu chat di lembar detail user.

**Aturan (JANGAN dibalik):** setiap `Navigator.push` ke `AdminChatViewScreen`
WAJIB lewat guard ini + `.then((_) => releaseChatPush(id))`. Test:
`test/admin_chat_back_button_test.dart` (back pop + 4 kasus guard).

---

## 19. Monitor chat — buka instan + sisi bubble tak pernah flip (2026-09-28)

**Keluhan 1:** klik chat di monitor admin lama tampil pesannya, tidak secepat
private chat.

**Akar:** kartu tap hanya memanaskan cache STREAM user
(`MessageCache.preloadMessages('private_<chatId>')`) — padahal monitor
membaca provider `_chatMsgMem` / disk `admin_chatmsg_<chatId>`. Jadi cache
yang dipanaskan tak terpakai; buka layar selalu menunggu SQLite → server.

**Rumus (instan):** provider `prefetchChatMessages(chatId)` dipanggil saat tap
— baca disk `admin_chatmsg_<id>` (lalu server hanya bila disk kosong) ke
`_chatMsgMem`. Layar `_fetch()` membaca `admin.peekChatMessages()` SINKRON di
langkah 0 sehingga frame pertama langsung terisi. Dedupe in-flight per chatId.

**Keluhan 2 (belum ter-resolve sebelumnya):** pesan kadang pindah ke sebelah
kanan SEMUA.

**Akar:** `isMe = senderId != _leftUid`. `_leftUid` dulu diambil dari
`participantOrder.first`, yang di list dibangun dari urutan key
`participant_names` (JSONB). Urutan key JSONB berubah saat nickname
di-rename / beda antara snapshot cache & fetch baru → `order.first` flip →
semua bubble lawan jadi "kanan".

**Rumus (anti-flip):** `computeMonitorLeftUid` kini memakai **chatId
`uid1_uid2` sebagai jangkar utama** (uid SORTED → abadi), baru participantOrder
cadangan. List + lembar detail user memakai `stableChatParticipantOrder` untuk
membangun urutan judul/avatar dari chatId juga, jadi label, avatar header, dan
sisi bubble selalu konsisten.

**Aturan (JANGAN dibalik):** jangan kembalikan participantOrder sebagai
prioritas `computeMonitorLeftUid`, dan jangan bangun `orderUids` dari urutan
key map. Test: `test/admin_chat_leftuid_test.dart` (urutan chatId menang +
`stableChatParticipantOrder`).

**Keluhan 3 (2026-09-28):** di monitor, chat tisubasah & novikoh tampil
"pesannya ke kanan semua" DAN "ada pesan orang kecampur ke situ".

**Akar:** `AdminProvider` menyimpan pesan di SATU buffer global
(`_chatMessages`) + satu flag `_chatMessagesHasMore`. Setiap
`AdminChatViewScreen` membaca `admin.chatMessages` (buffer bersama) di
`_applyMessages()` + `_poll`/`_onScroll`. Saat DUA layar monitor hidup
(mis. buka dari list lalu dari lembar detail user), layar atas menulis buffer
→ layar bawah (5 dtk poll) meng-apply pesan CHAT LAIN: pengirimnya bukan
`_leftUid` → semua bubble pindah ke kanan; pesan orang lain ikut tampil.
SQLite/KV sendiri SUDAH per-chat (`admin_chatmsg_<id>` + `messages.chat_key`)
— jadi bukan masalah penyimpanan, tapi buffer memori provider.

**Rumus (per-chat):** hapus `_chatMessages`/`_chatCurrentFor` global. Semua
operasi memakai map per-chat `_chatMsgMem` (sumber tunggal): tambah
`chatMessagesFor(chatId)` + `chatMessagesHasMoreFor(chatId)`; `fetchChatMessages`
/`fetchMoreChatMessages`/`refreshChatMessages` membaca-menulis per chatId.
`_applyRawMessages` di layar kini **MERGE by id** (union urut timestamp), bukan
replace — poll 15 pesan tak lagi memangkas riwayat hasil scroll.

**Aturan (JANGAN dibalik):** jangan tambahkan kembali buffer pesan bersama di
provider; layar WAJIB pakai `chatMessagesFor(chatId)`. Test:
`test/admin_provider_di_test.dart` grup "pesan monitor per-chat".

---

## 20. Stabilitas pg_cron — konsolidasi job per-menit (2026-09-28)

**Keluhan:** monitor admin / app "muter-muter" & sering gagal load; log
`[RT-RESILIENT] ... Too many database timeouts`, RPC `get_online_users`
timeout 6s, warmup 8s, timeline 10s.

**Akar (terukur live):** bukan bug UI. Instance **Micro**
(`max_worker_processes = 6`) dipakai bersama autovacuum (3), realtime
(2 walsender), pg_net, pg_cron launcher. Ada **5 job `* * * * *` terpisah**
+ 4 job `*/5` yang menabrak di menit kelipatan 5. Tiap job pg_cron butuh
1 worker → kehabisan → `job startup timeout`.

Bukti: `cron.job_run_details` 414/8956 run gagal (4.6%) dalam 24 jam; menit
:15 pernah **11 job gagal serentak**. p50 durasi 0.03s (instan) tapi max
**418s** — pola global stall, bukan job individu lambat.

**Rumus:**

> **Jumlah job pg_cron per-menit harus < sisa worker setelah autovacuum +
> realtime. Gabungkan housekeeping sejenis jadi SATU job wrapper, dan sebar
> job berkala ke menit berbeda.**

Perubahan (migration `20260928200000_stagger_cron_schedules.sql`):
1. `housekeeping_tick()` — wrapper memanggil `presence_idle_tick()`,
   `room_voice_sweep()`, + 2 DELETE cleanup room berurutan.
2. Job `chatyuk-housekeeping` (`* * * * *`) menggantikan 4 job per-menit.
3. `chatyuk-outbox-worker` → `*/2`; job `*/5` disebar (`1-59/5` dst).
4. `chatyuk-call-sweep` tidak diubah (dikunci `call_test.sql`).

**Hasil:** maks 5 job/menit (dulu 10–11), **0 gagal**.

**Aturan (JANGAN dibalik):**
- **JANGAN** menambah job `* * * * *` baru tanpa menggabung ke
  `housekeeping_tick()`. Instance Micro hanya punya 6 worker.
- **JANGAN** pakai format 6-field (detik) di `cron.schedule` — pg_cron
  instance ini tidak mendukung; job berhenti tanpa error.
- `chatyuk-call-sweep` WAJIB tetap `*/5 * * * *` (kontrak `call_test.sql`).
- Migrasi/ubah jadwal cron: jalankan `scripts/run_sql_tests.sh`
  (`ai_test`, `call_test`, `outbox_notif_test`) — minus jadwalnya bikin FAIL.

---

## 21. Admin watch call — audio tak lagi putus-nyambung (2026-09-28)

**Keluhan:** saat admin memantau (monitor chat) sebuah call, suara "sempat ada,
sempat hilang, muncul lagi" — terutama di voice call.

**Akar (terbukti dari `call_signals`):** koneksi watch dibangun ULANG terus.
Untuk satu call audio 9 detik: **5 `watch_request` + 3 `watch_offer` +
3 `watch_answer` + 12 `watch_candidate`**. Tiap rebuild menutup pc lama →
audio peserta putus sesaat.

Penyebabnya 2:
1. `CallSession._handleWatchRequest` (`call_service.dart`) — throttle 8 dtk
   hanya mencegah, tapi setelah ≥8 dtk pc lama **ditutup & dibuat ulang**,
   walau pc itu masih sehat.
2. `WatchSession` (`admin_call_watch_service.dart`) — timer `watch_request`
   3 dtk tidak berhenti saat peserta sudah terhubung; `p.connected` di-set
   benar tapi `_requestAll` tetap menembak & memicu rebuild.

**Rumus (kebijakan di `lib/core/call/watch_policy.dart`, terkunci test):**

> **Peserta: kalau pc watch untuk watcher itu MASIH SEHAT, JANGAN
> tutup-buat-ulang — cukup kirim `watch_state`. Admin: berhenti minta
> `watch_request` begitu tersambung, dan tahan saat sedang handshake.**

- `decideWatchReply()` → `sendState` bila pc sehat, `rebuildOffer` hanya bila
  pc belum ada / failed / closed / **basi (>20 dtk belum connect)**.
- `shouldRequestWatch()` → tidak minta bila `connected` atau `negotiating`
  (offer masuk < 8 dtk).
- `_watchPcCreatedAt` + `_watchPcStale` (20 dtk) mencegah deadlock bila offer
  hilang & ICE nyangkut di `connecting` (tetap boleh rebuild sekali).

**Aturan (JANGAN dibalik):**
- Jangan kembalikan "tutup pc tiap watch_request" — itu penyebab audio putus.
- `watch_state` bukan pengganti negosiasi: hanya dipakai saat pc sudah ada.
- Test: `test/watch_policy_test.dart`.

---

## 22. Stall admin 2026-09-29 — akar: compute NANO (RAM 0.5 GB), bukan beban

**Keluhan:** panel admin "mati" (RPC timeout, `statement_timeout` 57014,
`realtime.list_changes` 14 s, `ShareLock` menunggu 3.7 s). DB lambat sekaligus
(`select 1` 11–15 s).

**Diagnosa (ukur `EXPLAIN`, `pg_stat_*`, metrics):**

| Ukur | Nilai | Arti |
|---|---|---|
| `node_memory_MemTotal_bytes` | **406 MB** | instance **Nano** (0.5 GB) |
| Dashboard Infrastructure | MEMORY **89%**, CPU **89%** | memory pressure |
| I/O terpakai kita | **91 KB/s = 0,81%** baseline | **BUKAN** beban tinggi |
| Checkpoint | 1432 s untuk 16.364 buffer | disk tersendat (karena mem pressure) |

**Kesimpulan: bukan Query/RLS/kode.** Nano terlalu kecil: ~45 MB RAM sisa →
checkpoint & WAL tersendat → statement timeout → admin "mati".

**Perbaikan GRATIS (harga Nano == Micro, dashboard menandai "Free Upgrade"):**
`PATCH /v1/projects/{ref}/billing/addons {compute_instance: ci_micro}`:

| | Nano | Micro |
|---|---|---|
| RAM | 0,5 GB | 1 GB |
| Baseline I/O | 11 MB/s | **87 MB/s** |
| Max I/O | 261 MB/s | 2085 MB/s |
| Harga | $0.01344/jam | **$0.01344/jam (sama)** |

Hasil: `select 1` **0.7–2.3 s** (dari 11–15 s), REST 0,36 s, cron 0 gagal.

**Aturan (JANGAN dibalik):**
- **Cek compute lebih dulu** sebelum menuduh beban DB. Nano (0,5 GB) TIDAK
  layak produksi; **WAJIB minimal Micro (1 GB)** — harganya sama untuk org Pro,
  jadi tidak ada alasan tetap di Nano.
- Metric `MEMORY` > 85% + I/O %consumed rendah = **naikkan compute**, bukan
  optimasi query.

**Perbaikan pendamping (mengurangi volume tulis, tetap berguna):**
migrasi `20260929020000_reduce_presence_write_load.sql`:
- `notify_online_fanout` diubah **AFTER → BEFORE UPDATE** sehingga set
  `new.last_online_notified_at` langsung — menghapus `UPDATE profiles` NESTED
  di dalam trigger (dulu satu transisi status = 2× tulis + 9 trigger ulang).
- Kedua trigger online **mengecualikan akun dummy** (14 bot dulu ikut fanout
  tiap `ai_presence_tick` → `net.http_post` + outbox spam; 94 chat dummy).
- `housekeeping_tick` memangkas `cron.job_run_details` > 7 hari (44 MB / 137k
  baris tumbuh tanpa batas).

---

## 23. Regresi bitmap full-res di list Online + trim saat background (2026-10-02)

**Gejala (laporan user):** "aplikasi serasa ngelag saat pindah antar tab."

**Ukur HP (Xiaomi 24129PN74G, RAM 11 GB, swap 12 GB) via `adb` wireless:**

| Momen | VmRSS | Native Heap Alloc | Swap |
|---|---|---|---|
| Idle (app background) | ~298 MB | ~32 MB | ~250 MB |
| Begitu interaksi / pindah tab | **~765 MB** (spike ≤1,5 dtk) | ~490 MB | ~240 MB |

Kedua build (user **dan** admin) menunjukkan pola sama → **bukan** bug khas
satu fitur, tapi bitmap. Memory turun lagi saat idle (bukan leak permanen),
tapi spike ratusan MB saat membuka tab = GC berat + paging ke swap = lag.

**Akar:** melanggar aturan §13 ("jangan `Image.memory` tanpa `cacheWidth`").
`lib/screens/online_users_screen.dart` — `_AsyncAvatar` menyimpan
`MemoryImage(bytes)` **tanpa cap**: avatar di list hanya **40px fisik**, tapi
bitmap di-decode **full-res** (JPEG 1080px ≈ 4,6 MB/bitmap). 20 kartu = ~92 MB.
4 titik: `_avatarImageByUid` (3× `putIfAbsent`) + `CircleAvatar.backgroundImage`.

**Fix (client saja):**
- `_cappedAvatarImage()` → bungkus `ResizeImage(MemoryImage(b), width: 96)`;
  avatar list render ≤96px (cukup untuk 40px @2-3× DPI), ~25× lebih kecil.
- `_avatarImageByUid` berubah tipe `Map<String, MemoryImage>` →
  `Map<String, ImageProvider>` (provider stabil per-uid tetap → anti-kedip).
- `_avatarMapCap` 200 → **120** (bytes mentah disimpan untuk zoom).
- `imageCache` global `main.dart` 120/64MB → **80/48MB** (prioritas ringan;
  foto di-decode ulang dari disk cache saat scroll — murah).
- **Trim saat background:** `_MainNav.didChangeAppLifecycleState(paused)` →
  `imageCache.clear() + clearLiveImages()`. OS gencar menuntut RAM app
  background; bitmap di-hold percuma (layar tak terlihat). Resume → decode
  ulang dari disk.

**Aturan turunan (JANGAN dibalik):** lihat
[`docs/MEMORY_BEST_PRACTICES.md`](MEMORY_BEST_PRACTICES.md) — ringkasan
aturan memory untuk kontributor berikutnya.

**Test:** `flutter test` (image_cache_hygiene, image_cap_widgets,
online_users_provider, online_visibility) hijau.

---

## 24. Audit menyeluruh `Image.memory`/`MemoryImage` — user + admin (2026-10-02)

Lanjutan §23: audit SEMUA titik render gambar di app (23 file) untuk pola
"decode tanpa cap" yang sama. Hasil: **hampir semua sudah benar** (aturan §13
sudah tertanam) — **admin panel bersih total**; app user tinggal 1 titik.

**Titik yang diperbaiki:** `story_viewer_screen.dart` — halaman **tetangga**
(neighbor person, di-preload untuk transisi swipe mulus) render
`Image.memory(bytes)` **tanpa `cacheWidth`**. Kareni ini slide story (bisa
~5MB full-res) yang hanya tampil SEBAGIAN & tidak di-zoom → dibor untuk
decode penuh tiap tetangga. Fix: `cacheWidth: 720`.

**Hasil audit (semua ✅ kecuali 1 di atas):**

| Area | Titik | Cap |
|---|---|---|
| online_users avatar/zoom | 5 | 96 / 1080 |
| user_info carousel/zoom | 3 | 720 / 1080 |
| profile zoom | 1 | 1080 |
| private_chat bubble/thumb/zoom | 6 | 720-1600 + evict |
| post_card feed/avatar/zoom | 4 | 1080 / size×2 |
| post_photo_viewer | 2 | 128 / 1600 |
| async_photo thumb/viewer | 1 | 256 + ResizeImage |
| group_media grid | 1 | 256 |
| story composer/picker | 2 | 1080 / 300 |
| chat composer/video poster | 3 | 450 / 400 |
| room_icon / create_room_sheet | 2 | size×3 / 144 |
| leaderboard screen/sheet | 2 | ResizeImage 72 / 1080 |
| nearby_card / profile_avatar / story_viewer_avatar | 3 | ResizeImage |
| **admin** `avatar_circle` (list/zoom) | 2 | 96 / 1080 + evict |

**Aturan penegasan (lihat `MEMORY_BEST_PRACTICES.md`):** setiap `Image.memory`
WAJIB `cacheWidth` — termasuk **render yang cuma tampil sebagian** (neighbor /
preview). Kalau ragu: cap = `lebar_px_tampil × 2`, lalu evict bila full-screen.

**Test:** `flutter test` story (preload_window, slides_cache, viewer_model,
viewer_avatar) hijau.

---

## 25. METODE: Profiling jank tanpa DevTools UI via VM Service (2026-10-03)

Resep mengukur **jank transisi** (mis. "buka/tutup layar terasa telat") di HP
kerja tanpa buka DevTools UI. Terbukti mem-buktikan penyebab 853ms → 8.5ms
(§26). Semua dijalankan dari Mac memakai `adb` + `dart` (bundel Flutter SDK).

### Saat pakai metode ini
- Keluhan "X terasa ngelag / telat" yang **bukan** spike memori (cek dulu
  `dumpsys meminfo`, §1h & §23 — kalau memory flat, ini jank transisi).
- Ingin **angka** (durasi event per-frame), bukan tebakan urutan kode.

### Langkah

**1. Build PROFILE (bukan debug/release) + PERF_PROBE.**
`dlog`/`PerfProbe` aktif di profile, dan build profile di-sign keystore
release (lihat `android/app/build.gradle.kts` buildType `profile`) sehingga
menimpa install rilis tanpa uninstall:

```bash
flutter build apk --profile --flavor apkpureProd --dart-define=PERF_PROBE=true
adb install -r build/app/outputs/flutter-apk/app-apkpureprod-profile.apk
```

**2. Ambil URL VM Service + forward + serve DevTools/DDS.**
DevTools **sudah bundling** di Flutter SDK — tak perlu `pub global activate`
(paket `devtools` di pub.dev di-takedown; `dart devtools` dari SDK ini yang benar).

```bash
# URL muncul di logcat saat app start:
adb logcat -c; adb shell monkey -p com.chatyuk.chatyuk -c android.intent.category.LAUNCHER 1
URL=$(adb logcat -d | grep -o 'http://127.0.0.1:[0-9]*/[A-Za-z0-9_=+-]*/' | tail -1)
PORT=$(echo $URL | sed -E 's|.*:([0-9]+)/.*|\1|')
TOK=$(echo $URL  | sed -E 's|.*:[0-9]+/(.*)|\1|')
adb forward tcp:$PORT tcp:$PORT
# DART = $(dirname $(dirname $(which flutter)))/bin/cache/dart-sdk/bin/dart
$DART devtools --no-launch-browser --port=9100 "http://127.0.0.1:$PORT/$TOK"
# → cetak "DDS at ws://127.0.0.1:<DDS_PORT>/<DDS_TOK>=/ws" — pakai ws itu.
```

> Jangan lewatkan `http://` ke skrip probe; `dart devtools` menolak skema `ws`.
> URL harus diakhiri `/` (token diakhiri `=`).

**3. Skrip probe (paket `vm_service`).** Set timeline flagnya, tunggu, ambil,
lalu **pasangkan event `ph:B`↔`ph:E`** per thread (B sangat nested → pakai
STACK, bukan sepasang sekali). Field harus dibaca dari `e.json` (TIDAK ada
getter `.name/.dur/.ts` di `TimelineEvent` vm_service).

```dart
// pubspec: vm_service, web_socket_channel
final s = await vmServiceConnectUri('ws://127.0.0.1:PORT/TOK=/ws');
await s.setVMTimelineFlags(['Dart','GC','Compiler','Embedder','API']);
await Future.delayed(Duration(seconds: 12));      // user lakukan aksi di HP
final tl = await s.getVMTimeline();
dynamic g(TimelineEvent e, String k) => e.json?[k];   // name/ph/ts/tid/args
// stack B/E per '${pid}.${tid}' → dur = ts(E) - ts(B)  → sort desc
```

**4. Baca hasilnya — fokus thread `2.ui`.**
Event `Dart_HandleMessage` / `Dart_InvokeClosure` / `BUILD` yang **> 16ms**
di thread `2.ui` = kerja sinkron yang memblokir frame transisi. Contoh §26:
satu `Dart_HandleMessage` **853ms** = biang "back lambat".

### Batasan yang ketemu
- **CPU sampling profiler TIDAK jalan** di app yang sudah start tanpa
  `--profiler`. `getCpuSamples` → "Feature is disabled". Timeline trace
  cukup untuk menunjuk **durasi**; untuk tahu **fungsi**-nya, tambahkan
  `PerfProbe.measure`/`timed` (aktif dgn `--dart-define=PERF_PROBE=true`)
  di kandidat lalu baca logcat `[PERF]`.
- `gfxinfo` sering "Total frames: 0" untuk Flutter release (SurfaceView) —
  pakai trace VM service, bukan gfxinfo.
- Logcat ber-noise (BLE/scan proses lain) → filter ke PID app.

### Skrip probe tersimpan
`/var/folders/.../opencode/vmprobe/{pair.dart,cpu.dart,probe.dart}` (Mac local,
sekali pakai). Bila script permanent mau di-commit: taruh di `tool/perf/`.

---

## 26. Jank "back lambat" private chat — select presence berlebih (2026-10-03)

**Gejala (user):** "pas nutup private chat ada lag telat" & "buka Top Aktif
nutupnya ngelag". Buka chat sudah mulus setelah fix §27-ish (tunda kerja).

**Ukur (metode §25):**
```
853.08 ms | 2.ui | DartIsolate::HandleMessage   ← SATU pesan blokir UI thread
853.07 ms | 2.ui | Dart_HandleMessage
580.83 ms | 2.ui | Dart_InvokeClosure
```
Satu operasi sinkron **853ms** di UI thread tepat saat buka/tutup chat =
"back lambat bereaksi". Bukan memory (heap flat ±30-45MB sepanjang sesi).

**Akar:** `lib/screens/private_chats_screen.dart` (daftar chat di belakang,
hidup di `IndexedStack`) memakai:
```dart
final onlineUsers = context.select<OnlineUsersProvider, List<UserModel>>(
  (o) => o.users,          // SELURUH list online (bisa puluhan user)
);
```
`OnlineUsersProvider` emit tiap **event presence** (heartbeat ~30s, user
online/offline). Karena selector mengembalikan **seluruh list**, IDENTITY
list berubah tiap emit → **seluruh `PrivateChatsScreen` (AppBar + daftar 10
chat + thumbnail avatar) rebuild penuh**, sering menabrak frame transisi
push/pop chat → jank.

**Fix:** `select` hanya **status/nama uid yang benar-benar ada di daftar
chat** (Map kecil), bukan seluruh list:
```dart
final chatOtherUids = _lastChats.map((c) => c.participants.firstWhere(
  (p) => p != auth.uid, orElse: () => '')).where((u) => u.isNotEmpty).toSet();
final onlineRelevant = context.select<OnlineUsersProvider,
    ({Map<String,String> status, Map<String,String> name})>((o) {
  final st = <String,String>{}; final nm = <String,String>{};
  for (final u in o.users) {
    if (!chatOtherUids.contains(u.uid)) continue;
    st[u.uid] = u.status; if (u.nickname.isNotEmpty) nm[u.uid] = u.nickname;
  }
  return (status: st, name: nm);
});
final statusMap = onlineRelevant.status;   // dipakai seperti sebelumnya
final liveNameMap = onlineRelevant.name;
```
Presence user di luar daftar chat **tidak lagi** memicu rebuild daftar chat.

**Hasil terukur (trace ulang, §25):**

| | Sebelum | Sesudah |
|---|---|---|
| Event UI terpanjang | **853.1 ms** | **8.5 ms** |
| `Dart_InvokeClosure` max | 580.8 ms | 8.4 ms |
| Kesimpulan | blokir frame transisi | **semua frame < 14ms** ✅ |

**Aturan turunan:** **halaman penuh / daftar panjang JANGAN `watch`/`select`
seluruh list provider yang sering emit** (presence, heartbeat, points).
Turunkan selector ke **turunan terkecil** yang benar-benar dipakai render
(mis. Map uid→status untuk **uid relevan saja**).

**Test:** `flutter test` (chat_search, chat_base_di, private_initial_deleted,
photo_bubble_persistence) hijau.

### 26b. Profil — `watch<AuthProvider>` penuh (fix, 2026-10-03)

Pola sama di `lib/screens/profile_screen.dart`: `build()` memakai
`context.watch<AuthProvider>()` → SELURUH halaman (CustomScrollView + slivers
+ galeri) rebuild tiap `notifyListeners` AuthProvider, termasuk **heartbeat
presence** berkala. Kontradiksi dgn komentar §2.3 di file yang sama
(PointsProvider sudah `select` per field, AuthProvider masih `watch` penuh).

**Fix:** `select` SNAPSHOT field yang dipakai render (record Dart, banding
via equality):
```dart
final (:profile, :uid, :isAnonymous, :signingOut, :dummySessionActive,
       :emailConfirmed, :userEmail) =
  context.select<AuthProvider, ({UserModel? profile, String? uid, bool isAnonymous,
    bool signingOut, bool dummySessionActive, bool emailConfirmed, String? userEmail})>(
    (a) => (profile: a.profile, uid: a.uid, isAnonymous: a.isAnonymous,
      signingOut: a.signingOut, dummySessionActive: a.dummySessionActive,
      emailConfirmed: a.emailConfirmed, userEmail: a.userEmail));
```
Notify yang tidak mengubah field ini tak lagi me-rebuild halaman.

### 26c. Verifikasi Timeline & Profil pasca-fix (2026-10-03, metode §25)

Trace 14 dtk pindah-pindah tab Timeline/Profil → event UI terpanjang **7ms**
(`NotifyIdle`/GC). Laporan sesi terakhir (`PERF_PROBE`, tekan HOME):

```
frames=4000  build[p50=1.1 p90=1.5 max=10.5ms]  raster[p50=1.9 p90=2.1 max=7.3ms]
janky(build)=0  janky(raster)=0
build Profile=16  Online=15  Timeline=11  MainNav=9  ChatList=5
```

**0 jank** (build & raster max < 16ms). `ChatList=5` (dulu 6) menandakan fix
§26 menekan rebuild daftar. Timeline sudah `select` granular sejak awal
(`postsRaw/hasMore/loading/fetchFailed`) — sehat, tak perlu perubahan.

### 26d. Lazy-load foto post + cacheExtent Timeline (2026-10-03)

**Gejala (user):** "buka Timeline loadnya lebih berat dari chat".

**Akar:** `PostCard.initState` langsung `_loadImages(paths)` → SETIAP kartu
yang ter-build (termasuk yang masih di `cacheExtent` default 250px, belum
terlihat) langsung unduh + decode fotonya. Buka Timeline = puluhan foto
diunduh+decode sekaligus. Bedanya dgn chat: daftar chat hanya metadata
(nama/unread) + ~10 avatar; feed punya foto per post (jauh lebih berat).

**Fix:**
- `PostCard.initState`: `_loadImages` dipindah ke `addPostFrameCallback`
  (frame pertama murni layout — tidak menembak IO/decode).
- `timeline_screen.dart` `ListView.builder`: `cacheExtent: 100` (dulu default
  250) → lebih sedikit kartu ter-build di luar viewport.

**Verifikasi (trace §25):** buka Timeline → event UI terpanjang **7.25ms**
(`NotifyIdle`/GC), tak ada spike. Menu **Online → private chat** → terpanjang
**13.6ms** (di bawah 16ms = 60fps); jank yg dulu terasa teratasi oleh fix §26.

> Catatan beda Timeline vs Chat: Timeline **tak** punya swipe (post pakai
> tombol aksi; swipe bentrok scroll vertikal + carousel foto horizontal).
> Daftar chat/pesan punya `Dismissible`/`onHorizontalDrag` utk aksi cepat.

### 26e. "Balik dari chat, list Online susah diklik" — overlay bubble unread nyangkut (2026-10-03)

**Gejala (user):** balik dari private chat ke menu Online → kartu user "ga
sensitif / susah diklik" (tap tak nyahut), makin parah makin sering dibuka.

**Akar:** di `online_users_screen.dart`, tap kartu user yang PUNYA unread
memunculkan bubble preview via `OverlayEntry` (`_showUnreadBubble`). Bubble
itu punya lapisan **`Positioned.fill` transparan** (penangkap tap-dismiss).
Overlay hanya dihapus lewat **timer 4 dtk** + cek `entry.mounted`:

```dart
Future.delayed(const Duration(seconds: 4), () {
  try { if (entry.mounted) entry.remove(); } catch (_) {}
});
```

Skenario gagal: tap kartu ber-unread → bubble muncul → user LANGSUNG tap lagi
buka chat (< 4 dtk) → overlay belum ter-remove (timer belum jalan / `mounted`
false saat di-unmount) → balik ke Online → **lapisan transparan menelan semua
tap** → "list susah diklik".

**Fix:** simpan referensi `_unreadBubbleEntry` + helper `_dismissUnreadBubble()`;
paksa-remove saat (a) `_startChat` (navigasi), (b) `dispose`; remove entry lama
sebelum insert baru. Tidak lagi bergantung timer saja.

**Verifikasi (trace §25):** klik dari menu Online → chat berulang, event UI
terpanjang **6.78ms** (sehat, tak ada blokir). Fix `build Online` (§26, 170→3
rebuild) + overlay cleanup ini menuntaskan keluhan "klik dari Online berat /
susah diklik".

**Aturan turunan:** setiap `OverlayEntry` (bubble/popup) WAJIB di-remove di
`dispose` **dan** sebelum navigasi/perubahan route — jangan andalkan timer
auto-close saja (entry yang di-unmount bisa gagal `remove` → sisa penghalang
tap). Simpan referensinya, panggil `remove()` idempotent di try/catch.

### 26f. "Kartu list Online susah diklik — klik beberapa kali baru kebuka" — `releaseNav` lupa dipanggil (2026-10-03)

**Gejala (user):** di menu Online, tap kartu user kadang tak membuka chat —
harus klik beberapa kali baru kebuka; makin sering diklik makin susah.

**Akar:** `online_users_screen._startChat` memanggil `tryClaimNav(navKeyChat)`
lalu `Navigator.push(...)` **TANPA** `.then((_) => releaseNav(navKey))`
(sedangkan `private_chat_screen` & `user_info` SUDAH pakai). Klaim di
`_navClaim[key]` tak pernah dilepas saat route di-pop.

`tryClaimNav` menolak klaim kedua dalam **window 2 dtk**. Karena release tak
pernah jalan, tap berikutnya ke kartu yang sama dalam 2 dtk → **ditolak →
tap tertelan**. Tiap tap yang lolos me-reset `_navClaim[key]=now` → makin
sering diklik makin sering timer di-reset → terasa "makin susah".

**Verifikasi bahwa ini BUKAN jank:** trace §25 saat klik berulang → semua
frame UI < **7ms** (render normal). Jadi masalahnya **tap tak sampai ke
kartu** (hit-test/logika), bukan render/berat.

**Fix:** tambahkan `.then((_) => releaseNav(navKey))` pada `Navigator.push`
di `_startChat` (aturan nav_guard §18: setiap push WAJIB lepas klaim saat pop).

**Aturan turunan:** tiap `tryClaimNav` **WAJIB** berpasangan dengan
`.then((_) => releaseNav(key))`. Kalau tidak, tap ke tujuan yang sama
tertelan selama window 2 dtk. Cek juga jalur `return` sebelum push
(harus `releaseNav` kalau klaim sudah diambil — sudah ada di `!context.mounted`).

> Catatan diagnosa: "kartu susah diklik / nggak nyahut" = **hit-test**, bukan
> jank. Trace yang semua frame <16ms TAPI user bilang tidak responsif →
> curigai penghalang tap (overlay sisa, `tryClaimNav` nyangkut, `AbsorbPointer`)
> — BUKAN optimasi render.

### 26g. List Chat kurang responsif — tap lewat InkWell di dalam Dismissible (2026-10-03)

**Gejala (user):** tap kartu di list chat (tab Pesan) terasa kurang responsif
dibanding menu Online.

**Akar:** kartu chat dibungkus `AppGestureDetector(onLongPress)` →
`Dismissible` → `Material` → `InkWell(onTap)`. `InkWell` (tap) berada **DI
DALAM** `Dismissible` (drag) & di bawah long-press → tap harus menunggu
gesture arena memutuskan dulu → **delay**. Menu Online (`_UserCard`)
sebaliknya: tap ada di `AppGestureDetector` **lapis dalam yang sama** dgn
long-press & di luar drag → cepat.

**Verifikasi:** trace §25 saat tap kartu chat → semua frame < **7ms**
(render sehat) → memang gesture arena, bukan render.

**Fix:** samakan dgn Online — pindah `onTap` ke `AppGestureDetector` (tambah
`behavior: HitTestBehavior.opaque`, `onTap` → `_openChat(chat)` / toggle
select), `InkWell.onTap = null` (matikan penyerap gesture dalam; struktur
visual tetap). Logika push dipindah ke method `_openChat`.

**Aturan turunan:** **JANGAN taruh `InkWell`/`GestureDetector` tap DI DALAM
`Dismissible`**. Taruh tap di lapis **luar** (satu `AppGestureDetector` dgn
`onLongPress`) — pola `_UserCard` (`online_users_screen`) & `private_chats_screen`.

### 26h. Top Aktif "selalu loading" — tak ada cache (2026-10-03)

**Gejala (user):** tiap buka menu Top Aktif selalu loading.

**Akar:** `LeaderboardSheet.initState` → `Timer(300ms)` → `_load()` → **selalu**
RPC `activity_leaderboard` tanpa cache. Tiap buka = 300ms tunda + ~150-400ms
RPC = **~500-700ms loading**, berulang tiap buka.

**Fix:** cache statis per-scope (weekly/alltime) + cache lokal per-sheet:
- `initState`: isi dari cache dulu (instan, tanpa spinner) → refresh diam.
  Tunda animasi 300ms → **120ms** bila sudah ada cache.
- `_switchScope`: ganti tab pakai cache scope itu bila ada (instan).
- **TTL 60 dtk**: cache masih fresh → skip RPC sama sekali.
- Gagal refresh TAPI ada cache → **pertahankan data lama** (jangan kosongkan).

**Hasil:** buka pertama tetap loading (mengisi cache); **buka ulang & ganti
tab = instan** (data dari cache + refresh background).

**Aturan turunan:** sheet/halaman yang memuat daftar dari RPC **WAJIB cache
per-key + TTL**, tampilkan cache dulu, refresh di latar. Jangan RPC polos di
`initState` — itu penyebab "tiap buka selalu loading".

> Ringkas pola bug sesi 2026-10-03: banyak keluhan "lelet/ga responsif"
> ternyata **bukan** render (trace semua <16ms), melainkan (a) `select`
> provider kelewat lebar → rebuild berlebih (§26/26b), (b)
> `InkWell`/`tryClaimNav` ngeblok tap (§26f/26g), (c) tak ada cache → loading
> berulang (§26h). **Ukur dulu (trace §25 / `build X=`) sebelum optimasi render.**



### 27a. Call 1:1/video — signaling ephemeral + proximity (2026-10-05)

Review subsistem call; tiga perubahan berdampak, semuanya terverifikasi.

| Area | Sebelum | Sesudah |
|---|---|---|
| ICE candidate | 1 INSERT DB + 1 event realtime **per candidate** (puluhan/call) | Realtime **Broadcast** ephemeral (tanpa DB); fallback DB hanya bila channel belum siap |
| `call_billing_tick` saat fitur OFF | 2 SELECT `app_settings` + gate | Gate `feature_enabled_for` **paling atas** → 0 query config |
| RLS `calls_update` | `USING` saja (kolom identitas bisa diubah peserta) | `USING` + `WITH CHECK` (identitas terkunci, status/heartbeat tetap boleh) |
| Audio call | layar selalu hidup (wakelock) meski dekat telinga | `PROXIMITY_SCREEN_OFF_WAKE_LOCK` — layar mati saat didekatkan |

**Perubahan kode:**
- Baru `lib/core/call/signal_route.dart` (logika murni routing sinyal;
  `test/signal_route_test.dart` 11 kasus).
- `lib/services/call_service.dart`: `sendSignal`/`onSignal` bercabang
  reliable vs ephemeral; `_setProximity` pada transisi `inCall` + cleanup.
- `lib/services/call/call_ui.dart|call_ui_channel.dart`: method `setProximity`.
- Native: `ProximityManager.kt` + handler `setProximity` di `CallUiBridge.kt`
  + izin `WAKE_LOCK`.
- Migrasi: `20261005130000_calls_update_with_check.sql`,
  `20261005140000_call_billing_gate_first.sql`.

**Verifikasi:** `dart analyze` bersih (file tersentuh); 78 test call+signaling
lulus; `check_migrations` OK; `:app:compilePlayProdDebugKotlin` BUILD SUCCESSFUL.
Uji 2-device (panduan `docs/CALL_NATIVE.md § Uji`) untuk connect < 5 dtk &
`count(call_signals)` per call turun dari puluhan ke ~3.

### 27b. Call 1:1/video — heartbeat lebih hemat + keputusan signaling (2026-10-05)

Lanjutan §27a.

- **Heartbeat `touchCall` 15 dtk → 25 dtk** (`call_service.dart`
  `_touchHeartbeat`). Ambang zombie server (`admin_sweep_calls`) = 75 dtk;
  dengan 25 dtk worst-case (satu tick terlewat) = 50 dtk → margin 3×. Untuk
  call 30 menit: 120 → 72 update/peserta (−40%).
- **Keputusan: offer/answer TIDAK dimigrasi ke Realtime Broadcast.** Broadcast
  tidak replay; offer dikirim sebelum callee subscribe → hilang → call
  nyangkut. Catch-up SELECT `call_signals` wajib ada. Hanya `candidate` yang
  ephemeral. (Detail: `docs/CALL_NATIVE.md § Signaling call`.)
- `_syncAll` (12 dtk) sudah hemat: saat `inCall` + ICE connected hanya sync
  penuh tiap tick ke-3 (~36 dtk) ≈ 1.7 query/menit — tidak diubah.

### 27c. REVERT: candidate ephemeral → DB (regresi "call menghubungkan lama") 2026-10-05

Uji 2-device menemukan regresi dari §27a: candidate via Realtime Broadcast
**tidak sampai ke peer** (log callee tak pernah menerima `onSignal
type=candidate`) → ICE menunggu 15 dtk → `fallback all-candidates` → call
"menghubungkan lama" (baru connect setelah ~15 dtk).

**Fix:** `kEphemeralSignalTypes` dikosongkan → SEMUA sinyal (termasuk
candidate) kembali lewat DB `call_signals` (postgres_changes) — jalur lama
yang terbukti cepat. Kode broadcast dipertahankan (dorman) untuk diaktifkan
kembali setelah broadcast diperbaiki & diuji.

**Pelajaran:** jangan pindahkan sinyal yang butuh latensi rendah & andal ke
Broadcast tanpa uji 2-device; postgres_changes (DB) justru lebih andal untuk
kasus ini. Optimasi bandwidth §1k (heartbeat 25 dtk) tetap berlaku.

### 27d. Voice stage (audio grup) — percepat connect (2026-10-05)

Keluhan: voice stage connect **lebih lambat** dari call 1:1 (uji 2-device:
~8 dtk vs 3 dtk). Akar (baca kode): (1) handshake `v_speak`→`v_join`→`v_offer`
= 2 round-trip DB sebelum ICE mulai; (2) `getPeerConfig(relayOnly: false)`
hardcoded → negosiasi semua kandidat (call 1:1 relay-only = 1-3 dtk);
(3) fallback sync `_burstSync` hanya 1.5s/4s.

**Fix (`room_voice_service.dart`):**
- **A. ICE relay-only per-peer + fallback all-candidates.** `_relayOnlyFor`
  per peer; `_retryPeerAllCandidates` (sekali/peer) rebuild pc + offer ulang
  bila relay belum Connected >6 dtk (watchdog uplink & downlink/timer 6 dtk) —
  pola `_retryWithAllCandidates` call 1:1. Policy di-MIRROR lewat field
  `relay` di `v_offer` agar dua arah konsisten (cegah mixed relay/host).
- **B. Percepat handshake.** Saat speaker naik stage, langsung offer ke
  speaker lain yang sudah diketahui (potong round-trip `v_join`); `v_join`
  tetap jalur cadangan.
- **C. `_burstSync` lebih rapat** (400/1200/2500/4000 ms) di fase awal.

**Test:** `room_voice_session_test.dart` +3 kasus (relayOnlyFor per-peer).
**Verifikasi:** analyze bersih; 63 test lulus; uji 2-device (target ~3 dtk).

Migrasi: TIDAK ada (perubahan klien murni).

### 27e. Voice stage (audio grup) — izin mic + kualitas capture (2026-10-05)

Lanjutan §27d. Temuan saat "cek mic room global":

- **BUG izin (utama):** `room_chat_screen.dart` TIDAK pernah meminta izin
  mikrofon sebelum naik stage — beda dari semua jalur call lain
  (`ensureCallPermissions` dipakai di call history/incoming/private chat/user
  info). Akibat: device yang belum grant mic → `getUserMedia` gagal senyap
  tanpa dialog. **FIX:** `_ensureMicPermission()` (panggil
  `ensureCallPermissions(video:false)` + `showCallPermissionDialog` bila
  ditolak) dipanggil di KEDUA jalur naik stage.
- **Kualitas mic:** `getUserMedia({'audio':true})` tanpa constraint → tambah
  constraint eksplisit (AEC/NS/AGC + Google highpass/typing + mono), dengan
  **fallback** ke tanpa-constraint bila device menolak (Overconstrained) agar
  voice tetap jalan. Plus `Helper.selectAudioInput` (mic terbaik, best-effort).
- **Opus codec prefs:** `_preferOpusCodec` (transceiver audio) dipanggil
  sebelum `createOffer` (uplink) & `createAnswer` (downlink) — low-latency+FEC,
  best-effort.

**Verifikasi:** analyze bersih; test room lulus; rebuild `--profile` +
install 2 device. Uji: device belum grant mic → tap mic → muncul dialog izin →
grant → mic hijau & jelas.

### 27f. Voice stage — FIX full mesh 3-6 orang (2026-10-05)

Gejala (uji 3 device): "semua muter-muter" lalu "muter berhenti tapi tak ada
suara". Dua akar:

1. **`_applySpeakers` membuang pc downlink** — iterasi `_peers.keys` (termasuk
   `dn_<uid>`) dibandingkan dengan daftar speaker (uid tanpa prefix) → `dn_B`
   dianggap "bukan speaker" → downlink dibongkar tiap refresh daftar speaker
   (realtime + polling + burst) → koneksi mesh terus putus (gejala muter).
   FIX: skip key ber-prefix `dn_`.
2. **Arah audio speaker-lama → speaker-baru tidak pernah terbentuk.** Saat di
   stage menerima `v_speak` dari speaker baru, kode lama hanya membalas
   `v_join` (→ X offer ke aku = X→aku), TIDAK offer (aku→X). Dengan 2 orang
   kebetulan tercover urutan naik-stage; 3+ orang → sebagian pasangan bisu.
   FIX: di `v_speak`, bila aku JUGA di stage → `_makeOfferTo(from)` (aku→X);
   bila pendengar → tetap `v_join`. Plus `_applySpeakers` proaktif offer ke
   speaker baru yang belum punya pc (`meshNeedsOfferTo`).
3. **Glare guard** di `_handleOffer`: offer dengan `pcId` sama & remoteDescription
   sudah ada → abaikan (cegah `createAnswer ... state other than
   have-remote-offer` saat mesh 3+).

Hasil: tiap pasangan speaker membentuk 2 pc (uplink dua arah) → full mesh
3-6 orang bersuara. Test: +4 kasus `meshNeedsOfferTo`.

### 27g. Voice stage — mic tidak mati (keluar room & mute) 2026-10-05

Dua bug mic dari uji 3 device:

1. **Keluar room → mic masih nyala.** `RoomChatScreen.dispose()` hanya
   menghentikan `_broadcastSession`, TIDAK `_voiceSession` — jadi track mic
   tetap hidup + speakerphone/wakelock tidak dilepas. `stop()` voice hanya
   dipanggil saat user TAP-TAHAN mic. FIX: panggil
   `_voiceSession.stop()` (+ removeListener) di `dispose()`.
2. **Mute tidak benar-benar senyap.** `setMuted` hanya `track.enabled=false`;
   di sebagian device itu TIDAK memutus mic ke AudioDeviceModule. FIX: pakai
   `Helper.setMicrophoneMute(value, track)` (mute native ADM) BERSAMA
   `track.enabled`. Juga: saat masuk stage → `setMicrophoneMute(false)`
   (reset), saat turun stage/keluar → `setMicrophoneMute(true)` + `stop()`.

**Verifikasi:** analyze bersih; 19 test room lulus; build `--profile` +
install 3 device (Redmi/Xiaomi/Huawei).

### 27h. Private chat — perbaiki jank "ngetik & buka" (typing setState storm) 2026-10-05

Diukur via PerfProbe (build `--profile --dart-define=PERF_PROBE=true`): log
`[CHAT-BUILD]` muncul BERUNTUN (~4× dalam 50ms) tiap kali typing berubah —
bukti REBUILD-STORM seluruh layar.

**Akar:** `getTypingPulseStream` mengirim pulse tiap perubahan typing lawan;
handler `setState()` → **rebuild SELURUH `PrivateChatScreen`** → termasuk
rebuild `items` list pesan O(n) + SEMUA `UserAvatar` bubble (`[AVATAR]` log
beruntun) → jank saat mengetik / lawan mengetik.

**Fix:** typing di-drive `ValueNotifier<int> _typingState` (0=off/1=typing/
2=recording) + `ValueListenableBuilder` yang membungkus HANYA subtree list
pesan. Perubahan typing tidak lagi men-rebuild appbar/composer/overlay/
avatar di luar list. Pola sama dengan `_elapsed` di CallScreen.

**Catatan:** jank "buka" private chat sebelumnya sudah ditangani `bb817e7`
(defer 220ms kerja reaksi/starred/status). Jank "ngetik" ini terpisah.

**Verifikasi:** analyze bersih (hanya lint lama use_build_context_sync);
test private chat + typing lulus; build+install 2 device untuk uji.

### 27i. Fix hapus akun: tidak logout + bisa back ke Pengaturan (2026-10-05)

Dilaporkan user: setelah hapus akun berhasil, app TIDAK logout & user bisa
menekan back ke Pengaturan/Akun.

**Dua akar:**
1. `_confirmDelete` (account_screen) memanggil `await auth.signOut()` dan
   TIDAK pop route. Berbeda dari `_confirmLogout` yang sudah memakai
   `popUntil((r) => r.isFirst)` di `finally`.
2. Setelah RPC `delete_my_account` menghapus `auth.users` server-side,
   `signOut()` biasa (memanggil endpoint /logout dgn JWT yang sudah mati)
   bisa THROW → dulu tidak tertangani → app tetap di halaman.

**Fix:**
- `auth_service_auth.signOut()`: bungkus `_sb.auth.signOut()` dgn try/catch →
  fallback `signOut(scope: SignOutScope.local)` (buang sesi lokal) bila
  /logout gagal (user sudah terhapus).
- `account_screen._confirmDelete`: bungkus signOut dgn timeout 8s (tahan
  error), lalu `Navigator.popUntil((r) => r.isFirst)` → gate menampilkan
  EntryScreen, route lama (Pengaturan/Akun) dibuang.

**Verifikasi:** analyze bersih; test delete-account lulus; build+install 2 device.

### 27j. Fix flash kartu "Keamanan Akun" saat keluar (2026-10-05)

Dilaporkan: saat keluar, masih terlihat FLASH halaman Akun (kartu kuning
Keamanan Akun + tombol Daftarkan Email) sebelum ke menu utama.

**Akar:** di `_confirmLogout.finally`, `_leaving` direset ke false SEBELUM
`popUntil` + sebelum gate swap ke EntryScreen → ada 1 frame `_leaving=false`
& `isAnonymous` masih true → kartu kuning anon render sekejap (flash).

**Fix (`account_screen.dart`):**
- JANGAN reset `_leaving` setelah logout sukses — biarkan true sampai layar
  benar-benar di-pop (reset hanya bila logout GAGAL, agar interaksi normal).
- Saat `_leaving=true`, body diganti `_LeavingSkeleton` (STATIS — bukan
  spinner animasi, agar `pumpAndSettle` test tak menggantung) → tidak ada
  konten Akun yang sempat tampil.
- `return` dipindah keluar dari blok `finally` (hilangkan lint
  control_flow_in_finally).

**Verifikasi:** analyze bersih; test settings_account + delete_account lulus
(19); build+install Xiaomi.

### 27k. Komentar timeline — jank "ngetik" + sheet "buka lambat" (2026-10-06)

Dilaporkan: saat mengetik komentar terasa ngelag; saat menekan tombol
"tulis komentar" sheet terasa lambat terbuka.

**Akar** (semua di `lib/widgets/post_card.dart`, `_comment()`):
1. Seluruh sheet (header + `_CommentsList` + bar input) dibangun dalam satu
   `StatefulBuilder` di root. Setiap perubahan state internal (mode balas,
   keyboard muncul) memicu **rebuild yang menyentuh `_CommentsList`** —
   `ListView.builder` + tiap `_CommentAvatar` (decode foto/`compute`) ikut
   dibangun ulang. Tidak ada `RepaintBoundary` → ketikan merembet repaint
   seluruh sheet.
2. `TextEditingController` dibuat **baru setiap kali** sheet dibuka
   (`TextEditingController()` di dalam `_comment()`) dan **tidak pernah
   di-dispose** → kerja alokasi tiap buka + leak.
3. `kb = viewInsets/viewPadding` dihitung di root builder →
   `AnimatedPadding` meretrigger relayout SELURUH sheet saat keyboard
   animasi.

**Fix:**
- Bar input + list dipisah ke `_CommentSheet` (StatefulWidget) tersendiri:
  mode balas dikelola lokal (`setState`), **tidak** merelayout lewat
  `StatefulBuilder` di root.
- `_CommentsList` dibungkus `RepaintBoundary` (ketikan/balasan tidak
  merepaint list) dan tetap memakai `GlobalKey` agar state-nya persisten.
- Bar input dibungkus `RepaintBoundary`.
- `TextEditingController _commentCtrl` dipindah ke `_PostCardState` (dibuat
  SEKALI, di-`dispose()`) — hilangkan alokasi-per-buka + leak.
- Geser keyboard hanya menggerakkan bar input (`AnimatedPadding` di subtree
  `_CommentSheet`), list & tinggi sheet tetap diam.

**Verifikasi:** analyze bersih (hanya lint lama `_cleanupTestChannels`);
`test/post_card_test.dart` 17 lulus (2 regresi baru: "balas komentar → kirim
memakai parentId" & "mengetik tidak menghapus baris komentar"); suite
timeline/detail/functional 82 lulus.

### 27l. Admin panel — jank "kadang lancar kadang ngelag" saat buka tab (2026-10-06)

Dilaporkan: saat buka Admin Panel kadang ngelag, kadang lancar — tidak stabil.

**Akar:** `AdminProvider` adalah SATU `ChangeNotifier` yang menggabungkan 8
domain (stats, devices, chats, chat-org, deleted, contact, attribution, calls)
dengan **60 titik `notifyListeners()`**. Setiap tab memakai
`context.watch<AdminProvider>()` → **setiap** notify dari domain MANA PUN
me-rebuild **SEMUA** tab yang sudah dibangun sekaligus. Pemicu tak terkait:
- `refreshStats` (polling 60 dtk) → rebuild Perangkat/Terhapus/Monitor/Atribusi/Kontak
- `fetchDevices` (polling 60 dtk) → rebuild semua tab lagi
- realtime `fetchActiveCalls` → rebuild semua tab

"Kadang lancar kadang ngelag" karena: saat polling/realtime kebetulan menyala
TEPAT saat membuka tab berat (Perangkat `_groupByDevice` ratusan baris,
Terhapus, Monitor Chat), tab itu di-rebuild berulang → jank. Kalau tidak
berbarengan, lancar. Ini yang membuat gejalanya tak stabil/periodik.

**Fix — revision counter per-domain (granular rebuild):**
- `AdminBase` menambah counter `_revStats/_revDevices/_revChats/_revDeleted/
  _revContact/_revAttribution/_revChatOrg/_revCalls` + getter publik
  (`revStats` dst) + helper `_notifyStats()/_notifyDevices()/…` yang menaikkan
  counter domain lalu `notifyListeners()` (tetap satu notifier — interface
  publik & mock test TIDAK berubah).
- Semua `notifyListeners()` domain diganti `_notifyXxx()` sesuai domainnya
  (stats 17, devices 5, deleted 4, chats 19, contact 6, chatOrg 7, attribution
  7, calls 1). `clearAdminCache` tetap `notifyListeners()` mentah
  (lintas-domain, sengaja rebuild semua).
- Tiap tab/widget ganti `context.watch<AdminProvider>()` →
  `context.select<AdminProvider, int>((p) => p.revXxx)` + `final admin =
  context.read<AdminProvider>()`. Tab Monitor Chat bergantung ke DUA domain
  (`revChats` + `revCalls`) karena menampilkan daftar chat + badge call.
  Kartu stats (storage/registrasi/tablesize) → `revStats`; sheets Atribusi →
  `revAttribution`.

**Efek:** membuka tab berat tidak lagi di-rebuild oleh polling domain lain.
Polling stats tiap 60 dtk hanya menyentuh tab Ringkasan/Poin; polling devices
hanya menyentuh tab Perangkat.

**Verifikasi:** analyze bersih (provider 0 issue; sisa info lint lama di
screens); `test/admin_*.dart` 165 lulus + 2 test baru ("notify STATS tidak
menaikkan counter domain lain", "notify DEVICES hanya menaikkan revDevices").

### 27m. Ngetik ngelag "setelah app dipakai lama" — akumulasi cache memori (2026-10-06)

**Gejala (user):** fresh install lancar; setelah ±½–1 jam pakai, **ngetik di
private chat ngelag**; **restart app → normal lagi (sementara)**. Klik kartu
list→chat & menu Online→chat juga "berat"; hapus huruf terakhir teks panjang
ngelag.

**Diagnosis (§25):** trace frame UI saat ngetik **semua <12ms** (render sehat),
tapi keluhan konsisten "makin lama makin berat" → **akumulasi memori**
(GC storm), bukan satu-frame berat. Restart bersihkan cache → cocok.

**Akar — cache memori menahan base64/bytes foto (tumbuh seiring pemakaian):**
| Cache | Isi | Cap lama |
|---|---|---|
| `MessageCache._memCache` | 30 chat × pesan **termasuk `imageData` base64 foto** (~2MB/foto) | 30 |
| `decodedImageCache` (`private_chat_message`) | bytes foto asli (~2-3MB) | 40 |
| `timeline_provider._posts` | post feed | **tak ada cap** |

30 chat berisi foto bisa menahan **ratusan MB** tertahan → GC stop-the-world →
ngetik ketahan. Restart kosongkan → normal.

**Fix:**
- `_memCacheMax` 30 → **8** (chat lain dibaca dari SQLite saat dibuka).
- `_decodedCacheMax` 40 → **16**.
- `timeline_provider._posts` **cap 120** (helper `_capPosts`, dipanggil di 4
  titik add/insert; post lama tetap di `_scopeCache`/disk).
- **Trim saat resume (`app.dart`)**: kalau app di-background **>60 dtk**, pada
  resume panggil `MessageCache.trimMemCache()` + `ImageCacheHygiene.clearAll()`
  (buang cache memori, disk tetap). Background sebentar TIDAK di-trim → chat
  tetap instan. `MessageCache.trimMemCache()` = baru (in-memory saja).

**Fix lain sesi ini (jank tap & decode):**
- `activeMentionToken` (`utils/mention.dart`): scan mundur dibatasi
  `_maxQueryLen+2` — dulu ke awal teks = O(n) tiap keystroke → **O(n²)** saat
  ngetik/hapus teks panjang.
- `composer_link_preview.dart`: `extractUrl` (regex O(n)) + setState dipindah
  ke **dalam debounce 400ms** (dulu sinkron tiap `onChanged`).
- `decodeImageB64` (`private_chat_message.dart`): baca dimensi dari **header
  JPEG/PNG** (`parseImageDimensions`) — dulu `img.decodeImage` **full-res 12MP
  ≈ 48MB** tiap foto baru → spike ~470MB saat scroll chat berfoto (buffer =>
  user scroll). Terukur 46MB→**515MB** jadi 52MB→**55MB**.
- `online_users_screen._startChat`: 2 RPC (`isUserActive`+`startPrivateChat`)
  ditunda ~400ms (dulu jatuh di frame transisi).
- `online_users_screen` `_unreadSub`: `setState` hanya bila peta unread
  BERUBAH (dulu tiap emit chat-list → `build Online=170`).
- `leaderboard_sheet._load` cache per-scope + TTL 60 dtk (dulu tiap buka =
  loading ulang).
- Sheet komentar (post_card) & Top Aktif: viewPadding (nav bar) bukan padding;
  sheet komentar tak lagi ikut naik saat keyboard (input naik sendiri).

**Verifikasi:** analyze bersih; test (mention, link_preview, timeline,
photo_bubble, message_cache, leaderboard_cache, post_card) lulus; ukur heap
scroll chat berfoto 515MB→55MB.

### 27m. Private chat — jank "buka chat" (warm cache + koalesensi rebuild) 2026-10-06

Dilaporkan: "barusan masuk private chat ngelag lagi". Diukur via build
`--profile` + logcat (metode §25) di Xiaomi 15.

**Data sebelum (logcat):** rata-rata **3.47 `[CHAT-BUILD]` per buka** (push→pop);
**16 `[CACHE-TIME] server=` vs 10 `sqlite=`** — chat yang belum di cache harus
tunggu `server=~120-148ms` di jalur frame pertama. Tampak pasangan
`[CHAT-BUILD]` berjarak 16-17ms (rebuild-storm). Memory PSS 378 MB / swap 34 MB.

**Tiga akar:**
1. `_warmTopChats` hanya menghangatkan 2 chat teratas → chat lain (jarang
   dibuka) belum ada di cache SQLite → buka harus fetch server ~120-148ms.
2. Pekerjaan pasca-buka (timer 220ms reaksi/starred, 280ms channel+profil)
   masing-masing `setState` → layar penuh di-build 2-3× beruntun.
3. `_onCallChanged` setState SELALU saat `sess == null` (chat tanpa call =
   selalu true) tiap `CallProvider.notify` — rebuild penuh tak perlu.

**Fix:**
- `_warmTopChats` (private_chats_screen): 2 teratas langsung + **8 berikutnya
  di-idle** (jeda 1.2 dtk, berjarak 220ms) → cache siap sebelum ditekan.
- Helper `_scheduleRebuild()` (koalesensi via `scheduleFrameCallback`) di
  `private_chat_screen` — dipakai untuk setState pasca-buka (reaksi, starred,
  chatInfo stream, status lawan, getOtherProfile); rebuild yang jatuh di frame
  sama jadi SATU setState.
- `_onCallChanged` difilter signature (`callId|phase` / `_none`): rebuild
  hanya bila state call relevan berubah.

**Hasil terukur (setelah, logcat baru):**
- **build/pop 3.47 → 2.56** (−26%).
- **cache: 10 sqlite/16 server → 25 sqlite/9 server** (mayoritas buka dari
  cache lokal; server fetch turun ~44%).
- **Rebuild-storm HILANG**: jarak minimum antar `[CHAT-BUILD]` 16ms → **98ms**
  (tidak ada lagi burst <40ms).

**Verifikasi:** analyze 0 error; 73 test chat/reaksi/stream lulus (4 gagal di
`user_info_seed_test.dart` PRE-EXISTING, sudah gagal di HEAD). Catatan #3
(avatar/foto) sudah aman: semua `Image.memory` punya `cacheWidth`/`ResizeImage`
+ cache pesan LRU-bounded 8.

### 27n. Navigasi "back" konsisten di semua halaman — slide 150/120ms global 2026-10-06

Dilaporkan: back dari room (masuk topic) terasa lebih lambat dari private chat
(dari chat list). Permintaan: konsisten seperti private chat di SEMUA halaman.

**Akar (terverifikasi):** private chat cepat HANYA di 2 dari 11 tempat buka —
pakai `PageRouteBuilder` manual 150ms masuk / 120ms keluar + `SlideTransition`
(`private_chats_screen.dart:110`, `online_users_screen.dart:805`). **93 tempat
lain** (termasuk 8 tempat buka `RoomChatScreen`) pakai `MaterialPageRoute`
default ~300ms (Zoom). Tidak ada `pageTransitionsTheme` global. Akibat: room &
halaman lain back ~2.5× lebih lambat (dulu 120ms vs ~300ms).

**Temuan kunci (Flutter 3.47):** `PageTransitionsBuilder` mengekspos
`transitionDuration`/`reverseTransitionDuration` yang bisa di-override, dan
`MaterialPageRoute` membacanya dari theme (`material/page.dart:91-97`). Jadi
SATU custom builder global cukup mengubah 93 rute sekaligus.

**Fix (1 file: `lib/config/theme.dart`):**
- Kelas `AppSlidePageTransitionsBuilder extends PageTransitionsBuilder`:
  `transitionDuration=150ms`, `reverseTransitionDuration=120ms`,
  `buildTransitions` → `SlideTransition` `Offset(1,0)→0` dengan
  `Curves.easeOutCubic`/`easeInCubic` (identik private chat). Bila
  `route.fullscreenDialog` (Call/IncomingCall) → delegasi ke
  `ZoomPageTransitionsBuilder` (bottom-up, TIDAK slide).
- Daftarkan di `_buildTheme` → `pageTransitionsTheme` untuk SEMUA platform
  (android/iOS/macOS/windows/linux) → berlaku seluruh app (room, profil,
  setelan, auth/onboarding, admin).

**Tidak diubah (sengaja):** 8 tempat push room (otomatis ikut), 2
`PageRouteBuilder` manual private chat (hasil identik); bottom sheet/dialog
bukan page route.

**Verifikasi:** analyze 0 error (sisa 2 info `deprecated_member_use` lama);
test baru `test/page_transition_test.dart` 5 lulus — termasuk bukti objektif
`MaterialPageRoute.transitionDuration == 150ms` &
`reverseTransitionDuration == 120ms` (bukan 300ms), plus fullscreenDialog
tetap bottom-up. Suite regression/functional/widgets/chat 86 lulus; logcat HP
tanpa error Dart.

Catatan: `PredictiveBackPageTransitionsBuilder` (default Android) tergantikan
— back gesture tetap jalan tanpa animasi predictive (diterima user).

---

## 28. Tab non-aktif tidak rebuild (IndexedStack) + admin panel granular (2026-10-06)

**Keluhan (user):** "di private chat ada foto chat sama user, serasa ngelag
pas ada foto"; "klik tiap card di menu Online masuk-keluar private chat
berulang, makin lama makin lambat"; "buat ringan build, yang penting aja
ketika chat".

**Ukur (build DEBUG + logcat, karena `dlog` di-gate kDebugMode di rilis):
** 1058 `[AVATAR]` dalam satu sesi singkat, storm hingga **272 resolve/detik**.
Tiap buka-tutup chat, tab **Online** (di `IndexedStack`) ikut di-build ulang
walau tak terlihat → semua `UserAvatar` di-resolve ulang.

**Akar:** `IndexedStack` membangun SEMUA tab yang pernah dikunjungi. Setiap
`_MainNav` rebuild (badge unread/anon/select berubah) → SELURUH tab (termasuk
Online yang berisi puluhan `UserAvatar`) ikut di-build ulang. `TickerMode`
dulu hanya mematikan ANIMASI, **bukan** mencegah rebuild. Sama di admin:
`context.select<AdminProvider,int>((p) => p.revStats)` di ROOT `build()` →
tiap stats berubah (polling 60 dtk / realtime) SELURUH panel + semua tab
yang dibangun ikut rebuild.

**Fix:**
1. **`_TabFreeze`** (`lib/app.dart`) — widget yang menahan subtree tab yang
   TIDAK aktif: instance `child` terakhir dipertahankan (`didUpdateWidget`
   hanya update child saat tab aktif atau tepat transisi aktif→non-aktif),
   dibungkus `TickerMode(enabled: active)`. Jadi parent rebuild tak menyentuh
   tab belakang; saat tab dibuka, child terbaru langsung dipakai (data fresh).
   Dipakai di `IndexedStack` `_MainNav` (Online/Chat/Timeline/Profil).
2. **`UserAvatar._resolve` fast-path EMPTY** (`lib/widgets/user_avatar.dart`) —
   user tanpa foto (src kosong) yang sudah pernah diproses kosong → langsung
   return (dulu tiap build jatuh ke cabang EMPTY + log).
3. **Admin panel granular** (`lib/screens/admin_panel_screen.dart`) — buang
   `select(revStats)` dari root; tab **Overview** & **Poin** membungkus diri
   dengan `Consumer<AdminProvider>` (hanya keduanya yang butuh stats). Tab
   Perangkat/Terhapus/Chat-monitor kini tak tersentuh saat stats berubah.

**Hasil terukur (sebelum → sesudah, sesi mirip):**

| Metrik | Sebelum | Sesudah |
|---|---|---|
| `[AVATAR]` total/sesi | **1058** | **83** (−92%) |
| Storm avatar/detik | **272** | **30** (−89%) |
| `[CHAT-BUILD]` | 100 | 41 |

Session stream tetap **balance** (`start 29 / cancel 30`) — tidak ada leak.

**Aturan turunan (JANGAN dibalik):**
- **`IndexedStack` (atau container yang menahan banyak halaman hidup) WAJIB
  membungkus setiap child non-aktif dengan penahan-rebuild** (`_TabFreeze`
  pola). `TickerMode` saja TIDAK cukup — ia hanya mematikan animasi.
- `TabBarView` hanya build tab terlihat (+ neighbor) — lebih aman, TAPI
  pastikan tab tak mewarisi rebuild dari PARENT (root yang `select` domain
  berat = semua tab ikut). Taruh `select`/`Consumer` **sedekat mungkin** ke
  widget yang benar-benar memakai datanya.
- `UserAvatar` untuk uid tanpa foto jangan resolve ulang tiap build.

**Verifikasi:** analyze 0 error/warning; 32 test avatar/nav lulus; build
apkpureProd & adminProd release sukses + terinstall. Log `[SESSION]`/`[AVATAR]`
instrumentasi (dari penyelidikan) sudah DIHAPUS dari kode.

**Catatan diagnosa:** storm `[CHAT-BUILD]` saat buka chat (~10× @40ms) yang
tersisa berasal dari **animasi transisi route** (bukan kode kita) — biayanya
kini kecil setelah §27n (transisi 150ms) + fix di atas. Profil `[PERF]` frame
timing menunjukkan build p50≈1.5ms (sehat); jangan kejar jumlah rebuild tanpa
melihat biayanya (banyak rebuild murah ≠ jank).

---

## 29. Review storm menyeluruh (user + admin) — select granular (2026-10-06)

**Konteks:** lanjutan §28. Auditing SEMUA layar untuk pola storm (rebuild
berlebih) di ChatYuk user + admin.

**Temuan (pola sama, `watch<Provider>()` penuh di root build):**

| Layar | Dulu | Sumber notify sering |
|---|---|---|
| `group_screen` | `watch<RoomProvider>()` | RoomProvider 4 realtime sub (counts/private/membership/presence) |
| `lobby_screen` | `watch<RoomProvider>()` | sama (build utama cuma butuh `country`) |
| `rooms_explore_screen` | `watch<RoomProvider>()` | sama; `exploreRooms` = list BARU tiap akses |
| `online_users` `_OnlinePill` | `watch<RoomProvider>()` | sama |
| `settings_screen` | `watch<AuthProvider>()` | Auth notify (avatar/location/heartbeat) |
| `point_history_screen` | `watch<PointsProvider>()` | Points refresh berkala |
| `user_info_screen` | `watch<AuthProvider>()` + `watch<PointsProvider>().enabled` | Auth |
| `notification_settings_screen` | `watch<AuthProvider>()` (1 field) | Auth |

**Fix (semua `select` field yang benar-benar dirender):**
- `group_screen`: `select(myGroups)` + `select(myGroupsLoading)` — `_visibleGroups`
  kini terima `List<RoomModel>` (bukan provider).
- `lobby_screen`: `select(country)` (daftar room ada di RoomsExploreScreen).
- `rooms_explore_screen`: **JEBAKAN** — `exploreRooms` mengembalikan list BARU
  (`.where().toList()` + sort) → identity selalu beda, TIDAK boleh di-select
  langsung. Solusi: getter baru `RoomProvider.exploreSig` (signature murni dari
  isi `_explore`) + `select(exploreSig/exploreCategory/exploreLoading)`; data
  aktual dibaca via `read` saat rebuild dipicu. `exploreLoading` di-pass ke
  `_buildList` agar spinner tetap akurat.
- `online_users` pill: `select` **ANGKA** count general online (value-type).
- `settings_screen`: `select` record `(isAnonymous, dummySessionActive,
  isRealAdmin, notificationsEnabled)`.
- `point_history_screen`: `select` record `(points, topupPathOpen,
  yukcoinV2Active, ghostMode)`; aksi via `read`.
- `user_info_screen`: `select` record `(isAnonymous, callAllEnabled, uid)`.
- `notification_settings_screen`: `select(notificationsEnabled)`.

**Admin:** `admin_chat_list_screen` — `select(revChats)` + `select(revCalls)`
di root **DIPERTAHANKAN** (bukan storm): `activeCallsByChat` dipakai untuk
**SORT** (call aktif di atas) → rebuild saat call berubah memang diperlukan.
Tab admin lain sudah `select(revXxx)` per-domain (benar).

**PerfProbe.buildCount ditambah** di: `Group`, `Lobby`, `RoomsExplore`,
`AdminPanel`, `AdminChatList` (untuk verifikasi terukur).

**Hasil terukur (HP 24129PN74G, build debug + PERF_PROBE):**

| Metrik | Sebelum | Sesudah |
|---|---|---|
| `[AVATAR]` total/sesi | 1058 | **120** (−89%) |
| Storm avatar/detik | 272 | **16** (−94%) |
| `[CHAT-BUILD]` | 100 | **28** |
| Tab switch `tap→frame` | — | **10-20ms** (di bawah 16ms; 1 one-off 522ms saat RPC online 1457ms) |

`build Group=10 / Lobby=9 / RoomsExplore=13` sepanjang sesi multi-buka-tutup
(dulu 100+).

**Aturan turunan (PENTING):**
- **Getter List/Map yang membuat objek BARU tiap akses** (`.where()...toList()`,
  `.map()`, sort) **JANGAN di-`select` langsung** — identity selalu berubah →
  rebuild tiap notify (bug §26). Pakai **signature value-type** (String/int)
  atau select field tersimpan.
- Aksi provider (mis. `refreshWallet`, `setExploreCategory`) panggil lewat
  `read`, nilai untuk render lewat `select` — pisahkan keduanya.

**Sisa jank (di luar scope storm):** `janky(build)=81` + `max=324ms` berasal
dari **RPC server lambat** (`online.diskLoad 837ms`, `count_room_presence
1464ms`, `online.rpc 1457ms`) — bukan rebuild. Optimasi berikutnya (jika perlu)
= cache/defer RPC tersebut, bukan select.

**Verifikasi:** analyze 0 error/warning; 88 test (room/points/settings/privacy/
online) lulus; build debug user + release admin sukses & terinstall.

---

## 30. Admin panel — audit storm + RPC (2026-10-06)

**Audit menyeluruh semua menu admin** (Global Setting/Overview/Poin/Monitor
Chat/Dummy/Kontak/Perangkat/Terhapus/Atribusi/Docs).

**Hasil ukur (HP 24129PN74G, adminProd release + PERF_PROBE):**
- `frames=3236 build[p50=0.6 p90=1.8 max=35.5ms] janky(build)=11` = **0.34%**
  jank — SANGAT SEHAT.
- Tab switch `tap→frame 5-8ms` (instan).
- RPC admin **server-side cepat** (EXPLAIN ANALYZE): `admin_stats` 22ms,
  `admin_active_calls` 6ms, `admin_registration_kpis` 12ms,
  `admin_list_devices` 14ms, `admin_list_deleted` 25ms,
  `admin_storage_stats` 28ms, `admin_get_chat_org` 2ms.

**Kesimpulan:** tidak ada storm di admin. Struktur sudah benar:
- `AdminProvider` = 1 ChangeNotifier, tiap domain bump counter (`revXxx`) →
  tab `select(revXxx)` (rebuild granular, §26).
- Polling guarded: `fetchActiveCalls` diam bila sidik sama (§17.5);
  `_statsTimer`/`_notifyTimer` 60 dtk + cancel saat background.
- `TabBarView` admin lazy (`_visitedTabs`).

**Peningkatan (konsistensi + pencegahan):** tambah `RepaintBoundary` di kartu
list admin yang belum punya — `admin_chat_list_screen` (`_AdminChatCard`),
`admin_devices_tab` (`DeviceCard`/user-only), `admin_deleted_tab`
(`DeletedCard`), `admin_dummy_tab` (`DummyCard`) — agar satu kartu berubah
(badge call/unread/GPS/status) tidak merepaint seluruh list panjang
(konsisten dgn menu Online & daftar chat user).

**RPC lambat sisa (bukan admin, umum saat boot):** `chat.hiddenFetch 935ms`,
`list_my_groups 747ms`, `count_room_presence 515ms` — latensi network/HP
(server-side sudah diukur cepat). Kandidat optimasi berikutnya jika perlu.

**Verifikasi:** analyze 0 error/warning; build adminProd release sukses &
terinstall.

---

## 31. Audit RPC boot lambat (hiddenFetch/list_my_groups) (2026-10-06)

**Konteks:** RPC `chat.hiddenFetch` 935ms & `list_my_groups` 747ms saat boot
terlihat lambat di logcat HP.

**Audit — ukur server (EXPLAIN ANALYZE):**
- `getHiddenChats` (`hidden_by @> [uid]`): **Seq Scan** private_chats (1728
  rows, "Rows Removed by Filter: 1728") = 1.2ms server. Kecil tapi tumbuh
  linear (tanpa index).
- `list_my_groups`: 3.3ms server.
- Chat list: `listFetch` + `hiddenFetch` **sudah paralel** (1 RTT).

**Kesimpulan:** 935/747ms = **latensi network HP→DB**, BUKAN query (server
1-3ms). Server-side tak ada masalah.

**Optimasi:**
- **Server:** tambah `idx_private_chats_hidden_by` (GIN, migrasi
  `20261006100000`, **SUDAH APPLY**) → seq scan 1.2ms → bitmap index 0.02ms
  (pencegahan saat data besar; konsisten dgn pinned_by/muted_by/archived_by).
- **Client:** `getMyPrivateChats` reload pertama **di-defer 250ms** — list
  sudah tampil dari cache disk (`loadRawList`) → frame boot bersih tanpa
  nunggu RPC. Reload RPC tetap jalan (dedupe in-flight).
- Catatan: `loadMyGroups` sudah punya cache disk + TTL 30s + guard loading;
  dipanggil dari prewarm (defer 3s) — tak blokir boot.

**Sisa (infrastruktur, bukan kode):** RPC 500-1050ms saat cold start =
network/HP latency + `online.diskLoad` (SQLite decrypt native). Mitigasi
sudah ada (cache-dulu: list/chat/grup tampil instan dari disk, server
menyusul). Percepat lagi = naik compute / region DB lebih dekat.

**Verifikasi:** analyze 0 error/warning; 24 test chat/room lulus; index
terpasang & dipakai (EXPLAIN konfirmasi Bitmap Index Scan).

---

## 32. Nav bawah "lag diklik di awal, setelah dipencet jadi cepat" (2026-10-06)

**Keluhan (user):** "menu Online/Chat/Timeline/Profil lag untuk diklik di awal;
kalau sudah dipencet-pencet jadi cepat lagi".

**Diagnosa (PerfProbe `tab{N} tap→frame` di HP):**
```
tap pertama:  tab1=19-24ms  tab2=19ms  tab3=20-27ms  (jank, >16ms)
tap ke-2+:    tab1=10-14ms  tab2=12ms  tab3=12-15ms  (mulus)
```
Jank HANYA di tap pertama tiap tab, hilang setelahnya.

**Yang BUKAN penyebab (dibuktikan):**
- Bukan `_MainNav.build`: instrumentasi Stopwatch penuh `build()` → **tak
  pernah >5ms** (`[MAINNAV-SLOW]` tidak muncul).
- Bukan tab belum ter-build: prewarm terverifikasi jalan (`[PREWARM] building
  tab 1/2/3` selesai ~2 dtk setelah runApp, jauh sebelum tap ~6 dtk kemudian).
- Bukan shader raster (`janky(raster)` rendah).

**Akar:** `IndexedStack` hanya me-**layout+paint** child yang `index`-nya
aktif; child lain di-`Offstage` (build, tapi TIDAK layout/paint). Jadi layout
+paint pertama tab tujuan jatuh di **frame tap** (~20ms = 1-2 frame drop),
lalu ter-cache → tap berikutnya mulus.

**Keputusan (trade-off arsitektur, SENGAJA):** tetap **lazy `IndexedStack`**.
Alternatif (layout semua tab agar tap instan) = semua tab render tiap frame →
berat + risiko storm (§26: tab belakang rebuild). Untuk 4 halaman berat, 1
frame drop **sekali** di tap pertama per tab lebih baik daripada beban terus.
Perbaikan pendukung: prewarm dipercepat (mulai 32ms + interval 16ms, tab hangat
~50ms — hilangkan jank untuk user yang tap >50ms setelah boot).

**Tidak diubah:** arsitektur lazy. Jangan "fix" dengan membuat semua tab
selalu layout tanpa mengukur ulang `janky(build)` harian.

**Verifikasi:** analyze 0 error; prewarm terverifikasi (`[PREWARM]` log);
`tab{N} tap→frame` tap-2+ < 16ms.

---

## 33. RILIS lag "ngetik di private chat" — akar: shrinkResources (2026-10-06)

**Keluhan (user):** "di private chat kadang pas mau ngetik pertama kali ngelag;
pas nulis ngelag. **Tapi pake APK release lag, debug/profile lancar**."

**Diagnosa (eliminasi build variant):**
- profile/debug: `build[p50=1.5 p90=2.6] janky=7/4000` — LANCAR.
- release+PERF_PROBE: `p50=1.0ms janky=1/3751` — frame SANGAT sehat, tapi user
  tetap rasakan lag → lag **bukan** di render/build Dart (tidak terlihat di
  frame timing).
- Uji variant (build RILIS, tes "ketik di private chat"):
  | isMinifyEnabled | isShrinkResources | hasil |
  |---|---|---|
  | false | false | **lancar** |
  | true | true | ngelag |
  | true (+`-dontoptimize`) | true | ngelag |
  | true | **false** | **lancar** |
  | true | true (+`keep.xml` keep @*) | **lancar** ✅ |

**Akar:** `isShrinkResources=true` (R8 resource shrinker) men-strip resource
yang diakses **Dinamis/by-name** (bukan literal `R.*`) → saat runtime lookup
gagal & fallback berulang (terasa "ketik pertama tersendat"). Bukan optimisasi
bytecode (`-dontoptimize` saja tidak cukup).

**Fix:**
- `android/app/src/main/res/raw/keep.xml` → `tools:keep="@*"` (lindungi semua
  resource dari shrink). Ukuran APK TETAP 172MB (shrink non-asset tetap jalan).
- `android/app/build.gradle.kts`: `lint { abortOnError=false; checkReleaseBuilds=false }`
  — lint crash internal (Kotlin `LLFirModuleData`, Flutter 3.47 + KGP 2.3.20)
  menggagalkan build RILIS acak (tidak terkait kode). Bukan penyebab lag,
  tapi perlu agar build stabil.

**Aturan turunan:** JANGAN set `isShrinkResources=true` TANPA `keep.xml`
keep-all — tervalidasi user "lancar" setelah fix. Uji "ketik di private chat"
pada build RILIS setiap mengubah konfigurasi shrink/minify.

**Verifikasi:** user konfirmasi lancar; APK user 172MB + admin 176MB terinstall.
