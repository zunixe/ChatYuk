package com.chatyuk.chatyuk

import android.media.MediaDrm
import android.os.Bundle
import android.provider.Settings
import android.view.WindowManager
import android.widget.FrameLayout
import android.view.animation.DecelerateInterpolator
import androidx.core.view.WindowCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.chatyuk.chatyuk.call.CallConnection
import com.chatyuk.chatyuk.call.CallUiBridge
import com.chatyuk.chatyuk.image.ImageBridge
import com.chatyuk.chatyuk.crypto.CryptoBridge
import android.content.Intent

class MainActivity : FlutterActivity() {
    private val channel = "com.chatyuk.chatyuk/window"
    private val callUiChannel = "com.chatyuk.chatyuk/call_ui"
    private val updateChannel = "com.chatyuk.chatyuk/update"
    private val imageChannel = "com.chatyuk.chatyuk/image"
    private val cryptoChannel = "com.chatyuk.chatyuk/crypto"
    private val tiktokChannel = TikTokBridge.CHANNEL
    private var bootOverlay: FrameLayout? = null
    private var wasSecureAtPause = false
    private var callUiBridge: CallUiBridge? = null
    private var tiktokBridge: TikTokBridge? = null
    private var imageBridge: ImageBridge? = null
    private val mainHandler = android.os.Handler(android.os.Looper.getMainLooper())

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Android 15 (SDK 35+) memaksa edge-to-edge; targetSdk 36 tidak bisa
        // opt-out. Mode eksplisit + kompat-mundur: setDecorFitsSystemWindows
        // (false) membuat konten menggambar di bawah status/nav bar.
        // Ini padanan backward-compatible dari enableEdgeToEdge() yang
        // disarankan Play (berlaku mundur ke API lama via androidx.core).
        // Flutter menangani inset via Scaffold/SafeArea/MediaQuery.
        // (enableEdgeToEdge() androidx.activity setara — dipakai WindowCompat
        //  agar tidak bergantung versi runtime androidx.activity.)
        WindowCompat.setDecorFitsSystemWindows(window, false)

        // ── Refresh rate: JANGAN dikunci di sini ──────────────────────────
        // Awalnya dicoba set preferredDisplayModeId=3 (60 Hz) untuk mengunci
        // refresh rate. TERBUKTI TIDAK MENOLONG: stall tetap terjadi. Akar
        // masalah dari log MIUI SurfaceFlinger (Xiaomi 24129PN74G):
        //   MI-SF: isTpIdleScene, mAverageFrameRate is 0
        //   MI-SF: setTpIdleFps choose FPS:60
        //   DisplayModeController: Idle status skip setActiveMode,
        //                          isDdicIdleMode: 1
        // → MIUI mendeteksi "idle scene" (tak ada frame) lalu mematikan
        //   driver display (DDIC idle mode). Saat frame berikutnya datang,
        //   panel butuh ~165ms untuk bangun → frame tertahan 181ms
        //   (framestats: Vsync melompat +181ms, ui_work=0ms = UI thread
        //   TIDAK sibuk, jadi bukan kode Dart).
        // Ini optimasi MIUI di level sistem; mengunci mode display tidak
        // mencegahnya. Biarkan sistem mengatur refresh rate sendiri.

        // Anti-blink: task snapshot HyperOS bisa STALE terang (force-stop tidak
        // refresh snapshot) dan renderer Skia-GL sempat present frame abu
        // (#b6b6b6) saat konten berat first-paint. Overlay gelap menutup
        // keduanya, di-fade-out setelah Dart sinyal konten siap, fallback 6s.
        if (savedInstanceState == null) {
            val overlay = FrameLayout(this)
            // Splash branded: launch_background PERSIS (layer-list bg gelap +
            // logo 120dp tengah) — identik dengan system splash sebelumnya,
            // jadi cold start menyatu: splash system → overlay → konten.
            // TAMBAHAN: strip bawah setinggi sistem nav bar diwarnai warna
            // FOOTER (nav_bg = bgCard #1E1E1E). Pada edge-to-edge Android 15+
            // atribut theme `navigationBarColor` DIABAIKAN, sehingga nav bar
            // menampilkan apa yang digambar app di belakangnya — tanpa strip
            // ini area nav tampil #121212 (screen) lalu berubah ke #1E1E1E
            // (footer) = terlihat blink. Sekarang langsung warna footer.
            val bg = getDrawable(R.drawable.launch_background)
            val navStrip = android.graphics.drawable.ColorDrawable(
                androidx.core.content.ContextCompat.getColor(this, R.color.nav_bg)
            )
            val layers = android.graphics.drawable.LayerDrawable(arrayOf(bg, navStrip))
            overlay.background = layers
            overlay.isClickable = true
            // Tinggi nav bar HANYA diketahui setelah insets tersedia → pasang
            // listener insets, set tinggi strip saat itu. Fallback: strip
            // setinggi 0 (nav bar tak terlihat = tak masalah).
            androidx.core.view.ViewCompat.setOnApplyWindowInsetsListener(overlay) { v, insets ->
                val navH = insets.getInsets(
                    androidx.core.view.WindowInsetsCompat.Type.navigationBars()
                ).bottom
                layers.setLayerGravity(1, android.view.Gravity.BOTTOM)
                layers.setLayerHeight(1, navH)
                insets
            }
            window.addContentView(overlay, FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            ))
            androidx.core.view.ViewCompat.requestApplyInsets(overlay)
            bootOverlay = overlay
            window.decorView.postDelayed({ hideBootOverlay(false) }, 6000)
        }
    }

    // Snapshot anti-blink: FLAG_SECURE saat pause membuat task snapshot
    // (thumbnail launcher/recents) dirender GELAP oleh sistem — trik app
    // banking. Cold start berikutnya tap ikon → gelap → skeleton, bukan
    // foto konten terakhir yang terang. State secure Dart (private chat)
    // dipertahankan — hanya clear kalau memang bukan request Dart.
    override fun onPause() {
        super.onPause()
        wasSecureAtPause =
            window.attributes.flags and WindowManager.LayoutParams.FLAG_SECURE != 0
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
    }

    override fun onResume() {
        super.onResume()
        if (!wasSecureAtPause) {
            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
    }

    /**
     * Sinyal langsung dari OS saat memori menipis / app di-background.
     *
     * Arena native (jemalloc) membengkak karena decode gambar berulang dan
     * TIDAK menyusut sendiri (terukur reserved ~542MB / used ~57MB) → RSS
     * proses tinggi → GC/paging berat saat interaksi (gejala "ngelag").
     * Buang cache gambar native + kembalikan arena ke OS di sini.
     */
    override fun onTrimMemory(level: Int) {
        super.onTrimMemory(level)
        when (level) {
            android.content.ComponentCallbacks2.TRIM_MEMORY_UI_HIDDEN,
            android.content.ComponentCallbacks2.TRIM_MEMORY_BACKGROUND,
            android.content.ComponentCallbacks2.TRIM_MEMORY_MODERATE,
            android.content.ComponentCallbacks2.TRIM_MEMORY_COMPLETE,
            android.content.ComponentCallbacks2.TRIM_MEMORY_RUNNING_LOW,
            android.content.ComponentCallbacks2.TRIM_MEMORY_RUNNING_CRITICAL,
            -> imageBridge?.trim()
        }
    }

    override fun onLowMemory() {
        super.onLowMemory()
        imageBridge?.trim()
    }

    private fun hideBootOverlay(fade: Boolean) {
        val overlay = bootOverlay ?: return
        bootOverlay = null
        val parent = overlay.parent as? android.view.ViewGroup
        if (!fade || parent == null) {
            parent?.removeView(overlay)
            return
        }
        overlay.animate()
            .alpha(0f)
            .setDuration(250)
            .setInterpolator(DecelerateInterpolator())
            .withEndAction { (overlay.parent as? android.view.ViewGroup)?.removeView(overlay) }
            .start()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel).setMethodCallHandler { call, result ->
            when (call.method) {
                "hideBootOverlay" -> {
                    hideBootOverlay(true)
                    result.success(true)
                }
                "setSecure" -> {
                    window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    result.success(null)
                }
                "clearSecure" -> {
                    window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    result.success(null)
                }
                "androidId" -> {
                    // ANDROID_ID (Settings.Secure) — unik per perangkat + app-signing
                    // key, STABIL walau app di-reinstall (kecuali factory reset).
                    val id = Settings.Secure.getString(
                        contentResolver,
                        Settings.Secure.ANDROID_ID,
                    ) ?: ""
                    result.success(id)
                }
                "deviceUniqueId" -> {
                    // MediaDrm (Widevine) deviceUniqueId — stabil untuk SATU
                    // PERANGKAT FISIK tanpa bergantung app-signing key / user
                    // profile. Menutup celah ANDROID_ID yang berubah saat
                    // ganti keystore, Dual Apps, atau Second Space.
                    // Gagal (perangkat tanpa Widevine) → kembalikan "" agar
                    // Dart memakai fallback ANDROID_ID.
                    result.success(mediaDrmDeviceId())
                }
                else -> result.notImplemented()
            }
        }

        // Jembatan UI panggilan sistem (ConnectionService) — Dart memanggil
        // showIncoming/setConnected/dismiss; native memanggil kembali
        // onAccept/onDecline/onEnd.
        callUiBridge = CallUiBridge.create(
            this,
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, callUiChannel),
        )

        // Jembatan fitur update: deteksi installer package. Hanya update
        // in-app (Play Core) yang boleh dijalankan bila app di-install dari
        // Google Play (com.android.vending); selain itu popup mengarahkan
        // user ke listing Play di browser.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, updateChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInstallerPackage" -> {
                        result.success(installerPackageName())
                    }
                    else -> result.notImplemented()
                }
            }

        // Jembatan TikTok App Events (Business) SDK — init/identify/track/
        // purchase. Best-effort: semua error ditelan di bridge (pelacakan
        // iklan tidak boleh menggagalkan app).
        tiktokBridge = TikTokBridge(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, tiktokChannel)
            .setMethodCallHandler { call, result ->
                tiktokBridge?.handle(call, result) ?: result.success(false)
            }

        // Pipeline gambar native (BitmapFactory) + LRU native — decode/encode
        // avatar/thumbnail/proses-kirim foto di native heap (bukan Dart heap).
        imageBridge = ImageBridge(
            this,
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, imageChannel),
        ).also { it.attach() }

        // Kripto AES-GCM native (javax.crypto) + kunci di Android Keystore.
        CryptoBridge(
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, cryptoChannel),
        ).also { it.attach() }

        handleCallIntent(intent)
    }

    /**
     * Nama package yang meng-install app ini ("com.android.vending" = Google
     * Play). API modern getInstallSourceInfo (Android 11+), fallback ke
     * getInstallerPackageName untuk API lama. Return "" bila tidak diketahui.
     */
    @Suppress("DEPRECATION")
    private fun installerPackageName(): String {
        return try {
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.R) {
                packageManager.getInstallSourceInfo(packageName)
                    .installingPackageName ?: ""
            } else {
                packageManager.getInstallerPackageName(packageName) ?: ""
            }
        } catch (e: Exception) {
            android.util.Log.w("ChatYukUpdate", "installerPackageName gagal: $e")
            ""
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleCallIntent(intent)
    }

    override fun onDestroy() {
        callUiBridge?.detach()
        callUiBridge = null
        super.onDestroy()
    }

    /**
     * MediaDrm (Widevine) deviceUniqueId — ID perangkat FISIK.
     *
     * Stabil meski app di-reinstall / ganti signing key / dibuka dari user
     * profile (Second Space, Dual Apps) — inilah yang membedakannya dari
     * ANDROID_ID yang di-scope ke (device + user + signing key).
     *
     * Return "" bila Widevine tidak tersedia (sebagian HP murah) atau gagal
     * — pemanggil memakai fallback ANDROID_ID.
     */
    private fun mediaDrmDeviceId(): String {
        var drm: MediaDrm? = null
        return try {
            val widevine = java.util.UUID(-0x121074568629b532L, -0x5c37d8232ae2de13L)
            drm = MediaDrm(widevine)
            val bytes = drm.getPropertyByteArray(MediaDrm.PROPERTY_DEVICE_UNIQUE_ID)
            // Byte array → hex (stabil & aman disimpan).
            val hex = StringBuilder(bytes.size * 2)
            for (b in bytes) hex.append(String.format("%02x", b))
            hex.toString()
        } catch (e: Exception) {
            android.util.Log.w("ChatYukDevice", "mediaDrmDeviceId gagal: $e")
            ""
        } finally {
            try { drm?.close() } catch (_: Exception) {}
        }
    }

    /**
     * Aksi dari system call UI saat app baru dibuka (killed state): teruskan
     * ke Dart lewat channel call_ui supaya memakai jalur yang sama dengan
     * app hidup. Intent extra dibaca sekali (di-clear agar tidak diproses
     * ulang saat activity di-resume).
     */
    private fun handleCallIntent(intent: Intent?) {
        val action = intent?.getStringExtra(CallConnection.EXTRA_CALL_ACTION) ?: return
        val callId = intent.getStringExtra(CallConnection.EXTRA_CALL_ID) ?: ""
        intent.removeExtra(CallConnection.EXTRA_CALL_ACTION)
        intent.removeExtra(CallConnection.EXTRA_CALL_ID)
        if (callId.isEmpty()) return
        // Diproses Dart setelah engine siap.
        mainHandler.postDelayed({
            callUiBridge?.deliverToDart(action, callId)
        }, 600)
    }

}
