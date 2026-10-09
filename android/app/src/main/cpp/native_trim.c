// JNI helper: kembalikan arena allocator NATIVE ke OS.
//
// Kenapa perlu: allocator Android (jemalloc/scudo) agresif MENAHAN arena —
// terukur `Native Heap Size 538MB / Alloc 52MB / Free 482MB` (arena
// direservasi besar tapi isinya kosong) → SwapPss naik & RSS membengkak walau
// objek hidup nyaris nol. Android TIDAK mengembalikan arena ke OS sendiri, dan
// `System.gc()`/`imageCache.evict()` TIDAK menolong.
//
// CARA BENAR (docs Android <malloc.h>): `mallopt(M_PURGE, 0)` (API 28).
// HANYA M_PURGE yang dipakai — alasannya keras (bukti tombstone):
//   * `mallopt(M_DECAY_TIME=-100, 0)` SEGFAULT di dalam libc (mallopt+204,
//     SEGV_ACCERR) di Xiaomi Android 16 (scudo) — 10 crash identik 8–9 Okt
//     2026 di KEDUA app (user + admin), semua dari nativeTrim+48 (= return
//     address panggilan mallopt PERTAMA). M_DECAY_TIME dihapus total.
//   * `mallopt(M_PURGE_ALL=-104)` tidak pernah terbukti aman di scudo
//     (tak pernah jalan sampai sana — crash duluan di panggilan pertama),
//     jadi ikut dibuang. Konservatif > agresif untuk fungsi yang jalan
//     tiap 15 detik.
//
// Urutan: PURGE 2 pass (jemalloc/scudo kadang butuh >1 siklus untuk arena
// besar).
//
// Semua best-effort: kegagalan return 0 (bukan crash) → diabaikan.
//
// KENAPA dlsym (bukan link langsung): `mallopt` dideklarasikan/diekspor bionic
// HANYA sejak API 26, sedangkan proyek ini minSdk 24. `#include <malloc.h>`
// menyembunyikan deklarasinya (guard __BIONIC_AVAILABILITY_GUARD(26)), dan
// link langsung → `ld.lld: undefined symbol: mallopt`. Jadi dlsym WAJIB di
// sini — resolusi runtime di device modern (yang punya mallopt). PASSING:
// nilai M_* di-hardcode (stabil, terdokumentasi) agar tak bergantung header.
//
// CATATAN: `malloc_trim()` & `mallctl()` TIDAK diekspor libc Android sama
// sekali (readelf) → jangan dipakai (versi lama file ini salah memakainya).
//
// Urutan: DECAY_TIME 0 (lepas halaman segera) DULU, lalu purge_all + purge
// (beberapa pass; jemalloc kadang butuh >1 siklus untuk arena besar).
//
// Semua best-effort: kegagalan tidak pernah crash.

#include <jni.h>
#include <stdbool.h>
#include <stddef.h>
#include <dlfcn.h>
#include <android/log.h>

#define LOG_TAG "ChatYukTrim"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)

// Signature mallopt public bionic (API 26+). Return 1 sukses, 0 error.
typedef int (*mallopt_fn)(int option, int value);

// Nilai dari <malloc.h> bionic (hardcode: nilai stabil & terdokumentasi).
// Hanya M_PURGE yang dipakai (lihat alasan di header atas).
#define M_PURGE_VAL (-101)       // API 28: purge memori tak terpakai

// JNI dipanggil dari ImageBridge.trim() (thread IO, bukan main) — saat
// background lama / memory pressure / idle foreground. Tidak boleh melempar.
JNIEXPORT jboolean JNICALL
Java_com_chatyuk_chatyuk_image_ImageBridge_nativeTrim(JNIEnv *env, jobject thiz) {
    (void)env;
    (void)thiz;
    bool didSomething = false;

    void *sym = dlsym(RTLD_DEFAULT, "mallopt");
    if (sym == NULL) {
        LOGI("nativeTrim: mallopt tak ditemukan (API < 26?) -> no-op");
        return JNI_FALSE;
    }
    mallopt_fn mallopt = (mallopt_fn)sym;

    // HANYA M_PURGE (2 pass). M_DECAY_TIME & M_PURGE_ALL dihapus (lihat
    // header: crash SEGV di device ini). Return 0 = tak didukung → abaikan.
    if (mallopt(M_PURGE_VAL, 0) == 1) didSomething = true;

    // Pass kedua — allocator kadang butuh beberapa siklus untuk arena besar.
    mallopt(M_PURGE_VAL, 0);

    LOGI("nativeTrim -> did=%d (M_PURGE x2)",
         didSomething ? 1 : 0);

    return didSomething ? JNI_TRUE : JNI_FALSE;
}
