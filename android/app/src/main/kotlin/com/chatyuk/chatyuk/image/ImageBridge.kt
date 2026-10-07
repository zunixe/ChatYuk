package com.chatyuk.chatyuk.image

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Handler
import android.os.Looper
import android.util.Base64
import android.util.LruCache
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors
import kotlin.math.roundToInt

/**
 * Jembatan MethodChannel `com.chatyuk.chatyuk/image` — pipeline gambar di
 * NATIVE (BitmapFactory) alih-alih Dart `package:image` di isolate.
 *
 * Motivasi (ukur di HP 2026-10-07): engine Flutter memakai native/Dart arena
 * yang membengkak (reserved ~541MB, used ~55MB) karena banyaknya string
 * base64 + bytes hidup di heap Dart dan disalin lintas isolate → proses
 * ter-swap → "ngetik freeze". Memindah decode/encode (dan bytes) ke native +
 * LRU native membuat data besar TIDAK hidup di heap Dart (pola seperti WA).
 *
 * Kontrak (semua async di background executor; hasil dikirim ke main thread):
 *  - `aspectRatio(base64)`                 → {"w":Int,"h":Int}?  (header saja)
 *  - `decodeThumb(base64,maxPx,quality)`   → ByteArray (JPEG thumb)  / null
 *  - `decodeBytes(base64)`                 → ByteArray (PNG re-encode, bytes gambar utuh) / null
 *  - `decodeAvatar(base64,maxPx)`          → ByteArray (JPEG thumb) / null
 *  - `processJpeg(bytes,maxPx,quality)`    → String base64 (resize+JPEG) / null
 *  - `processViewOnce(bytes,seed)`         → String base64 (watermark+JPEG) / null
 *  - `detectWatermark(bytes,candidates,threshold)` → List<{seed,rho,z,matched}>
 *  - `processPost(bytes,maxW,quality)`     → {bytes,w,h} (resize lebar tetap) / null
 *  - `processStory(bytes,maxPx,quality)`   → String base64 (resize 1-sumbu) / null
 *  - `processSquare(bytes,size,quality)`   → String base64 (crop-stretch persegi) / null
 *  - `processGalleryPhoto(bytes,...)`      → {full,preview} base64 (galeri+blur) / null
 *  - `processAdminThumb(bytes,maxW,quality)` → String base64 (thumb lebar) / null
 *  - `aspectRatios(list)`                  → List<double?> (w/h header-only)
 *  - `processThumbB64(base64,maxW,quality)` → String base64 (thumb lebar) / null
 *  - `processRawRgba(bytes,w,h,quality)`   → ByteArray JPEG / null
 *  - `downscaleB64(base64,targetWidth,quality)` → String base64 / null
 *  - `downscaleBytes(bytes,targetWidth,quality)` → ByteArray JPEG / null
 *
 * Dart WAJIB punya fallback (channel tak ada di unit test/PC) — lihat
 * `lib/core/media/native_image.dart`.
 */
class ImageBridge(context: android.content.Context, private val channel: MethodChannel) {
    private val main = Handler(Looper.getMainLooper())
    private val io = Executors.newFixedThreadPool(2)

    // LRU native: bytes gambar terakhir (avatar/thumb) tetap di native heap,
    // bukan di Dart heap. ~24MB cukup untuk viewport list + cache avatar.
    private val cache = object : LruCache<String, ByteArray>(24 * 1024 * 1024) {
        override fun sizeOf(key: String, value: ByteArray): Int = value.size
    }

    fun attach() {
        channel.setMethodCallHandler { call, result -> handle(call, result) }
    }

    /**
     * Lepaskan byte gambar native + minta allocator mengembalikan arena ke OS.
     *
     * Kenapa perlu: alokasi `ByteArray` (base64/decoded) besar dan berulang
     * bikin arena native (jemalloc/scudo) membengkak — terukur reserved
     * ~542MB padahal used cuma ~57MB, Free ~481MB. Android TIDAK otomatis
     * mengembalikan arena ke OS, sehingga RSS proses tetap tinggi walau isi
     * heap sudah nyaris kosong (§23/§24 PERFORMANCE.md). Dipanggil saat
     * app di-background (`onTrimMemory`/`onLowMemory`) sehingga gambar yang
     * tak terlihat tak menahan RAM; saat resume gambar di-decode ulang dari
     * disk (murah).
     */
    fun trim() {
        io.execute {
            try {
                cache.evictAll()
            } catch (_: Throwable) {
            }
            // Kembalikan arena allocator native ke OS. TERVERIFIKASI heapprofd:
            // lonjakan "Native Heap" saat resume = buffer render Android (HWUI
            // Skia-Vulkan `vkCreateFramebuffer` via android::uirenderer) yang
            // dicommit ke arena, BUKAN kode image kita (lihat
            // docs/NATIVE_UI_ONLY.md). `mallopt(M_PURGE)` melepas halaman
            // free-committed → PSS turun ~500MB → ~37MB (terukur, stabil tiap
            // siklus resume). Purge beberapa kali: jemalloc butuh >1 pass.
            if (nativeLibLoaded) {
                for (pass in 0 until 3) {
                    runCatching { nativeTrim() }
                }
            }
            runCatching { System.gc() }
        }
    }

    /** Ukuran arena native (Debug.getNativeHeapSize) — untuk verifikasi trim. */
    @Suppress("unused")
    private fun debugNativeHeapSize(): Long =
        try { android.os.Debug.getNativeHeapSize() } catch (_: Throwable) { -1L }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        val method = call.method
        io.execute {
            try {
                when (method) {
                    "trim" -> {
                        // Dart meminta buang cache native + kembalikan arena
                        // (dipanggil saat app di-background). Already async.
                        trim()
                        main.post { result.success(true) }
                    }
                    "aspectRatio" -> {
                        val b64 = call.argument<String>("base64") ?: ""
                        val dims = aspectRatio(decodeBase64(b64))
                        main.post { result.success(dims) }
                    }
                    "decodeThumb" -> {
                        val b64 = call.argument<String>("base64") ?: ""
                        val maxPx = call.argument<Int>("maxPx") ?: 256
                        val quality = call.argument<Int>("quality") ?: 80
                        val key = "t:$maxPx:$quality:${b64.hashCode()}"
                        val bytes = cache.get(key) ?: thumb(decodeBase64(b64), maxPx, quality)?.also {
                            cache.put(key, it)
                        }
                        main.post { result.success(bytes) }
                    }
                    "decodeAvatar" -> {
                        val b64 = call.argument<String>("base64") ?: ""
                        val maxPx = call.argument<Int>("maxPx") ?: 300
                        val key = "a:$maxPx:${b64.hashCode()}"
                        val bytes = cache.get(key) ?: thumb(decodeBase64(b64), maxPx, 85)?.also {
                            cache.put(key, it)
                        }
                        main.post { result.success(bytes) }
                    }
                    "decodeBytes" -> {
                        val b64 = call.argument<String>("base64") ?: ""
                        val bytes = decodeBase64(b64)
                        main.post { result.success(bytes) }
                    }
                    "decodeWithDims" -> {
                        val b64 = call.argument<String>("base64") ?: ""
                        val bytes = decodeBase64(b64)
                        val dims = aspectRatio(bytes)
                        if (bytes == null) {
                            main.post { result.success(null) }
                        } else {
                            main.post {
                                result.success(
                                    mapOf(
                                        "bytes" to bytes,
                                        "w" to (dims?.get("w") ?: 0),
                                        "h" to (dims?.get("h") ?: 0),
                                    )
                                )
                            }
                        }
                    }
                    "processJpeg" -> {
                        val raw = call.argument<ByteArray>("bytes")
                        val maxPx = call.argument<Int>("maxPx") ?: 800
                        val quality = call.argument<Int>("quality") ?: 75
                        val out = processJpeg(raw, maxPx, quality)
                        main.post { result.success(out) }
                    }
                    "processViewOnce" -> {
                        val raw = call.argument<ByteArray>("bytes")
                        val seed = call.argument<String>("seed") ?: ""
                        val bmp = ForensicWatermark.embed(raw, seed)
                        val out = bmp?.let {
                            val s = encodeJpegB64(it, 82)
                            it.recycle()
                            s
                        }
                        main.post { result.success(out) }
                    }
                    "detectWatermark" -> {
                        val raw = call.argument<ByteArray>("bytes")
                        val candidates = call.argument<List<String>>("candidates") ?: emptyList()
                        val threshold = call.argument<Double>("threshold") ?: 2.0
                        val res = ForensicWatermark.detect(raw, candidates, threshold)
                        val out = res.map {
                            mapOf(
                                "seed" to it.seed,
                                "rho" to it.rho,
                                "z" to it.z,
                                "matched" to it.matched,
                            )
                        }
                        main.post { result.success(out) }
                    }
                    "processPost" -> {
                        val raw = call.argument<ByteArray>("bytes")
                        val maxW = call.argument<Int>("maxW") ?: 1080
                        val quality = call.argument<Int>("quality") ?: 78
                        val out = processPost(raw, maxW, quality)
                        main.post { result.success(out) }
                    }
                    "processStory" -> {
                        val raw = call.argument<ByteArray>("bytes")
                        val maxPx = call.argument<Int>("maxPx") ?: 1080
                        val quality = call.argument<Int>("quality") ?: 82
                        val out = processStory(raw, maxPx, quality)
                        main.post { result.success(out) }
                    }
                    "processSquare" -> {
                        val raw = call.argument<ByteArray>("bytes")
                        val size = call.argument<Int>("size") ?: 640
                        val quality = call.argument<Int>("quality") ?: 85
                        val out = processSquare(raw, size, quality)
                        main.post { result.success(out) }
                    }
                    "processGalleryPhoto" -> {
                        val raw = call.argument<ByteArray>("bytes")
                        val fullW = call.argument<Int>("fullW") ?: 600
                        val fullQ = call.argument<Int>("fullQ") ?: 82
                        val previewW = call.argument<Int>("previewW") ?: 120
                        val blur = call.argument<Int>("blur") ?: 8
                        val previewQ = call.argument<Int>("previewQ") ?: 50
                        val out = processGalleryPhoto(raw, fullW, fullQ, previewW, blur, previewQ)
                        main.post { result.success(out) }
                    }
                    "processAdminThumb" -> {
                        val raw = call.argument<ByteArray>("bytes")
                        val maxW = call.argument<Int>("maxW") ?: 512
                        val quality = call.argument<Int>("quality") ?: 70
                        val out = processAdminThumb(raw, maxW, quality)
                        main.post { result.success(out) }
                    }
                    "aspectRatios" -> {
                        val list = call.argument<List<ByteArray>>("list") ?: emptyList()
                        val out = list.map { b ->
                            val d = aspectRatio(b)
                            if (d == null) null
                            else {
                                val w = d["w"] ?: 0
                                val h = d["h"] ?: 0
                                if (w > 0 && h > 0) w.toDouble() / h.toDouble() else null
                            }
                        }
                        main.post { result.success(out) }
                    }
                    "processThumbB64" -> {
                        val b64 = call.argument<String>("base64") ?: ""
                        val maxW = call.argument<Int>("maxW") ?: 256
                        val quality = call.argument<Int>("quality") ?: 80
                        val out = processThumbB64(b64, maxW, quality)
                        main.post { result.success(out) }
                    }
                    "processRawRgba" -> {
                        val raw = call.argument<ByteArray>("bytes")
                        val w = call.argument<Int>("w") ?: 0
                        val h = call.argument<Int>("h") ?: 0
                        val quality = call.argument<Int>("quality") ?: 90
                        val out = processRawRgba(raw, w, h, quality)
                        main.post { result.success(out) }
                    }
                    "downscaleB64" -> {
                        val b64 = call.argument<String>("base64") ?: ""
                        val targetWidth = call.argument<Int>("targetWidth") ?: 0
                        val quality = call.argument<Int>("quality") ?: 75
                        val out = downscaleB64(b64, targetWidth, quality)
                        main.post { result.success(out) }
                    }
                    "downscaleBytes" -> {
                        val raw = call.argument<ByteArray>("bytes")
                        val targetWidth = call.argument<Int>("targetWidth") ?: 0
                        val quality = call.argument<Int>("quality") ?: 82
                        val out = downscaleBytes(raw, targetWidth, quality)
                        main.post { result.success(out) }
                    }
                    else -> main.post { result.notImplemented() }
                }
            } catch (t: Throwable) {
                // Jangan crash app karena gambar rusak — kembalikan null;
                // Dart fallback ke jalur `package:image` bila perlu.
                main.post { result.success(null) }
            }
        }
    }

    override fun toString(): String = "ImageBridge"

    companion object {
        /**
         * Native (JNI): `malloc_trim(0)` + jemalloc `mallctl(purge)`.
         * Lihat `src/main/cpp/native_trim.c`. Return true bila ada purge.
         */
        @JvmStatic
        external fun nativeTrim(): Boolean

        /** True bila libchatyuknative termuat (build dgn NDK). */
        var nativeLibLoaded = false
            private set

        init {
            nativeLibLoaded = try {
                System.loadLibrary("chatyuknative")
                true
            } catch (_: Throwable) {
                false
            }
        }

        /**
         * BAOS yang dipakai-ulang per-thread untuk encode JPEG.
         *
         * Motivasi (ukur 2026-10-07, docs/PERFORMANCE.md §40): chatyuk
         * reservasi arena native 536MB (Free 477MB) vs WhatsApp 83MB — akibat
         * `ByteArrayOutputStream()` baru tiap encode (default 32KB lalu
         * tumbuh 64→128→…→2MB, tiap tumbuh alokasi-decak + copy) saat scroll
         * cepat. `reset()` mengembalikan panjang tanpa melepas buffer →
         * buffer besar (mis. 2MB) dipakai lagi untuk gambar berikutnya,
         * memangkas alokasi-decak (pola pool ala WhatsApp).
         *
         * Executor IO hanya 2 thread → maksimal 2 BAOS hidup, tiap satu
         * mempertahankan kapasitas setinggi gambar terbesar yang pernah
         * di-encode di thread itu.
         */
        private val baosPool = ThreadLocal.withInitial { ReusableBaos(64 * 1024) }

        /** ByteArrayOutputStream yang mengekspos buffer internal (`buf`,
         *  `count`) agar base64 bisa di-encode TANPA `toByteArray()` copy. */
        private class ReusableBaos(size: Int) : ByteArrayOutputStream(size) {
            fun buffer(): ByteArray = buf
            fun length(): Int = count
        }

        /**
         * Encode bitmap → JPEG bytes memakai BAOS pool (thread-local).
         *
         * `toByteArray()` tetap meng-copy (buffer internal dibiarkan agar bisa
         * dipakai lagi) — copy itu tak terhindarkan karena hasilnya menyeberang
         * ke Dart. Yang dihemat: buffer internal BAOS tidak dialokasi-decak
         * berulang. Return null bila compress gagal.
         */
        private fun encodeJpeg(bmp: Bitmap, quality: Int): ByteArray? {
            val out = baosPool.get()!!
            out.reset()
            val ok = bmp.compress(
                Bitmap.CompressFormat.JPEG,
                quality.coerceIn(1, 100),
                out,
            )
            if (!ok) return null
            return out.toByteArray()
        }

        /**
         * Encode bitmap → base64 JPEG (mutasi BAOS pool, TANPA ByteArray
         * perantara). Encode base64 langsung dari buffer internal → satu
         * alokasi lebih sedikit tiap foto. Return null bila compress gagal.
         */
        private fun encodeJpegB64(bmp: Bitmap, quality: Int): String? {
            val out = baosPool.get()!!
            out.reset()
            val ok = bmp.compress(
                Bitmap.CompressFormat.JPEG,
                quality.coerceIn(1, 100),
                out,
            )
            if (!ok) return null
            return Base64.encodeToString(out.buffer(), 0, out.length(), Base64.NO_WRAP)
        }

        private fun decodeBase64(b64: String): ByteArray? = try {
            if (b64.isEmpty()) null else Base64.decode(b64, Base64.DEFAULT)
        } catch (_: Throwable) {
            null
        }

        /** Dimensi dari HEADER saja (tanpa decode penuh). */
        private fun aspectRatio(bytes: ByteArray?): Map<String, Int>? {
            if (bytes == null) return null
            return try {
                val o = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                BitmapFactory.decodeByteArray(bytes, 0, bytes.size, o)
                if (o.outWidth > 0 && o.outHeight > 0) {
                    mapOf("w" to o.outWidth, "h" to o.outHeight)
                } else null
            } catch (_: Throwable) {
                null
            }
        }

        /** Decode + downscale ke sisi terpanjang [maxPx] + JPEG [quality]. */
        private fun thumb(bytes: ByteArray?, maxPx: Int, quality: Int): ByteArray? {
            if (bytes == null) return null
            val decoded = decodeSampled(bytes, maxPx) ?: return null
            val scaled = scaleDown(decoded, maxPx)
            val out = encodeJpeg(scaled, quality)
            if (scaled !== decoded) scaled.recycle()
            decoded.recycle()
            return out
        }

        /**
         * Foto STORY: resize satu-sumbu ke [maxPx] (potret → tinggi, lanskap →
         * lebar; paritas dgn Dart `processStoryImage`) + JPEG [quality] →
         * base64. Return null bila decode gagal.
         */
        private fun processStory(bytes: ByteArray?, maxPx: Int, quality: Int): String? {
            if (bytes == null || bytes.isEmpty()) return null
            val decoded = try {
                BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
            } catch (_: Throwable) {
                null
            } ?: return null
            return try {
                val w = decoded.width
                val h = decoded.height
                if (w <= 0 || h <= 0) return null
                val isPortrait = h >= w
                val nw: Int
                val nh: Int
                if (isPortrait) {
                    nh = maxPx
                    nw = Math.round(w.toDouble() * maxPx / h).toInt().coerceAtLeast(1)
                } else {
                    nw = maxPx
                    nh = Math.round(h.toDouble() * maxPx / w).toInt().coerceAtLeast(1)
                }
                val resized = if (w == nw && h == nh) decoded
                    else Bitmap.createScaledBitmap(decoded, nw, nh, true)
                val out = encodeJpegB64(resized, quality)
                if (resized !== decoded) resized.recycle()
                decoded.recycle()
                out
            } catch (t: Throwable) {
                runCatching { decoded.recycle() }
                null
            }
        }

        /**
         * Avatar: resize KHOTBAH ke [size]x[size] (crop-stretch, NON-proporsional
         * — sumber sudah di-crop persegi oleh UI) + JPEG [quality] → base64.
         * Paritas dgn Dart `img.copyResize(width:640,height:640)`.
         */
        private fun processSquare(bytes: ByteArray?, size: Int, quality: Int): String? {
            if (bytes == null || bytes.isEmpty()) return null
            val decoded = try {
                BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
            } catch (_: Throwable) {
                null
            } ?: return null
            return try {
                val resized = if (decoded.width == size && decoded.height == size) decoded
                    else Bitmap.createScaledBitmap(decoded, size, size, true)
                val out = encodeJpegB64(resized, quality)
                if (resized !== decoded) resized.recycle()
                decoded.recycle()
                out
            } catch (t: Throwable) {
                runCatching { decoded.recycle() }
                null
            }
        }

        /**
         * Foto GALERI profil: full (lebar [fullW], q[fullQ]) + preview kecil
         * terblur ([previewW], blur radius [blur], q[previewQ]). Sumber sudah
         * di-orientasi EXIF (picker re-encode), tapi kita bake EXIF bila ada
         * supaya tak miring. Return {full, preview} base64 / null.
         */
        private fun processGalleryPhoto(
            bytes: ByteArray?,
            fullW: Int,
            fullQ: Int,
            previewW: Int,
            blur: Int,
            previewQ: Int,
        ): Map<String, String>? {
            if (bytes == null || bytes.isEmpty()) return null
            var decoded: Bitmap? = try {
                BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
            } catch (_: Throwable) {
                null
            } ?: return null
            return try {
                val oriented = applyExif(bytes, decoded!!)
                val full = scaleToWidth(oriented, fullW)
                val fullB64 = encodeB64(full, fullQ)
                var preview = scaleToWidth(oriented, previewW)
                preview = stackBlur(preview, blur)
                val previewB64 = encodeB64(preview, previewQ)
                if (preview !== oriented) preview.recycle()
                if (full !== oriented) full.recycle()
                oriented.recycle()
                if (fullB64 == null || previewB64 == null) null
                else mapOf("full" to fullB64, "preview" to previewB64)
            } catch (t: Throwable) {
                runCatching { decoded?.recycle() }
                null
            }
        }

        private fun encodeB64(bmp: Bitmap, quality: Int): String? {
            return encodeJpegB64(bmp, quality)
        }

        /** Resize ke lebar [w] (rasio dipertahankan) — paritas `copyResize(width:)`. */
        private fun scaleToWidth(src: Bitmap, w: Int): Bitmap {
            if (src.width == w) return src
            val nh = Math.round(src.height.toDouble() * w / src.width).toInt().coerceAtLeast(1)
            return Bitmap.createScaledBitmap(src, w, nh, true)
        }

        /** Putar bitmap sesuai tag orientasi EXIF (bila ada). */
        @Suppress("DEPRECATION")
        private fun applyExif(bytes: ByteArray, bmp: Bitmap): Bitmap {
            val orientation = try {
                val exif = android.media.ExifInterface(java.io.ByteArrayInputStream(bytes))
                exif.getAttributeInt(
                    android.media.ExifInterface.TAG_ORIENTATION,
                    android.media.ExifInterface.ORIENTATION_NORMAL,
                )
            } catch (_: Throwable) {
                android.media.ExifInterface.ORIENTATION_NORMAL
            }
            val m = android.graphics.Matrix()
            when (orientation) {
                android.media.ExifInterface.ORIENTATION_ROTATE_90 -> m.postRotate(90f)
                android.media.ExifInterface.ORIENTATION_ROTATE_180 -> m.postRotate(180f)
                android.media.ExifInterface.ORIENTATION_ROTATE_270 -> m.postRotate(270f)
                android.media.ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> m.postScale(-1f, 1f)
                android.media.ExifInterface.ORIENTATION_FLIP_VERTICAL -> m.postScale(1f, -1f)
                else -> return bmp
            }
            return try {
                val rotated = Bitmap.createBitmap(bmp, 0, 0, bmp.width, bmp.height, m, true)
                if (rotated != bmp) bmp.recycle()
                rotated
            } catch (_: Throwable) {
                bmp
            }
        }

        /**
         * Stack-blur (aproksimasi gaussian) — paritas kasar `img.gaussianBlur`
         * Dart. Cukup untuk teaser pratinjau. Bekerja per-kanal dgn 2 pass
         * (horizontal + vertikal) memakai running-sum box blur berulang.
         */
        private fun stackBlur(src: Bitmap, radius: Int): Bitmap {
            if (radius <= 0) return src
            val w = src.width
            val h = src.height
            if (w < 3 || h < 3) return src
            val px = IntArray(w * h)
            src.getPixels(px, 0, w, 0, 0, w, h)
            blurPass(px, w, h, radius, true)
            blurPass(px, w, h, radius, false)
            val out = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
            out.setPixels(px, 0, w, 0, 0, w, h)
            return out
        }

        private fun blurPass(px: IntArray, w: Int, h: Int, radius: Int, horizontal: Boolean) {
            val len = if (horizontal) h else w
            val span = if (horizontal) w else h
            val line = IntArray(span)
            val tmp = IntArray(span)
            for (i in 0 until len) {
                for (j in 0 until span) {
                    line[j] = if (horizontal) px[i * w + j] else px[j * w + i]
                }
                boxBlurLine(line, tmp, radius)
                for (j in 0 until span) {
                    val v = tmp[j]
                    if (horizontal) px[i * w + j] = v else px[j * w + i] = v
                }
            }
        }

        private fun boxBlurLine(line: IntArray, out: IntArray, radius: Int) {
            val n = line.size
            val r = radius.coerceAtMost(n)
            var sumA = 0L; var sumR = 0L; var sumG = 0L; var sumB = 0L
            var count = 0
            for (j in -r..r) {
                val idx = j.coerceIn(0, n - 1)
                val p = line[idx]
                sumA += (p ushr 24) and 0xFF
                sumR += (p ushr 16) and 0xFF
                sumG += (p ushr 8) and 0xFF
                sumB += p and 0xFF
                count++
            }
            for (j in 0 until n) {
                val a = (sumA / count).toInt()
                val rr = (sumR / count).toInt()
                val gg = (sumG / count).toInt()
                val bb = (sumB / count).toInt()
                out[j] = (a shl 24) or (rr shl 16) or (gg shl 8) or bb
                val addIdx = (j + r + 1).coerceIn(0, n - 1)
                val remIdx = (j - r).coerceIn(0, n - 1)
                val add = line[addIdx]
                val rem = line[remIdx]
                sumA += ((add ushr 24) and 0xFF) - ((rem ushr 24) and 0xFF)
                sumR += ((add ushr 16) and 0xFF) - ((rem ushr 16) and 0xFF)
                sumG += ((add ushr 8) and 0xFF) - ((rem ushr 8) and 0xFF)
                sumB += (add and 0xFF) - (rem and 0xFF)
            }
        }

        /**
         * Thumbnail admin (dari bytes gambar): bila lebar > [maxW] resize ke
         * [maxW] (rasio dipertahankan), lalu JPEG [quality] → base64.
         * Paritas dgn Dart `genThumbB64` (tak memperbesar bila ≤ maxW, tapi
         * tetap re-encode).
         */
        private fun processAdminThumb(bytes: ByteArray?, maxW: Int, quality: Int): String? {
            if (bytes == null || bytes.isEmpty()) return null
            val decoded = try {
                BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
            } catch (_: Throwable) {
                null
            } ?: return null
            return try {
                val w = decoded.width
                val h = decoded.height
                if (w <= 0 || h <= 0) return null
                val resized = if (w > maxW) {
                    val nh = (h.toDouble() * maxW / w).roundToInt().coerceAtLeast(1)
                    Bitmap.createScaledBitmap(decoded, maxW, nh, true)
                } else decoded
                val out = encodeJpegB64(resized, quality)
                if (resized !== decoded) resized.recycle()
                decoded.recycle()
                out
            } catch (t: Throwable) {
                runCatching { decoded.recycle() }
                null
            }
        }

        /**
         * Thumbnail dari base64: decode + resize LEBAR ke [maxW] (rasio
         * dipertahankan) + JPEG [quality] → base64. Paritas `decodeThumbB64`
         * Dart (width 256, quality 80).
         */
        private fun processThumbB64(b64: String, maxW: Int, quality: Int): String? {
            return processAdminThumb(decodeBase64(b64), maxW, quality)
        }

        /**
         * raw RGBA (dari `ui.Image.toByteData`) → JPEG [quality] → bytes.
         * Paritas `encodeRawRgbaToJpg` Dart.
         */
        private fun processRawRgba(rgba: ByteArray?, w: Int, h: Int, quality: Int): ByteArray? {
            if (rgba == null || w <= 0 || h <= 0) return null
            if (rgba.size < w * h * 4) return null
            return try {
                val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
                val px = IntArray(w * h)
                var i = 0
                var p = 0
                while (p < w * h) {
                    val r = rgba[i].toInt() and 0xFF
                    val g = rgba[i + 1].toInt() and 0xFF
                    val b = rgba[i + 2].toInt() and 0xFF
                    val a = rgba[i + 3].toInt() and 0xFF
                    px[p] = (a shl 24) or (r shl 16) or (g shl 8) or b
                    i += 4
                    p++
                }
                bmp.setPixels(px, 0, w, 0, 0, w, h)
                val out = encodeJpeg(bmp, quality)
                bmp.recycle()
                out
            } catch (_: Throwable) {
                null
            }
        }

        /**
         * Downscale base64 ke LEBAR [targetWidth] (bila lebih besar) + JPEG
         * [quality] → base64. Ganti jalur Skia `instantiateImageCodec` +
         * `img.encodeJpg` di `photo_cache`/`post_photo_cache`.
         * [targetWidth] <= 0 → tanpa resize (hanya re-encode).
         */
        private fun downscaleB64(b64: String, targetWidth: Int, quality: Int): String? {
            if (b64.isEmpty()) return null
            val srcBytes = decodeBase64(b64) ?: return null
            val out = downscaleBytes(srcBytes, targetWidth, quality) ?: return null
            return Base64.encodeToString(out, Base64.NO_WRAP)
        }

        /**
         * Downscale bytes gambar ke LEBAR [targetWidth] (bila lebih besar) +
         * JPEG [quality] → bytes. Paritas `_jpegDownscaled` (post thumb 1024).
         * [targetWidth] <= 0 → tanpa resize.
         */
        private fun downscaleBytes(bytes: ByteArray?, targetWidth: Int, quality: Int): ByteArray? {
            if (bytes == null || bytes.isEmpty()) return null
            val decoded = try {
                BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
            } catch (_: Throwable) {
                null
            } ?: return null
            return try {
                val resized = if (targetWidth > 0 && decoded.width > targetWidth) {
                    val nh = Math.round(decoded.height.toDouble() * targetWidth / decoded.width)
                        .toInt().coerceAtLeast(1)
                    Bitmap.createScaledBitmap(decoded, targetWidth, nh, true)
                } else decoded
                val out = encodeJpeg(resized, quality)
                if (resized !== decoded) resized.recycle()
                decoded.recycle()
                out
            } catch (_: Throwable) {
                runCatching { decoded.recycle() }
                null
            }
        }

        /** Decode + downscale + JPEG → base64 (jalur proses kirim). */
        private fun processJpeg(bytes: ByteArray?, maxPx: Int, quality: Int): String? {
            val jpeg = thumb(bytes, maxPx, quality) ?: return null
            return Base64.encodeToString(jpeg, Base64.NO_WRAP)
        }

        /**
         * Foto POST timeline: resize ke LEBAR tetap [maxW] (rasio dipertahankan,
         * paritas dgn Dart `img.copyResize(width: 1080)`) + JPEG [quality],
         * sekaligus kembalikan w/h hasil. Return {bytes,w,h} atau null.
         */
        private fun processPost(bytes: ByteArray?, maxW: Int, quality: Int): Map<String, Any>? {
            if (bytes == null) return null
            val decoded = try {
                BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
            } catch (_: Throwable) {
                null
            } ?: return null
            return try {
                val w = decoded.width
                val h = decoded.height
                if (w <= 0 || h <= 0) return null
                val nh = Math.round(h.toDouble() * maxW / w).toInt().coerceAtLeast(1)
                val resized = if (w == maxW) decoded else Bitmap.createScaledBitmap(decoded, maxW, nh, true)
                val out = encodeJpeg(resized, quality)
                val rw = resized.width
                val rh = resized.height
                if (resized !== decoded) resized.recycle()
                decoded.recycle()
                if (out == null) null else mapOf(
                    "bytes" to out,
                    "w" to rw,
                    "h" to rh,
                )
            } catch (t: Throwable) {
                runCatching { decoded.recycle() }
                null
            }
        }

        /** Decode dengan inSampleSize (hemat memori) tanpa memuat full-res. */
        private fun decodeSampled(bytes: ByteArray, maxPx: Int): Bitmap? {
            return try {
                val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
                var sample = 1
                val longest = maxOf(bounds.outWidth, bounds.outHeight)
                if (longest > 0) {
                    while (longest / (sample * 2) >= maxPx) sample *= 2
                }
                val opts = BitmapFactory.Options().apply {
                    inSampleSize = sample
                    inPreferredConfig = Bitmap.Config.ARGB_8888
                }
                BitmapFactory.decodeByteArray(bytes, 0, bytes.size, opts)
            } catch (_: Throwable) {
                null
            }
        }

        /** Perhalus ke tepat sisi terpanjang <= maxPx (bila masih lebih besar). */
        private fun scaleDown(src: Bitmap, maxPx: Int): Bitmap {
            val w = src.width
            val h = src.height
            val longest = maxOf(w, h)
            if (longest <= maxPx) return src
            val ratio = maxPx.toFloat() / longest
            val nw = (w * ratio).toInt().coerceAtLeast(1)
            val nh = (h * ratio).toInt().coerceAtLeast(1)
            return Bitmap.createScaledBitmap(src, nw, nh, true)
        }
    }
}
