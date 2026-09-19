package com.chatyuk.chatyuk.call

import android.content.Context
import android.content.Intent
import android.telecom.Connection
import android.telecom.ConnectionRequest
import android.telecom.ConnectionService
import android.telecom.PhoneAccount
import android.telecom.PhoneAccountHandle
import android.telecom.TelecomManager
import android.util.Log

/**
 * ConnectionService SELF-MANAGED untuk panggilan ChatYuk.
 *
 * Memberi panggilan masuk tampilan UI panggilan SISTEM Android (layar kunci,
 * headset, Bluetooth, Android Auto) seperti WhatsApp/Telegram — tanpa
 * menyentuh WebRTC (media tetap di Dart `CallSession`).
 *
 * Dipanggil dari dua sumber:
 *  1. Dart (app hidup) via [CallUiBridge].
 *  2. [ChartyukMessagingService] (app mati, push FCM `type=call`).
 */
class CallConnectionService : ConnectionService() {

    override fun onCreate() {
        super.onCreate()
        registerPhoneAccount()
    }

    override fun onCreateIncomingConnection(
        connectionManagerPhoneAccount: PhoneAccountHandle?,
        request: ConnectionRequest?,
    ): Connection {
        val extras = request?.extras
        val callId = extras?.getString(CallConnection.EXTRA_CALL_ID) ?: ""
        val callerName = extras?.getString(CallConnection.EXTRA_CALLER_NAME).orEmpty()
        val callType = extras?.getString(CallConnection.EXTRA_CALL_TYPE).orEmpty()

        Log.d(TAG, "onCreateIncomingConnection callId=$callId name=$callerName")

        // Hanya satu panggilan aktif pada satu waktu (sama seperti provider).
        current?.destroy()
        val conn = CallConnection(
            context = this,
            callId = callId,
            callerName = callerName,
            callType = callType,
            isIncoming = true,
        )
        current = conn
        return conn
    }

    override fun onCreateIncomingConnectionFailed(
        connectionManagerPhoneAccount: PhoneAccountHandle?,
        request: ConnectionRequest?,
    ) {
        Log.w(TAG, "onCreateIncomingConnectionFailed (izin/kebijakan Telecom)")
    }

    override fun onDestroy() {
        current?.destroy()
        current = null
        super.onDestroy()
    }

    private fun registerPhoneAccount() {
        val telecom = getSystemService(Context.TELECOM_SERVICE) as TelecomManager
        val handle = PhoneAccountHandle(
            android.content.ComponentName(this, CallConnectionService::class.java),
            ACCOUNT_ID,
        )
        val account = PhoneAccount.builder(handle, "ChatYuk")
            .setCapabilities(PhoneAccount.CAPABILITY_SELF_MANAGED)
            .build()
        try {
            telecom.registerPhoneAccount(account)
        } catch (e: Exception) {
            Log.w(TAG, "registerPhoneAccount gagal: $e")
        }
    }

    companion object {
        private const val TAG = "ChartyukCallService"
        private const val ACCOUNT_ID = "chatyuk_call_account_v1"

        @Volatile
        private var current: CallConnection? = null

        /** Panggilan sudah tersambung di Dart -> ubah state UI sistem. */
        fun markConnected() {
            current?.let { conn ->
                if (conn.state != Connection.STATE_ACTIVE) {
                    conn.setActive()
                }
            }
        }

        /** Tutup UI panggilan sistem (ditolak/dibatalkan/berakhir). */
        fun dismissCurrent() {
            val conn = current ?: return
            current = null
            try {
                // onDisconnect TIDAK dipanggil di sini (sudah selesai) —
                // langsung tandai terputus + hapus.
                conn.setDisconnected(
                    android.telecom.DisconnectCause(
                        android.telecom.DisconnectCause.REMOTE,
                    ),
                )
                conn.destroy()
            } catch (_: Exception) {
            }
        }

        /**
         * Mulai panggilan masuk: daftar PhoneAccount lalu minta Telecom
         * menampilkan UI panggilan masuk. Aman dipanggil dari app mati.
         */
        fun startIncoming(
            context: Context,
            callId: String,
            callerName: String,
            callType: String,
        ) {
            val app = context.applicationContext
            try {
                val telecom = app.getSystemService(Context.TELECOM_SERVICE) as TelecomManager
                val handle = PhoneAccountHandle(
                    android.content.ComponentName(app, CallConnectionService::class.java),
                    ACCOUNT_ID,
                )
                // Pastikan PhoneAccount terdaftar (Service mungkin belum
                // onCreate saat app baru dibuka dari push).
                registerAccount(app, telecom, handle)

                val extras = android.os.Bundle().apply {
                    putString(CallConnection.EXTRA_CALL_ID, callId)
                    putString(CallConnection.EXTRA_CALLER_NAME, callerName)
                    putString(CallConnection.EXTRA_CALL_TYPE, callType)
                }
                // Self-managed incoming call: Telecom menampilkan UI panggilan
                // masuk sistem (butuh izin MANAGE_OWN_CALLS).
                telecom.addNewIncomingCall(handle, extras)
                Log.d(TAG, "addNewIncomingCall ok callId=$callId name=$callerName")
            } catch (e: SecurityException) {
                Log.w(TAG, "startIncoming butuh izin MANAGE_OWN_CALLS: $e")
            } catch (e: Exception) {
                Log.w(TAG, "startIncoming gagal: $e")
            }
        }

        private fun registerAccount(
            app: Context,
            telecom: TelecomManager,
            handle: PhoneAccountHandle,
        ) {
            val account = PhoneAccount.builder(handle, "ChatYuk")
                .setCapabilities(PhoneAccount.CAPABILITY_SELF_MANAGED)
                .build()
            try {
                telecom.registerPhoneAccount(account)
            } catch (_: Exception) {
            }
        }
    }
}
