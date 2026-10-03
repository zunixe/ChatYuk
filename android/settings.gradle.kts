pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    // EKSPERIMEN branch experiment/agp9: AGP 9.0.1 + Gradle 9.3.1
    // (Play Console minta AGP ≥ 9.0; Flutter 3.47 berkahi combo ini:
    // gradle_utils.dart → AGP 9.0.x butuh Gradle 9.1+ ≤ 9.3.1).
    id("com.android.application") version "9.0.1" apply false
    // START: FlutterFire Configuration
    id("com.google.gms.google-services") version("4.4.2") apply false
    id("com.google.firebase.crashlytics") version("3.0.3") apply false
    // END: FlutterFire Configuration
    // 2.2.20 → 2.3.20: Flutter 3.47 memperingatkan KGP < 2.3.20 akan di-drop.
    id("org.jetbrains.kotlin.android") version "2.3.20" apply false
}

include(":app")
