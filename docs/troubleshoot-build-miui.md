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

## Resep APK DIAGNOSTIK — pakai build `--profile` (TERBAIK, dipakai harian)

**Kesepakatan kerja: pasang APK profil ke HP untuk kerja harian supaya kalau
ada error/bug langsung kelihatan log-nya. APK rilis baru dipakai kalau sudah
bagus (untuk APKPure/Play).**

Kenapa `--profile`, bukan `--debug` atau `--release`:

| Build | Google Sign-In | `dlog` muncul di logcat? | Berguna untuk diagnosa |
|---|---|---|---|
| `--debug` | ❌ gagal `12500` (debug key) | ✅ | tidak — tidak bisa login |
| `--release` (obfuscate) | ✅ | ❌ `kDebugMode=false` → di-strip | tidak — log hilang |
| **`--profile`** | ✅ (di-sign keystore RILIS) | ✅ `kProfileMode=true` | **ya** |

Rahasia: `android/app/build.gradle.kts` sudah menyetel buildType `profile`
memakai `signingConfigs.release`. Jadi APK profil **ditandatangani keystore
rilis** (SHA-256 `84e9...` = SHA-1 `8ccc42e3...`) → Sign-In jalan, tapi
`kProfileMode` membuat `dlog()` tetap aktif → semua `[PHOTO-DBG]`, `[AVATAR]`,
`[CACHE-TIME]`, `[NAV]`, `[CALL-START]`, dll. muncul di logcat.

### Build + push (copy-paste)

```bash
cd /Users/zunixe/Documents/ChatYuk
rm -rf build/app/outputs build/app/intermediates build/app/tmp .dart_tool/flutter_build

KEYSTORE_PASS="chatyuk2024secure" KEY_PASS="chatyuk2024secure" \
  flutter build apk --profile --flavor apkpureProd --dart-define=APP_FLAVOR=apkpure

APK=build/app/outputs/flutter-apk/app-apkpureprod-profile.apk
cp "$APK" ~/Downloads/chatyuk_profile.apk
```

- **JANGAN** pakai `--obfuscate` di build profil: obfuscation justru bikin
  stack trace susah dibaca. Profil tanpa obfuscate = nama class asli utuh.
- Output: `app-apkpureprod-profile.apk` (~200MB).
- Signature sama dengan rilis → bisa menimpa install rilis **tanpa uninstall**
  (sesi login aman).

### Verifikasi signature (WAJIB sebelum pasang)

```bash
APKSIGNER=$(find "$HOME/Library/Android/sdk/build-tools" -name apksigner | sort | tail -1)
"$APKSIGNER" verify --print-certs "$APK" | grep SHA-1
# harus: 8ccc42e3fe9337216ce4250e2bfccb22941e50a2 (keystore rilis v2)
```

Kalau SHA-1 bukan itu → build salah (mungkin ter-sign debug key) → jangan pasang.

### Baca log setelah pasang

```bash
export PATH="$PATH:$HOME/Library/Android/sdk/platform-tools"
D=192.168.18.240:PORT          # ganti sesuai `adb devices`

adb -s $D logcat -c                                  # bersihkan dulu
# ... reproduksi bug di HP (buka chat, kirim, buka profil, dst) ...
adb -s $D logcat -d -v time | grep -E "PHOTO-DBG|AVATAR|NAV|CALL-START|CACHE-TIME|POINTS|prefetch|flutter" | tail -80
```

- User **swipe-kill** app dari Recents dulu kalau UI tidak berubah (proses basi
  MIUI — lihat bagian atas dokumen ini).
- Install manual dari File Manager → `Download/chatyuk_profile.apk` (MIUI
  menolak `adb install`).

### Alur kerja harian yang disepakati

1. Kerja/perbaikan fitur → build **profil** → pasang ke HP → cek log + perilaku.
2. Kalau sudah bagus & tidak ada error → baru build **rilis** (obfuscate) untuk
   APKPure/Play, dengan gate `./scripts/check_release_apk.sh`.

Alasan: build profil punya log lengkap untuk diagnosa, tapi tetap bisa login
(keystore rilis), jadi tidak ada lagi siklus "kenapa errornya?" tanpa petunjuk.

## Resep debug APK lama (alternatif: debug + re-sign manual)

Debug key bikin login Google gagal (12500) dan beda signature (harus uninstall).
Alternatif kalau `--profile` tidak cocok: build debug, lalu **re-sign dengan
keystore release**:

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

## Screenshot hitam ≠ app freeze (FLAG_SECURE)

`app_settings.screenshot_enabled=false` → app pasang **FLAG_SECURE** →
`adb exec-out screencap` / `screencap -p` mengembalikan **gambar HITAM**
(status bar & nav button tetap kelihatan karena itu system UI).
Dart tetap jalan, data tetap masuk — yang hitam hanya hasil capture.

Jangan diagnosa "app freeze / layar hitam" dari screenshot sebelum cek:
1. `screenshot_enabled` di DB (`select screenshot_enabled from app_settings`).
2. Log Dart masih mengalir (`logcat --pid=<pid> | grep flutter`).
3. `dumpsys activity activities | grep topResumedActivity` (activity resumed?).

Kasus 2026-09-29: capture hitam dikira render freeze, ternyata FLAG_SECURE
(user di HP melihat konten normal: "udah tampil").

## Room kosong sesaat = jaringan putus, bukan data hilang

Gejala "room kadang tampil kadang kosong" (2026-09-29, room General + room lain):
- Data server UTUH (General: 9 pesan; `room_* server=... n=9` di logcat).
- Penyebab: HP sempat **kehilangan jaringan total** (`Failed host lookup ...
  No address associated with hostname`, RPC timeout 30 dtk) — hotspot
  192.168.137.x flapping. Fetch gagal + cache kosong → tampil kosong.
- Setelah jaringan balik → room keisi sendiri.

Urutan diagnosa room kosong: (1) cek data ada di server, (2) cek logcat
`room_<id> server=... n=...` (kalau n>0 = data masuk, masalah render),
(3) cek `Failed host lookup` / TimeoutException (jaringan), (4) baru curigai
kode/RLS. Jangan lompat ke kesimpulan kode rusak.
