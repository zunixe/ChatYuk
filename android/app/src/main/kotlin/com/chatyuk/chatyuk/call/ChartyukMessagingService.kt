package com.chatyuk.chatyuk.call

import android.util.Log
import com.google.firebase.messaging.RemoteMessage
import io.flutter.plugins.firebase.messaging.FlutterFirebaseMessagingService

/**
 * Menerima push FCM saat app MATI dan menampilkan panggilan masuk sebagai
 * UI panggilan SISTEM (ConnectionService).
 *
 * Kenapa extend [FlutterFirebaseMessagingService]: plugin FlutterFire sudah
 * memegang action `com.google.firebase.MESSAGING_EVENT`. Meng-extend-nya
 * (kelas ini bukan final) adalah pola resmi FlutterFire untuk menyisipkan
 * logika native tanpa menghilangkan penanganan Dart.
 *
 * **WAJIB** memanggil `super.onMessageReceived` di setiap jalur supaya
 * handler Dart (notifikasi chat/mention/online dll) tetap berjalan.
 */
class ChartyukMessagingService : FlutterFirebaseMessagingService() {

    override fun onMessageReceived(message: RemoteMessage) {
        // Selalu teruskan ke FlutterFire dulu — jangan pernah menghalangi
        // notifikasi biasa (chat, mention, follow, dsb).
        super.onMessageReceived(message)

        try {
            val data = message.data
            if (data["type"] != "call") return

            // Hanya saat app TIDAK di foreground dan tidak ada bridge Dart
            // aktif (app mati) — kalau app hidup, Dart yang menangani
            // (CallProvider._onIncoming → callUi.showIncoming).
            if (CallUiBridge.getInstance() != null) {
                Log.d(TAG, "app hidup — incoming call ditangani Dart")
                return
            }

            val callId = data["callId"] ?: return
            val name = data["fromName"] ?: data["otherName"] ?: ""
            val callType = data["callType"] ?: "video"
            Log.d(TAG, "app mati — tampilkan call sistem callId=$callId")

            CallConnectionService.startIncoming(
                context = applicationContext,
                callId = callId,
                callerName = name,
                callType = callType,
            )
        } catch (e: Exception) {
            Log.w(TAG, "onMessageReceived error: $e")
        }
    }

    companion object {
        private const val TAG = "ChartyukFcm"
    }
}
