package com.chatyuk.chatyuk.call

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.telecom.Connection
import android.telecom.DisconnectCause
import android.telecom.TelecomManager
import com.chatyuk.chatyuk.MainActivity

/**
 * Satu koneksi panggilan di sistem Telecom (ConnectionService).
 *
 * Tanggung jawab:
 *  - Menyimpan callId + nama pemanggil (untuk label di system call UI).
 *  - Meneruskan aksi pengguna (jawab/tolak/akhiri) ke Dart lewat
 *    [CallUiBridge], ATAU membuka MainActivity saat app belum jalan.
 *
 * TIDAK menyentuh WebRTC — media tetap milik CallSession di Dart.
 */
class CallConnection(
    private val context: Context,
    val callId: String,
    val callerName: String,
    val callType: String,
    private val isIncoming: Boolean,
) : Connection() {

    init {
        connectionProperties = PROPERTY_SELF_MANAGED
        audioModeIsVoip = true
        setAddress(
            android.net.Uri.fromParts("tel", callerName.ifEmpty { "ChatYuk" }, null),
            TelecomManager.PRESENTATION_ALLOWED,
        )
        if (isIncoming) {
            setCallerDisplayName(callerName, TelecomManager.PRESENTATION_ALLOWED)
            setRinging()
        }
    }

    override fun onAnswer() {
        super.onAnswer()
        // Bila app hidup + UI Dart siap → teruskan ke Dart (satu jalur aksi).
        // Bila app baru dibuka dari kondisi mati → buka MainActivity dengan
        // penanda accept; Dart menangani sisanya (startSession callee).
        if (CallUiBridge.getInstance()?.deliverToDart(ACTION_ACCEPT, callId) == true) {
            setActive()
        } else {
            launchActivity(ACTION_ACCEPT)
        }
    }

    override fun onReject() {
        super.onReject()
        if (CallUiBridge.getInstance()?.deliverToDart(ACTION_DECLINE, callId) != true) {
            launchActivity(ACTION_DECLINE)
        }
        setDisconnected(DisconnectCause(DisconnectCause.REJECTED))
        destroy()
    }

    override fun onDisconnect() {
        super.onDisconnect()
        if (CallUiBridge.getInstance()?.deliverToDart(ACTION_END, callId) != true) {
            launchActivity(ACTION_END)
        }
        setDisconnected(DisconnectCause(DisconnectCause.LOCAL))
        destroy()
    }

    override fun onAbort() {
        super.onAbort()
        setDisconnected(DisconnectCause(DisconnectCause.CANCELED))
        destroy()
    }

    private fun launchActivity(action: String) {
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra(EXTRA_CALL_ACTION, action)
            putExtra(EXTRA_CALL_ID, callId)
            putExtra(EXTRA_CALLER_NAME, callerName)
            putExtra(EXTRA_CALL_TYPE, callType)
        }
        try {
            context.startActivity(intent)
        } catch (_: Exception) {
        }
    }

    companion object {
        const val ACTION_ACCEPT = "accept"
        const val ACTION_DECLINE = "decline"
        const val ACTION_END = "end"

        const val EXTRA_CALL_ACTION = "chatyuk_call_action"
        const val EXTRA_CALL_ID = "chatyuk_call_id"
        const val EXTRA_CALLER_NAME = "chatyuk_caller_name"
        const val EXTRA_CALL_TYPE = "chatyuk_call_type"
    }
}
