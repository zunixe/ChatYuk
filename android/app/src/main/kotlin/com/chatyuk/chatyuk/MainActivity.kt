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

class MainActivity : FlutterActivity() {
    private val channel = "com.chatyuk.chatyuk/window"
    private var bootOverlay: FrameLayout? = null
    private var wasSecureAtPause = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Android 15 (SDK 35)+ edge-to-edge default. Flutter menangani inset
        // via Scaffold/SafeArea/MediaQuery — tidak perlu enableEdgeToEdge()
        // eksplisit (FlutterActivity sudah melakukannya, dan androidx.activity
        // versi runtime gagal resolve extension ini → build gagal).
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
    }
}
