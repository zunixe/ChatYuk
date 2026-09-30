allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// Naikkan compileSdk plugin lama ke 34+ agar tidak menolak build.
// Konteks: `android_play_install_referrer` (dan beberapa plugin lain) masih
// meng-compile terhadap android-33, padahal dependency transitif modern
// (androidx.exifinterface 1.4.x dsb) menuntut compileSdk >= 34 → build
// release GAGAL ("requires libraries ... compile against version 34 or
// later"). Fix global di sini (bukan patch per-plugin) supaya plugin baru
// dengan masalah sama tidak menggigit lagi.
// HANYA menyentuh compileSdk; targetSdk/minSdk TIDAK diubah (perilaku app
// tetap sesuai konfigurasi aslinya).
subprojects {
    fun bumpCompileSdk() {
        val androidExt = extensions.findByName("android")
        if (androidExt is com.android.build.gradle.BaseExtension) {
            val current = androidExt.compileSdkVersion
                ?.removePrefix("android-")?.toIntOrNull() ?: 0
            if (current in 1..36) {
                androidExt.compileSdkVersion(36)
            }
        }
    }
    if (state.executed) {
        bumpCompileSdk()
    } else {
        afterEvaluate { bumpCompileSdk() }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
