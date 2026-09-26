# Flutter
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.**

# Firebase
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

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

# flutter_webrtc
-keep class org.webrtc.** { *; }
-dontwarn org.webrtc.**
