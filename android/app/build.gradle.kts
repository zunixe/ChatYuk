plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    id("com.google.firebase.crashlytics")
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

import java.util.Properties

// ============================================================
// GUARD: proyek Firebase WAJIB chatyuk-7c9e4.
// Riwayat insiden: flavor `play` pernah memakai project LAMA `chatyuk-8470e`
// (google_app_id 990163663226) → Google Sign-In di build Play GAGAL walau
// build `apkpure` normal. Guard ini MENGHENTIKAN build sebelum APK/AAB
// "salah project" sempat terbuat.
// ============================================================
val expectedFirebaseProject = "chatyuk-7c9e4"
run {
    val gsFiles = listOf(
        file("google-services.json"),
        file("src/play/google-services.json"),
        file("src/admin/google-services.json"),
    )
    gsFiles.filter { it.exists() }.forEach { f ->
        if (!f.readText().contains("\"$expectedFirebaseProject\"")) {
            throw GradleException(
                "GUARD Firebase: ${f.path} TIDAK memuat project " +
                    "'$expectedFirebaseProject' (kemungkinan 'chatyuk-8470e' " +
                    "= project lama → Google Sign-In GAGAL di build Play). " +
                    "Perbaiki: bash scripts/setup_play_google_services.sh"
            )
        }
    }
}

// Baca kredensial keystore dari key.properties (fallback ke env var).
val keystoreProps = Properties()
val keystorePropsFile = rootProject.file("key.properties")
if (keystorePropsFile.exists()) {
    keystoreProps.load(keystorePropsFile.inputStream())
}
fun envOr(envKey: String, propsKey: String, fallback: String): String {
    val env = System.getenv(envKey)
    return if (!env.isNullOrBlank()) env
        else keystoreProps.getProperty(propsKey, fallback)
}

android {
    namespace = "com.chatyuk.chatyuk"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    // JNI native: ImageBridge.nativeTrim() → malloc_trim/mallctl untuk
    // mengembalikan arena jemalloc ke OS (docs/PERFORMANCE.md §27). ABIs
    // disamakan dgn Flutter (arm64-v8a, armeabi-v7a, x86_64).
    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.chatyuk.chatyuk"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // Nama default — flavor dev menimpa dengan "ChatYuk Dev".
        manifestPlaceholders["appName"] = "ChatYuk"
    }

    signingConfigs {
        create("release") {
            storeFile = file(envOr("KEYSTORE_PATH", "storeFile", "../../android/keystore/chatyuk-release-v2.jks"))
            storePassword = envOr("KEYSTORE_PASS", "storePassword", "")
            keyAlias = envOr("KEY_ALIAS", "keyAlias", "chatyuk")
            keyPassword = envOr("KEY_PASS", "keyPassword", "")
        }
    }

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
        // Build diagnosis: profile mode = `dlog` AKTIF (kProfileMode) tapi
        // tetap di-sign keystore RELEASE supaya bisa menimpa install rilis
        // (signature harus sama). BuildType `profile` sudah ada bawaan AGP —
        // cukup konfigurasi signing-nya (jangan `create` lagi).
        getByName("profile") {
            signingConfig = signingConfigs.getByName("release")
        }
    }

    // Flavor distribusi: apkpure (default) vs play (Google Play).
    // Keduanya memakai applicationId & versionName yang SAMA (com.chatyuk.chatyuk),
    // hanya dibedakan oleh `--dart-define=APP_FLAVOR` + google-services.json.
    //
    // Flavor `admin`: build internal (JANGAN pernah diupload store).
    // Entry Dart: -t lib/main_admin.dart. AppId beda supaya bisa
    // ter-install berdampingan dengan app user di satu HP.
    //
    // Flavor `dev`: build development lawan Supabase local (54321).
    // AppId ber-akhiran .dev + nama "ChatYuk Dev" supaya bisa ter-install
    // berdampingan dengan app prod di satu HP. JANGAN pernah diupload store.
    // Jalankan via tool/run_dev.sh (mengisi --dart-define APP_ENV=SUPABASE_*).
    flavorDimensions += listOf("store", "env")
    productFlavors {
        create("apkpure") {
            dimension = "store"
            applicationId = "com.chatyuk.chatyuk"
        }
        create("play") {
            dimension = "store"
            applicationId = "com.chatyuk.chatyuk"
        }
        create("admin") {
            dimension = "store"
            applicationId = "com.chatyuk.chatyuk.admin"
            versionNameSuffix = "-admin"
            // Nama beda supaya gampang dibedakan di home screen.
            manifestPlaceholders["appName"] = "ChatYuk Admin"
        }
        // dimensi env
        create("prod") {
            dimension = "env"
            // default: tanpa suffix, tanpa perubahan apa pun (identik perilaku lama)
        }
        create("dev") {
            dimension = "env"
            applicationIdSuffix = ".dev"
            versionNameSuffix = "-dev"
            manifestPlaceholders["appName"] = "ChatYuk Dev"
        }
    }

    // Lint crash internal (Kotlin LLFirModuleData, Flutter 3.47 + KGP 2.3.20)
    // menggagalkan build RILIS secara acak — tidak terkait kode kita. Jangan
    // abortOnError supaya build tak tumble karena bug lint toolchain.
    lint {
        abortOnError = false
        checkReleaseBuilds = false
    }

    // Buang ABI x86_64 (emulator/Chromebook Intel) dari APK — tak ada di HP
    // fisik (semua ARM). `defaultConfig.ndk.abiFilters` DIABAIKAN Flutter
    // Gradle plugin (Flutter set target-platforms sendiri), jadi filter di
    // level packaging (jniLibs excludes) — berlaku SETELAH Flutter menaruh
    // .so. Permanen di gradle. arm64-v8a + armeabi-v7a DIPERTAHANKAN.
    packaging {
        jniLibs {
            excludes += listOf("lib/x86_64/**")
        }
    }
}

// Jaminan nama: build dev (variant mengandung "Dev") SELALU dapat nama
// "ChatYuk Dev" — flavor dimension store menimpa placeholder yang sama
// saat manifest merge, jadi kita assert ulang di level variant API.
androidComponents {
    onVariants { variant ->
        if (variant.name.contains("Dev", ignoreCase = true)) {
            variant.manifestPlaceholders.put("appName", "ChatYuk Dev")
        }
    }
}

flutter {
    source = "../.."
}

// KGP 2.3.20: `kotlinOptions { jvmTarget }` di dalam `android {}` sudah
// deprecated (jadi error di build). Pindah ke compilerOptions DSL.
kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

// Plugin facebook_app_events memakai versi DINAMIS `[18.0,19.0)` yang harus
// resolve metadata Maven tiap build → rawan gagal ("Repository MavenRepo is
// disabled due to earlier error") saat jaringan lambat. Pin ke versi stabil
// yang sudah ter-cache (18.3.0).
configurations.configureEach {
    resolutionStrategy {
        force("com.facebook.android:facebook-android-sdk:18.3.0")
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    // Firebase Messaging di classpath APLIKASI — dibutuhkan agar
    // ChartyukMessagingService bisa extends FlutterFirebaseMessagingService
    // (menangkap push type=call saat app MATI → UI panggilan sistem).
    // Versi mengikuti BOM yang dipakai plugin firebase_core (33.16.0).
    implementation(platform("com.google.firebase:firebase-bom:33.16.0"))
    implementation("com.google.firebase:firebase-messaging")
    // ── TikTok App Events (Business) SDK ──
    // Melacak event in-app (install/login/register/purchase) untuk iklan
    // TikTok. Native Android saja → dijembatani ke Dart lewat MethodChannel
    // `com.chatyuk.chatyuk/tiktok` (lihat TikTokBridge.kt & TikTokService.dart).
    implementation("com.github.tiktok:tiktok-business-android-sdk:1.7.1")
    // Dibutuhkan SDK: lifecycle (deteksi app foreground) + Install Referrer.
    implementation("androidx.lifecycle:lifecycle-process:2.8.7")
    implementation("androidx.lifecycle:lifecycle-common-java8:2.8.7")
    implementation("com.android.installreferrer:installreferrer:2.2")
}
