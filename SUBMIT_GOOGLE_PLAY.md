# Panduan Submit Google Play Console untuk ChatYuk

## ⚠️ WAJIB: Google Sign-In di build Play (insiden 2026-09-19)

Build `play`/AAB **ditandatangani ULANG oleh Google** (Play App Signing), jadi
SHA-nya BEDA dari keystore upload kita. Tiga hal ini WAJIB benar atau
Google Sign-In **gagal di versi Play** (walau build `apkpure` normal):

1. **`android/app/src/play/google-services.json` HARUS project `chatyuk-7c9e4`**
   (BUKAN project lama `chatyuk-8470e`). File ini di-gitignore → buat ulang:
   ```bash
   bash scripts/setup_play_google_services.sh
   ```
   Guard Gradle akan **MENGHENTIKAN build** kalau project salah.

2. **SHA Play App Signing terdaftar di Firebase project `chatyuk-7c9e4`**
   → Android `com.chatyuk.chatyuk` → SHA certificate hashes:
   - SHA-1 `7A:19:AF:A5:22:11:E9:AA:61:F5:8E:16:54:28:04:E8:32:EE:3C:B1`
   - SHA-256 `9778574b360e91f03c7e53b4a14dfdf4112d3b9a6c0b07d69886da60ac0d56ce`
   - (+ SHA keystore upload: `8C:CC:42:E3:…` / `84e96398…`)
   Cara dapat SHA Play: install dari Play di HP → `adb pull` base.apk →
   `apksigner verify --print-certs base.apk | grep SHA-1`.

3. **Cek sebelum upload** (otomatis dijalankan Fastfile, bisa manual):
   ```bash
   bash scripts/check_google_signin.sh   # harus "SEMUA COCOK"
   ```

## Persyaratan
- [ ] Akun developer Google Play dengan akses ke app `com.chatyuk.chatyuk`
- [ ] APK rilis terbaru (`app-apkpureprod-release.apk`)
- [ ] Data Safety form sudah diisi sesuai panduan

## Langkah Submit
1. **Login ke Google Play Console**
   - URL: https://play.google.com/console/developers
   - Gunakan akun `chatyuk.admin@gmail.com` (atau akun dengan akses)

2. **Pilih aplikasi** `com.chatyuk.chatyuk`
   - Pastikan URL mengandung `developers/8359197228304141922/app/4974318379582736850`

3. **Ke Tab Rilis → Rilis baru**
   - Upload APK: `build/app/outputs/flutter-apk/app-apkpureprod-release.apk`
   - Pilih track: **Pengujian terbuka** (alpha)
   - Tambahkan catatan rilis

4. **Ke Tab Kebijakan → Keamanan Data**
   - Isi formulir sesuai `play_console_data_safety_guide.md`
   - Verifikasi dengan menjalankan `dart verify_data_collection.dart`

5. **Submit untuk ditinjau**
   - Klik "Kirim untuk ditinjau"
    - Tunggu 1-3 hari untuk persetujuan

## Verifikasi Data Collection
```bash
# Jalankan verifikasi sebelum submit
dart verify_data_collection.dart
flutter clean && flutter build apk --release --flavor apkpureProd --dart-define=APP_FLAVOR=apkpure
```

## Jalur upload yang benar (AAB + fastlane)

Upload resmi pakai AAB flavor `play` (bukan APK apkpure):
```bash
# wajib bump version: x.y.z+N (N tidak boleh dipakai ulang)
flutter clean && flutter pub get
KEYSTORE_PASS="chatyuk2024secure" KEY_PASS="chatyuk2024secure" \
  flutter build appbundle --release --flavor playProd --dart-define=APP_FLAVOR=play \
  --obfuscate --split-debug-info=build/app/symbols
fastlane play_upload track:alpha   # atau track:production
```
`fastlane` otomatis menjalankan guard `check_google_signin` dulu.

## Catatan Penting
- **JANGAN** submit tanpa mengisi Data Safety form
- **JANGAN** ubah versi aplikasi sebelum submit
- **WAJIB** pakai keystore `chatyuk-release-v2.jks`
- **WAJIB** pakai app ID `com.chatyuk.chatyuk`
- **WAJIB** `src/play/google-services.json` = project `chatyuk-7c9e4`
  (guard Gradle menolak project lain — insiden 8470e)
- **WAJIB** SHA Play App Signing terdaftar di Firebase 7c9e4

---

**Status saat ini:**
- [x] APK rilis siap (`131.0MB`)
- [x] Data Safety form siap diisi
- [x] Verifikasi data collection siap
- [ ] Akun developer akses
- [ ] Submit ke Google Play

**Next steps:**
1. Login ke akun developer yang punya akses
2. Isi Data Safety form sesuai panduan
3. Submit APK untuk ditinjau
