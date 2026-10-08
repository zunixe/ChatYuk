// JNI helper: kembalikan arena allocator NATIVE ke OS.
//
// Kenapa perlu: allocator Android (jemalloc/scudo) agresif MENAHAN arena —
// terukur `Native Heap Size 538MB / Alloc 52MB / Free 482MB` (arena
// direservasi besar tapi isinya kosong) → SwapPss naik & RSS membengkak walau
// objek hidup nyaris nol. Android TIDAK mengembalikan arena ke OS sendiri, dan
// `System.gc()`/`imageCache.evict()` TIDAK menolong.
//
// CARA BENAR (docs Android <malloc.h>): `mallopt(M_PURGE, 0)` (API 28) &
// `mallopt(M_PURGE_ALL, 0)` (API 34, paling menyeluruh).
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
#define M_DECAY_TIME_VAL (-100)  // 0 = release unused pages immediately
#define M_PURGE_VAL (-101)       // API 28: purge memori tak terpakai
#define M_PURGE_ALL_VAL (-104)   // API 34: purge SETIAP memori yang mungkin

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

    // 1) Decay time 0 = lepas halaman tak terpakai SEGERA (bukan menunggu
    //    interval). Set sebelum purge supaya halaman berikutnya juga cepat
    //    dilepas → mencegah arena membengkak lagi.
    if (mallopt(M_DECAY_TIME_VAL, 0) == 1) didSomething = true;

    // 2) PURGE_ALL (API 34+): "examines everything" → paling bersih, tapi bisa
    //    >2× lebih lama dari M_PURGE. Dipanggil RUNTIME (nilai -104 hardcoded),
    //    BUKAN via #if __ANDROID_API__ — file di-compile minSdk 24, guard
    //    kompilasi akan menghapus baris ini selamanya (bug halus). Di device
    //    < API 34 mallopt balikan 0 (bukan crash) → diabaikan. Aman karena
    //    jalan di thread IO.
    if (mallopt(M_PURGE_ALL_VAL, 0) == 1) didSomething = true;

    // 3) PURGE (API 28+): jalur utama di API < 34, pelengkap di API >= 34.
    if (mallopt(M_PURGE_VAL, 0) == 1) didSomething = true;

    // 4) Pass kedua — jemalloc kadang butuh beberapa siklus untuk arena besar.
    mallopt(M_PURGE_VAL, 0);

    LOGI("nativeTrim -> did=%d (M_DECAY_TIME+M_PURGE_ALL+M_PURGE)",
         didSomething ? 1 : 0);

    return didSomething ? JNI_TRUE : JNI_FALSE;
}
