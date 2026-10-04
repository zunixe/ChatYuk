# Referensi Konfigurasi Build (Gradle/Android) — ChatYuk

> **SUMBER KEBENARAN** konfigurasi build Android. Kalau build RILIS berbeda
> perilaku (mis. lag, obfuscation, Google Play), bandingkan dengan file ini.
> Dibuat 2026-10-06 setelah insiden "lag ngetik private chat" yang akarnya
> konfigurasi R8 resource shrinker.

## Ringkasan (build RILIS yang BENAR)

| Setelan | Nilai | Alasan |
|---|---|---|
| `isMinifyEnabled` | `true` | Obfuscate+shrink kode; skor Play Console + ukuran. |
| `isShrinkResources` | `true` | Shrink resource (ukuran). **WAJIB bareng `keep.xml`.** |
| `proguardFiles` | `proguard-android-optimize.txt` + `proguard-rules.pro` | Normal AGP. |
| `proguard-rules.pro` | **TIDAK ada `-dontoptimize`** | Optimisasi R8 BUKAN penyebab lag (sudah diuji). |
| `res/raw/keep.xml` | **`tools:keep="@*"`** | 🔴 **KRITIS** — tanpa ini, shrinkResources stripp resource runtime → LAG ngetik. |
| `lint { abortOnError=false; checkReleaseBuilds=false }` | ada | Lint crash internal (Kotlin LLFirModuleData, Flutter 3.47+KGP 2.3.20) → build gagal acak. |

## Kenapa ini penting (insiden 2026-10-06)

**Gejala:** di build RILIS, private chat "ngelag saat menulis" (ketik pertama
tersendat). Build **debug/profile LANCAR**. Frame timing Dart di rilis SEHAT
(`p50=1.0ms janky=1`) → lag BUKAN di render Dart, tapi di **resource lookup**.

**Akar (terbukti lewat eliminasi variant):**

| isMinifyEnabled | isShrinkResources | Hasil |
|---|---|---|
| false | false | lancar |
| true | true | **NGELAG** |
| true (+`-dontoptimize`) | true | **NGELAG** (optimisasi BUKAN penyebab) |
| true | **false** | lancar |
| true | true + **keep.xml** | **lancar** ✅ |

`isShrinkResources=true` men-strip resource yang diakses **by-name/dinamis**
(bukan literal `R.*`) → lookup gagal & fallback berulang saat runtime.

**Fix final:** keep `isShrinkResources=true` + `res/raw/keep.xml`
`tools:keep="@*"`. Ukuran APK tetap 172MB (shrink non-asset jalan).

## File yang HARUS ada (jangan dihapus/ubah tanpa uji RILIS)

### `android/app/build.gradle.kts`
```kotlin
buildTypes {
    release {
        signingConfig = signingConfigs.getByName("release")
        isMinifyEnabled = true
        isShrinkResources = true
        proguardFiles(
            getDefaultProguardFile("proguard-android-optimize.txt"),
            "proguard-rules.pro"
        )
    }
    // ... profile { signingConfig release } dst
}

// di dalam blok android { }, setelah productFlavors:
lint {
    abortOnError = false
    checkReleaseBuilds = false
}
```

### `android/app/src/main/res/raw/keep.xml`
```xml
<resources xmlns:tools="http://schemas.android.com/tools"
    tools:keep="@*" />
```

### `android/app/proguard-rules.pro`
- TIDAK boleh ada `-dontoptimize` (sudah terbukti tak menyelesaikan lag).
- Rules keep SEMPIT (Flutter entry, firebase-messaging, UCrop, webrtc, dst).

## Cara verifikasi setelah ubah konfigurasi build

1. Build RILIS: `flutter build apk --release --flavor apkpureProd`
2. Install ke HP, buka private chat, **ketik** → harus LANCAR.
3. Jika lag lagi saat ketik → cek `keep.xml` masih ada & `isShrinkResources`
   masih `true`; jangan pernah `isShrinkResources=true` tanpa `keep.xml`.

## Upload Google Play (AAB)
```bash
flutter clean
KEYSTORE_PASS="chatyuk2024secure" KEY_PASS="chatyuk2024secure" \
  flutter build appbundle --release --flavor playProd \
  --dart-define=APP_FLAVOR=play \
  --obfuscate --split-debug-info=build/app/symbols
# Output: build/app/outputs/bundle/playProdRelease/app-play-prod-release.aab
fastlane play_upload track:alpha     # atau track:production
```
PENTING: upload pakai lane `play_upload` (TIDAK rebuild gradle — gradle rebuild
menghapus obfuscation Dart).

## ⚠️ Peringatan kolaborasi
Repo ini dikerjakan **lebih dari satu sesi AI/user**. Kalau perilaku build
tiba-tiba berbeda dari referensi ini, cek `git log -- android/` — mungkin ada
perubahan build config dari sesi lain. Jangan asumsikan; bandingkan dengan file
ini.
