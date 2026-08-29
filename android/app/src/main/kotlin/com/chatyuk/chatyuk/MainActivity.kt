package com.chatyuk.chatyuk

import android.os.Bundle
import android.provider.Settings
import android.view.WindowManager
import androidx.core.view.WindowCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channel = "com.chatyuk.chatyuk/window"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Android 15 (SDK 35) edge-to-edge default — biarkan Flutter handle inset
        // via Scaffold + SafeArea. WindowCompat false agar tidak enforce non-edge.
        WindowCompat.setDecorFitsSystemWindows(window, false)
        // Anti-screenshot TIDAK diaktifkan di sini.
        // Kontrol flag secure dipindah ke per-screen (lobby/entry bisa screenshot,
        // private chat & view-once diaktifkan via MethodChannel setSecure).
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel).setMethodCallHandler { call, result ->
            when (call.method) {
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
