// JNI helper: kembalikan arena allocator NATIVE ke OS.
//
// Kenapa perlu: jemalloc Android (ro.malloc.impl=jemalloc) agresif MENAHAN
// arena — terukur `Native Heap Size 531MB / Alloc 49MB / Free 477MB` (arena
// direservasi besar tapi isinya kosong; ~380MB RssAnon). Ini bikin RSS proses
// ~830MB saat render gambar, walau objek hidup nyaris nol. Android TIDAK
// mengembalikan arena ke OS sendiri, dan `System.gc()`/`imageCache.evict()`
// TIDAK menolong (terbukti: `am send-trim-memory COMPLETE` → RSS tetap).
//
// Satu-satunya cara: `malloc_trim(0)` (glibc/bionic) atau jemalloc
// `mallctl("arena...purge")`. Keduanya butuh kode native → file ini.
//
// Semua best-effort: bila simbol tidak ada / gagal, return false (tidak crash).

#include <jni.h>
#include <stdbool.h>
#include <stddef.h>
#include <dlfcn.h>

// bionic menyediakan malloc_trim() sejak API 26 (minSdk proyek = 24). Kita
// resolusi lewat dlsym supaya tidak crash di API < 26 (simbol tak ada).
typedef int (*malloc_trim_fn)(size_t pad);

// jemalloc mallctl (hanya bila build memakai jemalloc). Signature asli:
//   int mallctl(const char *name, void *oldp, size_t *oldlenp, void *newp,
//               size_t newlen);
typedef int (*mallctl_fn)(const char *, void *, size_t *, void *, size_t);

// JNI dipanggil dari ImageBridge.trim() — sekali per sinyal OS (background /
// memory pressure). Tidak boleh melempar; semua error ditelan.
JNIEXPORT jboolean JNICALL
Java_com_chatyuk_chatyuk_image_ImageBridge_nativeTrim(JNIEnv *env, jobject thiz) {
    (void)env;
    (void)thiz;
    bool didSomething = false;

    // 1) malloc_trim(0) — mengembalikan free chunk di top-of-heap + memicu
    //    purge arena (bionic dengan jemalloc/Debug malloc). Resolusi via
    //    dlsym supaya API < 26 (tanpa simbol) tidak crash.
    void *trimSym = dlsym(RTLD_DEFAULT, "malloc_trim");
    if (trimSym != NULL) {
        if (((malloc_trim_fn)trimSym)(0)) {
            didSomething = true;
        }
    }

    // 2) jemalloc purge eksplisit (belt-and-suspenders). `mallctl` ada bila
    //    allocator = jemalloc; kalau tidak, dlsym gagal → skip.
    //    Nama berversi → coba beberapa.
    void *sym = dlsym(RTLD_DEFAULT, "mallctl");
    if (sym != NULL) {
        mallctl_fn mallctl = (mallctl_fn)sym;
        static const char *names[] = {
            "arena.purge",
            "arena.0.purge",
            "arenas.purge",
        };
        for (size_t i = 0; i < sizeof(names) / sizeof(names[0]); ++i) {
            if (mallctl(names[i], NULL, NULL, NULL, 0) == 0) {
                didSomething = true;
            }
        }
    }

    return didSomething ? JNI_TRUE : JNI_FALSE;
}
