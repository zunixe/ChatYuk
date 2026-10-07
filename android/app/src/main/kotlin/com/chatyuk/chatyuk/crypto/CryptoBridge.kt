package com.chatyuk.chatyuk.crypto

import android.os.Handler
import android.os.Looper
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.security.KeyStore
import java.util.concurrent.Executors
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

/**
 * Jembatan MethodChannel `com.chatyuk.chatyuk/crypto` — AES-256-GCM di NATIVE
 * (`javax.crypto`) + kunci di **Android Keystore** (non-exportable).
 *
 * Motivasi: enkripsi/dekripsi cache pesan & foto sebelumnya memakai
 * `package:cryptography` (Pure-Dart) di `compute()` isolate → spawn isolate +
 * salin bytes besar ke Dart heap. Native: tanpa isolate, kunci dijaga Keystore,
 * jauh lebih cepat (terutama batch baca file foto terenkripsi).
 *
 * FORMAT KOMPATIBEL (sama persis dgn Dart lama):
 *   ciphertext = base64( JSON{ n: base64(nonce 12B), c: base64(ciphertext),
 *                              m: base64(mac/tag 16B) } )
 *   - AES/GCM/NoPadding, tag 128-bit, nonce 12 byte acak.
 *   - Kunci: 256-bit.
 *
 * KUNCI:
 *  - Diambil/dibuat di Android Keystore (alias [KEY_ALIAS]), non-exportable.
 *  - MIGRASI: bila Keystore belum punya kunci, Dart mengirim kunci lama
 *    (base64 dari flutter_secure_storage) via `importKey` → diimpor ke
 *    Keystore. Setelah itu semua enkripsi/dekripsi memakai kunci itu →
 *    data lama (dienkripsi kunci lama) TETAP terbaca.
 */
class CryptoBridge(private val channel: MethodChannel) {
    private val main = Handler(Looper.getMainLooper())
    private val io = Executors.newFixedThreadPool(2)

    fun attach() {
        channel.setMethodCallHandler { call, result -> handle(call, result) }
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        val method = call.method
        io.execute {
            try {
                when (method) {
                    "hasKey" -> main.post { result.success(hasKey()) }
                    "importKey" -> {
                        val b64 = call.argument<String>("key") ?: ""
                        main.post { result.success(importKey(b64)) }
                    }
                    "encrypt" -> {
                        val plain = call.argument<String>("plain") ?: ""
                        main.post { result.success(encrypt(plain)) }
                    }
                    "decrypt" -> {
                        val encoded = call.argument<String>("encoded") ?: ""
                        main.post { result.success(decrypt(encoded)) }
                    }
                    "decryptFile" -> {
                        val path = call.argument<String>("path") ?: ""
                        main.post { result.success(decryptFile(path)) }
                    }
                    "decryptFiles" -> {
                        val paths = call.argument<Map<String, String>>("paths") ?: emptyMap()
                        main.post { result.success(decryptFiles(paths)) }
                    }
                    "encryptToFile" -> {
                        val path = call.argument<String>("path") ?: ""
                        val plain = call.argument<String>("plain") ?: ""
                        main.post { result.success(encryptToFile(path, plain)) }
                    }
                    else -> main.post { result.notImplemented() }
                }
            } catch (t: Throwable) {
                main.post { result.success(null) }
            }
        }
    }

    override fun toString(): String = "CryptoBridge"

    companion object {
        private const val KEY_ALIAS = "chatyuk_msg_key_v1"
        private const val ANDROID_KEYSTORE = "AndroidKeyStore"
        private const val GCM_TAG_BITS = 128
        private const val NONCE_LEN = 12

        private fun keyStore(): KeyStore {
            val ks = KeyStore.getInstance(ANDROID_KEYSTORE)
            ks.load(null)
            return ks
        }

        private fun hasKey(): Boolean = try {
            keyStore().containsAlias(KEY_ALIAS)
        } catch (_: Throwable) {
            false
        }

        /**
         * Impor kunci lama (base64 32 byte) ke Keystore. Bila Keystore sudah
         * punya kunci, TIDAK menimpa (biar data lama tetap valid).
         * Return true bila kunci tersedia setelah operasi.
         */
        private fun importKey(b64: String): Boolean {
            if (hasKey()) return true
            val raw = try {
                Base64.decode(b64, Base64.DEFAULT)
            } catch (_: Throwable) {
                ByteArray(0)
            }
            return try {
                val ks = keyStore()
                if (raw.size == 32) {
                    val key = SecretKeySpec(raw, "AES")
                    ks.setEntry(
                        KEY_ALIAS,
                        KeyStore.SecretKeyEntry(key),
                        null,
                    )
                } else {
                    // Tidak ada kunci lama → buat baru di Keystore.
                    generateKey()
                }
                hasKey()
            } catch (_: Throwable) {
                false
            }
        }

        private fun generateKey(): SecretKey {
            val gen = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, ANDROID_KEYSTORE)
            val spec = KeyGenParameterSpec.Builder(
                KEY_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .setRandomizedEncryptionRequired(false)
                .build()
            gen.init(spec)
            return gen.generateKey()
        }

        private fun key(): SecretKey? {
            val ks = keyStore()
            val existing = (ks.getEntry(KEY_ALIAS, null) as? KeyStore.SecretKeyEntry)?.secretKey
            if (existing != null) return existing
            return try {
                generateKey()
            } catch (_: Throwable) {
                null
            }
        }

        private fun encrypt(plain: String): String? {
            val k = key() ?: return null
            return try {
                val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                cipher.init(Cipher.ENCRYPT_MODE, k)
                val ct = cipher.doFinal(plain.toByteArray(Charsets.UTF_8))
                val iv = cipher.iv
                val tagLen = GCM_TAG_BITS / 8
                // javax.crypto menggabungkan ciphertext+tag; pisah agar format
                // sama dgn Dart (c & m terpisah).
                val bodyLen = ct.size - tagLen
                val body = ct.copyOfRange(0, bodyLen)
                val tag = ct.copyOfRange(bodyLen, ct.size)
                val json = JSONObject()
                    .put("n", b64(iv))
                    .put("c", b64(body))
                    .put("m", b64(tag))
                b64(json.toString().toByteArray(Charsets.UTF_8))
            } catch (_: Throwable) {
                null
            }
        }

        private fun decrypt(encoded: String): String? {
            val k = key() ?: return null
            return try {
                val payload = JSONObject(String(Base64.decode(encoded, Base64.DEFAULT), Charsets.UTF_8))
                val nonce = Base64.decode(payload.getString("n"), Base64.DEFAULT)
                val body = Base64.decode(payload.getString("c"), Base64.DEFAULT)
                val mac = Base64.decode(payload.getString("m"), Base64.DEFAULT)
                val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                cipher.init(Cipher.DECRYPT_MODE, k, GCMParameterSpec(GCM_TAG_BITS, nonce))
                val ct = body + mac
                String(cipher.doFinal(ct), Charsets.UTF_8)
            } catch (_: Throwable) {
                null
            }
        }

        private fun decryptFile(path: String): String? {
            return try {
                val f = java.io.File(path)
                if (!f.exists()) return null
                decrypt(f.readText())
            } catch (_: Throwable) {
                null
            }
        }

        private fun decryptFiles(paths: Map<String, String>): Map<String, String> {
            val out = HashMap<String, String>()
            for ((key, path) in paths) {
                val clear = decryptFile(path)
                if (clear != null) out[key] = clear
            }
            return out
        }

        private fun encryptToFile(path: String, plain: String): Boolean {
            val enc = encrypt(plain) ?: return false
            return try {
                java.io.File(path).writeText(enc)
                true
            } catch (_: Throwable) {
                false
            }
        }

        private fun b64(bytes: ByteArray): String =
            Base64.encodeToString(bytes, Base64.NO_WRAP)
    }
}
