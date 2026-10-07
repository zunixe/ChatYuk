// JNI helper: kembalikan arena allocator NATIVE ke OS.
//
// Kenapa perlu: allocator Android (jemalloc/scudo) agresif MENAHAN arena —
// terukur `Native Heap Size 538MB / Alloc 52MB / Free 482MB` (arena
// direservasi besar tapi isinya kosong) → SwapPss naik. Ini bikin memori app
// bengkak walau objek hidup nyaris nol. Android TIDAK mengembalikan arena ke
// OS sendiri, dan `System.gc()`/`imageCache.evict()` TIDAK menolong.
//
// CARA BENAR (docs Android malloc.h): `mallopt(M_PURGE, 0)` — public &
// diekspor sejak API 28. Nilai -101 = M_PURGE (purge memori tak terpakai),
// -104 = M_PURGE_ALL (API 34+, lebih menyeluruh).
//
// CATATAN PENTING: `malloc_trim()` dan `mallctl()` TIDAK diekspor oleh libc
// Android (diverifikasi via readelf) — dulu file ini memakai keduanya lewat
// dlsym → SELALU gagal (trim = no-op). itu sebab arena tak pernah menyusut.
//
// Semua best-effort: bila simbol tidak ada / gagal, tidak crash.

#include <jni.h>
#include <stdbool.h>
#include <stddef.h>
#include <dlfcn.h>

// mallopt(const char* name, int value) → int. Public API bionic (API 27+).
typedef int (*mallopt_fn)(int param, int value);

// Nilai dari <malloc.h> bionic (hardcode agar tak bergantung header NDK saat
// build; nilainya stabil & terdokumentasi).
#define M_PURGE_VAL (-101)
#define M_PURGE_ALL_VAL (-104)
#define M_DECAY_TIME_VAL (-100)

// JNI dipanggil dari ImageBridge.trim() — saat background LAMA / memory
// pressure (bukan tiap pause; lihat lib/app.dart). Tidak boleh melempar.
JNIEXPORT jboolean JNICALL
Java_com_chatyuk_chatyuk_image_ImageBridge_nativeTrim(JNIEnv *env, jobject thiz) {
    (void)env;
    (void)thiz;
    bool didSomething = false;

    void *sym = dlsym(RTLD_DEFAULT, "mallopt");
    if (sym == NULL) {
        // Fallback jarang: coba malloc_trim (glibc; umum tak ada di Android).
        typedef int (*malloc_trim_fn)(size_t);
        void *trimSym = dlsym(RTLD_DEFAULT, "malloc_trim");
        if (trimSym != NULL) {
            if (((malloc_trim_fn)trimSym)(0)) didSomething = true;
        }
        return didSomething ? JNI_TRUE : JNI_FALSE;
    }

    mallopt_fn mallopt = (mallopt_fn)sym;

    // Decay time 0 = lepas halaman tak terpakai SEGERA (hindari retensi jangka
    // panjang). Set SEBELUM purge supaya halaman berikutnya juga cepat lepas.
    mallopt(M_DECAY_TIME_VAL, 0);

    // 1) PURGE_ALL (API 34+, paling menyeluruh).
    if (mallopt(M_PURGE_ALL_VAL, 0) != 0) {
        didSomething = true;
    }
    // 2) PURGE (API 28+). Cukup untuk membebaskan arena ke OS.
    if (mallopt(M_PURGE_VAL, 0) != 0) {
        didSomething = true;
    }
    // 3) Ulang purge — jemalloc sering butuh >1 pass untuk arena besar.
    mallopt(M_PURGE_VAL, 0);

    return didSomething ? JNI_TRUE : JNI_FALSE;
}
