package com.chatyuk.chatyuk.call

import android.content.Context
import android.os.PowerManager
import android.util.Log

/**
 * Proximity wake lock untuk panggilan AUDIO 1:1.
 *
 * Saat aktif: layar mati otomatis ketika HP didekatkan ke telinga (pola
 * `PROXIMITY_SCREEN_OFF_WAKE_LOCK` — persis yang dipakai aplikasi telepon).
 * Tujuan: hemat baterai + cegah pipi menyentuh tombol selama panggilan.
 *
 * Dipakai lewat channel `call_ui` (`setProximity`). Sengaja:
 *  - hanya AUDIO (video butuh layar tetap hidup),
 *  - best-effort: tanpa izin WAKE_LOCK → no-op (tidak crash),
 *  - release wajib saat panggilan selesai untuk membebaskan wake lock.
 *
 * Butuh izin `android.permission.WAKE_LOCK` (sudah ada di manifest).
 */
object ProximityManager {
    private const val TAG = "ChartyukProximity"

    @Volatile
    private var wakeLock: PowerManager.WakeLock? = null

    /** Aktifkan proximity screen-off. Idempoten. */
    fun acquire(context: Context) {
        try {
            val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
            if (!pm.isWakeLockLevelSupported(PowerManager.PROXIMITY_SCREEN_OFF_WAKE_LOCK)) {
                Log.d(TAG, "proximity tidak didukung device ini → no-op")
                return
            }
            val existing = wakeLock
            if (existing?.isHeld == true) return
            val lock = pm.newWakeLock(
                PowerManager.PROXIMITY_SCREEN_OFF_WAKE_LOCK,
                "chatyuk:call_proximity",
            )
            lock.setReferenceCounted(false)
            lock.acquire()
            wakeLock = lock
            Log.d(TAG, "proximity ON")
        } catch (e: Exception) {
            Log.w(TAG, "acquire proximity gagal (no-op): $e")
        }
    }

    /** Matikan proximity + lepas wake lock. Idempoten & aman. */
    fun release() {
        val lock = wakeLock ?: return
        wakeLock = null
        try {
            if (lock.isHeld) lock.release()
            Log.d(TAG, "proximity OFF")
        } catch (e: Exception) {
            Log.w(TAG, "release proximity gagal: $e")
        }
    }
}
