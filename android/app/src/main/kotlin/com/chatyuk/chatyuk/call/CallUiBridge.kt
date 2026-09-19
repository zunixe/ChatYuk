package com.chatyuk.chatyuk.call

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel
import android.util.Log

/**
 * Jembatan MethodChannel `com.chatyuk.chatyuk/call_ui` antara Dart dan
 * UI panggilan sistem (ConnectionService).
 *
 * Dart -> native: `showIncoming`, `setConnected`, `dismiss`
 * native -> Dart: `onAccept`, `onDecline`, `onEnd`
 *
 * Bridge bersifat singleton tapi hanya aktif saat Flutter engine hidup.
 * Saat app mati, [getInstance] null → [CallConnection] membuka MainActivity
 * (jalur `launchActivity`) alih-alih memanggil Dart.
 */
class CallUiBridge private constructor(
    private val context: Context,
    private val channel: MethodChannel,
) {
    private val main = Handler(Looper.getMainLooper())

    fun attach() {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "showIncoming" -> {
                    val args = call.arguments as? Map<*, *>
                    val callId = args?.get("callId") as? String ?: ""
                    val name = args?.get("callerName") as? String ?: ""
                    val type = args?.get("callType") as? String ?: "video"
                    if (callId.isNotEmpty()) {
                        CallConnectionService.startIncoming(context, callId, name, type)
                    }
                    result.success(true)
                }
                "setConnected" -> {
                    CallConnectionService.markConnected()
                    result.success(true)
                }
                "dismiss" -> {
                    CallConnectionService.dismissCurrent()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    /** Kirim aksi sistem ke Dart. Return false bila tidak ada sesi Dart. */
    fun deliverToDart(action: String, callId: String): Boolean {
        if (!attached) return false
        main.post {
            try {
                channel.invokeMethod(action, callId)
            } catch (e: Exception) {
                Log.w(TAG, "invoke Dart $action gagal: $e")
            }
        }
        return true
    }

    fun detach() {
        attached = false
        try {
            channel.setMethodCallHandler(null)
        } catch (_: Exception) {
        }
        instance = null
    }

    companion object {
        private const val TAG = "ChartyukCallUi"

        @Volatile
        private var instance: CallUiBridge? = null

        @Volatile
        private var attached: Boolean = false

        fun create(context: Context, channel: MethodChannel): CallUiBridge {
            val bridge = CallUiBridge(context.applicationContext, channel)
            instance = bridge
            attached = true
            bridge.attach()
            return bridge
        }

        fun getInstance(): CallUiBridge? = if (attached) instance else null
    }
}
