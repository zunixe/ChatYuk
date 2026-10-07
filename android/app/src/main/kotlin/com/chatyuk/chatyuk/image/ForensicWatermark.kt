package com.chatyuk.chatyuk.image

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import java.io.ByteArrayOutputStream
import kotlin.math.cos
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sqrt

/**
 * Watermark forensik foto view-once — port NATIVE dari
 * `lib/core/media/forensic_watermark.dart`.
 *
 * MOTIVASI: dulu embed watermark dijalankan lewat Dart `compute()` (isolate):
 * decode + resize + DCT 2D per blok 64×64 + encode JPEG. Itu satu-satunya
 * jalur kirim foto yang masih memuat bytes besar di heap Dart. Port ke
 * native memindahkan beban itu keluar dari heap Dart (pola seperti WA).
 *
 * KOMPATIBILITAS DETECT (KRITIS):
 * Hasil embed HARUS tetap terbaca oleh `ForensicWatermark.detect` versi Dart
 * (alat ekstraksi forensik). Karena itu SEMUA parameter & urutan operasi
 * direplikasi PERSIS:
 *  - resize proporsional sisi terpanjang = [SIZE] (1200)
 *  - blok [BLOCK_SIZE] = 64, [COEFFS] = 32 koefisien low-freq (zigzag tanpa DC)
 *  - kode ±1 dari seed via FNV-1a + Fisher–Yates dgn **Dart Random** (MWC)
 *  - alpha adaptif varian: alpha * (0.5 + 0.5*min(var/400,1)), alpha = 50
 *  - DCT-II orthonormal 2D 64×64, tulis balik hanya kanal luma (Rec.601),
 *    Cb/Cr dipertahankan.
 *
 * Perbedaan float cos/sqrt antar-platform tidak masalah: DETECT memakai
 * korelasi cos-similarity + z-score antar-seed (ambang 2.0) yang tahan noise.
 */
object ForensicWatermark {
    const val SIZE = 1200
    const val BLOCK_SIZE = 64
    const val COEFFS = 32
    const val ALPHA = 50.0

    /** Posisi koefisien zigzag frekuensi rendah (tanpa DC) — sama dgn Dart. */
    private val POSITIONS: IntArray = intArrayOf(
        1, 0, 0, 1, 0, 2, 1, 1, 2, 0, 3, 0, 2, 1, 1, 2, 0, 3, 0, 4,
        1, 3, 2, 2, 3, 1, 4, 0, 5, 0, 4, 1, 3, 2, 2, 3, 1, 4, 0, 5,
        0, 6, 1, 5, 2, 4, 3, 3, 4, 2, 5, 1, 6, 0, 7, 0, 6, 1, 5, 2,
        4, 3, 3, 4,
    )

    /** FNV-1a 32-bit — sama dgn Dart `_fnv1a`. */
    private fun fnv1a(s: String): Int {
        var h = 0x811c9dc5.toInt()
        for (ch in s) {
            val c = ch.code
            h = h xor c
            h *= 0x01000193
        }
        return h
    }

    /**
     * Kode ±1 deterministik per seed (6×+1, 6×−1 di-parity, seimbang).
     * Fisher–Yates dari **Dart Random(seed)** (MWC) — direplikasi persis di
     * [dartRandomSeed] agar pola ±1 identik dengan Dart.
     */
    private fun code(seed: String): DoubleArray {
        val c = DoubleArray(COEFFS)
        val half = COEFFS / 2
        for (p in 0 until COEFFS) c[p] = if (p < half) 1.0 else -1.0
        // FNV-1a Kotlin `Int` bertanda; Dart memakai nilai UNSIGNED 32-bit.
        // WAJIB mask ke 0xFFFFFFFF sebelum di-widen, kalau tidak sign-extension
        // mengubah Thomas Wang mix → kode ±1 BEDA → detect GAGAL.
        val rng = DartRandom(fnv1a(seed).toLong() and 0xFFFFFFFFL)
        for (p in COEFFS - 1 downTo 1) {
            val j = rng.nextInt(p + 1)
            val t = c[p]; c[p] = c[j]; c[j] = t
        }
        return c
    }

    /**
     * Replikasi `dart:math` `Random(seed)` VM (Multiply-With-Carry, A=0xffffda61)
     * — supaya urutan `nextInt` identik dengan Dart (KANAL kode watermark).
     * Seed 32-bit FNV di-`_setupSeed` (Thomas Wang mix) lalu di-crank 4×.
     *
     * Catatan: Dart `int` = 64-bit bertanda yang WRAP; Kotlin `Long` identik
     * bit-per-bit (overflow wrap). WAJIB pakai `ushr` (unsigned) di tempat
     * Dart memakai `>>>`.
     */
    private class DartRandom(seed32: Long) {
        private var state: Long = setupSeed(seed32)
        init {
            repeat(4) { nextState() }
        }

        private fun nextState() {
            val a = 0xffffda61L
            val lo = state and 0xFFFFFFFFL
            val hi = state ushr 32
            state = (a * lo) + hi
        }

        /** Hanya untuk max pangkat-2 (dipakai: max ≤ 32). */
        fun nextInt(max: Int): Int {
            nextState()
            return ((state and 0xFFFFFFFFL) and (max.toLong() - 1L)).toInt()
        }

        private fun setupSeed(seed: Long): Long {
            var n = seed
            n = n.inv() + (n shl 21)
            n = n xor (n ushr 24)
            n *= 265
            n = n xor (n ushr 14)
            n *= 21
            n = n xor (n ushr 28)
            n += (n shl 31)
            if (n == 0L) n = 0x5a17
            return n
        }
    }

    // ── DCT-II orthonormal (cos table di-cache) ─────────────────
    // Precompute COS[k][i] untuk n = BLOCK_SIZE.
    private val cosTable: Array<DoubleArray> = Array(BLOCK_SIZE) { k ->
        DoubleArray(BLOCK_SIZE) { i ->
            cos((Math.PI * (2 * i + 1) * k) / (2.0 * BLOCK_SIZE))
        }
    }

    private val scale = sqrt(2.0 / BLOCK_SIZE)

    private fun dct1d(x: DoubleArray): DoubleArray {
        val n = x.size
        val out = DoubleArray(n)
        for (k in 0 until n) {
            var sum = 0.0
            for (i in 0 until n) sum += x[i] * cosTable[k][i]
            out[k] = (if (k == 0) scale / sqrt(2.0) else scale) * sum
        }
        return out
    }

    private fun idct1d(y: DoubleArray): DoubleArray {
        val n = y.size
        val out = DoubleArray(n)
        for (i in 0 until n) {
            var sum = 0.0
            for (k in 0 until n) {
                val ck = if (k == 0) scale / sqrt(2.0) else scale
                sum += ck * y[k] * cosTable[k][i]
            }
            out[i] = sum
        }
        return out
    }

    /** Transform 2D separabel (baris lalu kolom) memakai [axis]. */
    private fun transform2d(block: DoubleArray, axis: (DoubleArray) -> DoubleArray): DoubleArray {
        val n = BLOCK_SIZE
        val tmp = DoubleArray(n * n)
        val row = DoubleArray(n)
        for (r in 0 until n) {
            for (c in 0 until n) row[c] = block[r * n + c]
            val d = axis(row)
            for (c in 0 until n) tmp[r * n + c] = d[c]
        }
        val out = DoubleArray(n * n)
        val col = DoubleArray(n)
        for (c in 0 until n) {
            for (r in 0 until n) col[r] = tmp[r * n + c]
            val d = axis(col)
            for (r in 0 until n) out[r * n + c] = d[r]
        }
        return out
    }

    /** Decode 16-bit luminance (luma utuh di-cache) untuk 1 sub-blok. */
    private fun luma(r: Int, g: Int, b: Int): Double = 0.299 * r + 0.587 * g + 0.114 * b

    private fun blockVariance(block: DoubleArray): Double {
        var mean = 0.0
        for (v in block) mean += v
        mean /= block.size
        var varSum = 0.0
        for (v in block) { val d = v - mean; varSum += d * d }
        return varSum / block.size
    }

    /**
     * Embed watermark ke bytes gambar → JPEG base64 (NO_WRAP), atau null bila
     * bytes tak bisa didecode. `seed` = uid penerima.
     */
    fun embedToBase64(bytes: ByteArray?, seed: String): ByteArray? {
        if (bytes == null || bytes.isEmpty()) return null
        val decoded = decodeSafe(bytes) ?: return null
        val resized = resizeMaxSide(decoded, SIZE)
        return try {
            embedInto(resized, seed)
            val out = ByteArrayOutputStream()
            val ok = resized.compress(Bitmap.CompressFormat.JPEG, 82, out)
            if (resized !== decoded) resized.recycle()
            decoded.recycle()
            if (ok) out.toByteArray() else null
        } catch (t: Throwable) {
            if (resized !== decoded) runCatching { resized.recycle() }
            runCatching { decoded.recycle() }
            null
        }
    }

    private fun decodeSafe(bytes: ByteArray): Bitmap? = try {
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
    } catch (_: Throwable) {
        null
    }

    private fun resizeMaxSide(src: Bitmap, maxSide: Int): Bitmap {
        val w = src.width
        val h = src.height
        if (w <= maxSide && h <= maxSide) return src
        val s = maxSide.toDouble() / maxOf(w, h)
        val nw = (w * s).roundToInt().coerceAtLeast(1)
        val nh = (h * s).roundToInt().coerceAtLeast(1)
        return Bitmap.createScaledBitmap(src, nw, nh, true)
    }

    private fun embedInto(im: Bitmap, seed: String) {
        val n = BLOCK_SIZE
        val w = im.width
        val h = im.height
        val gridX = w / n
        val gridY = h / n
        if (gridX == 0 || gridY == 0) return

        // Salin piksel & hitung luma + Cb/Cr sekali (hemat getPixel berulang).
        val px = IntArray(w * h)
        im.getPixels(px, 0, w, 0, 0, w, h)
        val y = DoubleArray(w * h)
        for (idx in px.indices) {
            val p = px[idx]
            val r = (p shr 16) and 0xFF
            val g = (p shr 8) and 0xFF
            val b = p and 0xFF
            y[idx] = luma(r, g, b)
        }

        val code = code(seed)
        val block = DoubleArray(n * n)
        for (by in 0 until gridY) {
            for (bx in 0 until gridX) {
                for (i in 0 until n) {
                    val src = (by * n + i) * w + bx * n
                    for (j in 0 until n) block[i * n + j] = y[src + j]
                }
                val dct = transform2d(block, ::dct1d)
                val varb = blockVariance(block)
                val alphaB = ALPHA * (0.5 + 0.5 * min(varb / 400.0, 1.0))
                for (p in 0 until COEFFS) {
                    val r = POSITIONS[p * 2]
                    val c = POSITIONS[p * 2 + 1]
                    dct[r * n + c] += alphaB * code[p]
                }
                val back = transform2d(dct, ::idct1d)
                for (i in 0 until n) {
                    val dst = (by * n + i) * w + bx * n
                    for (j in 0 until n) y[dst + j] = back[i * n + j]
                }
            }
        }

        // Tulis balik Y, pertahankan Cb/Cr (warna tak berubah).
        for (idx in px.indices) {
            val p = px[idx]
            val r0 = (p shr 16) and 0xFF
            val g0 = (p shr 8) and 0xFF
            val b0 = p and 0xFF
            val l0 = luma(r0, g0, b0)
            val cb = (b0 - l0) * 0.564 + 128.0
            val cr = (r0 - l0) * 0.713 + 128.0
            val ny = y[idx].roundToInt().coerceIn(0, 255)
            val rr = (ny + 1.402 * (cr - 128.0)).roundToInt().coerceIn(0, 255)
            val gg = (ny - 0.344136 * (cb - 128.0) - 0.714136 * (cr - 128.0))
                .roundToInt().coerceIn(0, 255)
            val bb = (ny + 1.772 * (cb - 128.0)).roundToInt().coerceIn(0, 255)
            px[idx] = (0xFF shl 24) or (rr shl 16) or (gg shl 8) or bb
        }
        im.setPixels(px, 0, w, 0, 0, w, h)
    }

    /** Untuk test: kode ±1 seed (paritas dgn Dart `_code`). */
    internal fun codeForTest(seed: String): IntArray = code(seed).map { it.toInt() }.toIntArray()
}
