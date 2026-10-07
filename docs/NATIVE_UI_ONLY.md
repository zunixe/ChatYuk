# Arsitektur: Flutter = UI saja (proses berat di Native)

Keputusan arah: **semua pemrosesan berat (gambar, kripto) dijalankan di NATIVE
(Kotlin)**, Flutter sekadar menyusun UI. Tiap method native punya **fallback
Dart** agar tetap jalan di unit test/PC/desktop.

## Channel MethodChannel

| Channel | File Kotlin | Isi |
|---|---|---|
| `com.chatyuk.chatyuk/image` | `image/ImageBridge.kt`, `image/ForensicWatermark.kt` | decode/encode/resize gambar + watermark |
| `com.chatyuk.chatyuk/crypto` | `crypto/CryptoBridge.kt` | AES-256-GCM + Android Keystore |
| `com.chatyuk.chatyuk/window` | `MainActivity.kt` | boot overlay, edge-to-edge |
| `com.chatyuk.chatyuk/call_ui` | `call/CallUiBridge.kt` | UI panggilan |
| `com.chatyuk.chatyuk/update` | — | update APK |
| `com.chatyuk.chatyuk/tiktok` | `TikTokBridge.kt` | attribution |

Wrapper Dart: `lib/core/media/native_image.dart` (`NativeImage`) dan
`lib/core/cache/crypto_native.dart` (`CryptoNative`) — keduanya **fallback
transparan** bila channel tak ada.

## Method native gambar (`ImageBridge.kt`)

`aspectRatio`, `decodeThumb`, `decodeAvatar`, `decodeBytes`, `decodeWithDims`,
`processJpeg`, `processViewOnce`, `detectWatermark`, `processPost`,
`processStory`, `processSquare`, `processGalleryPhoto`, `processAdminThumb`,
`aspectRatios`, `processThumbB64`, `processRawRgba`, `downscaleB64`,
`downscaleBytes`, `trim`.

## Method native kripto (`CryptoBridge.kt`)

`hasKey`, `importKey`, `encrypt`, `decrypt`, `decryptFile`, `decryptFiles`,
`encryptToFile`.

- **Format payload** (kompatibel data lama): `base64(JSON{n,c,m})` — n=nonce,
  c=ciphertext, m=tag. AES/GCM/NoPadding, tag 128-bit, kunci 256-bit.
- **Kunci**: Android Keystore (non-exportable), alias `chatyuk_msg_key_v1`.
  Migrasi: kunci lama (secure-storage) diimpor sekali via `importKey`.
- **Dua kunci** (desain): (1) AES-GCM = Keystore; (2) password SQLCipher =
  tetap dari `flutter_secure_storage` (butuh bytes exportable). Lihat
  `message_cache.dart::_getKey`.

## Fallback layer (SENGAJA tetap Dart + `package:image`)

- `lib/core/media/chat_photo_helper.dart` — implementasi Dart semua pipeline
  gambar (dipakai bila channel native tak ada).
- `lib/core/media/forensic_watermark.dart` — referensi murni watermark
  (embed + detect) untuk fallback & unit test.

`package:image` **hanya** ada di 2 file ini. **Seluruh runtime** (`lib/screens`,
`lib/widgets`, `lib/core/cache`, `lib/services`) **tidak** lagi memakainya.

## SENGAJA DIKECUALIKAN (bukan "berat", atau rewrite besar)

- **QR generate** (`qr_flutter`, 2 layar: private rooms, room members):
  hanya menggambar QR di canvas Flutter — bukan kerja CPU/bytes. QR **scan**
  sudah native (`mobile_scanner`). Tidak dipindah.
- **`flutter_map`** (peta: admin usermap, route map, location bubble/picker):
  raster tile compositing = domain render framework. Mengganti ke Google Maps
  SDK = rewrite besar (5 widget, API beda, API key, biaya) tanpa manfaat
  terukur. Tetap `flutter_map`.

## ANALISIS MEMORI (heapprofd) — lonjakan "Native Heap" saat resume

**Gejala:** buka app → HOME (background) → kembali (resume); `dumpsys meminfo
com.chatyuk.chatyuk` menunjukkan `Native Heap PSS` melonjak ~500MB lalu turun.

**Metode debug (yang BENAR):** Perfetto **heapprofd** (native heap profiler) —
`android:profileable` di build profile, config `android.heapprofd`, lalu baca
stack dengan `trace_processor_shell`. Ini melacak **setiap alokasi + stack**,
bukan menebak.

**Hasil (stack alokasi teratas saat resume):**
```
vkCreateFramebuffer ← GrVkFramebuffer::Make ← GrDirectContext::flush
  ← android::uirenderer::renderthread::CanvasContext::draw
  ← DrawFrameTask::run ← VulkanManager::finishFrame
  ← SkiaVulkanPipeline::draw  (calloc)
```
→ Sumber = **Android HWUI** (`android::uirenderer`) memakai **Skia Vulkan**
untuk meng-composite SurfaceView Flutter. **BUKAN** `libchatyuknative` / kode
image kita. (Bukti pendukung: akumulasi per-mapping didominasi
`libhwui.so`/`libflutter.so`/`libGLESv2_adreno.so`/`vulkan.adreno.so`.)

**Perbandingan (kontrol):** app **Admin** (UI beda, TANPA SurfaceView path)
**tidak** spike — mengonfirmasi penyebabnya = komposisi SurfaceView, bukan
pipeline gambar.

**Konfirmasi bukan-leak:** steady-state (idle & scroll) **datar 36-40MB**;
soak 8 siklus resume → settle **32-40MB** tiap kali (tidak naik). `Debug
.getNativeHeapAllocatedSize()` hanya ~50MB (objek hidup kecil); 500MB = halaman
**committed** arena yang harus di-purge.

**FIX (terbukti):** `mallopt(M_PURGE, 0)` / `M_PURGE_ALL` — SATU-SATUNYA cara
melepas arena (bukan `malloc_trim`/`mallctl`; **keduanya TIDAK diekspor libc
Android** — dulu `native_trim.c` pakai dlsym keduanya → SELALU no-op). Setelah
fix: `NativeImage.trim()` menurunkan **~500MB → ~37MB** tiap resume.

- `native_trim.c`: pakai `mallopt` (API 27+) via `dlsym("mallopt")`, purge
  3 pass.
- `lib/app.dart`: trim di resume pada `[0, 2s, 4s, 7s, 10s]` (puncak render
  bergeser → multi-titik) + `onTrimMemory`/`onLowMemory` (native).
- **JANGAN** pindahkan `imageCache.clear()` ke `onPause` (dulu begitu → HOME
  singkat memicu re-decode massal). Sekarang hanya saat background LAMA (≥60s).

**JANGAN diulang / misdiagnosis:**
- Lonjakan resume **BUKAN** kebocoran kode kita & **BUKAN** pipeline gambar.
- `malloc_trim`/`mallctl` **tidak ada** di libc Android → jangan dipakai.
- Mengaktifkan Impeller / mematikan toggle FLAG_SECURE **tidak** menghilangkan
  spike (sudah diuji — falsified).

## Gotcha Kotlin (jangan diulang)
- Array Kotlin: `.size` (BUKAN `.length`).
- `roundToInt()` / `cos` / `sqrt`: import `kotlin.math.*`.
- `dart:math Random` = MWC (A=0xffffda61) — replikasi WAJIB pakai `ushr`
  (unsigned), dan FNV-1a Kotlin `Int` bertanda WAJIB `and 0xFFFFFFFFL`.
- `Base64.encodeToString(..., NO_WRAP)` **tetap** memberi padding `=` (sama
  dgn Dart `base64Encode`). Jangan `withoutPadding` (Java) — bikin beda.
