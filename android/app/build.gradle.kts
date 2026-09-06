plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

import java.util.Properties

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

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
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

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
