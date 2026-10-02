package com.chatyuk.chatyuk

import android.app.Application
import android.content.Context
import android.util.Log
import com.tiktok.TikTokBusinessSdk
import com.tiktok.appevents.base.EventName
import com.tiktok.appevents.contents.TTContentsEventConstants
import com.tiktok.appevents.contents.TTPurchaseEvent
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Jembatan native TikTok App Events (Business) SDK untuk Flutter.
 *
 * Flutter TIDAK punya plugin resmi untuk SDK ini, jadi dipanggil lewat
 * MethodChannel `com.chatyuk.chatyuk/tiktok` (pola sama dengan `call_ui`/
 * `update`/`window` di MainActivity).
 *
 * Inisialisasi SDK dilakukan di sini (bukan auto-init manifest) supaya
 * Access Token rahasia bisa disuntik dari BuildConfig/Dart tanpa ditulis
 * di source. App ID / TikTok App ID dibaca SDK dari AndroidManifest
 * meta-data (com.tiktok.sdk.*) — lihat AndroidManifest.xml + strings.xml.
 *
 * Semua method BEST-EFFORT: kegagalan TikTok TIDAK boleh menggagalkan app
 * (return false / null, tanpa throw ke Dart).
 */
class TikTokBridge(private val context: Context) {

    companion object {
        const val CHANNEL = "com.chatyuk.chatyuk/tiktok"
        private const val TAG = "ChatYukTikTok"
    }

    private var initialized = false

    /** Aplikasi dari Context (Activity/Application). */
    private fun app(): Application? = context.applicationContext as? Application

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "initialize" -> result.success(initialize(call))
                "identify" -> result.success(identify(call))
                "track" -> result.success(track(call))
                "purchase" -> result.success(purchase(call))
                "logout" -> result.success(logout())
                "isInitialized" -> result.success(TikTokBusinessSdk.isInitialized())
                else -> result.notImplemented()
            }
        } catch (e: Throwable) {
            // Jangan pernah melempar ke Dart — pelacakan bersifat opsional.
            Log.w(TAG, "TikTok ${call.method} error: $e")
            result.success(false)
        }
    }

    /**
     * Inisialisasi SDK. Argumen: { accessToken?: String, debug?: bool }.
     * App ID & TikTok App ID dibaca dari res/values/strings.xml
     * (tiktok_app_id / tiktok_tt_app_id) lalu di-set ke TTConfig.
     */
    private fun initialize(call: MethodCall): Boolean {
        if (TikTokBusinessSdk.isInitialized()) {
            initialized = true
            return true
        }
        val application = app() ?: return false
        val accessToken = call.argument<String>("accessToken")
        val debug = call.argument<Boolean>("debug") ?: false

        // App ID & TikTok App ID dari resources (string.xml).
        val appId = stringRes("tiktok_app_id")
        val ttAppId = stringRes("tiktok_tt_app_id")
        if (appId.isEmpty() || ttAppId.isEmpty()) {
            Log.w(TAG, "initialize: App ID / TikTok App ID kosong — dilewati")
            return false
        }

        val config = TikTokBusinessSdk.TTConfig(application)
            .setAppId(appId)
            .setTTAppId(ttAppId)
            .setLogLevel(
                if (debug) TikTokBusinessSdk.LogLevel.DEBUG
                else TikTokBusinessSdk.LogLevel.NONE
            )
        // Init ASYNC: keberhasilan dikonfirmasi lewat TTInitCallback.success().
        // Setelah sukses, baru set Access Token (updateAccessToken menolak
        // bila SDK belum initialized — lihat bytecode SDK) & mulai tracking.
        TikTokBusinessSdk.initializeSdk(config, object : TikTokBusinessSdk.TTInitCallback {
            override fun success() {
                if (!accessToken.isNullOrEmpty()) {
                    TikTokBusinessSdk.updateAccessToken(accessToken)
                }
                TikTokBusinessSdk.startTrack()
                initialized = TikTokBusinessSdk.isInitialized()
                Log.i(
                    TAG,
                    "initialize success: appId=$appId ttAppId=$ttAppId " +
                        "token=${!accessToken.isNullOrEmpty()} isInitialized=$initialized"
                )
            }

            override fun fail(code: Int, message: String?) {
                initialized = false
                Log.w(TAG, "initialize FAIL code=$code msg=$message")
            }
        })
        return true
    }

    /** Baca string resource app (mis. "tiktok_app_id") — referensi R langsung
     *  (bukan getIdentifier via refleksi) agar TIDAK di-shrink R8 di release. */
    private fun stringRes(name: String): String {
        return try {
            when (name) {
                "tiktok_app_id" -> context.getString(R.string.tiktok_app_id)
                "tiktok_tt_app_id" -> context.getString(R.string.tiktok_tt_app_id)
                else -> ""
            }
        } catch (e: Throwable) {
            ""
        }
    }

    /**
     * User-identify (external id / name / phone / email). Panggil tiap kali
     * info user berubah & setelah login/daftar. Argumen: { externalId,
     * externalUserName?, phoneNumber?, email? }.
     */
    private fun identify(call: MethodCall): Boolean {
        if (!TikTokBusinessSdk.isInitialized()) return false
        val externalId = call.argument<String>("externalId") ?: return false
        val externalUserName = call.argument<String>("externalUserName") ?: ""
        val phoneNumber = call.argument<String>("phoneNumber") ?: ""
        val email = call.argument<String>("email") ?: ""
        TikTokBusinessSdk.identify(externalId, externalUserName, phoneNumber, email)
        return true
    }

    /**
     * Event standar tanpa konten. Argumen: { event: String }.
     * Nama event = nama enum EventName (mis. "LOGIN", "REGISTRATION",
     * "GENERATE_LEAD", "RATE", "START_TRIAL", "LAUNCH_APP", dll).
     */
    private fun track(call: MethodCall): Boolean {
        if (!TikTokBusinessSdk.isInitialized()) return false
        val name = call.argument<String>("event") ?: return false
        return try {
            val eventName = EventName.valueOf(name)
            TikTokBusinessSdk.trackTTEvent(eventName)
            true
        } catch (e: IllegalArgumentException) {
            Log.w(TAG, "track: EventName tidak dikenal '$name'")
            false
        }
    }

    /**
     * Event Purchase (TTContentsEvent). Argumen: { value: double,
     * currency?: String (ISO 4217, default IDR), description?, contentId?,
     * contentType?, contentName? }.
     */
    private fun purchase(call: MethodCall): Boolean {
        if (!TikTokBusinessSdk.isInitialized()) return false
        val value = call.argument<Double>("value") ?: return false
        val currencyCode = (call.argument<String>("currency") ?: "IDR").uppercase()
        val currency = try {
            TTContentsEventConstants.Currency.valueOf(currencyCode)
        } catch (e: IllegalArgumentException) {
            TTContentsEventConstants.Currency.IDR
        }
        val builder = TTPurchaseEvent.newBuilder()
            .setValue(value)
            .setCurrency(currency)
        call.argument<String>("description")?.let { builder.setDescription(it) }
        call.argument<String>("contentId")?.let { builder.setContentId(it) }
        call.argument<String>("contentType")?.let { builder.setContentType(it) }
        TikTokBusinessSdk.trackTTEvent(builder.build())
        return true
    }

    /** Logout: bersihkan identitas user di SDK (sesuai panduan TikTok). */
    private fun logout(): Boolean {
        if (!TikTokBusinessSdk.isInitialized()) return false
        // identify("", "", "", "") = reset identitas (panduan: logout dulu,
        // lalu identify ulang saat login berikutnya).
        TikTokBusinessSdk.identify("", "", "", "")
        return true
    }
}
