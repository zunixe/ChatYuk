# MEMORY BEST PRACTICES — cara bikin ChatYuk tetap ringan

> **BACA INI sebelum menulis widget yang menampilkan gambar/foto/video, list
> panjang, atau apa pun yang bisa jalan terus-menerus.** Target: app terasa
> ringan di HP kelas menengah, tidak lag saat pindah tab, tidak dibunuh OS.

Dokumen ini ringkasan aturan praktis. Riwayat insiden + angka ukur lengkap ada
di [`PERFORMANCE.md`](PERFORMANCE.md) (lihat §13, §14, §23).

---

## 0. Prinsip utama

1. **Ukur dulu, jangan tebak.** Komplain "ngelag" hampir selalu = waktu
   tunggu data (RPC/DB) atau bitmap, **bukan** render widget. Render Flutter
   di HP kerja sudah 0% jank. Ukur dengan `adb` dulu (`PERFORMANCE.md` §1h).
2. **Ringan > nol re-decode.** Lebih baik gambar di-decode ulang dari disk
   (murah, ~ms) daripada menahan ratusan MB bitmap di RAM. Cache harus
   **dibatasi (bounded)**, jangan pernah unbounded.
3. **Setiap `Image.memory` WAJIB punya `cacheWidth`** (atau `ResizeImage`)
   kecuali viewer full-screen yang memang butuh resolusi penuh. Ini aturan
   paling sering dilanggar — penyebab insiden berulang.

---

## 1. Menampilkan gambar — ATURAN KERAS

### 1.1 Selalu cap decode

```dart
// ❌ SALAH — decode full-res (JPEG 1080px ≈ 4,6 MB bitmap) untuk avatar 40px
Image.memory(bytes)

// ✅ BENAR — cap sesuai ukuran tampil (px fisik × 2-3 untuk retina)
Image.memory(bytes, cacheWidth: (size * 2).round())

// ✅ BENAR (di CircleAvatar / BoxDecoration)
backgroundImage: ResizeImage(MemoryImage(bytes), width: 96)
```

**Kenapa:** Flutter decode gambar di **native heap** (Skia/Impeller). Satu
JPEG 1080px = ~4,6 MB bitmap. 20 gambar = ~92 MB. Cap ke ukuran tampil
menghemat 10-25×.

### 1.2 Ukuran cap yang benar

| Tampil | Cap (`cacheWidth`) |
|---|---|
| Avatar list kecil (40px) | 96 |
| Avatar sedang (72px) | 160 |
| Thumbnail grid foto | 256 |
| Bubble foto chat | 720-1080 |
| Viewer full-screen | 1280-1600 (lalu **evict**) |

Aturan: `cacheWidth = lebar_px_tampil × 2` (retina 2×). Lebih dari itu hanya
membuang memory.

### 1.3 Viewer / dialog / zoom WAJIB evict saat ditutup

Gambar full-res yang dibuka lalu ditutup **harus** dikeluarkan dari
`ImageCache`, kalau tidak ia tertinggal sampai LRU kebanjiran.

```dart
// Setelah Navigator.pop / di dispose():
PaintingBinding.instance.imageCache.evict(MemoryImage(fullResBytes));
```

Contoh yang sudah benar: `post_photo_viewer.dart`, `async_photo.dart`
(`AsyncPhotoViewer.dispose`), `private_chat_message.dart` (view-once),
`online_users_screen.dart` (dialog zoom).

### 1.4 Jangan pernah `Image.memory` di list panjang tanpa cap

List panjang (daftar online, chat, timeline, komentar) = N gambar sekaligus.
Tanpa cap, memory meledak. Gunakan pola `ImageProvider` **stabil per-id**
(lihat §3.2) supaya rebuild tidak decode ulang.

---

## 2. Cache harus BOUNDED

Semua cache gambar/byte di memori **wajib** punya batas. Pola di repo:

| Cache | Batas |
|---|---|
| `ImageCache` global (`main.dart`) | 80 entri / 48 MB |
| `PostPhotoCache._mem` | 30 MB (LRU) |
| `PhotoCache._memCache` | 20 MB |
| `AvatarB64Service._cache` / `._pathCache` | 100 entri (satu-satunya store avatar by-uid/path; `ChatService._avatarCache` kini delegasi ke sini) |
| `user_avatar.dart` map render avatar (bytes + ImageProvider stabil) | 120 entri (cap `_avatarMapCap`) |
| `profile_avatar` `_bytesCache` | 60 entri |
| `MessageCache._memCache` | 30 chat |

```dart
// ✅ Pola LRU / FIFO sederhana
void _put(String key, Uint8List bytes) {
  _cache.remove(key);
  _cache[key] = bytes;
  while (_cache.length > _max) {
    _cache.remove(_cache.keys.first);
  }
}
```

**Kalau menambah cache baru: beri batas + komentar alasannya + ukuran.**

---

## 3. Pola widget yang benar

### 3.1 Jangan decode di build()

`build()` bisa jalan puluhan kali per detik. Decode/IO tidak boleh di sini.

```dart
// ❌ decode di build → jank tiap rebuild
Widget build(...) => Image.memory(base64Decode(widget.b64));

// ✅ decode sekali (initState / cache), simpan hasilnya
Uint8List? _bytes;
void initState() { _bytes = _cache[src] ?? _decode(src); }
Widget build(...) => Image.memory(_bytes!, cacheWidth: 96);
```

Butuh decode besar saat scroll? Pakai `compute()` (isolate) supaya UI thread
tidak terblok — contoh: `online_users_screen._decodeAvatarB64Iso`.

### 3.2 Instance ImageProvider stabil per-id (anti-kedip + cache hit)

Kalau `Image.memory(MemoryImage(bytes))` dibuat ulang tiap build, `ImageCache`
menganggapnya gambar **baru** (identity beda) → decode ulang + kedip. Simpan
instance per-uid:

```dart
final Map<String, ImageProvider> _imageByUid = {};
_provider = _imageByUid.putIfAbsent(
  uid,
  () => ResizeImage(MemoryImage(bytes), width: 96), // instance STABIL
);
```

Verifikasi: `image_cap_widgets_test.dart`, `PERFORMANCE.md` §16.

### 3.3 `gaplessPlayback: true` untuk foto yang berganti

Supaya tidak blank putih saat gambar baru di-decode.

### 3.4 TickerMode untuk animasi di halaman tersembunyi

Animasi `repeat()` (`AnimationController`) di tab yang tidak aktif **terus
minta frame** → compositor tak pernah idle → semua tab berat. ChatYuk
mematikan animasi halaman non-aktif via `TickerMode(enabled: tab == i)`
(lihat `app.dart` `_MainNav`). Jangan hapus.

---

## 4. Layar & tab

- **Lazy build:** halaman tab hanya dibangun saat pertama dikunjungi
  (`_visitedTabs`), bukan 4 sekaligus. Tab lain di-prewarm **saat idle**
  (satu per 250ms) supaya tap pertama instan tanpa membangun di frame tap.
- **TickerMode** untuk tab tersembunyi (lihat §3.4).
- **`context.select` granular**, bukan `context.watch` provider besar — hindari
  rebuild seluruh tree saat presence/ping. Lihat komentar di `_MainNav.build`.

---

## 5. Lifecycle — lepas memory saat background

Saat app di-**background**, OS gencar menuntut RAM. Bitmap yang di-hold
percuma (layar tidak terlihat) → risiko app dibunuh / lag saat resume.

```dart
// app.dart — _MainNav.didChangeAppLifecycleState
if (state == AppLifecycleState.paused) {
  PaintingBinding.instance.imageCache
    ..clear()
    ..clearLiveImages();
  // resume → gambar tampil di-decode ulang dari disk cache (murah)
}
```

**Logout / ganti akun** juga WAJIB bersihkan semua cache gambar →
`ImageCacheHygiene.clearAll()` (`lib/core/media/image_cache_hygiene.dart`),
dipanggil dari `AuthProvider.signOut()` dan setelah login Google.

---

## 6. Jangan pasang listener/timer/channel tanpa cleanup

Semua `Timer.periodic`, `StreamSubscription`, channel Supabase, dan
`AnimationController` **wajib** di-dispose. Realtime channel yang tidak
di-`removeChannel` = socket + memory bocor.

- Polling **stop saat background** (pola di `admin_*_tab`, `chat_service_*`).
- Channel: `onCancel = () => _sb.removeChannel(channel)`.

---

## 7. Cara mengukur (adb)

```bash
# HP (wireless debugging): adb pair <ip:port> <kode> lalu adb connect <ip:port>

# Memory runtime
adb shell cat /proc/$(adb shell pidof com.chatyuk.chatyuk)/status | grep -E 'VmRSS|VmSwap'
adb shell dumpsys meminfo com.chatyuk.chatyuk   # Native Heap = bitmap

# Jank frame (layer name berubah tiap app dibuka — cari dulu)
adb shell dumpsys SurfaceFlinger --list | grep chatyuk
adb shell dumpsys SurfaceFlinger --latency-clear '<nama-layer>'
# ...pindah tab / scroll...
adb shell dumpsys SurfaceFlinger --latency '<nama-layer>'
```

> `dumpsys gfxinfo` **TIDAK** bisa dipakai untuk Flutter (pipeline Skia/
> Vulkan, bukan HWUI) — selalu `SurfaceFlinger --latency`.

**Target:** VmRSS idle < ~350 MB, tidak spike >500 MB saat pindah tab.

---

## 8. Checklist PR (sebelum merge)

- [ ] Semua `Image.memory` baru punya `cacheWidth` / `ResizeImage` (kecuali
      viewer full-screen, yang lalu **di-evict** saat tutup).
- [ ] Cache baru punya batas ukuran + komentar.
- [ ] Tidak ada decode/IO di `build()`.
- [ ] Timer/subscription/channel/controller di-dispose.
- [ ] Animasi di halaman tersembunyi dibungkus `TickerMode`.
- [ ] `ImageProvider` per-id stabil (anti-kedip) untuk list.
- [ ] Uji di HP: idle VmRSS wajar, spike saat pindah tab <500 MB.

---

## 9. Riwayat insiden memory (peta cepat)

| Tanggal | Gejala | Akar | Fix |
|---|---|---|---|
| 2026-09-26 | 864MB→225MB | foto chat full-res semua bubble + viewer | `cacheWidth` + evict (§13) |
| 2026-09-26 | celah bitmap sisa | 4 `Image.memory` tanpa cap | cap + hygiene logout (§14) |
| 2026-10-02 | lag pindah tab, spike 765MB | avatar list online full-res (40px decode 1080px) | `ResizeImage` 96 + trim background (§23) |
| 2026-10-02 | audit menyeluruh (23 file) | 1 titik: story neighbor tanpa cap | `cacheWidth: 720` (§24); admin bersih |

**Pola berulang:** `Image.memory` tanpa cap di permukaan persisten. Kalau
menemukan lagi, langsung cap sesuai ukuran tampil.

---

## 4. Arena allocator (bukan bitmap) — diagnosis "RSS besar padahal cache bounded"

Kalau user lapor "masih ngelag / RSS besar", **jangan langsung tuduh bitmap**.
Ukur dulu (`dumpsys meminfo` + `/proc/PID/status`). Ciri **arena bloat
allocator** (jemalloc/scudo), bukan leak:

| Sinyal | Arti |
|---|---|
| `Native Heap` **Free >> Alloc** (mis. Size 531MB / Alloc 49MB / Free 477MB) | arena direservasi besar, isinya kosong |
| `Bitmap (malloced)` kecil (mis. 5MB) | bitmap Android BUKAN biang |
| `RssAnon` tinggi tapi Native Heap tracked kecil | anonymous malloc arena (di luar heap dilacak) |
| `am send-trim-memory COMPLETE` → RSS **tidak turun** | arena tidak responsif thd evict/GC Dart |
| RSS naik saat scroll list gambar, turun saat idle | arena fragmentasi akibat alokasi-decak byte besar |

**Penyebab:** alokasi `ByteArray`/base64 besar berulang yang menyeberang
MethodChannel (decode/encode gambar). jemalloc Android menahan arena dan
**hanya** mengembalikannya ke OS via `malloc_trim()`/`mallctl(purge)` (JNI).

**Yang TIDAK menolong:** `imageCache.evict`, `clearLiveImages`, `System.gc()`,
`am send-trim-memory`. Sudah diuji — RSS tidak berubah.

**Yang menolong:** kurangi volume alokasi besar di channel (kirim thumb, bukan
gambar penuh), atau panggil `malloc_trim(0)` native di `onTrimMemory`.

**Aturan ukur:** `RssAnon` ≈ `RssFile` + heap? Kalau `RssAnon >> Native Heap
tracked` → arena allocator, bukan objek app.
