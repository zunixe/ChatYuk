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

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        val method = call.method
        io.execute {
            try {
                when (method) {
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
            val out = ByteArrayOutputStream()
            val ok = scaled.compress(Bitmap.CompressFormat.JPEG, quality.coerceIn(1, 100), out)
            if (scaled !== decoded) scaled.recycle()
            decoded.recycle()
            return if (ok) out.toByteArray() else null
        }

        /** Decode + downscale + JPEG → base64 (jalur proses kirim). */
        private fun processJpeg(bytes: ByteArray?, maxPx: Int, quality: Int): String? {
            val jpeg = thumb(bytes, maxPx, quality) ?: return null
            return Base64.encodeToString(jpeg, Base64.NO_WRAP)
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
