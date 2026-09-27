# ============================================================
# ChatYuk ProGuard/R8 — dibuat SESEMPIT mungkin agar skor
# optimasi/obfuscation/shrink Play Console maksimal.
# Prinsip: JANGAN keep-all paket library. Komponen yang dideklarasikan
# di AndroidManifest (Activity/Service/Receiver) OTOMATIS di-keep R8 —
# tidak perlu keep manual. Library GMS/Firebase-core/Facebook membawa
# consumer ProGuard rules sendiri di AAR-nya (terverifikasi di Gradle
# cache, 2026-09-28) — tidak perlu keep manual.
# ============================================================

# Flutter embedding: HANYA entry-point. Registrasi plugin via
# GeneratedPluginRegistrant adalah referensi kode langsung (bukan
# refleksi) → class plugin lain boleh di-shrink/obfuscate R8.
# MainActivity + service aplikasi (.call.*) + service/activity plugin
# (UCrop, foreground_task, dexterous, firebase_messaging) semuanya
# dideklarasikan di manifest → auto-keep R8.
-keep class io.flutter.embedding.android.FlutterActivity { *; }
-keep class io.flutter.embedding.android.FlutterFragmentActivity { *; }
-keep class io.flutter.plugins.GeneratedPluginRegistrant { *; }
-dontwarn io.flutter.**

# Firebase: TANPA keep-all. firebase-common/components/encoders membawa
# consumer rules sendiri. firebase-messaging TIDAK membawa rules →
# keep sempit HANYA paket messaging (kecil, ~157KB) sebagai pengaman
# (dipakai ChartyukMessagingService saat app mati).
-keep class com.google.firebase.messaging.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# Facebook SDK (App Events): semua AAR-nya membawa consumer rules
# sendiri (terverifikasi: core/login/share/applinks/common 18.3.0).
-dontwarn com.facebook.**
-dontwarn com.facebook.android.**

# OkHttp / Okio: JANGAN keep-all manual. Aturan consumer bawaan library
# (META-INF/proguard/okhttp3.pro & okio.pro, otomatis dipakai AGP) sudah
# menjaga yang perlu (PublicSuffixDatabase dsb). Keep-all `okhttp3.**`
# mematikan obfuscation+optimasi R8 untuk library besar ini → Play Console
# memprotes "persentase obfuscation rendah". -dontwarn tetap dipertahankan.
-dontwarn okhttp3.**
-dontwarn okio.**
-dontwarn retrofit2.**

# Keep R8 from stripping serialization classes
-keepattributes Signature
-keepattributes *Annotation*
-keepclassmembers class * {
    @com.google.gson.annotations.SerializedName <fields>;
}

# Flutter local notifications
-keep class com.dexterous.** { *; }

# app_links / deep link
-keep class com.llfbandit.app_links.** { *; }

# image_cropper (UCrop): AAR-nya TIDAK membawa consumer rules →
# keep sempit paketnya (kecil). UCropActivity di manifest auto-keep.
-keep class com.yalantis.ucrop.** { *; }
-dontwarn com.yalantis.ucrop.**

# flutter_webrtc
-keep class org.webrtc.** { *; }
-dontwarn org.webrtc.**
