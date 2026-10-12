# NATIVE IMAGE LIFECYCLE — ownership & zero-leak (poster video)

> Perbaikan bug lifecycle bitmap native pada pool poster video (§"NATIVE IMAGE
> LIFECYCLE SAFETY & ZERO-LEAK FIX"). 2026-10-12.

## 1. Root cause terverifikasi

| # | Masalah | Bukti |
|---|---|---|
| R1 | `_persistBitmap(path, frame.image)` menahan `frame.image` **async** (I/O disk bisa detik) → bitmap sumber tak bisa dibebaskan | Kode + regresi Native Heap 500MB+ |
| R2 | `frame.image` **tidak pernah di-dispose**; hanya `small` (hasil downscale). Saat pool di-clear, `ui.Image` **tetap hidup** karena dipegang `_persistBitmap` + bubble | Terukur: 30× buka-tutup → Native 36→517 MB |
| R3 | `codec` (`ui.instantiateImageCodec`) **tidak di-dispose** | Audit kode |
| R4 | Decode ganda key sama: entry bisa terisi oleh decode lain saat `await` → bitmap yatim (tak di-dispose, tak dipakai) | Guard `containsKey` tak ada sebelum `_putPosterImage` |
| R5 | `Completer` `decodeImageFromPixels` dapat **gantung** bila galat → future tak selesai | `_loadPersistedBitmap`/`_resizeRgba` tanpa error handler |

## 2. Ownership map

| Objek | Dibuat oleh | Pemilik (hak dispose) | Meminjam |
|---|---|---|---|
| `frame.image` | `_doDecodePoster` | pool `_posterImages` | bubble `_posterImg` (render) |
| `persisted` | `_loadPersistedBitmap` | pool | bubble |
| `small` | `_downscaleImage` | `_persistBitmap` (dispose lokal) | — |
| `codec` | `_doDecodePoster` | `_doDecodePoster` (dispose segera) | — |
| `_posterImg` | `posterImageSync` (pinjam) | pool | bubble (lepas saat dispose, tak dispose) |

**Aturan (Phase 2):**
1. Pool = pemilik tunggal `ui.Image` poster. **Dispose HANYA saat replace kunci-sama** (objek digantikan; caller kita sendiri yang menaruh). Pola sama `decodedImageCache`.
2. **Evict/clear → lepas referensi, BUKAN dispose** (entry bisa masih dirender bubble lain).
3. Bubble **hanya meminjam** → lepas `_posterImg=null` di dispose, TIDAK dispose.
4. `_persistBitmap` **tidak memiliki** `img` → tak pernah `img.dispose()`; ekstrak byte dulu.
5. `_disposeAllPosterImages` hanya saat logout (tak ada bubble aktif).

## 3. File & fungsi diubah

| File | Fungsi | Perubahan |
|---|---|---|
| `lib/widgets/video_prefetch.dart` | `_persistBitmap` | Ekstrak byte dulu; dispose HANYA `small` (miliknya); tak tahan `img` |
| | `_doDecodePoster` | Dispose `codec`; guard race (entry terisi saat await → dispose milik sendiri); pakai `_putPosterImage` |
| | `_putPosterImage` (baru) | Replace kunci-sama → dispose lama; evict → `_clearPosterImages` (lepas) |
| | `_loadPersistedBitmap` | Pakai `_decodeRgbaToImage` (completer selalu selesai) |
| | `_resizeRgba` | Validasi ukuran buffer + `_decodeRgbaToImage` |
| | `_decodeRgbaToImage` (baru) | Completer selalu selesai (try/catch) |
| | `posterImageCount`/`hasPosterImage` (baru) | Hook test |
| `lib/widgets/chat_video_bubble.dart` | `dispose` | Lepas `_posterImg`/`_poster` (tak dispose) |
| `lib/app.dart` | resume ≥60s | `VideoPrefetch.clearPosterMem()` |

## 4. Alasan dispose

| Lokasi | Alasan |
|---|---|
| `_putPosterImage` replace kunci-sama | Objek lama untuk path SAMA digantikan; kita pemilik entry itu; pengganti objek baru → aman (pola `decodedImageCache`) |
| `_persistBitmap` → `small` | Bitmap dibuat fungsi ini, dipakai sekali (ekstrak byte), lalu tak perlu |
| `_doDecodePoster` → `codec` | Codec dipakai 1 frame; tak perlu ditahan |
| `_doDecodePoster` guard race | Bitmap kita dibuat tapi entry sudah terisi decode lain → tak terpakai → dispose |

## 5. Alasan TIDAK dispose saat clear/evict

`_clearPosterImages()` (evict pool penuh / clear) hanya **lepas referensi**. Entry yang dibuang **bisa masih dirender bubble lain** (`RawImage _posterImg`). Dispose di sini = `Cannot clone a disposed image` (bug 2026-10-12 sebelumnya). Pola sama `decodedImageCache` (evict LRU tidak dispose).

## 6. `_persistBitmap` & lifetime sumber

Byte RGBA diekstrak **sebelum** I/O disk. Setelah `toByteData`, tak ada referensi ke `img` yang ditahan → bitmap sumber bebas dibebaskan owner-nya kapan saja. Persist boleh selesai setelah bubble unmount (hanya menulis file, tak menyentuh `ui.Image`).

## 7. Race yang ditutup

| Race | Penanganan |
|---|---|
| Decode ganda key sama | `_pendingDecode` dedupe + guard `containsKey` sebelum put |
| Entry terisi saat await (persisted/codec) | Cek `containsKey` → dispose milik sendiri |
| Persist selesai setelah entry diganti | Aman (byte independen) |
| Bubble unmount saat decode | `.then` guard `mounted`; bubble hanya pinjam |
| Clear saat image dipakai | Clear = lepas referensi (tidak dispose) |
| Completer gantung (galat decode) | `_decodeRgbaToImage` selalu selesai |

## 8. Test & hasil

`test/video_poster_ownership_test.dart` (7 test) — **7/7 lolos**:
decode pertama; decode ulang kunci sama (instance sama, tak menumpuk); 3 decode
bersamaan (tak dobel, handle hidup); pool dibatasi (≤ budget+1); clear → kosong;
decode bytes rusak (no crash, entry valid tetap); 50× siklus clear+decode → tetap 1.

## 9. Native memory sebelum/sesudah (HP fisik, 50× buka-tutup chat)

| | Sebelum fix | Sesudah fix |
|---|---|---|
| Native Heap | **517 MB** | **29 MB** |
| TOTAL PSS | 998 MB | 316 MB |
| Pola naik | naik tiap siklus | **stabil 28–29 MB** |
| Crash disposed | muncul | **0** |

**Terverifikasi:** 50 siklus buka-tutup → Native 42→29 MB (tidak naik);
0 `Cannot clone a disposed image`; `M_PURGE` tak lagi "menyembunyikan" leak
(menurunkan 36MB→29MB karena memang tak ada bitmap tertahan).

## 10. Risiko belum teratasi

- Uji heapprofd native detail belum dijalankan (butuh `perfetto`); bukti saat
  ini dari `dumpsys meminfo` Native Heap (bukan Dart heap) — sudah memadai
  untuk klaim "tidak naik tanpa batas".
- Skenario video SANGAT banyak (1000+) belum diuji; pool bounded 12 → aman
  secara desain.
