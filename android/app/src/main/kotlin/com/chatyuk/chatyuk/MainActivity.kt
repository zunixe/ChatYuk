package com.chatyuk.chatyuk

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
import android.content.Intent

class MainActivity : FlutterActivity() {
    private val channel = "com.chatyuk.chatyuk/window"
    private val callUiChannel = "com.chatyuk.chatyuk/call_ui"
    private var bootOverlay: FrameLayout? = null
    private var wasSecureAtPause = false
    private var callUiBridge: CallUiBridge? = null
    private val mainHandler = android.os.Handler(android.os.Looper.getMainLooper())

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Android 15 (SDK 35+) memaksa edge-to-edge; targetSdk 36 tidak bisa
        // opt-out. Mode eksplisit + kompat-mundur: setDecorFitsSystemWindows
        // (false) membuat konten menggambar di bawah status/nav bar.
        // Flutter menangani inset via Scaffold/SafeArea/MediaQuery.
        // (enableEdgeToEdge() androidx.activity setara — dipakai WindowCompat
        //  agar tidak bergantung versi runtime androidx.activity.)
        WindowCompat.setDecorFitsSystemWindows(window, false)

        // Anti-blink: task snapshot HyperOS bisa STALE terang (force-stop tidak
        // refresh snapshot) dan renderer Skia-GL sempat present frame abu
        // (#b6b6b6) saat konten berat first-paint. Overlay gelap menutup
        // keduanya, di-fade-out setelah Dart sinyal konten siap, fallback 6s.
        if (savedInstanceState == null) {
            val overlay = FrameLayout(this)
            // Splash branded: pakai launch_background PERSIS (layer-list
            // bg gelap + logo 120dp tengah) — identik dengan system splash
            // sebelumnya, jadi cold start menyatu: splash system → overlay
            // (logo sama) → konten. Tidak ada lagi layar hitam polos.
            overlay.setBackgroundResource(R.drawable.launch_background)
            overlay.isClickable = true
            window.addContentView(overlay, FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            ))
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

        handleCallIntent(intent)
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
