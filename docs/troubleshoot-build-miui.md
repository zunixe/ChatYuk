# Troubleshooting: Build Terinstall Tapi UI Tidak Berubah (MIUI + Wireless ADB)

Masalah ini BERULANG beberapa kali (terakhir 2026-09-05: ~2 jam debugging sia-sia).
Baca file ini DULU sebelum menuduh kode salah atau build system rusak.

## Gejala

- `flutter build` sukses + `adb install -r` sukses, tapi screenshot HP menunjukkan UI lama.
- Beberapa build beruntun menghasilkan APK berukuran byte IDENTIK.
- Screenshot konsisten menampilkan UI lama walau kode sudah diubah total.

## Akar masalah: PROSES BASI (stale process)

Di MIUI via wireless ADB, install APK baru **TIDAK membunuh proses lama**:

| Perintah | Hasil di MIUI wireless ADB |
|---|---|
| `adb install -r` | Sukses ganti file APK, tapi proses lama sering TETAP JALAN dengan kode lama |
| `adb shell am force-stop` | Exit 0 tapi **diam-diam GAGAL** (proses tetap hidup!) |
| `adb shell monkey -p ... LAUNCHER 1` | Hanya me-RESUME proses lama, bukan restart |
| `adb shell kill -9 <pid>` | `Operation not permitted` (diblokir) |
| `adb uninstall` | `DELETE_FAILED_INTERNAL_ERROR` (diblokir) |
| `adb shell pm clear` | `SecurityException` (diblokir, sudah diketahui) |

Akibatnya semua "verifikasi screenshot" menampilkan **proses yang lahir SEBELUM install** —
tidak valid, menyesatkan, dan memicu teori salah (build stale, SDK salah, kode mati, dsb).

## Cara verifikasi (WAJIB tiap install)

Bandingkan **umur proses** vs **waktu install**:

```bash
D=192.168.18.33:PORT
P=$(adb -s $D shell pidof com.chatyuk.chatyuk | tr -d '\r')
adb -s $D shell "stat -c %y /proc/$P"          # lahir proses
adb -s $D shell dumpsys package com.chatyuk.chatyuk | grep lastUpdateTime  # install
```

**Kalau proses lahir SEBELUM install → BASI. Jangan percaya screenshot apa pun.**

## Cara restart yang reliable

adb TIDAK BISA di MIUI wireless. Satu-satunya cara pasti:

1. **User swipe-kill ChatYuk dari Recents** (atau Setelan → Aplikasi → ChatYuk → Force stop)
2. Baru launch ulang (`monkey` / tap ikon) → PID baru → screenshot valid

## Pencegahan lain (sudah terbukti)

- **Layar tidur → screenshot hitam.** Kunci layar tetap nyala tiap sesi:
  `adb shell settings put system screen_off_timeout 600000`
- **Heads-up notification & dialog izin lokasi menutupi toolbar.** Dismiss dulu
  (swipe) sebelum screenshot verifikasi.
- **Port wireless ADB berubah-ubah** (40527 → 40485, dst). Kalau `device offline`,
  minta IP:port baru dari HP (Setelan → Opsi pengembang → Proses debug nirkabel).
- **Ukuran APK identik BUKAN bukti build stale** (red herring — diff kecil + zip
  bisa menghasilkan ukuran sama). Verifikasi via marker visual / log, bukan size.
- **Dua Flutter SDK di mesin ini**: formula (`/opt/homebrew/share/flutter`, dipakai
  IDE language-server) vs cask (`/opt/homebrew/Caskroom/flutter`, dipakai build).
  Pastikan build selalu via satu SDK yang sama.
- **XSpace (user 999) aktif** di HP. Kalau bingung, cek foreground:
  `dumpsys activity activities | grep mFocusedApp` (harus `u0 com.chatyuk.chatyuk`).

## Resep debug APK (debuggable + login tetap jalan + tanpa uninstall)

Debug key bikin login Google gagal (12500) dan beda signature (harus uninstall).
Solusi: build debug, lalu **re-sign dengan keystore release**:

```bash
flutter build apk --debug --flavor apkpure --dart-define=APP_FLAVOR=apkpure
APKSIGNER=~/Library/Android/sdk/build-tools/36.0.0/apksigner
cp build/app/outputs/flutter-apk/app-apkpure-debug.apk /tmp/dbg.apk
"$APKSIGNER" sign --ks android/keystore/chatyuk-release-v2.jks \
  --ks-pass pass:chatyuk2024secure --key-pass pass:chatyuk2024secure \
  --ks-key-alias chatyuk --out /tmp/dbg_release.apk /tmp/dbg.apk
"$APKSIGNER" verify --print-certs /tmp/dbg_release.apk | grep SHA-1
# harus: 8ccc42e3fe9337216ce4250e2bfccb22941e50a2
adb install -r /tmp/dbg_release.apk   # signature sama → tanpa uninstall, sesi aman
```

Verifikasi terinstall = build debug: `dumpsys package ... | grep DEBUGGABLE`.

## Teknik verifikasi kode jalan (bukan dari screenshot)

- **Marker visual sementara** (mis. prefix judul): membuktikan pipeline build→install→render.
- **Log sementara + logcat**: `debugPrint('ZZZLOG_...')` lalu
  `adb shell logcat -d -s flutter | grep ZZZLOG` — membuktikan fungsi dieksekusi.
- Selalu: `logcat -c` dulu, force-stop/user-kill, launch, baru baca log.
- HAPUS semua marker/log sementara setelah selesai + rebuild bersih.
